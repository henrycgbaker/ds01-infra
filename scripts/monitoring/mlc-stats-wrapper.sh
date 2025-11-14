# File: /opt/ds01-infra/scripts/monitoring/mlc-stats-wrapper.sh
#!/bin/bash
# Enhanced stats command with more detail

USERNAME=${1:-$(whoami)}
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${GREEN}${BOLD}━━━ Container Statistics for $USERNAME ━━━${NC}\n"

# Get containers
containers=$(docker ps -a --filter "label=aime.mlc.DS01_USER=$USERNAME" --format "{{.Names}}")

if [ -z "$containers" ]; then
    echo "No containers found for user: $USERNAME"
    exit 0
fi

for container in $containers; do
    short_name=$(echo "$container" | cut -d'.' -f1)
    status=$(docker inspect "$container" --format='{{.State.Status}}' 2>/dev/null)
    image=$(docker inspect "$container" --format='{{index .Config.Labels "aime.mlc.DS01_IMAGE"}}' 2>/dev/null)
    created=$(docker inspect "$container" --format='{{.Created}}' 2>/dev/null | cut -d'T' -f1)
    
    echo -e "${BOLD}Container: ${CYAN}$short_name${NC}"
    echo "  Status: $status"
    echo "  Image: $image"
    echo "  Created: $created"
    
    if [ "$status" = "running" ]; then
        # Get resource usage
        stats=$(docker stats "$container" --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}} ({{.MemPerc}}), Network: {{.NetIO}}, Block I/O: {{.BlockIO}}" 2>/dev/null)
        echo "  $stats"
        
        # Get GPU info if available
        gpu_info=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | \
            while read line; do
                pid=$(echo "$line" | cut -d',' -f1 | xargs)
                if docker exec "$container" test -d /proc/$pid 2>/dev/null; then
                    echo "$line"
                fi
            done)
        
        if [ -n "$gpu_info" ]; then
            echo "  GPU Processes:"
            echo "$gpu_info" | sed 's/^/    /'
        fi
    fi
    
    echo ""
done

# Resource limits
echo -e "${BOLD}Your Resource Limits:${NC}"
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py "$USERNAME" 2>/dev/null || echo "  Could not fetch limits"
echo ""

# Tips
echo -e "${BOLD}Quick Actions:${NC}"
echo "  Full dashboard: ${GREEN}ds01-dashboard${NC}"
echo "  Open container: ${GREEN}mlc-open <name>${NC}"
echo "  Stop container: ${GREEN}mlc-stop <name>${NC}"