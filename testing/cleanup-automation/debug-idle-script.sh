#!/bin/bash
# Debug version of check-idle-containers.sh to see what's happening

set -x  # Enable debug mode

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
STATE_DIR="/var/lib/ds01/container-states-test"  # Use test directory
mkdir -p "$STATE_DIR"

echo "=== Finding containers ==="
containers=$(docker ps --format "{{.Names}}" | grep '\._\.' || true)
echo "Found containers: $containers"

if [ -z "$containers" ]; then
    echo "No containers found matching pattern"
    exit 0
fi

for container in $containers; do
    echo "=== Processing: $container ==="

    # Extract user ID
    user_id=$(echo "$container" | rev | cut -d'.' -f1 | rev)
    echo "  User ID: $user_id"

    # Get username
    username=$(getent passwd "$user_id" | cut -d: -f1 2>/dev/null || echo "")
    echo "  Username: $username"

    if [ -z "$username" ]; then
        echo "  ERROR: Cannot resolve username"
        continue
    fi

    # Get idle timeout
    echo "  Getting idle timeout for $username..."
    timeout_str=$(python3 - <<PYEOF
import yaml
import sys

try:
    with open("$CONFIG_FILE") as f:
        config = yaml.safe_load(f)

    # Check user overrides
    if 'user_overrides' in config and '$username' in config['user_overrides']:
        timeout = config['user_overrides']['$username'].get('idle_timeout')
        if timeout:
            print(timeout)
            sys.exit(0)

    # Check groups
    if 'groups' in config:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and '$username' in group_config['members']:
                timeout = group_config.get('idle_timeout')
                if timeout:
                    print(timeout)
                    sys.exit(0)

    # Default
    default_timeout = config.get('defaults', {}).get('idle_timeout', '48h')
    print(default_timeout)
except Exception as e:
    print("48h", file=sys.stderr)
    sys.exit(1)
PYEOF
)
    echo "  Timeout string: $timeout_str"

    # Check if active
    echo "  Checking activity..."
    cpu=$(docker stats "$container" --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    echo "  CPU: $cpu%"

    if (( $(echo "$cpu > 1.0" | bc -l) )); then
        echo "  ✓ Container is ACTIVE (CPU > 1%)"
    else
        echo "  ✗ Container is IDLE (CPU <= 1%)"
    fi

    echo ""
done

echo "=== Debug complete ==="
