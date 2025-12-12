#!/bin/bash
# ============================================================================
# DS01 Group Membership Sync Script
# ============================================================================
# Auto-populates config/groups/*.members files from /home/ directory scan.
#
# DATA FLOW:
#   /home/ directory scan
#       ↓
#   + config/group-overrides.txt (deterministic assignments)
#       ↓
#   MERGE into config/groups/*.members (ADD only, never remove)
#       ↓
#   Downstream: resource-limits.yaml reads these files
#
# KEY BEHAVIOR:
#   - MERGES new users (adds if not present)
#   - NEVER removes existing entries (preserves admin changes)
#   - Respects archived.members (skips archived users)
#   - Respects group-overrides.txt (deterministic assignments)
#
# USAGE:
#   sync-group-membership.sh              # Normal sync (merge)
#   sync-group-membership.sh --dry-run    # Show what would be added
#   sync-group-membership.sh --verbose    # Show all processing
#
# CRON:
#   0 4 * * * root /opt/ds01-infra/scripts/system/sync-group-membership.sh
# ============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="${SCRIPT_DIR}/../.."
GROUPS_DIR="${INFRA_ROOT}/config/groups"
OVERRIDES_FILE="${INFRA_ROOT}/config/group-overrides.txt"
ARCHIVED_FILE="${GROUPS_DIR}/archived.members"
LOG_TAG="DS01-sync-groups"

# Options
DRY_RUN=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: sync-group-membership.sh [--dry-run] [--verbose]"
            echo ""
            echo "Syncs user group membership from /home/ to config/groups/*.members"
            echo "Uses MERGE logic: adds new users, never removes existing entries."
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be added without making changes"
            echo "  --verbose    Show all processing details"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Logging helper
