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
# Format: "target_name:source_file" or just "name" if they match
USER_COMMANDS=(
    "container:container-dispatcher.sh"
    "image:image-dispatcher.sh"
    "project:project-dispatcher.sh"
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
    # Parse command (format: "target:source" or just "name")
    if [[ "$cmd" == *":"* ]]; then
        TARGET_NAME="${cmd%%:*}"
        SOURCE_FILE="${cmd#*:}"
    else
        TARGET_NAME="$cmd"
        SOURCE_FILE="$cmd"
    fi

    SOURCE="$USER_SCRIPTS_DIR/$SOURCE_FILE"
    TARGET="/usr/local/bin/$TARGET_NAME"
    MIRROR_FILE="$MIRROR_DIR/$TARGET_NAME.link"

    if [ ! -f "$SOURCE" ]; then
        echo "⚠  Skip: $TARGET_NAME (source not found: $SOURCE_FILE)"
        continue
    fi

    cat > "$MIRROR_FILE" << EOF
# Symlink record for: $TARGET_NAME
# Created: $(date -Iseconds)
# Source: $SOURCE
# Target: $TARGET

ln -sf $SOURCE $TARGET
EOF

    echo "✓ Record created: $TARGET_NAME.link"
done

echo ""
echo "Symlink records created in: $MIRROR_DIR"
echo ""
echo "To create actual symlinks in /usr/local/bin, run:"
echo "  sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh"
echo ""
