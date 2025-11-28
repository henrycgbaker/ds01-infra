#!/bin/bash
# /opt/ds01-infra/scripts/system/pam-add-docker-group.sh
# PAM session script to auto-add users to docker group on first login
#
# This script is called by PAM on user login. It runs as root.
# It checks if the user is in the docker group and adds them if not.
#
# Installation:
#   Add to /etc/pam.d/common-session:
#   session optional pam_exec.so /opt/ds01-infra/scripts/system/pam-add-docker-group.sh
#
# PAM provides these environment variables:
#   PAM_USER - the username
#   PAM_TYPE - open_session or close_session

# Only run on session open
[ "$PAM_TYPE" = "open_session" ] || exit 0

# Need a username
[ -n "$PAM_USER" ] || exit 0

# Skip system users (UID < 1000)
USER_UID=$(id -u "$PAM_USER" 2>/dev/null) || exit 0
[ "$USER_UID" -ge 1000 ] || exit 0

# Skip if already in docker group
if groups "$PAM_USER" 2>/dev/null | grep -q '\bdocker\b'; then
    exit 0
fi

# Add to docker group (silently)
usermod -aG docker "$PAM_USER" 2>/dev/null || true

# Log the addition
echo "[$(date '+%Y-%m-%d %H:%M:%S')] PAM: Added $PAM_USER to docker group on first login" >> /var/log/ds01/docker-group-additions.log 2>/dev/null || true

exit 0
