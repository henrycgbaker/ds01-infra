#!/bin/bash
# ============================================================================
# DS01 Admin Sudo Safety Script
# ============================================================================
# Ensures the datasciencelab admin account is always in the sudo group.
# Protects against accidental removal from sudo group.
#
# USAGE:
#   ensure-admin-sudo.sh              # Check and restore if needed
#   ensure-admin-sudo.sh --check      # Check only, don't modify
#
# CRON (hourly):
#   0 * * * * root /opt/ds01-infra/scripts/maintenance/ensure-admin-sudo.sh
# ============================================================================

set -e

# Configuration
ADMIN_USER="datasciencelab"
LOG_TAG="DS01-admin-sudo"
CHECK_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: ensure-admin-sudo.sh [--check]"
            echo ""
            echo "Ensures $ADMIN_USER is in the sudo group."
            echo ""
            echo "Options:"
            echo "  --check    Check only, don't modify"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Logging helper
log() {
    local level="$1"
    local msg="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg"
    logger -t "$LOG_TAG" -p "auth.${level}" "$msg" 2>/dev/null || true
}

# Check if user exists
if ! id "$ADMIN_USER" &>/dev/null; then
    log "error" "Admin user $ADMIN_USER does not exist!"
    exit 1
fi

# Check if user is in sudo group
if groups "$ADMIN_USER" 2>/dev/null | grep -q '\bsudo\b'; then
    log "info" "$ADMIN_USER is in sudo group - OK"
    exit 0
fi

# User is NOT in sudo group
log "warning" "$ADMIN_USER is NOT in sudo group!"

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "CHECK ONLY: Would restore $ADMIN_USER to sudo group"
    exit 1
fi

# Restore to sudo group
log "warning" "Restoring $ADMIN_USER to sudo group"
usermod -aG sudo "$ADMIN_USER"

if groups "$ADMIN_USER" 2>/dev/null | grep -q '\bsudo\b'; then
    log "info" "$ADMIN_USER successfully restored to sudo group"

    # Send alert (optional - configure email if needed)
    # echo "WARNING: $ADMIN_USER was removed from sudo group and has been restored." | \
    #     mail -s "DS01 ALERT: Admin sudo group restored" admin@example.com

    exit 0
else
    log "error" "Failed to restore $ADMIN_USER to sudo group!"
    exit 1
fi
