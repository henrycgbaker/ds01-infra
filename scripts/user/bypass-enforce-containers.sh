# File: /opt/ds01-infra/scripts/user/bypass-enforce-container.sh
#!/bin/bash
# Give admin ability to bypass enforcement

USERNAME="${1:-$(whoami)}"
USER_HOME=$(eval echo "~$USERNAME")

cat >> "$USER_HOME/.bashrc" << 'BYPASSEOF'

# Admin bypass for container enforcement
export DS01_ADMIN_BYPASS=1

# Restore original PATH
if [ -n "$DS01_ADMIN_BYPASS" ]; then
    export PATH=$(echo "$PATH" | sed 's|/opt/ds01-infra/wrappers:||g')
fi
BYPASSEOF

echo "✓ Admin bypass enabled for $USERNAME"
echo "  Set DS01_ADMIN_BYPASS=1 to use bare metal Python"