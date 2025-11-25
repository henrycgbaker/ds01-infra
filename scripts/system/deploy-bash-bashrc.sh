#!/bin/bash
# Deploy system-wide bash.bashrc with DS01 PATH configuration
# File: /opt/ds01-infra/scripts/system/deploy-bash-bashrc.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo "Deploying /etc/bash.bashrc with DS01 PATH configuration..."

# Backup original
if [ ! -f /etc/bash.bashrc.backup-ds01 ]; then
    cp /etc/bash.bashrc /etc/bash.bashrc.backup-ds01
    echo "✓ Backed up original to /etc/bash.bashrc.backup-ds01"
fi

# Deploy from mirror
cp /opt/ds01-infra/config/etc-mirrors/bash.bashrc /etc/bash.bashrc
chmod 644 /etc/bash.bashrc

echo "✓ Deployed /etc/bash.bashrc"
echo ""
echo "This ensures ALL interactive bash shells get /usr/local/bin in PATH"
echo "No user action required - works immediately for new shells"
