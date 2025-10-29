 # File: /opt/ds01-infra/scripts/monitoring/who-owns-containers.sh
#!/bin/bash
# Show container ownership and resource usage

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DS01 Container Ownership Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get all DS01 containers
docker ps -a --filter "label=ds01.user" \
    --format "{{.Names}}|{{.Status}}|{{index .Labels \"ds01.user\"}}|{{index .Labels \"ds01.user_id\"}}|{{index .Labels \"ds01.project\"}}" | \
while IFS='|' read -r container status user uid project; do
    
    short_name=$(echo "$container" | cut -d'.' -f1)
    
    echo "Container: $short_name"
    echo "  Owner: $user (UID: $uid)"
    echo "  Project: ${project:-N/A}"
    echo "  Status: $status"
    
    if [[ "$status" == Up* ]]; then
        # Get resource usage
        stats=$(docker stats "$container" --no-stream --format "CPU: {{.CPUPerc}}, Mem: {{.MemPerc}}, Net: {{.NetIO}}" 2>/dev/null)
        echo "  Resources: $stats"
        
        # Check for running processes
        proc_count=$(docker exec "$container" ps aux 2>/dev/null | wc -l)
        echo "  Processes: $((proc_count - 1))"
        
        # Check GPU allocation
        gpu=$(docker inspect "$container" --format='{{range .HostConfig.DeviceRequests}}{{range .DeviceIDs}}GPU{{.}} {{end}}{{end}}' 2>/dev/null || echo "N/A")
        echo "  GPU: ${gpu:-N/A}"
    fi
    
    echo ""
done

# Summary by user
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary by User"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

docker ps -a --filter "label=ds01.user" --format "{{index .Labels \"ds01.user\"}}" | \
    sort | uniq -c | while read count user; do
    echo "  $user: $count container(s)"
done

echo ""   