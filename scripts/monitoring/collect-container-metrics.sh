#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/collect-container-metrics.sh
# Collect Docker container metrics every 5 minutes
# Outputs: /var/log/ds01-infra/metrics/containers/YYYY-MM-DD.log

set -euo pipefail

# Configuration
LOG_DIR="/var/log/ds01-infra/metrics/containers"
DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Check if Docker is available and accessible
if ! command -v docker &> /dev/null; then
    echo "$TIMESTAMP|ERROR|Docker command not found" >> "$LOG_FILE"
    exit 0
fi

if ! docker ps -q &>/dev/null 2>&1; then
    echo "$TIMESTAMP|ERROR|Cannot access Docker daemon" >> "$LOG_FILE"
    exit 0
fi

# Collect metrics
{
    echo "=== CONTAINER_METRICS_START|$TIMESTAMP ==="
    
    # Container stats (one-shot, no streaming)
    docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}" 2>/dev/null | \
    while IFS='|' read -r name cpu mem net block pids; do
        # Get container ID and image
        container_id=$(docker ps --filter "name=^${name}$" --format "{{.ID}}" 2>/dev/null)
        image=$(docker ps --filter "name=^${name}$" --format "{{.Image}}" 2>/dev/null)
        
        echo "CONTAINER_STATS|$name|$container_id|$image|$cpu|$mem|$net|$block|$pids"
    done
    
    # Container list with status
    docker ps -a --format "{{.Names}}|{{.ID}}|{{.Image}}|{{.Status}}|{{.CreatedAt}}" 2>/dev/null | \
    while IFS='|' read -r name id image status created; do
        echo "CONTAINER_LIST|$name|$id|$image|$status|$created"
    done
    
    # Get owner of each container (by matching container name pattern or labels)
    docker ps --format "{{.Names}}" 2>/dev/null | \
    while read -r container_name; do
        # Try to extract username from container name (common pattern: username_*)
        # Adjust pattern based on your naming convention
        if [[ $container_name =~ ^([a-z][a-z0-9_-]+)_ ]]; then
            username="${BASH_REMATCH[1]}"
            echo "CONTAINER_OWNER|$container_name|$username"
        else
            # Check container labels for owner information
            owner=$(docker inspect "$container_name" --format '{{.Config.Labels.owner}}' 2>/dev/null || echo "unknown")
            if [ "$owner" != "unknown" ] && [ -n "$owner" ]; then
                echo "CONTAINER_OWNER|$container_name|$owner"
            fi
        fi
    done
    
    echo "=== CONTAINER_METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>&1

# Optional: Compress old logs
find "$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

exit 0
