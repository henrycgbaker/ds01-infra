#!/bin/bash
# Deploy PAM session script for automatic .bashrc creation
# File: /opt/ds01-infra/scripts/system/deploy-pam-bashrc.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo "Deploying PAM bashrc automation..."

# 1. Copy PAM script to /usr/local/bin
cp /opt/ds01-infra/scripts/system/pam-ensure-bashrc.sh /usr/local/bin/pam-ensure-bashrc.sh
chmod 755 /usr/local/bin/pam-ensure-bashrc.sh
echo "✓ Installed /usr/local/bin/pam-ensure-bashrc.sh"

# 2. Check if PAM common-session already has our hook
if grep -q "pam-ensure-bashrc.sh" /etc/pam.d/common-session; then
    echo "✓ PAM hook already configured in /etc/pam.d/common-session"
else
    # Backup original
    if [ ! -f /etc/pam.d/common-session.backup-ds01 ]; then
        cp /etc/pam.d/common-session /etc/pam.d/common-session.backup-ds01
        echo "✓ Backed up /etc/pam.d/common-session"
    fi

    # Add PAM hook at end of file
    echo "" >> /etc/pam.d/common-session
    echo "# DS01: Auto-create .bashrc on first login" >> /etc/pam.d/common-session
    echo "session optional pam_exec.so seteuid /usr/local/bin/pam-ensure-bashrc.sh" >> /etc/pam.d/common-session

    echo "✓ Added PAM hook to /etc/pam.d/common-session"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PAM Automation Deployed Successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "What this does:"
echo "  - Runs /usr/local/bin/pam-ensure-bashrc.sh on every user login"
echo "  - If user has no ~/.bashrc, copies from /etc/skel/.bashrc"
echo "  - Works for domain users, local users, SSH, console logins"
echo "  - Completely automatic, no user action required"
echo ""
echo "Next login: All users will automatically get .bashrc with DS01 PATH"
