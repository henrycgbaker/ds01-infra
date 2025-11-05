#!/bin/bash
# DS01 Infrastructure - Symlink Management
# Creates symlinks for all DS01 commands in /usr/local/bin
# Run with: sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh
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
echo -e "${BOLD}DS01 Infrastructure - Symlink Update${NC}"
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

    if ln -sf "$target" "$SYMLINK_DIR/$linkname" 2>/dev/null; then
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
echo -e "${BOLD}TIER 2: Modular Unit Commands${NC}"
echo ""

echo -e "${BOLD}Container Management (7 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-create" "container-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-run" "container-run" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stop" "container-stop" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-list" "container-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-stats" "container-stats" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-cleanup" "container-cleanup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/container-exit" "container-exit" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Image Management (4 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/image-create" "image-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-list" "image-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-update" "image-update" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-delete" "image-delete" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Project Setup Modules (5 commands):${NC}"
create_symlink "$INFRA_ROOT/scripts/user/dir-create" "dir-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/git-init" "git-init" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/readme-create" "readme-create" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/ssh-setup" "ssh-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/vscode-setup" "vscode-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 3: Workflow Orchestrators & Dispatchers${NC}"
echo ""

echo -e "${BOLD}Orchestrators:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/project-init" "project-init" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

echo -e "${BOLD}Dispatchers:${NC}"
create_symlink "$INFRA_ROOT/scripts/user/container-dispatcher.sh" "container" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/image-dispatcher.sh" "image" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/project-dispatcher.sh" "project" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/user-dispatcher.sh" "user" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}TIER 4: Workflow Wizards${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/user/user-setup" "user-setup" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${BOLD}Admin & Utility Commands${NC}"
echo ""

create_symlink "$INFRA_ROOT/scripts/user/ds01-status" "ds01-status" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
create_symlink "$INFRA_ROOT/scripts/user/alias-list" "alias-list" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
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
