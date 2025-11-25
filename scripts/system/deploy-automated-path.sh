#!/bin/bash
# Master script: Deploy automated PATH configuration for all users
# File: /opt/ds01-infra/scripts/system/deploy-automated-path.sh
#
# This script implements a robust, automated solution that ensures ALL users
# (domain and local) get /usr/local/bin in PATH automatically, without manual intervention.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DS01 Automated PATH Configuration Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Layer 1: System-wide /etc/bash.bashrc (immediate fix)
echo "LAYER 1: Deploying /etc/bash.bashrc"
echo "-------------------------------------"
/opt/ds01-infra/scripts/system/deploy-bash-bashrc.sh
echo ""

# Layer 2: PAM session automation (first-login .bashrc creation)
echo "LAYER 2: Deploying PAM automation"
echo "-------------------------------------"
/opt/ds01-infra/scripts/system/deploy-pam-bashrc.sh
echo ""

# Layer 3: Verify existing files
echo "LAYER 3: Verifying existing configuration"
echo "-------------------------------------"
echo -n "  /etc/profile.d/ds01-path.sh ... "
if [ -f /etc/profile.d/ds01-path.sh ]; then
    echo "✓"
else
    echo "✗ (run deploy-profile-d.sh)"
fi

echo -n "  /etc/skel/.bashrc (with DS01) ... "
if grep -q "DS01: Ensure /usr/local/bin" /etc/skel/.bashrc 2>/dev/null; then
    echo "✓"
else
    echo "✗ (needs DS01 PATH config)"
fi

echo -n "  /etc/bash.bashrc (with DS01) ... "
if grep -q "DS01: Ensure /usr/local/bin" /etc/bash.bashrc 2>/dev/null; then
    echo "✓"
else
    echo "✗"
fi

echo -n "  /usr/local/bin/shell-setup ... "
if [ -L /usr/local/bin/shell-setup ]; then
    echo "✓"
else
    echo "✗ (run update-symlinks.sh)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deployment Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Coverage Matrix:"
echo "  ✓ Current sessions: /etc/bash.bashrc (immediate)"
echo "  ✓ SSH login (non-login): /etc/bash.bashrc"
echo "  ✓ SSH login (login): /etc/profile.d/ds01-path.sh"
echo "  ✓ First-time users: PAM auto-creates .bashrc"
echo "  ✓ New user accounts: /etc/skel/.bashrc template"
echo "  ✓ Manual fallback: shell-setup command"
echo ""
echo "Action Required:"
echo "  - Tell currently logged-in users to start a new shell: bash"
echo "  - OR wait for them to log out and log back in"
echo "  - Future logins work automatically (no user action needed)"
echo ""