log() {
    local msg="$1"
    if [[ "$VERBOSE" == "true" ]] || [[ "$2" == "always" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
    fi
    logger -t "$LOG_TAG" "$msg" 2>/dev/null || true
}

# Check if user is in archived.members
is_archived() {
    local username="$1"
    if [[ -f "$ARCHIVED_FILE" ]]; then
        # Match exact username (not partial)
        # Use || return 1 to handle grep's exit code without triggering set -e
        grep -qE "^${username}(\s|$)" "$ARCHIVED_FILE" 2>/dev/null || return 1
        return 0
    else
        return 1
    fi
}

# Get override group from group-overrides.txt
get_override_group() {
    local username="$1"
    if [[ -f "$OVERRIDES_FILE" ]]; then
        # Format: username:group  # comment
        # Extract group, strip comments and whitespace
        # Use || true to prevent set -e from exiting on no match
        local line=$(grep -E "^${username}:" "$OVERRIDES_FILE" 2>/dev/null | head -1 || true)
        if [[ -n "$line" ]]; then
            # Get field after : , remove comments, strip whitespace
            local override=$(echo "$line" | cut -d: -f2 | sed 's/#.*//' | tr -d '[:space:]')
            if [[ -n "$override" ]]; then
                echo "$override"
                return 0
            fi
        fi
    fi
    return 1
}

# Classify user based on username pattern
classify_by_pattern() {
    local username="$1"

    # Pattern: numeric ID @ domain = student
    if [[ "$username" =~ ^[0-9]+@ ]]; then
        echo "student"
        return
    fi

    # Pattern: firstname.lastname @ domain = researcher (staff-style)
    if [[ "$username" =~ ^[a-z]+\.[a-z]+@ ]]; then
        echo "researcher"
        return
    fi

    # Default: student
    echo "student"
}

# Main classification function
classify_user() {
    local username="$1"

    # 1. Check if archived (skip entirely)
    if is_archived "$username"; then
        echo "archived"
        return 0
    fi

    # 2. Check override file (deterministic assignment)
    # Use set +e/set -e to prevent exit on get_override_group failure
    set +e
    local override_group
    override_group=$(get_override_group "$username")
    local override_status=$?
    set -e

    if [[ $override_status -eq 0 ]] && [[ -n "$override_group" ]]; then
        echo "$override_group"
        return 0
    fi

    # 3. Pattern matching
    classify_by_pattern "$username"
}

# Check if user already in members file
is_in_members() {
    local username="$1"
    local members_file="$2"

    if [[ -f "$members_file" ]]; then
        grep -qE "^${username}(\s|$)" "$members_file" 2>/dev/null || return 1
        return 0
    else
        return 1
    fi
}

# Add user to members file
add_to_members() {
    local username="$1"
    local group="$2"
    local members_file="${GROUPS_DIR}/${group}.members"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would add: $username -> ${group}.members"
        return
    fi

    # Create file if doesn't exist
    if [[ ! -f "$members_file" ]]; then
        cat > "$members_file" << EOF
# ================================================
# ${group^} Group Members
# ================================================
# Auto-populated by sync-group-membership.sh
# Manual additions are preserved (merge, not replace).
# ================================================

EOF
    fi

    # Add user
    echo "$username" >> "$members_file"
    log "Added $username to ${group}.members" "always"
}

# Main sync function
sync_groups() {
    local added_count=0
    local skipped_count=0
    local archived_count=0

    log "Starting group membership sync" "always"

    # Ensure groups directory exists
    mkdir -p "$GROUPS_DIR"

    # Scan /home for LDAP users
    for dir in /home/*@hertie-school.lan /home/*@HERTIE-SCHOOL.LAN; do
        [[ -d "$dir" ]] || continue

        local username=$(basename "$dir")
        log "Processing: $username"

        # Classify user
        local group=$(classify_user "$username")

        # Handle archived users
        if [[ "$group" == "archived" ]]; then
            log "Skipped (archived): $username"
            archived_count=$((archived_count + 1))
            continue
        fi

        # Check if already in the correct members file
        local members_file="${GROUPS_DIR}/${group}.members"
        if is_in_members "$username" "$members_file"; then
            log "Already in ${group}.members: $username"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Also check if user is in ANY other group (to avoid duplicates)
        local found_elsewhere=false
        for other_group in student researcher faculty admin; do
            if [[ "$other_group" != "$group" ]]; then
                local other_file="${GROUPS_DIR}/${other_group}.members"
                if is_in_members "$username" "$other_file"; then
                    log "Note: $username found in ${other_group}.members (not moving)"
                    found_elsewhere=true
                    break
                fi
            fi
        done

        if [[ "$found_elsewhere" == "true" ]]; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Add to members file
        add_to_members "$username" "$group"
        added_count=$((added_count + 1))
    done

    # Summary
    log "Sync complete: Added=$added_count, Skipped=$skipped_count, Archived=$archived_count" "always"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "DRY RUN - No changes made"
    fi
}

# Also sync to Linux groups (for ACL access)
sync_linux_groups() {
    log "Syncing Linux groups for ACL access"

    for group in student researcher faculty admin; do
        local members_file="${GROUPS_DIR}/${group}.members"
        local linux_group="ds01-${group}"

        [[ -f "$members_file" ]] || continue

        # Check if Linux group exists
        if ! getent group "$linux_group" &>/dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[DRY-RUN] Would create Linux group: $linux_group"
            else
                log "Creating Linux group: $linux_group"
                groupadd "$linux_group" 2>/dev/null || true
            fi
        fi

        # Add users to Linux group
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Extract username (first word)
            local username=$(echo "$line" | awk '{print $1}')
            [[ -z "$username" ]] && continue

            # Check if user exists
            if ! id "$username" &>/dev/null; then
                log "User not found in system: $username"
                continue
            fi

            # Check if already in group
            if groups "$username" 2>/dev/null | grep -q "\b${linux_group}\b"; then
                log "Already in Linux group $linux_group: $username"
                continue
            fi

            # Add to Linux group
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[DRY-RUN] Would add $username to Linux group $linux_group"
            else
                log "Adding $username to Linux group $linux_group"
                usermod -aG "$linux_group" "$username" 2>/dev/null || true
            fi
        done < "$members_file"
    done
}

# Run main sync
sync_groups

# Optionally sync Linux groups (only if running as root)
if [[ $EUID -eq 0 ]]; then
    sync_linux_groups
else
    log "Not running as root - skipping Linux group sync"
fi

log "All done" "always"
