#!/bin/bash
# DS01 Infrastructure - Command Deployment
# Copies all DS01 commands to /usr/local/bin (not symlinks)
# Run with: sudo /opt/ds01-infra/scripts/system/deploy-commands.sh
#
# Security: Copies files instead of symlinking to keep /opt/ds01-infra secure
# This allows /opt/ds01-infra to have restrictive permissions (700) while
# commands in /usr/local/bin remain accessible (755) to all users
#
# Four-Tier Architecture:
#   Tier 1: Base System (mlc-* wrappers)
#   Tier 2: Modular Unit Commands (single-purpose, reusable)
#   Tier 3: Workflow Orchestrators (multi-step workflows)
#   Tier 4: Workflow Wizards (complete onboarding)

#set -e

INFRA_ROOT="/opt/ds01-infra"
SYMLINK_DIR="/usr/local/bin"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 Infrastructure - Command Deployment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Require root
RED='\033[0;31m'
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This command requires sudo${NC}"
    echo "Run with: sudo deploy"
    exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}Setting Source File Permissions${NC}"
echo ""
# All scripts need 755 (rwxr-xr-x) so they can be:
# - Sourced by other scripts (bash source command)
# - Called via python3 /path/to/script.py
# - Executed by wrapper scripts

chmod 755 "$INFRA_ROOT"/scripts/user/* 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/user/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/lib/*.sh "$INFRA_ROOT"/scripts/lib/*.py 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/lib/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/docker/*.sh "$INFRA_ROOT"/scripts/docker/*.py 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/docker/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/admin/* 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/admin/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/monitoring/*.sh "$INFRA_ROOT"/scripts/monitoring/*.py 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/monitoring/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/maintenance/*.sh 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/maintenance/* → 755"

chmod 755 "$INFRA_ROOT"/scripts/system/*.sh 2>/dev/null
echo -e "${GREEN}✓${NC} scripts/system/* → 755"

# Config files need 644 (rw-r--r--) - readable by all
chmod 644 "$INFRA_ROOT"/config/*.yaml "$INFRA_ROOT"/config/*.yml 2>/dev/null
echo -e "${GREEN}✓${NC} config/*.yaml → 644"

echo ""

create_symlink() {
    local target=$1
    local linkname=$2
    local description=$3

    if [ ! -f "$target" ] && [ ! -d "$target" ]; then
        echo -e "${YELLOW}⚠${NC} Skipped: $linkname (target not found: $target)"
        return 1
    fi

    # Copy file instead of symlinking (keeps /opt/ds01-infra secure)
    # Remove old symlink/file first
    rm -f "$SYMLINK_DIR/$linkname" 2>/dev/null

    if cp "$target" "$SYMLINK_DIR/$linkname" 2>/dev/null; then
        chmod 755 "$SYMLINK_DIR/$linkname" 2>/dev/null
        echo -e "${GREEN}✓${NC} $linkname ${description:+→ $description}"
        return 0
    else
        echo -e "${YELLOW}✗${NC} Failed: $linkname (permission denied?)"
        return 1
    fi
}

SUCCESS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════════════════════════════════════════
#                              USER COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}USER COMMANDS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --- Onboarding & Setup ---
echo -e "${BOLD}Onboarding:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/user-setup" "user-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/project-init" "project-init" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/project-launch" "project-launch" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/shell-setup" "shell-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/ssh-setup" "ssh-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/vscode-setup" "vscode-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Container Commands ---
echo -e "${BOLD}Container Lifecycle:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-deploy" "container-deploy" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-retire" "container-retire" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-create" "container-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-start" "container-start" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-run" "container-run" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-attach" "container-attach" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stop" "container-stop" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-remove" "container-remove" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-pause" "container-pause" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-exit" "container-exit" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-list" "container-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stats" "container-stats" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Image Commands ---
echo -e "${BOLD}Image Management:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/image-create" "image-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-update" "image-update" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/install-to-image.sh" "image-install" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-list" "image-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-delete" "image-delete" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Dashboard (user-facing) ---
echo -e "${BOLD}Dashboard:${NC}"
create_symlink "$INFRA_ROOT/scripts/admin/dashboard" "dashboard" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Resource Info ---
echo -e "${BOLD}Resource Info:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/check-limits" "check-limits" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/docker/gpu-queue-manager.py" "gpu-queue" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Dispatchers (natural language style) ---
echo -e "${BOLD}Dispatchers:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-dispatcher.sh" "container" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-dispatcher.sh" "image" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/project-dispatcher.sh" "project" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-dispatcher.sh" "user" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Help & Info ---
echo -e "${BOLD}Help:${NC}"
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "help" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "commands" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/version" "version" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Legacy (deprecated) ---
echo -e "${BOLD}Legacy (deprecated):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/project-init" "new-project" "(use project-init)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-setup" "new-user" "(use user-setup)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
#                              ADMIN COMMANDS (ds01-*)
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}ADMIN COMMANDS (ds01-* prefix)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --- Deployment ---
echo -e "${BOLD}Deployment:${NC}"
create_symlink "$INFRA_ROOT/scripts/system/deploy-commands.sh" "deploy" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Dashboard & Monitoring ---
echo -e "${BOLD}Dashboards:${NC}"
create_symlink "$INFRA_ROOT/scripts/admin/dashboard" "ds01-dashboard" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/gpu-status-dashboard.py" "ds01-gpu" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/container-dashboard.sh" "ds01-containers" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/gpu-utilization-monitor.py" "ds01-gpu-util" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/mig-utilization-monitor.py" "ds01-mig-util" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- System Management ---
echo -e "${BOLD}System:${NC}"
create_symlink "$INFRA_ROOT/scripts/admin/ds01-users" "ds01-users" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-logs" "ds01-logs" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/ds01-events" "ds01-events" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-mig-partition" "ds01-mig-partition" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/who-owns-containers.sh" "ds01-who" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/ds01-health-check" "ds01-health" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Auditing ---
echo -e "${BOLD}Auditing:${NC}"
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-system.sh" "ds01-audit" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-docker.sh" "ds01-audit-docker" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-container.sh" "ds01-audit-container" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Resource Management ---
echo -e "${BOLD}Resources:${NC}"
create_symlink "$INFRA_ROOT/scripts/docker/gpu-queue-manager.py" "ds01-gpu-queue" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/resource-alert-checker.sh" "ds01-alerts" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh" "ds01-idle" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# --- Maintenance ---
echo -e "${BOLD}Maintenance:${NC}"
create_symlink "$INFRA_ROOT/scripts/maintenance/backup-logs.sh" "ds01-backup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
#                              INTERNAL (not advertised)
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}INTERNAL (Tier 1 - not advertised)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh" "mlc-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/mlc-stats-wrapper.sh" "mlc-stats" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
#                              SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Commands deployed: ${GREEN}$SUCCESS_COUNT${NC}"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "Failed/Skipped:    ${YELLOW}$FAIL_COUNT${NC}"
fi
echo ""
echo -e "${BOLD}Quick Reference:${NC}"
echo ""
echo -e "  ${GREEN}User Commands:${NC}"
echo "    container deploy <name>    Start working"
echo "    container retire <name>    Done for the day"
echo "    help                       Show all commands"
echo ""
echo -e "  ${YELLOW}Admin Commands (sudo required):${NC}"
echo "    sudo deploy                Redeploy all commands"
echo "    ds01-dashboard             System overview"
echo "    ds01-users                 User management"
echo ""
echo -e "${YELLOW}💡 Run 'help' to see all available commands${NC}"
echo ""
