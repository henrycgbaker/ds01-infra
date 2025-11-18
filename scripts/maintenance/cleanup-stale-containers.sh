#!/bin/bash
# Cleanup stale containers that have been stopped longer than container_hold_after_stop
# /opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh
#
# This script should be run periodically (e.g., via cron every hour)
# to remove stopped containers that have exceeded their container_hold_after_stop timeout.
# This helps maintain system hygiene and prevents GPU allocation issues.

set -e

# Configuration
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
RESOURCE_PARSER="$INFRA_ROOT/scripts/docker/get_resource_limits.py"
GPU_ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator.py"
CONTAINER_REMOVE="$INFRA_ROOT/scripts/user/container-remove"
METADATA_DIR="/var/lib/ds01/container-metadata"
LOG_DIR="/var/log/ds01"
LOG_FILE="$LOG_DIR/container-stale-cleanup.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Parse duration string (e.g., "12h", "0.5h") to seconds
parse_duration() {
    local duration="$1"

    if [ "$duration" = "never" ] || [ "$duration" = "null" ] || [ "$duration" = "None" ]; then
        echo "-1"  # Never remove
        return
    fi

    # Remove 'h' suffix and convert to seconds
    local hours=$(echo "$duration" | sed 's/h$//')
    local seconds=$(echo "$hours * 3600" | bc)
    echo "${seconds%.*}"  # Remove decimal part
}

# Check if resource parser exists
if [ ! -f "$RESOURCE_PARSER" ]; then
    log "ERROR: Resource parser not found at $RESOURCE_PARSER"
    exit 1
fi

log "Starting stale container cleanup..."

# Find all stopped containers
STOPPED_CONTAINERS=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}" 2>/dev/null || true)

if [ -z "$STOPPED_CONTAINERS" ]; then
    log "✓ No stopped containers found"
    exit 0
fi

REMOVED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

while IFS= read -r container_tag; do
    [ -z "$container_tag" ] && continue

    # Extract username and container name from tag (format: name._.uid)
    if [[ "$container_tag" =~ ^(.+)\._\.([0-9]+)$ ]]; then
        container_name="${BASH_REMATCH[1]}"
        user_id="${BASH_REMATCH[2]}"
    else
        log "WARN: Skipping container with invalid name format: $container_tag"
        ((SKIPPED_COUNT++))
        continue
    fi

    # Get username from UID
    username=$(getent passwd "$user_id" | cut -d: -f1 2>/dev/null || echo "unknown")

    if [ "$username" = "unknown" ]; then
        log "WARN: Cannot find username for UID $user_id (container: $container_tag)"
        ((SKIPPED_COUNT++))
        continue
    fi

    # Get user's container hold timeout
    container_hold=$(python3 "$RESOURCE_PARSER" "$username" --container-hold-time 2>/dev/null || echo "never")
    hold_seconds=$(parse_duration "$container_hold")

    # If never remove, skip
    if [ "$hold_seconds" -eq -1 ]; then
        continue
    fi

    # Check metadata for stopped timestamp
    metadata_file="$METADATA_DIR/${container_tag}.json"

    if [ ! -f "$metadata_file" ]; then
        # No metadata - container might be very old or created before metadata tracking
        # Be conservative and skip it
        continue
    fi

    # Extract stopped_at timestamp from metadata
    stopped_at=$(grep -o '"stopped_at": *"[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4 || echo "")

    if [ -z "$stopped_at" ]; then
        # Container never had GPU or wasn't tracked properly
        # Check docker's "FinishedAt" timestamp instead
        stopped_at=$(docker inspect --format '{{.State.FinishedAt}}' "$container_tag" 2>/dev/null || echo "")

        if [ -z "$stopped_at" ] || [ "$stopped_at" = "0001-01-01T00:00:00Z" ]; then
            # Container never ran or no finish timestamp
            continue
        fi
    fi

    # Calculate elapsed time since stop
    stopped_epoch=$(date -d "$stopped_at" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    elapsed_seconds=$((current_epoch - stopped_epoch))

    # Check if exceeded timeout
    if [ "$elapsed_seconds" -gt "$hold_seconds" ]; then
        log "Removing stale container: $container_name (user: $username, stopped: ${elapsed_seconds}s ago, limit: ${hold_seconds}s)"

        # Remove container with force flag (no prompts)
        if "$CONTAINER_REMOVE" "$container_name" --force &>/dev/null; then
            log "✓ Removed: $container_name"
            ((REMOVED_COUNT++))
        else
            log "ERROR: Failed to remove $container_name"
            ((ERROR_COUNT++))
        fi
    fi

done <<< "$STOPPED_CONTAINERS"

# Summary
if [ "$REMOVED_COUNT" -gt 0 ]; then
    log "✓ Removed $REMOVED_COUNT stale container(s)"
fi

if [ "$SKIPPED_COUNT" -gt 0 ]; then
    log "INFO: Skipped $SKIPPED_COUNT container(s)"
fi

if [ "$ERROR_COUNT" -gt 0 ]; then
    log "WARN: Failed to remove $ERROR_COUNT container(s)"
fi

if [ "$REMOVED_COUNT" -eq 0 ] && [ "$ERROR_COUNT" -eq 0 ]; then
    log "✓ No stale containers to remove"
fi

log "Cleanup completed successfully"
