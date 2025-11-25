#!/bin/bash
# Test ONLY the get functions, not the full scripts

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"

echo "Testing Fixed Get Functions"
echo "============================"
echo ""

# Define get_idle_timeout (copy from fixed script)
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
    if 'user_overrides' in config and config['user_overrides'] is not None:
        if username in config['user_overrides']:
            timeout = config['user_overrides'][username].get('idle_timeout')
            if timeout:
                print(timeout)
                sys.exit(0)

    # Check groups
    if 'groups' in config and config['groups'] is not None:
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

# Define get_max_runtime (copy from fixed script)
get_max_runtime() {
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
    if 'user_overrides' in config and config['user_overrides'] is not None:
        if username in config['user_overrides']:
            runtime = config['user_overrides'][username].get('max_runtime')
            if runtime:
                print(runtime)
                sys.exit(0)

    # Check groups
    if 'groups' in config and config['groups'] is not None:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and username in group_config['members']:
                runtime = group_config.get('max_runtime')
                if runtime:
                    print(runtime)
                    sys.exit(0)

    # Default runtime
    default_runtime = config.get('defaults', {}).get('max_runtime', 'null')
    print(default_runtime)
except Exception as e:
    print("null", file=sys.stderr)
    sys.exit(1)
PYEOF
}

echo "[Test 1] get_idle_timeout for datasciencelab..."
timeout=$(get_idle_timeout "datasciencelab")
echo "  Result: '$timeout'"
echo "  Expected: '0.5h'"
[ "$timeout" = "0.5h" ] && echo "  ✅ PASS" || echo "  ❌ FAIL (got '$timeout')"
echo ""

echo "[Test 2] get_max_runtime for datasciencelab..."
runtime=$(get_max_runtime "datasciencelab")
echo "  Result: '$runtime'"
echo "  Expected: '12h'"
[ "$runtime" = "12h" ] && echo "  ✅ PASS" || echo "  ❌ FAIL (got '$runtime')"
echo ""

echo "[Test 3] get_idle_timeout for non-existent user..."
timeout=$(get_idle_timeout "nobody")
echo "  Result: '$timeout'"
echo "  Expected: '0.5h' (from defaults)"
[ "$timeout" = "0.5h" ] && echo "  ✅ PASS" || echo "  ❌ FAIL (got '$timeout')"
echo ""

echo "============================"
echo "All tests complete!"
echo "============================"
