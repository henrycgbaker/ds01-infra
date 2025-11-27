#!/bin/bash
# DS01 Docker Group Auto-Add
# Automatically adds users to docker group on first login
# File: /etc/profile.d/ds01-docker-group.sh
#
# DEPLOYMENT:
#   sudo cp /opt/ds01-infra/config/etc-mirrors/profile.d/ds01-docker-group.sh /etc/profile.d/
#   sudo chmod 644 /etc/profile.d/ds01-docker-group.sh
#
# REQUIREMENTS:
#   Add to /etc/sudoers.d/ds01-docker-group:
#   ALL ALL=(root) NOPASSWD: /opt/ds01-infra/scripts/system/add-user-to-docker.sh

# Only run in interactive shells
[[ $- == *i* ]] || return

# Skip if already in docker group
if groups 2>/dev/null | grep -qw docker; then
    return
fi

# Skip if docker command doesn't exist
if ! command -v docker &>/dev/null; then
    return
fi

# Try to add user to docker group (requires NOPASSWD sudoers entry)
if sudo -n /opt/ds01-infra/scripts/system/add-user-to-docker.sh "$USER" 2>/dev/null; then
    echo ""
    echo -e "\033[0;32m✓ Docker access has been enabled for your account.\033[0m"
    echo ""
    echo "Please log out and log back in for this to take effect."
    echo "Then run: user-setup"
    echo ""
fi
