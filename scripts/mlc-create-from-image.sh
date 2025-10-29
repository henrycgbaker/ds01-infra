#!/bin/bash
# Create container from custom Docker image
# Usage: mlc-create-from-image <container-name> <image-name>

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
CONTAINER_NAME="$1"
IMAGE_NAME="$2"
WORKSPACE_DIR="${3:-$HOME/workspace}"

if [[ -z "$CONTAINER_NAME" ]] || [[ -z "$IMAGE_NAME" ]]; then
    cat << EOF
${GREEN}Create Container from Custom Image${NC}

Usage: mlc-create-from-image <container-name> <image-name> [workspace-dir]

Examples:
  mlc-create-from-image thesis-run1 my-pytorch-image
  mlc-create-from-image experiment1 my-pytorch-image ~/projects/thesis

Your images:
$(docker images --format "  - {{.Repository}}" | grep "^  - $(whoami)-")

EOF
    exit 1
fi

USERNAME=$(whoami)
USER_ID=$(id -u)
GROUP_ID=$(id -g)
CONTAINER_TAG="${CONTAINER_NAME}._.$USER_ID"

# Verify image exists
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    log_error "Image '$IMAGE_NAME' not found"
    echo "Available images:"
    docker images --format "  - {{.Repository}}:{{.Tag}}" | grep "$USERNAME-"
    exit 1
fi

# Check if container already exists
if docker ps -a --filter "name=^${CONTAINER_TAG}$" --format '{{.Names}}' | grep -q "^${CONTAINER_TAG}$"; then
    log_error "Container '$CONTAINER_NAME' already exists"
    log_info "Use: mlc-open $CONTAINER_NAME (to open it)"
    log_info "Or:  mlc-remove $CONTAINER_NAME (to delete it first)"
    exit 1
fi

# Ensure workspace exists
mkdir -p "$WORKSPACE_DIR"

log_info "Creating container '$CONTAINER_NAME' from image '$IMAGE_NAME'"
log_info "Workspace: $WORKSPACE_DIR"

# Get resource limits (reuse from mlc-create-wrapper)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RESOURCE_PARSER="$SCRIPT_DIR/get_resource_limits.py"
CONFIG_FILE="$SCRIPT_DIR/../../config/resource-limits.yaml"

if [ -f "$RESOURCE_PARSER" ] && [ -f "$CONFIG_FILE" ]; then
    RESOURCE_LIMITS=$(python3 "$RESOURCE_PARSER" "$USERNAME" --docker-args 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESOURCE_LIMITS" ]; then
        log_info "Applying resource limits..."
        echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    else
        RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
    fi
else
    RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
fi

# Parse resource limits into docker run format
DOCKER_LIMITS=""
for arg in $RESOURCE_LIMITS; do
    DOCKER_LIMITS="$DOCKER_LIMITS $arg"
done

# Create container
log_info "Creating container..."

docker run -dit \
    --name "$CONTAINER_TAG" \
    --hostname "$CONTAINER_NAME" \
    --user "$USER_ID:$GROUP_ID" \
    -v "$WORKSPACE_DIR:/workspace" \
    -w /workspace \
    --gpus all \
    $DOCKER_LIMITS \
    --network host \
    --ipc host \
    --restart unless-stopped \
    --label "ds01.user=$USERNAME" \
    --label "ds01.container=$CONTAINER_NAME" \
    --label "ds01.image=$IMAGE_NAME" \
    --label "ds01.created=$(date -Iseconds)" \
    "$IMAGE_NAME" \
    bash

if [ $? -eq 0 ]; then
    docker stop "$CONTAINER_TAG" &>/dev/null
    
    log_success "Container '$CONTAINER_NAME' created from image '$IMAGE_NAME'"
    echo ""
    log_info "Next steps:"
    echo "  1. Open: ${GREEN}mlc-open $CONTAINER_NAME${NC}"
    echo "  2. Code in /workspace"
    echo "  3. When done: ${GREEN}mlc-stop $CONTAINER_NAME${NC}"
    echo ""
    log_info "Container lifecycle:"
    echo "  - Container is disposable (can be killed anytime)"
    echo "  - Work saved in /workspace persists"
    echo "  - Recreate from same image: mlc-create-from-image new-name $IMAGE_NAME"
    echo ""
else
    log_error "Failed to create container"
    exit 1
fi