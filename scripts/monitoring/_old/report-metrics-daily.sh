#!/bin/bash
# opt/ds01-infra/scripts/scripts/report-metrics-daily.sh
# Generate daily report from metrics logs
# Run at 23:55 daily via cron

METRICS_DIR=~/server_infra/logs/metrics
REPORTS_DIR=~/server_infra/logs/daily_reports
DATE=${1:-$(date '+%Y%m%d')}
LOG_FILE="$METRICS_DIR/${DATE}.log"
REPORT_FILE="$REPORTS_DIR/daily_report_${DATE}.md"

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Check if log file exists
if [ ! -f "$LOG_FILE" ] && [ ! -f "${LOG_FILE}.gz" ]; then
    echo "Error: No log file found for $DATE"
    exit 1
fi

# Decompress if needed
if [ -f "${LOG_FILE}.gz" ] && [ ! -f "$LOG_FILE" ]; then
    gunzip -c "${LOG_FILE}.gz" > "$LOG_FILE.tmp"
    LOG_FILE="$LOG_FILE.tmp"
    CLEANUP_TMP=1
fi

# Analysis functions
analyze_gpu() {
    echo "## GPU Utilization Summary"
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
    }' "$LOG_FILE"
    
    echo ""
    echo "### GPU Usage Timeline (Hourly Average)"
    echo ""
    echo "| Hour | Avg GPU 0 Util | Avg GPU 1 Util | Avg GPU 2 Util | Avg GPU 3 Util |"
    echo "|------|----------------|----------------|----------------|----------------|"
    
    awk -F'|' '
    /^=== METRICS_START/ {
        split($2, dt, " ")
        split(dt[2], t, ":")
        hour = t[1]
    }
    /^GPU_DEVICE\|/ {
        gpu = $2
        util = $4
        gpu_hour[hour][gpu] += util
        gpu_count[hour][gpu]++
    }
    END {
        for (h=0; h<24; h++) {
            hstr = sprintf("%02d:00", h)
            printf "| %s |", hstr
            for (g=0; g<4; g++) {
                if (gpu_count[sprintf("%02d", h)][g] > 0) {
                    printf " %.1f%% |", gpu_hour[sprintf("%02d", h)][g] / gpu_count[sprintf("%02d", h)][g]
                } else {
                    printf " - |"
                }
            }
            print ""
        }
    }' "$LOG_FILE"
    
    echo ""
}

analyze_gpu_users() {
    echo "## 👥 Per-User GPU Usage"
    echo ""
    
    # Aggregate GPU memory usage by user
    awk -F'|' '/^USER_GPU\|/ {
        user = $2
        mem = $4
        user_mem[user] += mem
        user_count[user]++
    }
    END {
        if (length(user_mem) > 0) {
            print "| User | Total GPU Memory Used | Avg per Sample | Samples |"
            print "|------|----------------------|----------------|---------|"
            for (u in user_mem) {
                printf "| %s | %.0f MB | %.0f MB | %d |\n",
                    u, user_mem[u], user_mem[u]/user_count[u], user_count[u]
            }
        } else {
            print "*No GPU usage detected*"
        }
    }' "$LOG_FILE"
    
    echo ""
}

analyze_cpu() {
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
        printf "- **Average CPU Utilization**: %.1f%%\n", util_sum/util_count
        printf "- **Peak CPU Utilization**: %.1f%%\n", util_max
        printf "- **Minimum CPU Utilization**: %.1f%%\n", util_min
        printf "- **Average Load (1/5/15 min)**: %.2f / %.2f / %.2f\n", 
            load1_sum/util_count, load5_sum/util_count, load15_sum/util_count
        printf "- **Peak Load (1 min)**: %.2f\n", load1_max
        printf "- **Samples**: %d\n", util_count
    }' "$LOG_FILE"
    
    echo ""
}

analyze_memory() {
    echo "## 🧠 Memory Summary"
    echo ""
    
    awk -F'|' '/^MEMORY_OVERALL\|/ {
        total = $2
        used = $3
        free = $4
        
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
        printf "- **Total Memory**: %d MB\n", total
        printf "- **Average Used**: %.0f MB (%.1f%%)\n", 
            used_sum/used_count, util_sum/util_count
        printf "- **Peak Used**: %.0f MB (%.1f%%)\n", used_max, util_max
        if (swap_count > 0) {
            printf "- **Total Swap**: %d MB\n", swap_total
            printf "- **Average Swap Used**: %.0f MB\n", swap_sum/swap_count
            printf "- **Peak Swap Used**: %.0f MB\n", swap_max
        }
        printf "- **Samples**: %d\n", used_count
    }' "$LOG_FILE"
    
    echo ""
}

