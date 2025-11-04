#!/bin/bash
# Container Management - Main dispatcher for container operations
# Usage: container <subcommand> [args...]

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
    echo -e "  ${BOLD}Container Management${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  container <subcommand> [args...]"
    echo ""
    echo -e "${BOLD}Subcommands:${NC}"
    echo -e "  ${GREEN}create${NC}      Create a new container"
    echo -e "  ${GREEN}run${NC}         Start and attach to a container"
    echo -e "  ${GREEN}stop${NC}        Stop a running container"
    echo -e "  ${GREEN}exit${NC}        Exit container (without stopping)"
    echo -e "  ${GREEN}list${NC}        List your containers"
    echo -e "  ${GREEN}stats${NC}       Show resource usage statistics"
    echo -e "  ${GREEN}cleanup${NC}     Remove stopped containers"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}container create${NC} my-project pytorch"
    echo -e "  ${CYAN}container list${NC}"
    echo -e "  ${CYAN}container run${NC} my-project"
    echo -e "  ${CYAN}container stop${NC} my-project"
    echo -e "  ${CYAN}container stats${NC}"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use hyphenated form: ${CYAN}container-create${NC}, ${CYAN}container-list${NC}, etc."
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
SUBCOMMAND_SCRIPT="$SCRIPT_DIR/container-$SUBCOMMAND"

if [ ! -f "$SUBCOMMAND_SCRIPT" ]; then
    echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
    echo ""
    echo "Available subcommands: create, run, stop, exit, list, stats, cleanup"
    echo "Run 'container help' for more information"
    exit 1
fi

# Execute subcommand, passing all remaining arguments
shift
exec "$SUBCOMMAND_SCRIPT" "$@"
