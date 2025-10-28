#!/bin/bash
# opt/ds01-infra/scripts/log_metrics_5min.sh
# Collect comprehensive server metrics every 5 minutes
# Outputs structured data for easy parsing

BASE_DIR=~/server_infra/logs/metrics
DATE=$(date '+%Y%m%d')
LOG_FILE="$BASE_DIR/${DATE}.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create logs directory
mkdir -p "$BASE_DIR"

# Helper function to get per-user stats
get_user_stats() {
    # Get all users with running processes (excluding system users)
    ps -eo user,pid | tail -n +2 | awk '{print $1}' | sort -u | \
    while read -r username; do
        # Skip system users
        if id "$username" &>/dev/null && [ "$(id -u "$username")" -ge 1000 ]; then
            # CPU usage for user
            cpu=$(ps -u "$username" -o %cpu= | awk '{sum+=$1} END {printf "%.2f", sum}')
            # Memory usage for user (in MB)
            mem=$(ps -u "$username" -o rss= | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
            # Process count
            procs=$(ps -u "$username" -o pid= | wc -l)
            
            echo "USER_STATS|$username|$cpu|$mem|$procs"
        fi
    done
}

# Helper function to get per-user GPU usage
get_user_gpu_stats() {
    if ! command -v nvidia-smi &> /dev/null; then
        return
    fi
    
    # Get GPU processes with their PIDs
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null | \
    while IFS=',' read -r pid mem; do
        pid=$(echo "$pid" | xargs)
        mem=$(echo "$mem" | xargs)
        
        # Get username for this PID
        if [ -n "$pid" ] && ps -p "$pid" &>/dev/null; then
            username=$(ps -p "$pid" -o user= | xargs)
            echo "USER_GPU|$username|$pid|$mem"
        fi
    done
}

# Start logging
{
    echo "=== METRICS_START|$TIMESTAMP ==="
    
    # ==================== GPU METRICS ====================
    if command -v nvidia-smi &> /dev/null; then
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
        
        # GPU processes
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
        
        # Per-user GPU aggregation
        get_user_gpu_stats
    fi
    
    # ==================== CPU METRICS ====================
    # Overall CPU utilization
    cpu_stats=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    load_avg=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
    echo "CPU_OVERALL|$cpu_stats|$load_avg"
    
    # Per-core CPU (if available)
    mpstat -P ALL 1 1 2>/dev/null | awk '/^[0-9]/ && !/Average/ {printf "CPU_CORE|%s|%.2f\n", $2, 100-$NF}' || true
    
    # Top 10 processes by CPU
    ps aux --sort=-%cpu | head -11 | tail -10 | \
    awk '{printf "TOP_CPU|%s|%s|%s|%s|", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print ""}'
    
    # ==================== MEMORY METRICS ====================
    # Overall memory
    free -m | awk '/^Mem:/ {printf "MEMORY_OVERALL|%d|%d|%d|%d|%d\n", $2, $3, $4, $6, $7}'
    free -m | awk '/^Swap:/ {printf "MEMORY_SWAP|%d|%d|%d\n", $2, $3, $4}'
    
    # Top 10 processes by memory
    ps aux --sort=-%mem | head -11 | tail -10 | \
    awk '{printf "TOP_MEM|%s|%s|%s|%s|", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print ""}'
    
    # ==================== DISK I/O METRICS ====================
    if command -v iostat &> /dev/null; then
        iostat -x 1 2 | awk '/^[sv]d[a-z]/ {if (NR>10) printf "DISK_IO|%s|%.2f|%.2f|%.2f|%.2f\n", $1, $4, $5, $6, $14}' || true
    fi
    
    # ==================== NETWORK I/O METRICS ====================
    # Capture current network stats (we'll calculate delta next time)
    cat /proc/net/dev | awk 'NR>2 {gsub(/:/, " "); printf "NET_IO|%s|%s|%s\n", $1, $2, $10}'
    
    # ==================== DOCKER CONTAINER METRICS ====================
    if command -v docker &> /dev/null && docker ps -q &>/dev/null 2>&1; then
        docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}" 2>/dev/null | \
        while IFS='|' read -r name cpu mem net block; do
            echo "DOCKER_CONTAINER|$name|$cpu|$mem|$net|$block"
        done
    fi
    
    # ==================== PER-USER RESOURCE STATS ====================
    get_user_stats
    
    echo "=== METRICS_END|$TIMESTAMP ==="
    
} >> "$LOG_FILE" 2>/dev/null

# Optional: Compress logs older than 1 day
find "$BASE_DIR" -name "*.log" -type f -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null || true