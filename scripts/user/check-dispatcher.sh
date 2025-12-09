#!/bin/bash
# Check dispatcher - routes 'check limits' to check-limits
# Usage: check <subcommand> [args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo ""
    echo "Usage: check <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  limits    Show your resource limits and usage"
    echo ""
    echo "Examples:"
    echo "  check limits"
    echo "  check-limits"
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
        echo "Run 'check --help' for usage."
        exit 1
        ;;
esac
