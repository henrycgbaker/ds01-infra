#!/bin/bash
# Cleanup stale containers that have been stopped longer than container_hold_after_stop
# /opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh
#
# This script should be run periodically (e.g., via cron every hour)
# to remove stopped containers that have exceeded their container_hold_after_stop timeout.
# Uses Docker-native queries (no metadata files needed).

set -e

# Configuration
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
LOG_DIR="/var/log/ds01"
LOG_FILE="$LOG_DIR/cleanup-stale-containers.log"

# Source shared library for colors and utilities
source "$INFRA_ROOT/scripts/lib/init.sh"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Get container hold timeout for user (in hours)
get_container_hold_timeout() {
    local username="$1"
    # Use centralized get_resource_limits.py CLI instead of embedded heredoc
    python3 "$INFRA_ROOT/scripts/docker/get_resource_limits.py" "$username" --container-hold-time
}

# Parse duration string (e.g., "12h", "0.5h") to seconds
# Wrapper around centralized ds01_parse_duration from init.sh
parse_duration() {
    local duration="$1"
    ds01_parse_duration "$duration"
}

log "Starting stale container cleanup (Docker-native)..."

# Find all stopped DS01-managed containers (have aime.mlc.USER label)
STOPPED_CONTAINERS=$(docker ps -a --filter "status=exited" --filter "status=created" --filter "label=aime.mlc.USER" --format "{{.Names}}" 2>/dev/null || true)

if [ -z "$STOPPED_CONTAINERS" ]; then
    log "✓ No stopped DS01-managed containers found"
    exit 0
fi

REMOVED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

while IFS= read -r container_tag; do
    [ -z "$container_tag" ] && continue

    # Get username from Docker label (not from container name UID)
    username=$(docker inspect --format '{{index .Config.Labels "aime.mlc.USER"}}' "$container_tag" 2>/dev/null || echo "")

    if [ -z "$username" ] || [ "$username" = "<no value>" ]; then
        log "WARN: Cannot find username label for container: $container_tag"
        ((SKIPPED_COUNT += 1))
        continue
    fi

    # Get user's container hold timeout
    container_hold=$(get_container_hold_timeout "$username")
    hold_seconds=$(parse_duration "$container_hold")

    # If never remove, skip
    if [ "$hold_seconds" -eq -1 ]; then
        log "Container $container_tag (user: $username) has indefinite hold, skipping"
        continue
    fi

    # Get FinishedAt timestamp from Docker state (automatic)
    finished_at=$(docker inspect --format '{{.State.FinishedAt}}' "$container_tag" 2>/dev/null || echo "")

    if [ -z "$finished_at" ] || [ "$finished_at" = "0001-01-01T00:00:00Z" ]; then
        log "WARN: Container $container_tag has no valid FinishedAt timestamp, skipping"
        ((SKIPPED_COUNT += 1))
        continue
    fi

    # Calculate elapsed time since stop
    stopped_epoch=$(date -d "$finished_at" +%s 2>/dev/null || echo "0")

    if [ "$stopped_epoch" -eq 0 ]; then
        log "WARN: Could not parse FinishedAt for $container_tag, skipping"
        ((SKIPPED_COUNT += 1))
        continue
    fi

    current_epoch=$(date +%s)
    elapsed_seconds=$((current_epoch - stopped_epoch))
    elapsed_hours=$((elapsed_seconds / 3600))

    # Check if exceeded timeout
    if [ "$elapsed_seconds" -gt "$hold_seconds" ]; then
        log "Removing stale container: $container_tag (user: $username, stopped: ${elapsed_hours}h ago, limit: $container_hold)"

        # Remove container directly (GPU already freed by cleanup-stale-gpu-allocations if applicable)
        if docker rm "$container_tag" &>/dev/null; then
            log "✓ Removed: $container_tag"
            logger -t ds01-cleanup "Removed stale container: $container_tag (user: $username, stopped: ${elapsed_seconds}s ago)"
            ((REMOVED_COUNT += 1))
        else
            log "ERROR: Failed to remove $container_tag"
            ((ERROR_COUNT += 1))
        fi
    else
        # Still within hold period
        time_remaining=$((hold_seconds - elapsed_seconds))
        hours_remaining=$((time_remaining / 3600))
        log "Container $container_tag (user: $username): ${elapsed_hours}h stopped, will remove in ${hours_remaining}h"
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
