#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/collect-memory-metrics.sh
# Collect memory metrics every 5 minutes
# Outputs: /var/log/ds01-infra/metrics/memory/YYYY-MM-DD.log

set -euo pipefail

# Configuration
LOG_DIR="/var/log/ds01-infra/metrics/memory"
DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Collect metrics
{
    echo "=== MEMORY_METRICS_START|$TIMESTAMP ==="
    
    # Overall memory stats
    # Format: MEMORY_OVERALL|total|used|free|buff_cache|available
    free -m | awk '/^Mem:/ {printf "MEMORY_OVERALL|%d|%d|%d|%d|%d\n", $2, $3, $4, $6, $7}'
    
    # Swap stats
    # Format: MEMORY_SWAP|total|used|free
    free -m | awk '/^Swap:/ {printf "MEMORY_SWAP|%d|%d|%d\n", $2, $3, $4}'
    
    # Top 10 processes by memory
    ps aux --sort=-%mem | head -11 | tail -10 | \
    awk '{printf "TOP_MEM|%s|%s|%s|%s|", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print ""}'
    
    # Per-user memory aggregation
    ps -eo user,pid | tail -n +2 | awk '{print $1}' | sort -u | \
    while read -r username; do
        # Skip system users (UID < 1000)
        if id "$username" &>/dev/null && [ "$(id -u "$username")" -ge 1000 ]; then
            # Memory usage in MB
            mem=$(ps -u "$username" -o rss= | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
            procs=$(ps -u "$username" -o pid= | wc -l)
            echo "USER_MEMORY|$username|$mem|$procs"
        fi
    done
    
    echo "=== MEMORY_METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>&1

# Optional: Compress old logs
find "$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

exit 0
