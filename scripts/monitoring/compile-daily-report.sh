#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/compile-daily-report.sh
# Compile daily report from modular metric collectors
# Run at 23:55 daily via cron

set -euo pipefail

# Configuration
METRICS_BASE="/var/log/ds01-infra/metrics"
REPORTS_DIR="/var/log/ds01-infra/reports/daily"
DATE=${1:-$(date '+%Y-%m-%d')}
REPORT_FILE="$REPORTS_DIR/${DATE}.md"

# Individual metric log files
GPU_LOG="$METRICS_BASE/gpu/${DATE}.log"
CPU_LOG="$METRICS_BASE/cpu/${DATE}.log"
MEMORY_LOG="$METRICS_BASE/memory/${DATE}.log"
DISK_LOG="$METRICS_BASE/disk/${DATE}.log"
CONTAINER_LOG="$METRICS_BASE/containers/${DATE}.log"

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Helper: Decompress if needed
decompress_if_needed() {
    local log_file="$1"
    if [ -f "${log_file}.gz" ] && [ ! -f "$log_file" ]; then
        gunzip -c "${log_file}.gz" > "${log_file}.tmp"
        echo "${log_file}.tmp"
    elif [ -f "$log_file" ]; then
        echo "$log_file"
    else
        echo ""
    fi
}

# Prepare log files (decompress if needed)
GPU_LOG=$(decompress_if_needed "$GPU_LOG")
CPU_LOG=$(decompress_if_needed "$CPU_LOG")
MEMORY_LOG=$(decompress_if_needed "$MEMORY_LOG")
DISK_LOG=$(decompress_if_needed "$DISK_LOG")
CONTAINER_LOG=$(decompress_if_needed "$CONTAINER_LOG")

# Track temp files for cleanup
TEMP_FILES=()
[[ "$GPU_LOG" == *.tmp ]] && TEMP_FILES+=("$GPU_LOG")
[[ "$CPU_LOG" == *.tmp ]] && TEMP_FILES+=("$CPU_LOG")
[[ "$MEMORY_LOG" == *.tmp ]] && TEMP_FILES+=("$MEMORY_LOG")
[[ "$DISK_LOG" == *.tmp ]] && TEMP_FILES+=("$DISK_LOG")
[[ "$CONTAINER_LOG" == *.tmp ]] && TEMP_FILES+=("$CONTAINER_LOG")

# Cleanup function
cleanup() {
    for f in "${TEMP_FILES[@]}"; do
        [ -f "$f" ] && rm -f "$f"
    done
}
trap cleanup EXIT

# Analysis functions
analyze_gpu() {
    [ ! -f "$GPU_LOG" ] && echo "*No GPU data available*" && return
    
    echo "## 🎮 GPU Utilization Summary"
    echo ""
    
    awk -F'|' '/^GPU_DEVICE\|/ {
        gpu=$2
        util=$4
        mem_used=$5
        mem_total=$6
        temp=$7
        power=$8
        
        util_sum[gpu] += util
        util_count[gpu]++
        if (util > util_max[gpu] || util_max[gpu] == "") util_max[gpu] = util
        if (util < util_min[gpu] || util_min[gpu] == "") util_min[gpu] = util
        
        mem_sum[gpu] += mem_used
        mem_max[gpu] = mem_total
        
        temp_sum[gpu] += temp
        if (temp > temp_max[gpu] || temp_max[gpu] == "") temp_max[gpu] = temp
        
        power_sum[gpu] += power
        if (power > power_max[gpu] || power_max[gpu] == "") power_max[gpu] = power
    }
    END {
        print "| GPU | Avg Util | Max Util | Avg Mem Used | Max Mem | Avg Temp | Max Temp | Avg Power | Samples |"
        print "|-----|----------|----------|--------------|---------|----------|----------|-----------|---------|"
        for (g in util_sum) {
            printf "| %s | %.1f%% | %.1f%% | %.0f MB | %.0f MB | %.1f°C | %.1f°C | %.1f W | %d |\n",
                g,
                util_sum[g]/util_count[g],
                util_max[g],
                mem_sum[g]/util_count[g],
                mem_max[g],
                temp_sum[g]/util_count[g],
                temp_max[g],
                power_sum[g]/util_count[g],
                util_count[g]
        }
    }' "$GPU_LOG"
    
    echo ""
    
    # Per-user GPU usage
    echo "### Per-User GPU Memory Usage"
    echo ""
    
    awk -F'|' '/^USER_GPU\|/ {
        user = $2
        mem = $4
        user_mem[user] += mem
        user_count[user]++
    }
    END {
        if (length(user_mem) > 0) {
            print "| User | Total GPU Memory | Avg per Sample | Samples |"
            print "|------|------------------|----------------|---------|"
            for (u in user_mem) {
                printf "| %s | %.0f MB | %.0f MB | %d |\n",
                    u, user_mem[u], user_mem[u]/user_count[u], user_count[u]
            }
        } else {
            print "*No GPU usage detected*"
        }
    }' "$GPU_LOG"
    
    echo ""
}

