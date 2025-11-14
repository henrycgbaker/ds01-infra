# File: /opt/ds01-infra/scripts/admin/emergency-container-stop.sh
#!/bin/bash
# Emergency stop for containers by user or all

USER="$1"

if [ -z "$USER" ]; then
    echo "Usage: emergency-container-stop.sh <username|all>"
    echo ""
    echo "Stop all containers for a user or all users"
    exit 1
fi

if [ "$USER" = "all" ]; then
    echo "⚠️  Stopping ALL DS01 containers..."
    docker ps --filter "label=aime.mlc.DS01_USER" --format "{{.Names}}" | while read container; do
        user=$(docker inspect "$container" --format='{{index .Config.Labels "aime.mlc.DS01_USER"}}')
        echo "  Stopping $container (user: $user)"
        docker stop "$container" 2>/dev/null
    done
else
    echo "Stopping containers for user: $USER"
    docker ps --filter "label=aime.mlc.DS01_USER=$USER" --format "{{.Names}}" | while read container; do
        echo "  Stopping $container"
        docker stop "$container" 2>/dev/null
    done
fi

echo ""
echo "✓ Complete"