#!/bin/bash
# DS01 Infrastructure - Command Deployment
# Copies all DS01 commands to /usr/local/bin (not symlinks)
# Run with: sudo /opt/ds01-infra/scripts/system/deploy.sh
#
# Security: Copies files instead of symlinking to keep /opt/ds01-infra secure
# This allows /opt/ds01-infra to have restrictive permissions (700) while
# commands in /usr/local/bin remain accessible (755) to all users
#
# Usage: sudo deploy [--verbose|-v]

INFRA_ROOT="/opt/ds01-infra"
DEST_DIR="/usr/local/bin"

# Subdirectory shortcuts
USER_ATOMIC="$INFRA_ROOT/scripts/user/atomic"
USER_ORCHESTRATORS="$INFRA_ROOT/scripts/user/orchestrators"
USER_WIZARDS="$INFRA_ROOT/scripts/user/wizards"
USER_HELPERS="$INFRA_ROOT/scripts/user/helpers"
USER_DISPATCHERS="$INFRA_ROOT/scripts/user/dispatchers"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Parse arguments
VERBOSE=false
for arg in "$@"; do
    case $arg in
        -v|--verbose) VERBOSE=true ;;
        -h|--help)
            echo "Usage: sudo deploy [OPTIONS]"
            echo ""
            echo "Deploy DS01 commands to /usr/local/bin"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show each command being deployed"
            echo "  -h, --help       Show this help"
            exit 0
            ;;
    esac
done

# Require root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This command requires sudo${NC}"
    echo "Run with: sudo deploy"
    exit 1
fi

# ============================================================================
# Helper Functions
# ============================================================================

# Counters for each category
declare -A CATEGORY_SUCCESS
declare -A CATEGORY_FAIL
declare -A CATEGORY_ERRORS
TOTAL_SUCCESS=0
TOTAL_FAIL=0

# Deploy a single command (silent by default)
deploy_cmd() {
    local target=$1
    local name=$2
    local category=$3

    if [ ! -f "$target" ]; then
        CATEGORY_FAIL[$category]=$((${CATEGORY_FAIL[$category]:-0} + 1))
        CATEGORY_ERRORS[$category]+="  ${YELLOW}!${NC} $name (not found)\n"
        ((TOTAL_FAIL++))
        return 1
    fi

    rm -f "$DEST_DIR/$name" 2>/dev/null
    if cp "$target" "$DEST_DIR/$name" && chmod 755 "$DEST_DIR/$name" 2>/dev/null; then
        CATEGORY_SUCCESS[$category]=$((${CATEGORY_SUCCESS[$category]:-0} + 1))
        ((TOTAL_SUCCESS++))
        $VERBOSE && echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        CATEGORY_FAIL[$category]=$((${CATEGORY_FAIL[$category]:-0} + 1))
        CATEGORY_ERRORS[$category]+="  ${RED}✗${NC} $name (copy failed)\n"
        ((TOTAL_FAIL++))
        return 1
    fi
}

# Print category result
print_category() {
    local name=$1
    local success=${CATEGORY_SUCCESS[$name]:-0}
    local fail=${CATEGORY_FAIL[$name]:-0}
    local total=$((success + fail))

    if [ $fail -eq 0 ]; then
        printf "  %-28s ${GREEN}✓${NC} %d commands\n" "$name" "$success"
    else
        printf "  %-28s ${YELLOW}!${NC} %d/%d (${YELLOW}%d failed${NC})\n" "$name" "$success" "$total" "$fail"
        echo -e "${CATEGORY_ERRORS[$name]}"
    fi
}

# ============================================================================
# Header
# ============================================================================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 Infrastructure - Command Deployment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================================================
# Set Permissions
# ============================================================================

