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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠ Warning: Not running as root${NC}"
    echo "Some symlinks may fail to create. Run with: sudo $0"
    echo ""
fi

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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 1: Base System Wrappers${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh" "mlc-create" "(wraps aime-ml-containers)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/mlc-stats-wrapper.sh" "mlc-stats" "(wraps aime-ml-containers)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 2: Atomic Unit Commands${NC}"
echo ""

echo -e "${BOLD}Container Management (10 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-create" "container-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-run" "container-run" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-open" "container-open" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-start" "container-start" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stop" "container-stop" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-pause" "container-pause" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-list" "container-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stats" "container-stats" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-remove" "container-remove" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-exit" "container-exit" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Image Management (4 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/image-create" "image-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-list" "image-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-update" "image-update" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-delete" "image-delete" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Project Setup Modules (6 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/dir-create" "dir-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/git-init" "git-init" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/readme-create" "readme-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/shell-setup" "shell-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/ssh-setup" "ssh-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/vscode-setup" "vscode-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 3: Container Orchestrators${NC}"
echo ""

echo -e "${BOLD}Container Orchestrators (ephemeral model):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-deploy" "container-deploy" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-retire" "container-retire" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Dispatchers:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-dispatcher.sh" "container" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-dispatcher.sh" "image" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/project-dispatcher.sh" "project" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-dispatcher.sh" "user" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 4: Workflow Orchestrators${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/user/project-init" "project-init" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-setup" "user-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}User Utilities${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/user/ds01-status" "ds01-status" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/ds01-run" "ds01-run" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/get-limits" "get-limits" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/ssh-config" "ssh-config" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/install-to-image.sh" "install-to-image" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Admin Commands${NC}"
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "alias-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "aliases" "(→ alias-list)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "commands" "(→ alias-list)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/alias-list" "help" "(→ alias-list)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/alias-create" "alias-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-dashboard" "ds01-dashboard" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-logs" "ds01-logs" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-users" "ds01-users" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/ds01-mig-partition" "ds01-mig-partition" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/admin/version" "version" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Monitoring & Audit Commands${NC}"
create_symlink "$INFRA_ROOT/scripts/monitoring/container-dashboard.sh" "container-dashboard" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/gpu-status-dashboard.py" "gpu-dashboard" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh" "check-idle-containers" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-system.sh" "audit-system" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-docker.sh" "audit-docker" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/audit-container.sh" "audit-container" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/monitoring/who-owns-containers.sh" "ds01-who" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}Legacy Aliases (Deprecated - For Backwards Compatibility)${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/user/project-init" "new-project" "(→ project-init)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-setup" "new-user" "(→ user-setup)" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Symlinks created: ${GREEN}$SUCCESS_COUNT${NC}"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "Failed/Skipped:   ${YELLOW}$FAIL_COUNT${NC}"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}Command Examples:${NC}"
echo ""
echo -e "${CYAN}Tier 4 - Complete Onboarding:${NC}"
echo "  user-setup                  # First-time user onboarding wizard"
echo "  user setup                  # Same (via dispatcher)"
echo "  get-limits                  # Show resource limits and usage"
echo "  user get-limits --guided    # With explanations"
echo ""
echo -e "${CYAN}Tier 3 - Project Setup:${NC}"
echo "  project-init                # Complete project setup"
echo "  project-init --guided       # With explanations"
echo "  project init --guided       # Same (via dispatcher)"
echo ""
echo -e "${CYAN}Tier 2 - Container Management:${NC}"
echo "  container-create my-proj pytorch    # Create container"
echo "  container-run my-proj               # Start and enter container"
echo "  container list                      # List containers (via dispatcher)"
echo "  container-list                      # Same (direct command)"
echo ""
echo -e "${CYAN}Tier 2 - Image Management:${NC}"
echo "  image-create my-image --type=cv    # Create custom image"
echo "  image list                         # List images (via dispatcher)"
echo ""
echo -e "${CYAN}Tier 1 - Base System (Enhanced):${NC}"
echo "  mlc-create my-proj pytorch         # Create with resource limits"
echo "  mlc-open my-proj                   # Open container"
echo "  mlc-list                           # List containers"
echo "  mlc-stats                          # Show resource usage"
echo ""
echo -e "${YELLOW}💡 All commands support --help for usage information${NC}"
echo ""