analyze_users() {
    echo "## 👤 Per-User Resource Summary"
    echo ""
    
    awk -F'|' '/^USER_STATS\|/ {
        user = $2
        cpu = $3
        mem = $4
        procs = $5
        
        user_cpu[user] += cpu
        user_mem[user] += mem
        user_procs[user] += procs
        user_count[user]++
        
        if (cpu > user_cpu_max[user]) user_cpu_max[user] = cpu
        if (mem > user_mem_max[user]) user_mem_max[user] = mem
    }
    END {
        if (length(user_cpu) > 0) {
            print "| User | Avg CPU % | Peak CPU % | Avg Memory (MB) | Peak Memory (MB) | Avg Processes | Samples |"
            print "|------|-----------|------------|-----------------|------------------|---------------|---------|"
            for (u in user_cpu) {
                printf "| %s | %.1f%% | %.1f%% | %.0f | %.0f | %.0f | %d |\n",
                    u,
                    user_cpu[u]/user_count[u],
                    user_cpu_max[u],
                    user_mem[u]/user_count[u],
                    user_mem_max[u],
                    user_procs[u]/user_count[u],
                    user_count[u]
            }
        } else {
            print "*No user activity detected*"
        }
    }' "$LOG_FILE"
    
    echo ""
}

analyze_top_processes() {
    echo "## 🔝 Top Resource Consumers (by average presence)"
    echo ""
    echo "### Top CPU Processes"
    echo ""
    
    awk -F'|' '/^TOP_CPU\|/ {
        user = $2
        pid = $3
        cmd = $5
        # Create a key from user and command
        key = user ":" cmd
        count[key]++
    }
    END {
        n = 0
        for (k in count) {
            if (n < 10) {
                split(k, parts, ":")
                printf "- **%s**: %s (appeared %d times)\n", parts[1], parts[2], count[k]
                n++
            }
        }
    }' "$LOG_FILE"
    
    echo ""
    echo "### Top Memory Processes"
    echo ""
    
    awk -F'|' '/^TOP_MEM\|/ {
        user = $2
        pid = $3
        cmd = $5
        key = user ":" cmd
        count[key]++
    }
    END {
        n = 0
        for (k in count) {
            if (n < 10) {
                split(k, parts, ":")
                printf "- **%s**: %s (appeared %d times)\n", parts[1], parts[2], count[k]
                n++
            }
        }
    }' "$LOG_FILE"
    
    echo ""
}

analyze_docker() {
    echo "## 🐳 Docker Container Activity"
    echo ""
    
    # Check if there are any docker metrics
    if ! grep -q "^DOCKER_CONTAINER|" "$LOG_FILE" 2>/dev/null; then
        echo "*No Docker containers detected*"
        echo ""
        return
    fi
    
    awk -F'|' '/^DOCKER_CONTAINER\|/ {
        name = $2
        containers[name]++
    }
    END {
        if (length(containers) > 0) {
            print "**Active Containers:**"
            for (c in containers) {
                printf "- %s (active in %d samples)\n", c, containers[c]
            }
        }
    }' "$LOG_FILE"
    
    echo ""
}

# Generate the report
{
    echo "# Daily Server Performance Report"
    echo ""
    echo "**Date:** $(date -d "$DATE" '+%A, %B %d, %Y' 2>/dev/null || date '+%A, %B %d, %Y')"
    echo ""
    echo "**Report Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Calculate sample count
    SAMPLE_COUNT=$(grep -c "^=== METRICS_START" "$LOG_FILE")
    echo "**Total Samples Collected:** $SAMPLE_COUNT (every 5 minutes)"
    echo ""
    
    echo "---"
    echo ""
    
    analyze_gpu
    analyze_gpu_users
    analyze_cpu
    analyze_memory
    analyze_users
    analyze_top_processes
    analyze_docker
    
    echo "---"
    echo ""
    echo "*Report generated by report_metrics_daily.sh*"
    
} > "$REPORT_FILE"

# Cleanup temporary file if needed
if [ -n "$CLEANUP_TMP" ]; then
    rm -f "$LOG_FILE"
fi

# Create symlink to latest report
ln -sf "$(basename "$REPORT_FILE")" "$REPORTS_DIR/_latest_daily_report.md"

echo "✅ Daily report complete: $REPORT_FILE"
echo "📊 Analyzed $SAMPLE_COUNT samples"
echo "📄 Latest report symlink: $REPORTS_DIR/_latest_daily_report.md"