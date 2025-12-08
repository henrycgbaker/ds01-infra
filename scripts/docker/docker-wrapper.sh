#!/bin/bash
# /opt/ds01-infra/scripts/docker/docker-wrapper.sh
# DS01 Docker Wrapper - Universal Resource Enforcement & Ownership Tracking
#
# Phase A+B: Cgroup injection + Owner labels + Visibility filtering (Dec 2025)
#
# This wrapper intercepts Docker commands and:
# - Injects per-user cgroup-parent for resource limits
# - Injects owner labels (ds01.user, ds01.managed) for ownership tracking
# - Filters 'docker ps' to show only user's containers (non-admins)
#
# Installation: Copy to /usr/local/bin/docker (takes precedence over /usr/bin/docker)
#
# How it works:
# 1. Intercepts 'docker run' and 'docker create' commands
# 2. Extracts user's group from resource-limits.yaml
# 3. Ensures user's slice exists (ds01-{group}-{user}.slice)
# 4. Injects --cgroup-parent if not already specified
# 5. Injects --label ds01.user=<username> for ownership tracking
# 6. Filters 'docker ps' for non-admin users (ds01-admin group bypasses)
# 7. Passes through to real Docker binary
#
# Admin users (in ds01-admin group) see all containers.
# Non-admin users see only containers with their ds01.user label.

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

# Check if ds01.user label is already specified in args
has_owner_label() {
    local prev_arg=""
    for arg in "$@"; do
        # Check for --label=ds01.user=*
        if [[ "$arg" == "--label=ds01.user="* ]]; then
            return 0
        fi
        # Check for --label ds01.user=* (two separate args)
        if [[ "$prev_arg" == "--label" ]] && [[ "$arg" == "ds01.user="* ]]; then
            return 0
        fi
        prev_arg="$arg"
    done
    return 1
}

# Extract owner from devcontainer.local_folder label if present
# VS Code dev containers set this label to the project path: /home/USER/...
get_devcontainer_owner() {
    local prev_arg=""
    for arg in "$@"; do
        # Check for --label=devcontainer.local_folder=/home/USER/...
        if [[ "$arg" == "--label=devcontainer.local_folder=/home/"* ]]; then
            local path="${arg#--label=devcontainer.local_folder=}"
            echo "$path" | cut -d/ -f3
            return 0
        fi
        # Check for --label devcontainer.local_folder=/home/USER/... (two separate args)
        if [[ "$prev_arg" == "--label" ]] && [[ "$arg" == "devcontainer.local_folder=/home/"* ]]; then
            local path="${arg#devcontainer.local_folder=}"
            echo "$path" | cut -d/ -f3
            return 0
        fi
        prev_arg="$arg"
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

# Phase B: Container list filtering - DISABLED (Dec 2025)
#
# Previously filtered 'docker ps' to show only user's containers for non-admins.
# This was removed because:
# 1. It broke GPU state reader (couldn't see other users' GPU allocations)
# 2. OPA policy already prevents operations on other users' containers
# 3. Visibility != Access - seeing containers is harmless, OPA controls actions
# 4. Simpler architecture = fewer bugs
#
# Access control is now handled entirely by OPA authorization plugin.

# Check if user is an admin (ds01-admin group) - kept for potential future use
is_admin() {
    groups "$CURRENT_USER" 2>/dev/null | grep -qE '\bds01-admin\b'
}

# No longer filtering - all users see all containers
# OPA handles access control for operations
filter_container_list() {
    log_debug "Passing through container list (no filtering)"
    exec "$REAL_DOCKER" "$@"
}

# Main logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$REAL_DOCKER"
    fi

    # Get the Docker subcommand
    local subcommand="$1"

    # Phase B: Filter 'ps' command for non-admins
    if [[ "$subcommand" == "ps" ]]; then
        filter_container_list "$@"
    fi

    # Phase B: Filter 'container ls' or 'container list' for non-admins
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
            # Check if this is a VS Code devcontainer with a local_folder path
            local devcontainer_owner
            devcontainer_owner=$(get_devcontainer_owner "$@")
            if [ -n "$devcontainer_owner" ]; then
                # VS Code container - extract owner from devcontainer.local_folder path
                INJECT_ARGS+=("--label" "ds01.user=$devcontainer_owner")
                INJECT_ARGS+=("--label" "ds01.managed=devcontainer")
                log_debug "Injecting owner label from devcontainer: ds01.user=$devcontainer_owner"
            else
                # Regular container - use current user
                INJECT_ARGS+=("--label" "ds01.user=$CURRENT_USER")
                INJECT_ARGS+=("--label" "ds01.managed=true")
                log_debug "Injecting owner label: ds01.user=$CURRENT_USER"
            fi
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
