#!/bin/bash
# /opt/ds01-infra/scripts/system/setup-disk-quotas.sh
# DS01 Disk Quota Setup Script
#
# Sets up per-user disk quotas on ext4 filesystem using Linux quota system.
# Must be run as root.
#
# WARNING: This modifies /etc/fstab and requires remounting the filesystem.
# Test on a non-production system first!
#
# Usage:
#   sudo ./setup-disk-quotas.sh --check         # Check if quotas are available
#   sudo ./setup-disk-quotas.sh --install       # Install quota tools
#   sudo ./setup-disk-quotas.sh --enable        # Enable quotas on filesystem
#   sudo ./setup-disk-quotas.sh --set-user USER # Apply limits for user
#   sudo ./setup-disk-quotas.sh --set-all       # Apply limits for all users

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
WORKSPACE_ROOT="/home"  # Where user workspaces live

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if quota tools are installed and quotas are enabled
check_quotas() {
    echo "Checking disk quota status..."
    echo ""

    # Check quota tools
    if command -v repquota &>/dev/null; then
        log_info "Quota tools installed"
    else
        log_error "Quota tools not installed (apt install quota)"
        return 1
    fi

    # Check kernel support
    if [[ -f /proc/fs/ext4/nvme0n1p2/options ]] || modinfo quota_v2 &>/dev/null; then
        log_info "Kernel quota support available"
    else
        log_warn "Cannot verify kernel quota support"
    fi

    # Check /etc/fstab
    if grep -qE '^\s*[^#].*\s+/\s+ext4\s+.*usrquota' /etc/fstab; then
        log_info "/etc/fstab has usrquota option"
    else
        log_warn "/etc/fstab missing usrquota option"
    fi

    # Check if quotas are active
    if quotaon -p / 2>/dev/null | grep -q "is on"; then
        log_info "Quotas are currently ENABLED"
    else
        log_warn "Quotas are currently DISABLED"
    fi

    # Check aquota.user file
    if [[ -f /aquota.user ]]; then
        log_info "Quota database exists (/aquota.user)"
    else
        log_warn "Quota database not found (/aquota.user)"
    fi

    echo ""
    df -h / | head -2
}

# Install quota tools
install_quota_tools() {
    log_info "Installing quota tools..."
    apt-get update
    apt-get install -y quota
    log_info "Quota tools installed"
}

# Enable quotas on root filesystem
enable_quotas() {
    log_info "Enabling quotas on root filesystem..."

    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    log_info "Backed up /etc/fstab"

    # Check if usrquota already in fstab
    if ! grep -qE '^\s*[^#].*\s+/\s+ext4\s+.*usrquota' /etc/fstab; then
        log_info "Adding usrquota option to /etc/fstab"

        # Modify the root mount options
        # This sed replaces the options field for the root ext4 mount
        sed -i.bak 's|\(^[^#].*\s\+/\s\+ext4\s\+\)\([a-z,]*\)|\1\2,usrquota|' /etc/fstab

        log_warn "Modified /etc/fstab - you should verify the changes"
        grep -E '^\s*[^#].*\s+/\s+ext4' /etc/fstab
    else
        log_info "usrquota already in /etc/fstab"
    fi

    # Remount filesystem
    log_info "Remounting filesystem with quota support..."
    mount -o remount /

    # Create quota files
    log_info "Creating quota database..."
    quotacheck -cum /

    # Turn on quotas
    log_info "Enabling quotas..."
    quotaon /

    log_info "Quotas enabled successfully"
    quotaon -p /
}

# Get user's storage limit from resource-limits.yaml
get_user_storage_limit() {
    local username="$1"

    # Use Python to parse YAML and get merged limits
    python3 "$INFRA_ROOT/scripts/docker/get_resource_limits.py" "$username" 2>/dev/null | \
        grep -oP 'storage_workspace:\s*\K[0-9]+[GMTK]?' || echo "100G"
}

# Convert size to KB for quota
size_to_kb() {
    local size="$1"
    local num="${size%[GMTK]*}"
    local unit="${size##*[0-9]}"

    case "$unit" in
        G|g) echo $((num * 1024 * 1024)) ;;
        M|m) echo $((num * 1024)) ;;
        T|t) echo $((num * 1024 * 1024 * 1024)) ;;
        K|k|'') echo "$num" ;;
        *) echo "$num" ;;
    esac
}

# Set quota for a specific user
set_user_quota() {
    local username="$1"

    # Check user exists
    if ! id "$username" &>/dev/null; then
        log_error "User $username does not exist"
        return 1
    fi

    # Get storage limit
    local storage_limit=$(get_user_storage_limit "$username")
    local soft_limit_kb=$(size_to_kb "$storage_limit")
    local hard_limit_kb=$((soft_limit_kb * 110 / 100))  # Hard limit = soft + 10%

    log_info "Setting quota for $username: soft=${storage_limit} hard=$((hard_limit_kb/1024/1024))G"

    # Set quota (soft block, hard block, soft inode, hard inode)
    # Inode limit = approximate files based on average 100KB file size
    local soft_inodes=$((soft_limit_kb / 100))
    local hard_inodes=$((hard_limit_kb / 100))

    setquota -u "$username" "$soft_limit_kb" "$hard_limit_kb" "$soft_inodes" "$hard_inodes" /

    # Verify
    repquota -u / | grep "^$username" || log_warn "Could not verify quota for $username"
}

# Set quotas for all users based on resource-limits.yaml
set_all_quotas() {
    log_info "Setting quotas for all users..."

    # Get all users with UID >= 1000
    local count=0
    while IFS=: read -r username _ uid _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            set_user_quota "$username" && ((count++)) || true
        fi
    done < /etc/passwd

    log_info "Set quotas for $count users"

    echo ""
    echo "Current quota status:"
    repquota -u / | head -20
}

# Show quota report
show_report() {
    echo "Disk Quota Report"
    echo "================="
    repquota -u / 2>/dev/null || log_error "Cannot generate quota report"
}

# Main
case "${1:-}" in
    --check)
        check_quotas
        ;;
    --install)
        check_root
        install_quota_tools
        ;;
    --enable)
        check_root
        enable_quotas
        ;;
    --set-user)
        check_root
        if [[ -z "${2:-}" ]]; then
            log_error "Usage: $0 --set-user USERNAME"
            exit 1
        fi
        set_user_quota "$2"
        ;;
    --set-all)
        check_root
        set_all_quotas
        ;;
    --report)
        show_report
        ;;
    *)
        echo "DS01 Disk Quota Setup"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  --check       Check if quotas are available"
        echo "  --install     Install quota tools"
        echo "  --enable      Enable quotas on filesystem (modifies fstab)"
        echo "  --set-user U  Set quota for user U from resource-limits.yaml"
        echo "  --set-all     Set quotas for all users"
        echo "  --report      Show quota report"
        echo ""
        echo "Typical setup process:"
        echo "  1. $0 --check      # Check current status"
        echo "  2. $0 --install    # Install tools if needed"
        echo "  3. $0 --enable     # Enable quotas (requires remount)"
        echo "  4. $0 --set-all    # Apply limits from resource-limits.yaml"
        echo ""
        echo "WARNING: Enabling quotas modifies /etc/fstab and remounts /."
        echo "         Test on non-production system first!"
        ;;
esac
