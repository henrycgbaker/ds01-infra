# File: /opt/ds01-infra/scripts/user/install-to-image.sh
#!/bin/bash
# Helper to install packages and update image

CONTAINER_NAME="$1"
shift
PACKAGES="$@"

if [ -z "$CONTAINER_NAME" ] || [ -z "$PACKAGES" ]; then
    echo "Usage: install-to-image <container-name> <packages...>"
    echo ""
    echo "Examples:"
    echo "  install-to-image my-project wandb optuna"
    echo "  install-to-image thesis transformers datasets"
    exit 1
fi

USERNAME=$(whoami)
USER_ID=$(id -u)
CONTAINER_TAG="${CONTAINER_NAME}._.$USER_ID"

# Check container exists
if ! docker ps -a --filter "name=^${CONTAINER_TAG}$" --format '{{.Names}}' | grep -q "^${CONTAINER_TAG}$"; then
    echo "Error: Container '$CONTAINER_NAME' not found"
    exit 1
fi

# Get the image name
IMAGE_NAME=$(docker inspect "$CONTAINER_TAG" --format='{{.Config.Image}}')

echo "Installing packages: $PACKAGES"
echo "To container: $CONTAINER_NAME"
echo "Base image: $IMAGE_NAME"
echo ""

# Start container if not running
docker start "$CONTAINER_TAG" 2>/dev/null || true

# Install packages
docker exec "$CONTAINER_TAG" pip install --no-cache-dir $PACKAGES

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Packages installed successfully"
    echo ""
    read -p "Commit changes to image? (creates new image version) [y/N]: " COMMIT
    
    if [[ "$COMMIT" =~ ^[Yy] ]]; then
        NEW_TAG="${IMAGE_NAME}-$(date +%Y%m%d-%H%M)"
        # CRITICAL: Truncate lastlog/faillog before commit to prevent huge sparse files
        # High UIDs cause these files to grow to 300GB+ which breaks docker commit
        docker exec "$CONTAINER_TAG" bash -c ': > /var/log/lastlog; : > /var/log/faillog' 2>/dev/null || true
        docker commit "$CONTAINER_TAG" "$NEW_TAG"
        echo ""
        echo "✓ New image created: $NEW_TAG"
        echo ""
        echo "To use this version for future containers:"
        echo "  mlc-create-from-image new-container $NEW_TAG"
    else
        echo ""
        echo "⚠  Changes NOT saved to image"
        echo "  Packages exist only in this container instance"
        echo "  To save permanently, rebuild your Dockerfile"
    fi
else
    echo "✗ Installation failed"
    exit 1
fi