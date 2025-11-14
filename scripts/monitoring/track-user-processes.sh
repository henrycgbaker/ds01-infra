# File: /opt/ds01-infra/scripts/monitoring/track-user-processes.sh
#!/bin/bash
# Track processes by user across containers and host

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DS01 Process Tracking by User"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get all DS01 users
USERS=$(docker ps -a --filter "label=aime.mlc.DS01_USER" --format "{{index .Config.Labels \"aime.mlc.DS01_USER\"}}" | sort -u)

for user in $USERS; do
    echo "User: $user"
    echo "────────────────────────────────────────────────────"
    
    user_id=$(id -u "$user" 2>/dev/null)
    
    if [ -n "$user_id" ]; then
        # Host processes
        host_procs=$(ps -U "$user_id" --no-headers | wc -l)
        echo "  Host processes: $host_procs"
        
        # Container processes
        user_containers=$(docker ps --filter "label=aime.mlc.DS01_USER=$user" --format "{{.Names}}")
        
        for container in $user_containers; do
            short_name=$(echo "$container" | cut -d'.' -f1)
            container_procs=$(docker exec "$container" ps aux 2>/dev/null | tail -n +2 | wc -l)
            echo "  Container '$short_name': $container_procs processes"
            
            # Show top processes
            echo "    Top processes:"
            docker exec "$container" ps aux --sort=-%cpu 2>/dev/null | head -n 4 | tail -n 3 | awk '{print "      " $11}'
        done
    fi
    
    echo ""
done