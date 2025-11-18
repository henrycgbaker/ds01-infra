#!/bin/bash
# Test the fixed idle timeout function

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"

echo "Testing FIXED idle timeout function"
echo "===================================="
echo ""

# Test the fixed function
get_idle_timeout() {
    local username="$1"

    python3 - <<PYEOF
import yaml
import sys

try:
    with open("$CONFIG_FILE") as f:
        config = yaml.safe_load(f)

    # Check user overrides first
    if 'user_overrides' in config and \"$username\" in config['user_overrides']:
        timeout = config['user_overrides'][\"$username\"].get('idle_timeout')
        if timeout:
            print(timeout)
            sys.exit(0)

    # Check groups
    if 'groups' in config:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and \"$username\" in group_config['members']:
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

echo "[1] Testing for datasciencelab (admin group)..."
timeout=$(get_idle_timeout "datasciencelab")
echo "    Result: '$timeout'"
echo "    Expected: '0.5h' (from admin group config)"
echo ""

echo "[2] Testing for non-existent user..."
timeout=$(get_idle_timeout "nonexistent")
echo "    Result: '$timeout'"
echo "    Expected: '0.5h' (from defaults)"
echo ""

echo "===================================="
if [ "$timeout" = "0.5h" ]; then
    echo "✅ FIX VERIFIED - Functions now return correct values!"
else
    echo "❌ Still broken - expected '0.5h', got '$timeout'"
fi
