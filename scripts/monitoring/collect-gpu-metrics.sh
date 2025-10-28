#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/collect-gpu-metrics.sh
# Collect GPU metrics every 5 minutes
# Outputs: /var/log/ds01-infra/metrics/gpu/YYYY-MM-DD.log

set -euo pipefail

# Configuration
LOG_DIR="/var/log/ds01-infra/metrics/gpu"
DATE=$(date '+%Y-%m-%d')
LOG_FILE="$LOG_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
    echo "$TIMESTAMP|ERROR|nvidia-smi not found" >> "$LOG_FILE"
    exit 0
fi

# Collect metrics
{
    echo "=== GPU_METRICS_START|$TIMESTAMP ==="
    
    # GPU device stats
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit \
               --format=csv,noheader,nounits 2>/dev/null | \
    while IFS=',' read -r idx name util mem_used mem_total temp power_draw power_limit; do
        # Clean whitespace
        idx=$(echo "$idx" | xargs)
        name=$(echo "$name" | xargs)
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        temp=$(echo "$temp" | xargs)
        power_draw=$(echo "$power_draw" | xargs)
        power_limit=$(echo "$power_limit" | xargs)
        
        echo "GPU_DEVICE|$idx|$name|$util|$mem_used|$mem_total|$temp|$power_draw|$power_limit"
    done
    
    # GPU processes with user information
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null | \
    while IFS=',' read -r pid proc mem; do
        pid=$(echo "$pid" | xargs)
        proc=$(echo "$proc" | xargs)
        mem=$(echo "$mem" | xargs)
        
        # Get username and command for this PID
        if ps -p "$pid" &>/dev/null; then
            username=$(ps -p "$pid" -o user= | xargs)
            cmd=$(ps -p "$pid" -o args= | cut -c1-100)
            echo "GPU_PROCESS|$pid|$username|$proc|$mem|$cmd"
        fi
    done
    
    # Per-user GPU memory aggregation
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null | \
    while IFS=',' read -r pid mem; do
        pid=$(echo "$pid" | xargs)
        mem=$(echo "$mem" | xargs)
        
        if [ -n "$pid" ] && ps -p "$pid" &>/dev/null; then
            username=$(ps -p "$pid" -o user= | xargs)
            echo "USER_GPU|$username|$pid|$mem"
        fi
    done
    
    echo "=== GPU_METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>&1

# Optional: Compress old logs (older than 1 day, not already compressed)
find "$LOG_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true

exit 0
