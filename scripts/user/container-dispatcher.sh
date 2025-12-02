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
    echo -e "${BOLD}L3 Orchestrators (Recommended):${NC}"
    echo -e "  ${GREEN}deploy${NC}      Create AND start container (create + run)"
    echo -e "  ${GREEN}retire${NC}      Stop AND remove container (stop + remove)"
    echo ""
    echo -e "${BOLD}L2 Atomic Commands (Advanced):${NC}"
    echo -e "  ${GREEN}create${NC}      Create a new container"
    echo -e "  ${GREEN}start${NC}       Start container in background"
    echo -e "  ${GREEN}run${NC}         Start and attach to a container"
    echo -e "  ${GREEN}open${NC}        Attach to running container"
    echo -e "  ${GREEN}stop${NC}        Stop a running container"
    echo -e "  ${GREEN}pause${NC}       Pause container (freeze processes, keep GPU)"
    echo -e "  ${GREEN}remove${NC}      Remove stopped containers"
    echo -e "  ${GREEN}list${NC}        List your containers"
    echo -e "  ${GREEN}stats${NC}       Show resource usage statistics"
    echo -e "  ${GREEN}exit${NC}        Exit container (without stopping)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}# Quick deploy (L3 Orchestrator)${NC}"
    echo -e "  container deploy my-project"
    echo -e "  container retire my-project"
    echo ""
    echo -e "  ${CYAN}# Step-by-step (L2 Atomic)${NC}"
    echo -e "  container create my-project pytorch"
    echo -e "  container run my-project"
    echo -e "  container pause my-project"
    echo -e "  container stop my-project"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use hyphenated form: ${CYAN}container-deploy${NC}, ${CYAN}container-list${NC}, etc."
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

# Check if subcommand script exists
SUBCOMMAND_SCRIPT="$SCRIPT_DIR/container-$SUBCOMMAND"

if [ ! -f "$SUBCOMMAND_SCRIPT" ]; then
    echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
    echo ""
    echo "Available subcommands:"
    echo "  L3 Orchestrators: deploy, retire"
    echo "  L2 Atomic: create, start, run, open, stop, pause, remove, list, stats, exit"
    echo ""
    echo "Run 'container help' for more information"
    exit 1
fi

# Execute subcommand, passing all remaining arguments
shift
exec "$SUBCOMMAND_SCRIPT" "$@"
