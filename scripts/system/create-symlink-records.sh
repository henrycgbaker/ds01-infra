#!/bin/bash
# Create symlink records in usr-mirrors (doesn't require sudo)
# Actual symlink creation requires sudo and running setup-user-commands.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
USER_SCRIPTS_DIR="$INFRA_ROOT/scripts/user"
MIRROR_DIR="$INFRA_ROOT/config/usr-mirrors/local/bin"

# Create mirror directory
mkdir -p "$MIRROR_DIR"

# List of user commands to symlink
USER_COMMANDS=(
    "container"
    "image"
    "project"
    "container-create"
    "container-run"
    "container-stop"
    "container-exit"
    "container-list"
    "container-stats"
    "container-cleanup"
    "image-create"
    "image-list"
    "image-update"
    "image-delete"
    "project-init"
    "ssh-config"
    "user-setup"
)

echo "Creating symlink records in $MIRROR_DIR"
echo ""

for cmd in "${USER_COMMANDS[@]}"; do
    SOURCE="$USER_SCRIPTS_DIR/$cmd"
    TARGET="/usr/local/bin/$cmd"
    MIRROR_FILE="$MIRROR_DIR/$cmd.link"

    if [ ! -f "$SOURCE" ]; then
        echo "⚠  Skip: $cmd (source not found)"
        continue
    fi

    cat > "$MIRROR_FILE" << EOF
# Symlink record for: $cmd
# Created: $(date -Iseconds)
# Source: $SOURCE
# Target: $TARGET

ln -sf $SOURCE $TARGET
EOF

    echo "✓ Record created: $cmd.link"
done

echo ""
echo "Symlink records created in: $MIRROR_DIR"
echo ""
echo "To create actual symlinks in /usr/local/bin, run:"
echo "  sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh"
echo ""
