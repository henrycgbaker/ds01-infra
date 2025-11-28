#!/bin/bash
# /opt/ds01-infra/scripts/maintenance/auto-add-docker-group-cron.sh
# Cron script to auto-add new users to docker group
# Run hourly to catch new users
#
# Add to root crontab:
#   0 * * * * /opt/ds01-infra/scripts/maintenance/auto-add-docker-group-cron.sh

LOG_FILE="/var/log/ds01/docker-group-cron.log"

# Ensure we're root
if [ "$EUID" -ne 0 ]; then
    echo "Must run as root" >&2
    exit 1
fi

# Run the auto-add script in scan mode
/opt/ds01-infra/scripts/system/auto-add-docker-group.sh --scan >> "$LOG_FILE" 2>&1
