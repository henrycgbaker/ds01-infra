#!/bin/bash
# Debug Python heredoc to see what's happening

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
username="datasciencelab"

echo "Testing with debugging enabled"
echo "=============================="
echo ""

USERNAME="$username" CONFIG_FILE="$CONFIG_FILE" python3 - <<'PYEOF'
import yaml
import sys
import os

try:
    username = os.environ['USERNAME']
    config_file = os.environ['CONFIG_FILE']

    print(f"DEBUG: username = {username}")
    print(f"DEBUG: config_file = {config_file}")
    print()

    with open(config_file) as f:
        config = yaml.safe_load(f)

    # Check user overrides first
    print(f"DEBUG: Checking user_overrides...")
    if 'user_overrides' in config:
        print(f"DEBUG: user_overrides exists, keys: {list(config['user_overrides'].keys())}")
        if username in config['user_overrides']:
            print(f"DEBUG: Found {username} in user_overrides")
            timeout = config['user_overrides'][username].get('idle_timeout')
            if timeout:
                print(f"RESULT: {timeout} (from user_overrides)")
                print(timeout)
                sys.exit(0)
    print()

    # Check groups
    print(f"DEBUG: Checking groups...")
    if 'groups' in config:
        for group_name, group_config in config['groups'].items():
            print(f"DEBUG: Checking group '{group_name}'")
            if 'members' in group_config:
                print(f"DEBUG:   members = {group_config['members']}")
                if username in group_config['members']:
                    print(f"DEBUG:   ✓ {username} is in {group_name}")
                    timeout = group_config.get('idle_timeout')
                    print(f"DEBUG:   idle_timeout from group = {timeout}")
                    if timeout:
                        print(f"RESULT: {timeout} (from group {group_name})")
                        print(timeout)
                        sys.exit(0)
                    else:
                        print(f"DEBUG:   idle_timeout is None/null, checking next group")
            print()

    # Default timeout
    print(f"DEBUG: Using default...")
    default_timeout = config.get('defaults', {}).get('idle_timeout', '48h')
    print(f"RESULT: {default_timeout} (from defaults)")
    print(default_timeout)
except Exception as e:
    print(f"ERROR: {e}")
    print("48h", file=sys.stderr)
    sys.exit(1)
PYEOF
