#!/bin/bash
# Setup user command symlinks in /usr/local/bin
# Also creates records in config/usr-mirrors for tracking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
USER_SCRIPTS_DIR="$INFRA_ROOT/scripts/user"
MIRROR_DIR="$INFRA_ROOT/config/usr-mirrors/local/bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error:${NC} This script must be run as root (use sudo)"
    exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 User Command Symlink Setup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create mirror directory
mkdir -p "$MIRROR_DIR"

# List of user commands to symlink
USER_COMMANDS=(
    # Main dispatchers
    "container"
    "image"
    "project"

    # Container subcommands (also available as standalone)
    "container-create"
    "container-run"
    "container-stop"
    "container-exit"
    "container-list"
    "container-stats"
    "container-cleanup"

    # Image subcommands
    "image-create"
    "image-list"
    "image-update"
    "image-delete"

    # Project subcommands
    "project-init"

    # Standalone commands
    "ssh-config"
    "user-setup"
)

# Create symlinks and record them
echo -e "${BOLD}Creating symlinks...${NC}"
echo ""

for cmd in "${USER_COMMANDS[@]}"; do
    SOURCE="$USER_SCRIPTS_DIR/$cmd"
    TARGET="/usr/local/bin/$cmd"
    MIRROR_FILE="$MIRROR_DIR/$cmd.link"

    # Check if source exists
    if [ ! -f "$SOURCE" ]; then
        echo -e "${YELLOW}⚠${NC}  Skip: $cmd (source not found)"
        continue
    fi

    # Remove existing symlink if it exists
    if [ -L "$TARGET" ]; then
        rm "$TARGET"
    fi

    # Create symlink
    ln -sf "$SOURCE" "$TARGET"

    # Record symlink in mirror directory
    cat > "$MIRROR_FILE" << EOF
# Symlink record for: $cmd
# Created: $(date -Iseconds)
# Source: $SOURCE
# Target: $TARGET

ln -sf $SOURCE $TARGET
EOF

    echo -e "${GREEN}✓${NC} $cmd -> /usr/local/bin/$cmd"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Symlinks created: ${BOLD}${#USER_COMMANDS[@]}${NC}"
echo -e "Mirror records: ${CYAN}$MIRROR_DIR${NC}"
echo ""
echo -e "${BOLD}Test commands:${NC}"
echo "  container help"
echo "  container list"
echo "  image list"
echo "  user-setup"
echo ""
