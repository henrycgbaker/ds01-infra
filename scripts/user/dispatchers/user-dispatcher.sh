#!/bin/bash
# User Management - Main dispatcher for user operations
# Usage: user <subcommand> [args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_usage() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}User Commands${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  user <subcommand> [args...]"
    echo ""
    echo -e "${BOLD}Subcommands:${NC}"
    echo -e "  ${GREEN}setup${NC}, ${GREEN}new${NC}          Educational first-time user onboarding wizard"
    echo -e "  ${GREEN}get-limits${NC}, ${GREEN}limits${NC}   Show your resource limits and usage dashboard"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}user setup${NC}           # Run educational onboarding wizard"
    echo -e "  ${CYAN}user new${NC}             # Same as above"
    echo -e "  ${CYAN}user get-limits${NC}      # Show resource dashboard"
    echo -e "  ${CYAN}user limits${NC}          # Short alias"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use: ${CYAN}user-setup${NC}, ${CYAN}new-user${NC}, ${CYAN}get-limits${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Get subcommand
SUBCOMMAND="${1:-}"

if [ -z "$SUBCOMMAND" ] || [ "$SUBCOMMAND" = "help" ] || [ "$SUBCOMMAND" = "-h" ] || [ "$SUBCOMMAND" = "--help" ] || [ "$SUBCOMMAND" = "--info" ]; then
    show_usage
    exit 0
fi

# Map subcommands to scripts
case "$SUBCOMMAND" in
    setup|new)
        shift
        exec "$SCRIPT_DIR/user-setup" "$@"
        ;;
    get-limits|limits|quota)
        shift
        exec "$SCRIPT_DIR/get-limits" "$@"
        ;;
    *)
        echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
        echo ""
        echo "Available subcommands: setup, new, get-limits, limits"
        echo "Run 'user help' for more information"
        exit 1
        ;;
esac