echo -e "${DIM}Setting source permissions...${NC}"
chmod 755 "$USER_ATOMIC"/* 2>/dev/null
chmod 755 "$USER_ORCHESTRATORS"/* 2>/dev/null
chmod 755 "$USER_WIZARDS"/* 2>/dev/null
chmod 755 "$USER_HELPERS"/* 2>/dev/null
chmod 755 "$USER_DISPATCHERS"/* 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/lib/*.sh "$INFRA_ROOT"/scripts/lib/*.py 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/docker/*.sh "$INFRA_ROOT"/scripts/docker/*.py 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/admin/* 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/monitoring/*.sh "$INFRA_ROOT"/scripts/monitoring/*.py 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/maintenance/*.sh 2>/dev/null
chmod 755 "$INFRA_ROOT"/scripts/system/*.sh 2>/dev/null
chmod 644 "$INFRA_ROOT"/config/*.yaml "$INFRA_ROOT"/config/*.yml 2>/dev/null
echo ""

# ============================================================================
# Deploy Commands
# ============================================================================

echo -e "${BOLD}Deploying commands...${NC}"
echo ""

# --- Wizards (L4) ---
$VERBOSE && echo -e "${DIM}Wizards:${NC}"
deploy_cmd "$USER_WIZARDS/user-setup" "user-setup" "Wizards"
deploy_cmd "$USER_WIZARDS/project-init" "project-init" "Wizards"
deploy_cmd "$USER_WIZARDS/project-launch" "project-launch" "Wizards"

# --- Orchestrators (L3) ---
$VERBOSE && echo -e "${DIM}Orchestrators:${NC}"
deploy_cmd "$USER_ORCHESTRATORS/container-deploy" "container-deploy" "Orchestrators"
deploy_cmd "$USER_ORCHESTRATORS/container-retire" "container-retire" "Orchestrators"

# --- Atomic Container Commands (L2) ---
$VERBOSE && echo -e "${DIM}Container:${NC}"
deploy_cmd "$USER_ATOMIC/container-create" "container-create" "Container"
deploy_cmd "$USER_ATOMIC/container-start" "container-start" "Container"
deploy_cmd "$USER_ATOMIC/container-run" "container-run" "Container"
deploy_cmd "$USER_ATOMIC/container-attach" "container-attach" "Container"
deploy_cmd "$USER_ATOMIC/container-stop" "container-stop" "Container"
deploy_cmd "$USER_ATOMIC/container-remove" "container-remove" "Container"
deploy_cmd "$USER_ATOMIC/container-pause" "container-pause" "Container"
deploy_cmd "$USER_ATOMIC/container-unpause" "container-unpause" "Container"
deploy_cmd "$USER_ATOMIC/container-exit" "container-exit" "Container"
deploy_cmd "$USER_ATOMIC/container-list" "container-list" "Container"
deploy_cmd "$USER_ATOMIC/container-stats" "container-stats" "Container"

# --- Atomic Image Commands (L2) ---
$VERBOSE && echo -e "${DIM}Image:${NC}"
deploy_cmd "$USER_ATOMIC/image-create" "image-create" "Image"
deploy_cmd "$USER_ATOMIC/image-update" "image-update" "Image"
deploy_cmd "$USER_HELPERS/install-to-image.sh" "image-install" "Image"
deploy_cmd "$USER_ATOMIC/image-list" "image-list" "Image"
deploy_cmd "$USER_ATOMIC/image-delete" "image-delete" "Image"

# --- Dispatchers ---
$VERBOSE && echo -e "${DIM}Dispatchers:${NC}"
deploy_cmd "$USER_DISPATCHERS/container-dispatcher.sh" "container" "Dispatchers"
deploy_cmd "$USER_DISPATCHERS/image-dispatcher.sh" "image" "Dispatchers"
deploy_cmd "$USER_DISPATCHERS/project-dispatcher.sh" "project" "Dispatchers"
deploy_cmd "$USER_DISPATCHERS/user-dispatcher.sh" "user" "Dispatchers"
deploy_cmd "$USER_DISPATCHERS/check-dispatcher.sh" "check" "Dispatchers"
deploy_cmd "$USER_DISPATCHERS/get-dispatcher.sh" "get" "Dispatchers"

# --- Helpers ---
$VERBOSE && echo -e "${DIM}Helpers:${NC}"
deploy_cmd "$USER_HELPERS/shell-setup" "shell-setup" "Helpers"
deploy_cmd "$USER_HELPERS/ssh-setup" "ssh-setup" "Helpers"
deploy_cmd "$USER_HELPERS/vscode-setup" "vscode-setup" "Helpers"
deploy_cmd "$USER_HELPERS/check-limits" "check-limits" "Helpers"
deploy_cmd "$USER_HELPERS/check-limits" "get-limits" "Helpers"
deploy_cmd "$INFRA_ROOT/scripts/docker/gpu-queue-manager.py" "gpu-queue" "Helpers"

# --- Help & Info ---
$VERBOSE && echo -e "${DIM}Help:${NC}"
deploy_cmd "$INFRA_ROOT/scripts/admin/alias-list" "help" "Help"
deploy_cmd "$INFRA_ROOT/scripts/admin/alias-list" "commands" "Help"
deploy_cmd "$INFRA_ROOT/scripts/admin/version" "version" "Help"
deploy_cmd "$INFRA_ROOT/scripts/admin/dashboard" "dashboard" "Help"

# --- Legacy aliases ---
$VERBOSE && echo -e "${DIM}Legacy:${NC}"
deploy_cmd "$USER_WIZARDS/project-init" "new-project" "Legacy"
deploy_cmd "$USER_WIZARDS/user-setup" "new-user" "Legacy"

# --- Admin Commands ---
$VERBOSE && echo -e "${DIM}Admin:${NC}"
deploy_cmd "$INFRA_ROOT/scripts/system/deploy.sh" "deploy" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/admin/dashboard" "ds01-dashboard" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/gpu-status-dashboard.py" "ds01-gpu" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/container-dashboard.sh" "ds01-containers" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/gpu-utilization-monitor.py" "ds01-gpu-util" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/mig-utilization-monitor.py" "ds01-mig-util" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/admin/ds01-users" "ds01-users" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/admin/ds01-logs" "ds01-logs" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/ds01-events" "ds01-events" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/admin/ds01-mig-partition" "ds01-mig-partition" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/who-owns-containers.sh" "ds01-who" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/ds01-health-check" "ds01-health" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/audit-system.sh" "ds01-audit" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/audit-docker.sh" "ds01-audit-docker" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/audit-container.sh" "ds01-audit-container" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/docker/gpu-queue-manager.py" "ds01-gpu-queue" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/resource-alert-checker.sh" "ds01-alerts" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh" "ds01-idle" "Admin"
deploy_cmd "$INFRA_ROOT/scripts/maintenance/backup-logs.sh" "ds01-backup" "Admin"

# --- Internal (hidden from users) ---
$VERBOSE && echo -e "${DIM}Internal:${NC}"
deploy_cmd "$INFRA_ROOT/scripts/docker/docker-wrapper.sh" "docker" "Internal"
deploy_cmd "$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh" "mlc-create" "Internal"
deploy_cmd "$INFRA_ROOT/scripts/monitoring/mlc-stats-wrapper.sh" "mlc-stats" "Internal"

# ============================================================================
# Summary
# ============================================================================

if ! $VERBOSE; then
    # Compact output (default)
    print_category "Wizards"
    print_category "Orchestrators"
    print_category "Container"
    print_category "Image"
    print_category "Dispatchers"
    print_category "Helpers"
    print_category "Help"
    print_category "Admin"
    print_category "Internal"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $TOTAL_FAIL -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Deployed ${BOLD}$TOTAL_SUCCESS${NC} commands successfully"
else
    echo -e "${YELLOW}!${NC} Deployed ${BOLD}$TOTAL_SUCCESS${NC} commands, ${YELLOW}$TOTAL_FAIL failed${NC}"
fi

echo ""
echo -e "${DIM}Run 'help' to see all available commands${NC}"
echo ""
