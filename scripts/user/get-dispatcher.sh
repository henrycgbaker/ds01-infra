#!/bin/bash
# Get dispatcher - routes 'get limits' to check-limits
# Usage: get <subcommand> [args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo ""
    echo "Usage: get <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  limits    Show your resource limits and usage"
    echo ""
    echo "Examples:"
    echo "  get limits"
    echo "  get-limits"
    echo ""
}

SUBCOMMAND="${1:-}"
shift 2>/dev/null || true

case "$SUBCOMMAND" in
    limits)
        exec "$SCRIPT_DIR/check-limits" "$@"
        ;;
    -h|--help|help|"")
        show_usage
        ;;
    *)
        echo "Unknown subcommand: $SUBCOMMAND"
        echo "Run 'get --help' for usage."
        exit 1
        ;;
esac
