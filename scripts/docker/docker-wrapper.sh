#!/bin/bash
# /opt/ds01-infra/scripts/docker/docker-wrapper.sh
# DS01 Docker Wrapper - Universal Resource Enforcement & Ownership Tracking
#
# This wrapper intercepts Docker commands and injects:
# - Per-user cgroup-parent for resource limits
# - Owner labels for permission enforcement
#
# Installation: Copy to /usr/local/bin/docker (takes precedence over /usr/bin/docker)
#
# How it works:
# 1. Intercepts 'docker run' and 'docker create' commands
# 2. Extracts user's group from resource-limits.yaml
# 3. Ensures user's slice exists (ds01-{group}-{user}.slice)
# 4. Injects --cgroup-parent if not already specified
# 5. Injects --label ds01.user=<username> for ownership tracking
# 6. Passes through to real Docker binary
#
# All other Docker commands pass through unchanged.

# Real Docker binary
REAL_DOCKER="/usr/bin/docker"

# DS01 paths
INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
RESOURCE_PARSER="$INFRA_ROOT/scripts/docker/get_resource_limits.py"
CREATE_SLICE="$INFRA_ROOT/scripts/system/create-user-slice.sh"
USERNAME_UTILS="$INFRA_ROOT/scripts/lib/username-utils.sh"
LOG_FILE="/var/log/ds01/docker-wrapper.log"

# Source username sanitization library (fail silently if not available)
if [ -f "$USERNAME_UTILS" ]; then
    source "$USERNAME_UTILS"
else
    # Fallback: simple sanitization if library not available
    sanitize_username_for_slice() {
        echo "$1" | sed 's/@/-at-/g; s/\./-/g; s/[^a-zA-Z0-9_:-]/-/g; s/--*/-/g; s/^-//; s/-$//'
    }
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Log function (silent unless DEBUG_DS01_WRAPPER=1)
log_debug() {
    if [ "${DEBUG_DS01_WRAPPER:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Get current user info
CURRENT_USER=$(whoami)
CURRENT_UID=$(id -u)

# Check if this is a 'run' or 'create' command that needs cgroup injection
needs_cgroup_injection() {
    local cmd="$1"
    # Only inject for 'run' and 'create' subcommands
    [[ "$cmd" == "run" ]] || [[ "$cmd" == "create" ]]
}

# Check if --cgroup-parent is already specified
has_cgroup_parent() {
    for arg in "$@"; do
        case "$arg" in
            --cgroup-parent=*|--cgroup-parent)
                return 0
                ;;
        esac
    done
    return 1
}

# Check if ds01.user label is already specified
has_owner_label() {
    for arg in "$@"; do
        case "$arg" in
            --label=ds01.user=*|--label)
                # Check next arg for ds01.user=
                if [[ "$arg" == "--label" ]]; then
                    continue
                fi
                if [[ "$arg" == ds01.user=* ]]; then
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# Get user's group from resource-limits.yaml
get_user_group() {
    local user="$1"

    if [ -f "$RESOURCE_PARSER" ] && [ -f "$CONFIG_FILE" ]; then
        python3 "$RESOURCE_PARSER" "$user" --group 2>/dev/null || echo "student"
    else
        echo "student"
    fi
}

# Ensure user slice exists
ensure_user_slice() {
    local group="$1"
    local user="$2"

    if [ -f "$CREATE_SLICE" ]; then
        # Try to create slice (requires sudo, will fail silently if not root)
        # The slice creation is idempotent - exits 0 if already exists
        sudo "$CREATE_SLICE" "$group" "$user" 2>/dev/null || true
    fi
}

# Check if user is an admin (ds01-admin group)
is_admin() {
    groups "$CURRENT_USER" 2>/dev/null | grep -qE '\bds01-admin\b'
}

# Filter docker ps/container ls to show only user's containers (non-admins)
filter_container_list() {
    # Admins see all containers
    if is_admin; then
        log_debug "Admin user - showing all containers"
        exec "$REAL_DOCKER" "$@"
    fi

    # Non-admins: filter by ds01.user label
    log_debug "Filtering container list for user $CURRENT_USER"
    exec "$REAL_DOCKER" "$@" --filter "label=ds01.user=$CURRENT_USER"
}

# Main logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$REAL_DOCKER"
    fi

    # Get the Docker subcommand
    local subcommand="$1"

    # Filter 'ps' command for non-admins
    if [[ "$subcommand" == "ps" ]]; then
        filter_container_list "$@"
    fi

    # Filter 'container ls' or 'container list' for non-admins
    if [[ "$subcommand" == "container" ]] && [[ "${2:-}" == "ls" || "${2:-}" == "list" ]]; then
        filter_container_list "$@"
    fi

    # Check if we need to inject for container creation
    if needs_cgroup_injection "$subcommand"; then
        log_debug "Intercepting '$subcommand' for user $CURRENT_USER"

        # Get user's group
        USER_GROUP=$(get_user_group "$CURRENT_USER")
        log_debug "User group: $USER_GROUP"

        # Build the cgroup-parent path (with sanitized username for systemd compatibility)
        SANITIZED_USER=$(sanitize_username_for_slice "$CURRENT_USER")
        SLICE_NAME="ds01-${USER_GROUP}-${SANITIZED_USER}.slice"
        log_debug "Sanitized user: $SANITIZED_USER"

        # Ensure the slice exists
        ensure_user_slice "$USER_GROUP" "$CURRENT_USER"
        log_debug "Ensured slice: $SLICE_NAME"

        # Build injection arguments
        local INJECT_ARGS=()

        # Inject --cgroup-parent if not already specified
        if ! has_cgroup_parent "$@"; then
            INJECT_ARGS+=("--cgroup-parent=$SLICE_NAME")
            log_debug "Injecting cgroup-parent: $SLICE_NAME"
        fi

        # Inject owner label if not already specified
        if ! has_owner_label "$@"; then
            INJECT_ARGS+=("--label" "ds01.user=$CURRENT_USER")
            INJECT_ARGS+=("--label" "ds01.managed=true")
            log_debug "Injecting owner label: ds01.user=$CURRENT_USER"
        fi

        # Remove subcommand from args
        shift

        # Execute with injected args
        log_debug "Executing: $REAL_DOCKER $subcommand ${INJECT_ARGS[*]} $*"
        exec "$REAL_DOCKER" "$subcommand" "${INJECT_ARGS[@]}" "$@"
    else
        # Pass through unchanged
        log_debug "Pass-through: $REAL_DOCKER $*"
        exec "$REAL_DOCKER" "$@"
    fi
}

# Run main
main "$@"
