#!/bin/bash
# Restore original timeouts from backup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Restoring original timeouts...${NC}"
echo ""

# Find most recent backup
LATEST_BACKUP=$(ls -t "$CONFIG_FILE".backup-* 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}Error: No backup file found${NC}"
    echo "Backup files should match: $CONFIG_FILE.backup-*"
    exit 1
fi

echo -e "${YELLOW}Found backup: $LATEST_BACKUP${NC}"
echo ""

# Show current test values
echo -e "${BLUE}Current (test) values:${NC}"
grep -E "max_runtime:|idle_timeout:|gpu_hold_after_stop:|container_hold_after_stop:" "$CONFIG_FILE" | head -4

# Restore
cp "$LATEST_BACKUP" "$CONFIG_FILE"

echo ""
echo -e "${BLUE}Restored values:${NC}"
grep -E "max_runtime:|idle_timeout:|gpu_hold_after_stop:|container_hold_after_stop:" "$CONFIG_FILE" | head -4

echo ""
echo -e "${GREEN}✓ Original timeouts restored${NC}"
echo ""
echo "Backup preserved at: $LATEST_BACKUP"
echo ""
