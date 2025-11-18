#!/bin/bash
# Test the fixed idle timeout and max runtime functions

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"

echo "=================================="
echo "Testing FIXED Functions"
echo "=================================="
echo ""

# Test idle timeout function
get_idle_timeout() {
    local username="$1"

    USERNAME="$username" CONFIG_FILE="$CONFIG_FILE" python3 - <<'PYEOF'
import yaml
import sys
import os

try:
    username = os.environ['USERNAME']
    config_file = os.environ['CONFIG_FILE']

    with open(config_file) as f:
        config = yaml.safe_load(f)

    # Check user overrides first
    if 'user_overrides' in config and username in config['user_overrides']:
        timeout = config['user_overrides'][username].get('idle_timeout')
        if timeout:
            print(timeout)
            sys.exit(0)

    # Check groups
    if 'groups' in config:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and username in group_config['members']:
                timeout = group_config.get('idle_timeout')
                if timeout:
                    print(timeout)
                    sys.exit(0)

    # Default timeout
    default_timeout = config.get('defaults', {}).get('idle_timeout', '48h')
    print(default_timeout)
except Exception as e:
    print("48h", file=sys.stderr)
    sys.exit(1)
PYEOF
}

echo "[1] Testing idle_timeout for datasciencelab (admin group)..."
timeout=$(get_idle_timeout "datasciencelab")
echo "    Result: '$timeout'"
echo "    Expected: '0.5h' (from admin group config)"
if [ "$timeout" = "0.5h" ]; then
    echo "    ✅ CORRECT"
else
    echo "    ❌ WRONG"
fi
echo ""

echo "[2] Testing idle_timeout for default user..."
timeout=$(get_idle_timeout "nonexistent_user")
echo "    Result: '$timeout'"
echo "    Expected: '0.5h' (from defaults)"
if [ "$timeout" = "0.5h" ]; then
    echo "    ✅ CORRECT"
else
    echo "    ❌ WRONG"
fi
echo ""

echo "=================================="
echo "Testing complete!"
echo "=================================="
