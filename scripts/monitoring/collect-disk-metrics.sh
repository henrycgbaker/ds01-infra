#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/collect-disk-metrics.sh
# Collect disk I/O and space metrics every 5 minutes
# Outputs: /var/log/ds01-infra/metrics/disk/YYYY-MM-DD.log

set -euo pipefail

# Configuration
LOG_DIR="/var/log/ds01-infra/metrics/disk"
DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Collect metrics
{
    echo "=== DISK_METRICS_START|$TIMESTAMP ==="
    
    # Disk space usage
    df -h | awk 'NR>1 {printf "DISK_SPACE|%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6}'
    
    # Disk I/O stats (if iostat available)
    if command -v iostat &> /dev/null; then
        # Run iostat twice, use second output (first is since boot)
        iostat -x 1 2 | awk '/^[sv]d[a-z]/ {
            if (NR>10) 
                printf "DISK_IO|%s|%.2f|%.2f|%.2f|%.2f\n", $1, $4, $5, $6, $14
        }' || true
    fi
    
    # Network I/O (as a bonus - can move to separate collector if needed)
    cat /proc/net/dev | awk 'NR>2 {
        gsub(/:/, " ")
        printf "NET_IO|%s|%s|%s\n", $1, $2, $10
    }'
    
    # Inode usage (important for systems with many small files)
    df -i | awk 'NR>1 {printf "INODE_USAGE|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5}'
    
    echo "=== DISK_METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>&1

# Optional: Compress old logs
find "$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

exit 0
