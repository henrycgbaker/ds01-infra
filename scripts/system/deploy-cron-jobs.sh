#!/bin/bash
# Deploy DS01 cron jobs to /etc/cron.d/
# Run with: sudo bash /opt/ds01-infra/scripts/system/deploy-cron-jobs.sh

set -e

# Resolve symlinks to get actual script location
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CRON_SOURCE="$INFRA_ROOT/config/etc-mirrors/cron.d"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 Cron Jobs Deployment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

# Check if source directory exists
if [ ! -d "$CRON_SOURCE" ]; then
    echo -e "${RED}Error: Cron source directory not found: $CRON_SOURCE${NC}"
    exit 1
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

echo -e "${BOLD}Deploying cron jobs from:${NC} $CRON_SOURCE"
echo ""

# Deploy each cron file
for cron_file in "$CRON_SOURCE"/*; do
    if [ ! -f "$cron_file" ]; then
        continue
    fi

    filename=$(basename "$cron_file")
    target="/etc/cron.d/$filename"

    echo -e "Deploying: ${CYAN}$filename${NC}"

    if cp "$cron_file" "$target"; then
        chmod 644 "$target"
        echo -e "  ${GREEN}✓${NC} Deployed to $target"
        ((SUCCESS_COUNT++))
    else
        echo -e "  ${RED}✗${NC} Failed to deploy $filename"
        ((FAIL_COUNT++))
    fi
    echo ""
done

# Restart cron service
echo -e "${BOLD}Restarting cron service...${NC}"
if systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Cron service restarted"
else
    echo -e "${YELLOW}⚠${NC} Could not restart cron service (may need manual restart)"
fi
echo ""

# Summary
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Cron jobs deployed: ${GREEN}$SUCCESS_COUNT${NC}"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "Failed:            ${RED}$FAIL_COUNT${NC}"
fi
echo ""

# List deployed jobs
echo -e "${BOLD}Deployed cron jobs:${NC}"
echo ""
ls -lh /etc/cron.d/ds01* 2>/dev/null || echo "No DS01 cron jobs found"
echo ""

# Show schedule
echo -e "${BOLD}Cron schedule summary:${NC}"
echo ""
echo "  GPU cleanup:       Every hour at :15"
echo "  Idle containers:   Every hour at :30"
echo "  Runtime limits:    Every hour at :45"
echo "  Metrics:           Every 5 minutes"
echo "  Daily report:      23:55"
echo "  Weekly audits:     Sunday 2-3am"
echo ""

echo -e "${GREEN}✓${NC} Cron deployment complete"
echo ""
