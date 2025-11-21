#!/bin/bash
# Create symlink records in usr-mirrors (doesn't require sudo)
# Actual symlink creation requires sudo and running update-symlinks.sh

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
    # Tier 3: Container Orchestrators (ephemeral model)
    "container-deploy"
    "container-retire"

    # Tier 3: Dispatchers
    "container:container-dispatcher.sh"
    "image:image-dispatcher.sh"
    "project:project-dispatcher.sh"
    "user:user-dispatcher.sh"

    # Tier 2: Container Management (9 commands)
    "container-create"
    "container-run"
    "container-start"
    "container-stop"
    "container-pause"
    "container-list"
    "container-stats"
    "container-remove"
    "container-exit"

    # Tier 2: Image Management (4 commands)
    "image-create"
    "image-list"
    "image-update"
    "image-delete"

    # Tier 2: Project Setup Modules (5 commands)
    "dir-create"
    "git-init"
    "readme-create"
    "ssh-setup"
    "vscode-setup"

    # Tier 4: Workflow Orchestrators
    "project-init"
    "user-setup"

    # User Utilities
    "ds01-status"
    "ds01-run"
    "get-limits"
    "ssh-config"
    "install-to-image:install-to-image.sh"
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
echo "  sudo /opt/ds01-infra/scripts/system/update-symlinks.sh"
echo ""
