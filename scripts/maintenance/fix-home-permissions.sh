#!/bin/bash
# ============================================================================
# DS01 Home Directory Permission Fixer
# ============================================================================
# Ensures all home directories have correct privacy permissions.
# Run manually or via cron to fix any permission drift.
#
# USAGE:
#   fix-home-permissions.sh              # Fix all home directories
#   fix-home-permissions.sh --check      # Check only, report issues
#
# CRON (optional - weekly):
#   0 2 * * 0 root /opt/ds01-infra/scripts/maintenance/fix-home-permissions.sh
# ============================================================================

set -e

CHECK_ONLY=false
FIXED_COUNT=0
ISSUE_COUNT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: fix-home-permissions.sh [--check]"
            echo ""
            echo "Ensures home directories have 700 permissions and /home has 711."
            echo ""
            echo "Options:"
            echo "  --check    Check only, don't fix"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "DS01 Home Directory Permission Check"
echo "====================================="

# Check /home directory itself
HOME_PERMS=$(stat -c "%a" /home)
if [[ "$HOME_PERMS" != "711" ]]; then
    echo "[ISSUE] /home has permissions $HOME_PERMS (should be 711)"
    if [[ "$CHECK_ONLY" == "false" ]]; then
        chmod 711 /home
        echo "  -> Fixed"
        FIXED_COUNT=$((FIXED_COUNT + 1))
    else
        ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
else
    echo "[OK] /home has permissions 711"
fi

# Check each home directory
for dir in /home/*; do
    [[ -d "$dir" ]] || continue

    # Skip special directories
    [[ "$(basename "$dir")" == "lost+found" ]] && continue

    PERMS=$(stat -c "%a" "$dir")
    if [[ "$PERMS" != "700" ]]; then
        echo "[ISSUE] $dir has permissions $PERMS (should be 700)"
        if [[ "$CHECK_ONLY" == "false" ]]; then
            chmod 700 "$dir"
            echo "  -> Fixed"
            FIXED_COUNT=$((FIXED_COUNT + 1))
        else
            ISSUE_COUNT=$((ISSUE_COUNT + 1))
        fi
    fi
done

echo ""
echo "====================================="
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "Check complete: $ISSUE_COUNT issues found"
    [[ $ISSUE_COUNT -gt 0 ]] && exit 1
else
    echo "Fix complete: $FIXED_COUNT directories fixed"
fi
