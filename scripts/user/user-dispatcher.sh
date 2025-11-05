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
    echo -e "  ${BOLD}User Onboarding & Setup${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  user <subcommand> [args...]"
    echo ""
    echo -e "${BOLD}Subcommands:${NC}"
    echo -e "  ${GREEN}setup${NC}, ${GREEN}new${NC}     Beginner-friendly project setup wizard"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}user setup${NC}           # Run beginner wizard"
    echo -e "  ${CYAN}user new${NC}             # Same as above"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use: ${CYAN}project-init-beginner${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Get subcommand
SUBCOMMAND="${1:-}"

if [ -z "$SUBCOMMAND" ] || [ "$SUBCOMMAND" = "help" ] || [ "$SUBCOMMAND" = "-h" ] || [ "$SUBCOMMAND" = "--help" ]; then
    show_usage
    exit 0
fi

# Map subcommands to project-init-beginner
case "$SUBCOMMAND" in
    setup|new)
        shift
        exec "$SCRIPT_DIR/project-init-beginner" "$@"
        ;;
    *)
        echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
        echo ""
        echo "Available subcommands: setup, new"
        echo "Run 'user help' for more information"
        exit 1
        ;;
esac
