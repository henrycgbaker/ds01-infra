#!/bin/bash
# PAM session script: Ensure user has .bashrc on login
# File: /opt/ds01-infra/scripts/system/pam-ensure-bashrc.sh
# Deploy to: /usr/local/bin/pam-ensure-bashrc.sh
# Called by: /etc/pam.d/common-session

# This script runs on every login and ensures the user has a .bashrc
# If missing, copies from /etc/skel/.bashrc

# Get user info from PAM environment
USER="${PAM_USER:-$USER}"
HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

# Exit if not a real user (root, system users, etc.)
if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    exit 0
fi

# Exit if user already has .bashrc
if [ -f "$HOME_DIR/.bashrc" ]; then
    exit 0
fi

# Copy .bashrc from skel template
if [ -f /etc/skel/.bashrc ]; then
    cp /etc/skel/.bashrc "$HOME_DIR/.bashrc"
    chown "$USER:$(id -gn "$USER")" "$HOME_DIR/.bashrc"
    chmod 644 "$HOME_DIR/.bashrc"

    # Log the action
    logger -t ds01-pam "Created .bashrc for user: $USER"
fi

exit 0
