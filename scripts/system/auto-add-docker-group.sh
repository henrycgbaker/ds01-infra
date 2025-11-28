#!/bin/bash
# /opt/ds01-infra/scripts/system/auto-add-docker-group.sh
# Auto-add users to docker group - can be called from user-setup or cron
#
# This script is designed to be run via sudo by users in the docker group
# or by root directly. It safely adds users to the docker group.
#
# Usage:
#   sudo auto-add-docker-group.sh <username>     # Add specific user
#   sudo auto-add-docker-group.sh --scan         # Scan for new users and add them

set -e

LOG_FILE="/var/log/ds01/docker-group-additions.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" 2>/dev/null || echo "$1"
}

# Must be run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Check if docker group exists
if ! getent group docker &>/dev/null; then
    echo "Error: docker group does not exist"
    exit 1
fi

add_user_to_docker() {
    local username="$1"

    # Validate username exists
    if ! id "$username" &>/dev/null; then
        log_msg "ERROR: User '$username' does not exist"
        return 1
    fi

    # Check if already in docker group
    if groups "$username" 2>/dev/null | grep -q '\bdocker\b'; then
        log_msg "INFO: User '$username' already in docker group"
        return 0
    fi

    # Add to docker group
    if usermod -aG docker "$username"; then
        log_msg "SUCCESS: Added '$username' to docker group"
        return 0
    else
        log_msg "ERROR: Failed to add '$username' to docker group"
        return 1
    fi
}

scan_and_add_new_users() {
    log_msg "INFO: Scanning for users not in docker group..."

    local added=0
    local skipped=0

    # Get all users with home directories in /home
    for homedir in /home/*; do
        [ -d "$homedir" ] || continue

        local username=$(basename "$homedir")

        # Skip system/special directories
        case "$username" in
            lost+found|shared|.*) continue ;;
        esac

        # Skip if user doesn't exist in passwd/LDAP
        if ! id "$username" &>/dev/null; then
            continue
        fi

        # Skip if already in docker group
        if groups "$username" 2>/dev/null | grep -q '\bdocker\b'; then
            ((skipped++))
            continue
        fi

        # Add to docker group
        if add_user_to_docker "$username"; then
            ((added++))
        fi
    done

    log_msg "INFO: Scan complete. Added: $added, Already in group: $skipped"
    echo "Added $added user(s) to docker group"
}

# Main logic
case "${1:-}" in
    --scan)
        scan_and_add_new_users
        ;;
    --help|-h)
        echo "Usage: $0 <username>     Add specific user to docker group"
        echo "       $0 --scan         Scan /home and add all users"
        echo "       $0 --help         Show this help"
        ;;
    "")
        echo "Error: Username required"
        echo "Usage: $0 <username> or $0 --scan"
        exit 1
        ;;
    *)
        add_user_to_docker "$1"
        ;;
esac
