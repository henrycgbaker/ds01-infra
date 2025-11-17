#!/bin/bash
# Cleanup stale GPU allocations for stopped containers that exceeded hold timeout
# /opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh
#
# This script should be run periodically (e.g., via cron every hour)
# to release GPU allocations from stopped containers that have exceeded
# their gpu_hold_after_stop timeout.

set -e

# Configuration
# Resolve symlinks to get actual script location
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
GPU_ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator.py"
LOG_DIR="/var/log/ds01"
LOG_FILE="$LOG_DIR/gpu-stale-cleanup.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Check if GPU allocator exists
if [ ! -f "$GPU_ALLOCATOR" ]; then
    log "ERROR: GPU allocator not found at $GPU_ALLOCATOR"
    exit 1
fi

log "Starting stale GPU allocation cleanup..."

# Release stale allocations
OUTPUT=$(python3 "$GPU_ALLOCATOR" release-stale 2>&1)
EXITCODE=$?

if [ $EXITCODE -eq 0 ]; then
    # Log the output
    echo "$OUTPUT" | while IFS= read -r line; do
        log "$line"
    done

    # Count releases from output
    RELEASE_COUNT=$(echo "$OUTPUT" | grep "Released" | wc -l)

    # Default to 0 if empty
    if [ -z "$RELEASE_COUNT" ]; then
        RELEASE_COUNT=0
    fi

    if [ "$RELEASE_COUNT" -gt 0 ]; then
        log "✓ Released $RELEASE_COUNT stale GPU allocation(s)"
    else
        log "✓ No stale allocations found"
    fi
else
    log "ERROR: GPU allocator failed with exit code $EXITCODE"
    log "$OUTPUT"
    exit 1
fi

log "Cleanup completed successfully"
