#!/bin/bash
# /opt/ds01-infra/scripts/docker/docker-wrapper.sh
# DS01 Docker Wrapper - Universal Resource Enforcement
#
# This wrapper intercepts Docker commands and injects per-user cgroup-parent
# for ALL containers created on the system, regardless of interface used.
#
# Installation: Copy to /usr/local/bin/docker (takes precedence over /usr/bin/docker)
#
# How it works:
# 1. Intercepts 'docker run' and 'docker create' commands
# 2. Extracts user's group from resource-limits.yaml
# 3. Ensures user's slice exists (ds01-{group}-{user}.slice)
# 4. Injects --cgroup-parent if not already specified
# 5. Passes through to real Docker binary
#
# All other Docker commands pass through unchanged.

# Real Docker binary
REAL_DOCKER="/usr/bin/docker"

# DS01 paths
INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
RESOURCE_PARSER="$INFRA_ROOT/scripts/docker/get_resource_limits.py"
CREATE_SLICE="$INFRA_ROOT/scripts/system/create-user-slice.sh"
LOG_FILE="/var/log/ds01/docker-wrapper.log"

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

# Main logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$REAL_DOCKER"
    fi

    # Get the Docker subcommand
    local subcommand="$1"

    # Check if we need to inject cgroup-parent
    if needs_cgroup_injection "$subcommand" && ! has_cgroup_parent "$@"; then
        log_debug "Intercepting '$subcommand' for user $CURRENT_USER"

        # Get user's group
        USER_GROUP=$(get_user_group "$CURRENT_USER")
        log_debug "User group: $USER_GROUP"

        # Build the cgroup-parent path
        SLICE_NAME="ds01-${USER_GROUP}-${CURRENT_USER}.slice"

        # Ensure the slice exists
        ensure_user_slice "$USER_GROUP" "$CURRENT_USER"
        log_debug "Ensured slice: $SLICE_NAME"

        # Inject --cgroup-parent after the subcommand
        # docker run [OPTIONS] IMAGE [COMMAND]
        # docker create [OPTIONS] IMAGE [COMMAND]
        shift  # Remove subcommand from args

        log_debug "Executing: $REAL_DOCKER $subcommand --cgroup-parent=$SLICE_NAME $*"
        exec "$REAL_DOCKER" "$subcommand" "--cgroup-parent=$SLICE_NAME" "$@"
    else
        # Pass through unchanged
        log_debug "Pass-through: $REAL_DOCKER $*"
        exec "$REAL_DOCKER" "$@"
    fi
}

# Run main
main "$@"
