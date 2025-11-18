#!/bin/bash
# Reconcile GPU allocator state with actual running containers
# Removes stale allocations for containers that no longer exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
GPU_ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu-allocator-smart.py"
GPU_STATE="/var/lib/ds01/gpu-state.json"
METADATA_DIR="/var/lib/ds01/container-metadata"
LOG_FILE="/var/log/ds01/reconciliation.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_color() {
    echo -e "${2}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log_color "Starting GPU state reconciliation" "$CYAN"

# Get all containers with GPU allocations
ALLOCATED_CONTAINERS=$(python3 "$GPU_ALLOCATOR" status 2>/dev/null | grep -E "^\s+- " | sed 's/^\s*- //' | sort)

if [ -z "$ALLOCATED_CONTAINERS" ]; then
    log "No GPU allocations found"
    exit 0
fi

# Get all actual running/stopped DS01 containers
ACTUAL_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep '\._\.' | sort)

# Find stale allocations (allocated but container doesn't exist)
STALE_COUNT=0
RELEASED_COUNT=0

for container in $ALLOCATED_CONTAINERS; do
    if ! echo "$ACTUAL_CONTAINERS" | grep -q "^${container}$"; then
        log_color "Stale allocation detected: $container (container doesn't exist)" "$YELLOW"
        ((STALE_COUNT++))

        # Release the GPU
        if python3 "$GPU_ALLOCATOR" release "$container" >> "$LOG_FILE" 2>&1; then
            log_color "  ✓ Released GPU for: $container" "$GREEN"
            ((RELEASED_COUNT++))

            # Remove metadata file if it exists
            METADATA_FILE="$METADATA_DIR/${container}.json"
            if [ -f "$METADATA_FILE" ]; then
                rm -f "$METADATA_FILE"
                log "  ✓ Removed stale metadata: $METADATA_FILE"
            fi
        else
            log_color "  ✗ Failed to release GPU for: $container" "$RED"
        fi
    fi
done

# Check for orphaned metadata files (metadata exists but no allocation)
if [ -d "$METADATA_DIR" ]; then
    for metadata_file in "$METADATA_DIR"/*.json; do
        [ -f "$metadata_file" ] || continue

        container_name=$(basename "$metadata_file" .json)

        # Check if container still exists
        if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
            log_color "Orphaned metadata detected: $container_name (container doesn't exist)" "$YELLOW"
            rm -f "$metadata_file"
            log_color "  ✓ Removed orphaned metadata: $metadata_file" "$GREEN"
        fi
    done
fi

# Summary
log_color "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CYAN"
if [ $STALE_COUNT -eq 0 ]; then
    log_color "✓ No stale allocations found - system is consistent" "$GREEN"
else
    log_color "Summary: Found $STALE_COUNT stale allocation(s), released $RELEASED_COUNT" "$BLUE"
fi

log_color "Reconciliation complete" "$CYAN"
