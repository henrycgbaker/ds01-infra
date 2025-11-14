# File: /opt/ds01-infra/scripts/docker/mlc-create-from-image.sh
#!/bin/bash
# Create container from custom image with user namespace support

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
  mlc-create-from-image thesis-run1 john-pytorch ~/workspace/thesis
  mlc-create-from-image experiment1 jane-cv-image

Your images:
$(docker images --format "  - {{.Repository}}:{{.Tag}}" | grep "$(whoami)-" || echo "  (none found)")

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
    echo ""
    echo "Available images:"
    docker images --format "  - {{.Repository}}:{{.Tag}}" | grep "$USERNAME-" || echo "  (none found)"
    echo ""
    echo "Create an image first with:"
    echo "  ds01-setup-wizard"
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
log_info "User namespace: $USER_ID:$GROUP_ID"

# Get resource limits
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
RESOURCE_PARSER="$INFRA_ROOT/scripts/docker/get_resource_limits.py"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"

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

# Create container with user namespace mapping
log_info "Creating container with user namespace..."

docker run -dit \
    --name "$CONTAINER_TAG" \
    --hostname "$CONTAINER_NAME" \
    --user "$USER_ID:$GROUP_ID" \
    -v "$WORKSPACE_DIR:/workspace" \
    -v "$HOME/.cache:/home/$USERNAME/.cache" \
    -w /workspace \
    --gpus all \
    $DOCKER_LIMITS \
    --network host \
    --ipc host \
    --restart unless-stopped \
    \
    # ===== IDENTIFICATION LABELS ===== \
    --label "aime.mlc.DS01_USER=$USERNAME" \
    --label "aime.mlc.DS01_USER_ID=$USER_ID" \
    --label "aime.mlc.DS01_GROUP_ID=$GROUP_ID" \
    --label "aime.mlc.DS01_CONTAINER=$CONTAINER_NAME" \
    --label "aime.mlc.DS01_IMAGE=$IMAGE_NAME" \
    --label "aime.mlc.DS01_CREATED=$(date -Iseconds)" \
    --label "aime.mlc.DS01_TYPE=custom" \
    --label "aime.mlc.DS01_PROJECT=$PROJECT_NAME" \
    --label "aime.mlc.DS01_WORKSPACE=$WORKSPACE_DIR" \
    \
    # ===== SECURITY & ISOLATION ===== \
    --security-opt=no-new-privileges:true \
    --cap-drop=ALL \
    --cap-add=SYS_PTRACE \
    --cap-add=NET_BIND_SERVICE \
    \
    # ===== PROCESS MANAGEMENT ===== \
    --pids-limit=4096 \
    \
    # ===== CGROUP HIERARCHY ===== \
    --cgroup-parent="ds01.slice/user-${USER_ID}.slice" \
    \
    # ===== ENVIRONMENT ===== \
    -e "DS01_CONTAINER=1" \
    -e "DS01_USER=$USERNAME" \
    -e "DS01_USER_ID=$USER_ID" \
    -e "HOME=/workspace" \
    \
    "$IMAGE_NAME" \
    bash

if [ $? -eq 0 ]; then
    # Stop container initially (user opens with mlc-open)
    docker stop "$CONTAINER_TAG" &>/dev/null
    
    log_success "Container '$CONTAINER_NAME' created!"
    echo ""
    log_info "Container details:"
    echo "  - Name: $CONTAINER_NAME"
    echo "  - Full: $CONTAINER_TAG"
    echo "  - Image: $IMAGE_NAME"
    echo "  - User: $USERNAME ($USER_ID:$GROUP_ID)"
    echo "  - Workspace: $WORKSPACE_DIR → /workspace"
    echo ""
    log_info "Next steps:"
    echo "  ${GREEN}mlc-open $CONTAINER_NAME${NC}    # Open container"
    echo "  ${GREEN}cd /workspace${NC}                # Your project files"
    echo "  ${GREEN}mlc-stop $CONTAINER_NAME${NC}    # Stop when done"
    echo ""
    log_info "Container lifecycle:"
    echo "  - Container is ephemeral (can be deleted/recreated)"
    echo "  - Work in /workspace persists"
    echo "  - Recreate anytime: mlc-create-from-image $CONTAINER_NAME $IMAGE_NAME"
    echo ""
else
    log_error "Failed to create container"
    exit 1
fi