analyze_cpu() {
    [ ! -f "$CPU_LOG" ] && echo "*No CPU data available*" && return
    
    echo "## 💻 CPU Utilization Summary"
    echo ""
    
    awk -F'|' '/^CPU_OVERALL\|/ {
        util = $2
        split($3, load, " ")
        
        util_sum += util
        util_count++
        if (util > util_max || util_max == "") util_max = util
        if (util < util_min || util_min == "") util_min = util
        
        load1_sum += load[1]
        load5_sum += load[2]
        load15_sum += load[3]
        if (load[1] > load1_max || load1_max == "") load1_max = load[1]
    }
    END {
        if (util_count > 0) {
            printf "- **Average CPU Utilization**: %.1f%%\n", util_sum/util_count
            printf "- **Peak CPU Utilization**: %.1f%%\n", util_max
            printf "- **Minimum CPU Utilization**: %.1f%%\n", util_min
            printf "- **Average Load (1/5/15 min)**: %.2f / %.2f / %.2f\n", 
                load1_sum/util_count, load5_sum/util_count, load15_sum/util_count
            printf "- **Peak Load (1 min)**: %.2f\n", load1_max
            printf "- **Samples**: %d\n", util_count
        }
    }' "$CPU_LOG"
    
    echo ""
    
    # Per-user CPU usage
    echo "### Per-User CPU Usage"
    echo ""
    
    awk -F'|' '/^USER_CPU\|/ {
        user = $2
        cpu = $3
        user_cpu[user] += cpu
        user_count[user]++
        if (cpu > user_cpu_max[user]) user_cpu_max[user] = cpu
    }
    END {
        if (length(user_cpu) > 0) {
            print "| User | Avg CPU % | Peak CPU % | Samples |"
            print "|------|-----------|------------|---------|"
            for (u in user_cpu) {
                printf "| %s | %.1f%% | %.1f%% | %d |\n",
                    u, user_cpu[u]/user_count[u], user_cpu_max[u], user_count[u]
            }
        }
    }' "$CPU_LOG"
    
    echo ""
}

analyze_memory() {
    [ ! -f "$MEMORY_LOG" ] && echo "*No memory data available*" && return
    
    echo "## 🧠 Memory Summary"
    echo ""
    
    awk -F'|' '/^MEMORY_OVERALL\|/ {
        total = $2
        used = $3
        
        used_sum += used
        used_count++
        if (used > used_max || used_max == "") used_max = used
        
        util = (used / total) * 100
        util_sum += util
        if (util > util_max || util_max == "") util_max = util
    }
    /^MEMORY_SWAP\|/ {
        swap_total = $2
        swap_used = $3
        swap_sum += swap_used
        swap_count++
        if (swap_used > swap_max || swap_max == "") swap_max = swap_used
    }
    END {
        if (used_count > 0) {
            printf "- **Total Memory**: %d MB (%.1f GB)\n", total, total/1024
            printf "- **Average Used**: %.0f MB (%.1f%%)\n", 
                used_sum/used_count, util_sum/used_count
            printf "- **Peak Used**: %.0f MB (%.1f%%)\n", used_max, util_max
            if (swap_count > 0) {
                printf "- **Total Swap**: %d MB\n", swap_total
                printf "- **Average Swap Used**: %.0f MB\n", swap_sum/swap_count
                printf "- **Peak Swap Used**: %.0f MB\n", swap_max
            }
            printf "- **Samples**: %d\n", used_count
        }
    }' "$MEMORY_LOG"
    
    echo ""
    
    # Per-user memory
    echo "### Per-User Memory Usage"
    echo ""
    
    awk -F'|' '/^USER_MEMORY\|/ {
        user = $2
        mem = $3
        user_mem[user] += mem
        user_count[user]++
        if (mem > user_mem_max[user]) user_mem_max[user] = mem
    }
    END {
        if (length(user_mem) > 0) {
            print "| User | Avg Memory (MB) | Peak Memory (MB) | Samples |"
            print "|------|-----------------|------------------|---------|"
            for (u in user_mem) {
                printf "| %s | %.0f | %.0f | %d |\n",
                    u, user_mem[u]/user_count[u], user_mem_max[user], user_count[u]
            }
        }
    }' "$MEMORY_LOG"
    
    echo ""
}

