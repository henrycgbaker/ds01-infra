#!/bin/bash
# Docker Image Management - Main dispatcher for image operations
# Usage: image <subcommand> [args...]

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
    echo -e "  ${BOLD}Docker Image Management${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  image <subcommand> [args...]"
    echo ""
    echo -e "${BOLD}Subcommands:${NC}"
    echo -e "  ${GREEN}create${NC}      Create a custom Docker image"
    echo -e "  ${GREEN}list${NC}        List available images"
    echo -e "  ${GREEN}update${NC}      Rebuild/update an existing image"
    echo -e "  ${GREEN}delete${NC}      Remove unused images"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}image create${NC}"
    echo -e "  ${CYAN}image list${NC}"
    echo -e "  ${CYAN}image update${NC} my-image"
    echo -e "  ${CYAN}image delete${NC} old-image"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can also use hyphenated form: ${CYAN}image-create${NC}, ${CYAN}image-list${NC}, etc."
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
SUBCOMMAND_SCRIPT="$SCRIPT_DIR/image-$SUBCOMMAND"

if [ ! -f "$SUBCOMMAND_SCRIPT" ]; then
    echo -e "${RED}Error:${NC} Unknown subcommand: ${BOLD}$SUBCOMMAND${NC}"
    echo ""
    echo "Available subcommands: create, list, update, delete"
    echo "Run 'image help' for more information"
    exit 1
fi

# Execute subcommand, passing all remaining arguments
shift
exec "$SUBCOMMAND_SCRIPT" "$@"
