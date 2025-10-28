#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/collect-cpu-metrics.sh
# Collect CPU metrics every 5 minutes
# Outputs: /var/log/ds01-infra/metrics/cpu/YYYY-MM-DD.log

set -euo pipefail

# Configuration
LOG_DIR="/var/log/ds01-infra/metrics/cpu"
DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Collect metrics
{
    echo "=== CPU_METRICS_START|$TIMESTAMP ==="
    
    # Overall CPU utilization
    cpu_stats=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    load_avg=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
    echo "CPU_OVERALL|$cpu_stats|$load_avg"
    
    # Per-core CPU (if mpstat available)
    if command -v mpstat &> /dev/null; then
        mpstat -P ALL 1 1 2>/dev/null | awk '/^[0-9]/ && !/Average/ {printf "CPU_CORE|%s|%.2f\n", $2, 100-$NF}' || true
    fi
    
    # Top 10 processes by CPU
    ps aux --sort=-%cpu | head -11 | tail -10 | \
    awk '{printf "TOP_CPU|%s|%s|%s|%s|", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print ""}'
    
    # Per-user CPU aggregation
    ps -eo user,pid | tail -n +2 | awk '{print $1}' | sort -u | \
    while read -r username; do
        # Skip system users (UID < 1000)
        if id "$username" &>/dev/null && [ "$(id -u "$username")" -ge 1000 ]; then
            cpu=$(ps -u "$username" -o %cpu= | awk '{sum+=$1} END {printf "%.2f", sum}')
            procs=$(ps -u "$username" -o pid= | wc -l)
            echo "USER_CPU|$username|$cpu|$procs"
        fi
    done
    
    echo "=== CPU_METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>&1

# Optional: Compress old logs
find "$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

exit 0
