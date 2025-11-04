#!/bin/bash
# Project Management - Main dispatcher for project operations
# Usage: project <subcommand> [args...]

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
    echo -e "  ${BOLD}Project Management${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  project <subcommand> [args...]"
    echo ""
    echo -e "${BOLD}Subcommands:${NC}"
    echo -e "  ${GREEN}init${NC}        Create a new project with GitHub integration"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}project init${NC}"
    echo -e "  ${CYAN}project init${NC} my-thesis"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use hyphenated form: ${CYAN}project-init${NC}"
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

# Check if subcommand script exists
SUBCOMMAND_SCRIPT="$SCRIPT_DIR/project-$SUBCOMMAND"

if [ ! -f "$SUBCOMMAND_SCRIPT" ]; then
    echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
    echo ""
    echo "Available subcommands: init"
    echo "Run 'project help' for more information"
    exit 1
fi

# Execute subcommand, passing all remaining arguments
shift
exec "$SUBCOMMAND_SCRIPT" "$@"
