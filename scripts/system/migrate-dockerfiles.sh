#!/bin/bash
# Migration script: Rename docker-images → dockerfiles
# Ensures accurate terminology and directory structure

set -e

BLUE='\033[94m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 Directory Migration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "This script will rename:"
echo -e "  ${YELLOW}~/docker-images/${NC} → ${GREEN}~/dockerfiles/${NC}"
echo ""
echo "Why? The old name was misleading - it stores Dockerfiles, not images."
echo "Docker images are stored in Docker's internal storage."
echo ""

OLD_DIR="$HOME/docker-images"
NEW_DIR="$HOME/dockerfiles"

# Check if old directory exists
if [ ! -d "$OLD_DIR" ]; then
    echo -e "${YELLOW}⚠ Nothing to migrate${NC}"
    echo "Directory $OLD_DIR does not exist."

    # Check if new directory already exists
    if [ -d "$NEW_DIR" ]; then
        echo -e "${GREEN}✓ $NEW_DIR already exists${NC}"
    else
        echo ""
        echo "Creating $NEW_DIR..."
        mkdir -p "$NEW_DIR"
        echo -e "${GREEN}✓ Created $NEW_DIR${NC}"
    fi
    echo ""
    exit 0
fi

# Check if new directory already exists
if [ -d "$NEW_DIR" ]; then
    echo -e "${RED}✗ Conflict detected${NC}"
    echo ""
    echo "Both directories exist:"
    echo "  $OLD_DIR"
    echo "  $NEW_DIR"
    echo ""
    echo "Please manually merge or remove one of them."
    echo ""
    exit 1
fi

# Show what will be migrated
echo -e "${BOLD}Files to migrate:${NC}"
echo ""
ls -lh "$OLD_DIR" | tail -n +2
echo ""

read -p "Continue with migration? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

echo ""
echo -e "${CYAN}Migrating files...${NC}"

# Rename directory
mv "$OLD_DIR" "$NEW_DIR"

echo -e "${GREEN}✓ Migration complete${NC}"
echo ""
echo "Your Dockerfiles are now in: ${GREEN}$NEW_DIR${NC}"
echo ""

# Update any .info files that reference the old path
INFO_DIR="$HOME/ds01-config/images"
if [ -d "$INFO_DIR" ]; then
    echo "Updating metadata files..."
    for info_file in "$INFO_DIR"/*.info; do
        if [ -f "$info_file" ]; then
            sed -i "s|$OLD_DIR|$NEW_DIR|g" "$info_file"
        fi
    done
    echo -e "${GREEN}✓ Metadata updated${NC}"
    echo ""
fi

echo -e "${BOLD}What's changed:${NC}"
echo ""
echo "  • Dockerfiles moved to ~/dockerfiles/"
echo "  • All existing images and containers still work"
echo "  • Commands automatically use new location"
echo ""
echo -e "${GREEN}No further action needed!${NC}"
echo ""
