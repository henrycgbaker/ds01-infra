# File: /opt/ds01-infra/scripts/monitoring/container-audit.sh
#!/bin/bash
# Audit script to check container ownership and security

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Container Security Audit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check all running containers
docker ps --format "{{.Names}}" | while read container; do
    echo "Auditing: $container"
    
    # Check if it's a DS01 container
    if docker inspect "$container" --format='{{index .Config.Labels "ds01.user"}}' 2>/dev/null | grep -q .; then
        user=$(docker inspect "$container" --format='{{index .Config.Labels "ds01.user"}}')
        uid=$(docker inspect "$container" --format='{{index .Config.Labels "ds01.user_id"}}')
        
        echo "  ✓ DS01 container"
        echo "  Owner: $user (UID: $uid)"
        
        # Check if running as correct user
        running_as=$(docker exec "$container" id -u 2>/dev/null)
        if [ "$running_as" = "$uid" ]; then
            echo "  ✓ Running as correct user ($uid)"
        else
            echo "  ⚠ Running as UID $running_as (expected $uid)"
        fi
        
        # Check cgroup
        cgroup=$(docker inspect "$container" --format='{{.HostConfig.CgroupParent}}')
        echo "  Cgroup: ${cgroup:-default}"
        
        # Check capabilities
        caps=$(docker inspect "$container" --format='{{.HostConfig.CapAdd}}')
        echo "  Capabilities: ${caps:-none added}"
        
        # Check resource limits
        cpu=$(docker inspect "$container" --format='{{.HostConfig.NanoCpus}}')
        mem=$(docker inspect "$container" --format='{{.HostConfig.Memory}}')
        echo "  GPU limit: ${gpu:-unlimited}"
        echo "  CPU limit: ${cpu:-unlimited}"
        echo "  Memory limit: ${mem:-unlimited}"
        
    else
        echo "  ⚠ Not a DS01 managed container"
    fi
    
    echo ""
done

# Check for containers without proper labels
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Unlabeled Containers (not DS01 managed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

docker ps -a --format "{{.Names}}" | while read container; do
    if ! docker inspect "$container" --format='{{index .Config.Labels "ds01.user"}}' 2>/dev/null | grep -q .; then
        status=$(docker inspect "$container" --format='{{.State.Status}}')
        created=$(docker inspect "$container" --format='{{.Created}}' | cut -d'T' -f1)
        echo "  $container [$status] (created: $created)"
    fi
done

echo ""