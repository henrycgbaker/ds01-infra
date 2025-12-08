# File: /opt/ds01-infra/scripts/monitoring/container-dashboard.sh
#!/bin/bash
# Real-time resource monitoring dashboard for DS01 containers

# TODO NEED TO IMPLEMENT THIS
# File: /usr/local/bin/ds01-dashboard
#!/bin/bash
# Symlink to container dashboard
#exec /opt/ds01-infra/scripts/monitoring/container-dashboard.sh "$@"

REFRESH_INTERVAL=2
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Get terminal size
get_terminal_size() {
    TERM_ROWS=$(tput lines)
    TERM_COLS=$(tput cols)
}

# Draw header
draw_header() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}                    DS01 GPU Server - Container Dashboard${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S')  |  Refresh: ${REFRESH_INTERVAL}s  |  Press 'q' to quit"
    echo ""
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
    else
        echo "$(echo "scale=2; $bytes/1024" | bc)KB"
    fi
}

# Get GPU allocation for container
get_gpu_allocation() {
    local container=$1
    docker inspect "$container" --format='{{range .HostConfig.DeviceRequests}}{{range .DeviceIDs}}GPU{{.}} {{end}}{{end}}' 2>/dev/null | xargs || echo "N/A"
}

# Get idle time for container
get_idle_time() {
    local container=$1
    local state_file="/var/lib/ds01-infra/container-states/${container}.state"
    
    if [ -f "$state_file" ]; then
        source "$state_file"
        local now=$(date +%s)
        local idle_seconds=$((now - LAST_ACTIVITY))
        local idle_hours=$((idle_seconds / 3600))
        echo "${idle_hours}h"
    else
        echo "N/A"
    fi
}

# Color code based on usage percentage
usage_color() {
    local usage=$1
    local value=$(echo "$usage" | sed 's/%//')
    
    if (( $(echo "$value >= 80" | bc -l) )); then
        echo -e "${RED}${usage}${NC}"
    elif (( $(echo "$value >= 50" | bc -l) )); then
        echo -e "${YELLOW}${usage}${NC}"
    else
        echo -e "${GREEN}${usage}${NC}"
    fi
}

# Draw container table
draw_containers() {
    echo -e "${BOLD}Your Containers:${NC}"
    echo ""
    
    # Table header
    printf "${BOLD}%-25s %-10s %-8s %-10s %-10s %-8s %-8s %-10s${NC}\n" \
        "CONTAINER" "USER" "STATUS" "CPU" "MEMORY" "GPU" "NET I/O" "IDLE"
    echo "────────────────────────────────────────────────────────────────────────────────────────────────"
    
    # Get current user's containers
    local current_user=$(whoami)
    local containers=$(docker ps -a --filter "label=aime.mlc.DS01_USER=$current_user" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        echo "No containers found"
        return
    fi
    
    for container in $containers; do
        # Get container info
        local short_name=$(echo "$container" | cut -d'.' -f1)
        local username=$(docker inspect "$container" --format='{{index .Config.Labels "aime.mlc.DS01_USER"}}' 2>/dev/null)
        local status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null)
        
        if [ "$status" = "running" ]; then
            # Get real-time stats
            local stats=$(docker stats "$container" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}" 2>/dev/null)
            
            local cpu=$(echo "$stats" | cut -d'|' -f1)
            local mem=$(echo "$stats" | cut -d'|' -f2)
            local mem_perc=$(echo "$stats" | cut -d'|' -f3)
            local net=$(echo "$stats" | cut -d'|' -f4)
            
            local gpu=$(get_gpu_allocation "$container")
            local idle=$(get_idle_time "$container")
            
            # Color code values
            cpu=$(usage_color "$cpu")
            mem_perc=$(usage_color "$mem_perc")
            
            local status_color="${GREEN}running${NC}"
        else
            local cpu="-"
            local mem="-"
            local mem_perc="-"
            local net="-"
            local gpu="-"
            local idle="-"
            local status_color="${YELLOW}stopped${NC}"
        fi
        
        printf "%-25s %-10s %-18s %-18s %-18s %-8s %-8s %-10s\n" \
            "$short_name" "$username" "$status_color" "$cpu" "$mem_perc" "$gpu" "$net" "$idle"
    done
}

# Draw GPU status
draw_gpu_status() {
    echo ""
    echo -e "${BOLD}GPU Status:${NC}"
    echo ""
    
    # Get GPU info using nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu \
            --format=csv,noheader,nounits | while IFS=, read -r idx name util mem_used mem_total temp; do
            
            util=$(echo $util | xargs)
            mem_used=$(echo $mem_used | xargs)
            mem_total=$(echo $mem_total | xargs)
            temp=$(echo $temp | xargs)
            
            # Calculate memory percentage
            mem_perc=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc)
            
            # Color code
            util_colored=$(usage_color "${util}%")
            mem_colored=$(usage_color "${mem_perc}%")
            
            echo -e "  GPU${idx}: ${name}"
            echo -e "    Utilization: ${util_colored}  |  Memory: ${mem_used}MB / ${mem_total}MB (${mem_colored})  |  Temp: ${temp}°C"
            echo ""
        done
    else
        echo "  nvidia-smi not available"
    fi
}

# Draw system summary
draw_summary() {
    echo -e "${BOLD}System Summary:${NC}"
    echo ""
    
    # Count containers by status
    local current_user=$(whoami)
    local total=$(docker ps -a --filter "label=aime.mlc.DS01_USER=$current_user" --format "{{.Names}}" | wc -l)
    local running=$(docker ps --filter "label=aime.mlc.DS01_USER=$current_user" --format "{{.Names}}" | wc -l)
    local stopped=$((total - running))
    
    echo -e "  Containers: $total total  |  ${GREEN}$running running${NC}  |  ${YELLOW}$stopped stopped${NC}"
    echo ""
    
    # Disk usage for workspace
    local workspace_usage=$(du -sh ~/workspace 2>/dev/null | cut -f1)
    echo "  Workspace: $workspace_usage used in ~/workspace"
    echo ""
}

# Draw footer
draw_footer() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Commands: ${BOLD}mlc-open${NC} <name>  |  ${BOLD}mlc-stop${NC} <name>  |  ${BOLD}mlc-list${NC}  |  ${BOLD}mlc-stats${NC}"
}

# Main dashboard loop
main() {
    # Check if running in interactive terminal
    if [ ! -t 0 ]; then
        echo "Error: This script must be run in an interactive terminal"
        exit 1
    fi
    
    # Set up trap for clean exit
    trap 'echo -e "\n${GREEN}Dashboard closed${NC}"; tput cnorm; exit 0' INT TERM
    
    # Hide cursor
    tput civis
    
    while true; do
        get_terminal_size
        draw_header
        draw_summary
        draw_containers
        draw_gpu_status
        draw_footer
        
        # Wait for refresh interval or user input
        read -t $REFRESH_INTERVAL -n 1 key 2>/dev/null || true
        
        if [[ "$key" == "q" ]] || [[ "$key" == "Q" ]]; then
            break
        fi
    done
    
    # Show cursor again
    tput cnorm
    echo -e "\n${GREEN}Dashboard closed${NC}"
}

# Run dashboard
main