analyze_disk() {
    [ ! -f "$DISK_LOG" ] && echo "*No disk data available*" && return
    
    echo "## 💾 Disk Usage Summary"
    echo ""
    
    # Get latest disk space snapshot
    awk -F'|' '/^DISK_SPACE\|/ {
        fs=$2; size=$3; used=$4; avail=$5; use_pct=$6; mount=$7
    } 
    END {
        if (fs != "") {
            printf "**Latest Disk Space** (from last sample):\n\n"
        }
    }' "$DISK_LOG"
    
    awk -F'|' 'BEGIN {seen=0} 
    /^DISK_SPACE\|/ {
        if (!seen) {
            print "| Filesystem | Size | Used | Available | Use% | Mounted On |"
            print "|------------|------|------|-----------|------|------------|"
            seen=1
        }
        printf "| %s | %s | %s | %s | %s | %s |\n", $2, $3, $4, $5, $6, $7
    }' "$DISK_LOG" | tail -20
    
    echo ""
}

analyze_containers() {
    [ ! -f "$CONTAINER_LOG" ] && echo "*No container data available*" && return
    
    echo "## 🐳 Docker Container Activity"
    echo ""
    
    # Check if there are any container metrics
    if ! grep -q "^CONTAINER_STATS|" "$CONTAINER_LOG" 2>/dev/null; then
        echo "*No Docker containers detected*"
        echo ""
        return
    fi
    
    awk -F'|' '/^CONTAINER_STATS\|/ {
        name = $2
        containers[name]++
    }
    END {
        if (length(containers) > 0) {
            print "**Active Containers:**"
            for (c in containers) {
                printf "- `%s` (active in %d samples)\n", c, containers[c]
            }
        }
    }' "$CONTAINER_LOG"
    
    echo ""
}

# Generate the report
{
    echo "# 📊 Daily Server Performance Report"
    echo ""
    echo "**Date:** $(date -d "$DATE" '+%A, %B %d, %Y' 2>/dev/null || date '+%A, %B %d, %Y')"
    echo "**Report Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Calculate total samples (from any log file)
    if [ -f "$GPU_LOG" ]; then
        SAMPLE_COUNT=$(grep -c "GPU_METRICS_START" "$GPU_LOG" 2>/dev/null || echo 0)
    elif [ -f "$CPU_LOG" ]; then
        SAMPLE_COUNT=$(grep -c "CPU_METRICS_START" "$CPU_LOG" 2>/dev/null || echo 0)
    else
        SAMPLE_COUNT=0
    fi
    
    echo "**Collection Interval:** Every 5 minutes"
    echo "**Total Samples:** $SAMPLE_COUNT"
    echo ""
    echo "---"
    echo ""
    
    analyze_gpu
    analyze_cpu
    analyze_memory
    analyze_disk
    analyze_containers
    
    echo "---"
    echo ""
    echo "*Report generated by compile-daily-report.sh*"
    echo "*Source metrics: /var/log/ds01-infra/metrics/*"
    
} > "$REPORT_FILE"

# Create symlink to latest report
ln -sf "$(basename "$REPORT_FILE")" "$REPORTS_DIR/_latest.md"

echo "✅ Daily report compiled: $REPORT_FILE"
echo "📊 Analyzed $SAMPLE_COUNT samples from $(date -d "$DATE" '+%Y-%m-%d')"
echo "📄 Latest report: $REPORTS_DIR/_latest.md"

exit 0
