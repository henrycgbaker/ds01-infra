#!/bin/bash
# Container Operation Logger - Single source of truth for all container operations
# All container create/start/stop/remove operations should log here

CONTAINER_LOG="/var/log/ds01/container-operations.log"

# Ensure log directory exists
mkdir -p "$(dirname "$CONTAINER_LOG")"

# Log format: timestamp|operation|user|container|gpu_id|status|details
log_container_operation() {
    local operation="$1"    # create, start, stop, remove, failed_create, etc.
    local user="$2"         # username
    local container="$3"    # container name with ._.uid
    local gpu_id="$4"       # GPU ID or "none"
    local status="$5"       # success, failed, warning
    local details="$6"      # Additional details/error message

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Pipe-delimited format for easy parsing
    echo "$timestamp|$operation|$user|$container|$gpu_id|$status|$details" >> "$CONTAINER_LOG"

    # Also log to syslog for centralized logging
    logger -t ds01-container "$operation|$user|$container|$gpu_id|$status|$details" 2>/dev/null || true
}

# Export function for use in other scripts
export -f log_container_operation 2>/dev/null || true
