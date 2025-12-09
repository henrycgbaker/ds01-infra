#!/bin/bash
# /opt/ds01-infra/config/deploy/profile.d/ds01-warnings.sh
# DS01 Login Warnings
#
# Deploy to /etc/profile.d/ to enable for all users:
#   sudo cp /opt/ds01-infra/config/deploy/profile.d/ds01-warnings.sh /etc/profile.d/
#   sudo chmod 644 /etc/profile.d/ds01-warnings.sh

# Only run for interactive shells
[[ $- != *i* ]] && return

# Only run for regular users (UID >= 1000)
[[ $(id -u) -lt 1000 ]] && return

# Run the login check script
DS01_LOGIN_CHECK="/opt/ds01-infra/scripts/user/ds01-login-check"
if [[ -x "$DS01_LOGIN_CHECK" ]]; then
    "$DS01_LOGIN_CHECK"
fi
