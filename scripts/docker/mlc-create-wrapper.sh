#!/bin/bash
# Enhanced MLC Create - container creation with resource limits
# /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh
#
# This wraps the original mlc-create and adds:
# - Automatic resource limits based on user/group
# - GPU allocation management
# - Simplified interface for students

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
RESOURCE_PARSER="$SCRIPT_DIR/get_resource_limits.py"
ORIGINAL_MLC="/opt/aime-ml-containers/mlc-create"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
print_usage() {
    cat << EOF

${GREEN}DS01 GPU Server - Container Creation${NC}

Usage: mlc-create <name> <framework> [version] [options]

${BLUE}Quick Start (Students):${NC}
  mlc-create my-project pytorch              # Latest PyTorch
  mlc-create my-project tensorflow           # Latest TensorFlow
  mlc-create my-project pytorch 2.5.1        # Specific version

${BLUE}Common Frameworks:${NC}
  - pytorch      (recommended for most deep learning)
  - tensorflow   (for TensorFlow users)

${BLUE}Options:${NC}
  -w=<path>      Workspace directory (default: ~/workspace)
  -d=<path>      Data directory (optional)
  -g=<id>        Request specific GPU (0-3, admins only)
  --cpu-only     Create CPU-only container (no GPU)
  --show-limits  Show your resource limits

${BLUE}Examples:${NC}
  # Create PyTorch container for computer vision project
  mlc-create cv-project pytorch

  # Create container with custom workspace
  mlc-create nlp-project pytorch -w=~/projects/nlp

  # Create CPU-only container for data preprocessing
  mlc-create preprocessing pytorch --cpu-only

${BLUE}After Creation:${NC}
  mlc-open <name>     # Open container
  mlc-list            # List your containers
  mlc-stop <name>     # Stop container

${BLUE}Need Help?${NC}
  - User guide: /home/shared/docs/getting-started.md
  - Office hours: Tuesdays 2-4pm
  - Email: datasciencelab@university.edu

EOF
}

# Check if user wants help
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
    print_usage
    exit 0
fi

# Parse arguments
CONTAINER_NAME="$1"
FRAMEWORK="${2:-pytorch}"  # Default to pytorch
VERSION="${3}"
WORKSPACE_DIR="$HOME/workspace"
DATA_DIR=""
REQUESTED_GPU=""
CPU_ONLY=false
SHOW_LIMITS=false

# Shift past container name and framework
shift 2 2>/dev/null || shift 1

# Parse remaining arguments
for arg in "$@"; do
    case $arg in
        -w=*|--workspace=*)
            WORKSPACE_DIR="${arg#*=}"
            ;;
        -d=*|--data=*)
            DATA_DIR="${arg#*=}"
            ;;
        -g=*|--gpu=*)
            REQUESTED_GPU="${arg#*=}"
            ;;
        --cpu-only)
            CPU_ONLY=true
            ;;
        --show-limits)
            SHOW_LIMITS=true
            ;;
        *)
            # Check if it's a version number (starts with digit)
            if [[ $arg =~ ^[0-9] ]]; then
                VERSION="$arg"
            else
                log_error "Unknown option: $arg"
                print_usage
                exit 1
            fi
            ;;
    esac
done

# Get current user
CURRENT_USER=$(whoami)
USER_ID=$(id -u)

# Show resource limits if requested
if [ "$SHOW_LIMITS" = true ]; then
    if [ -f "$RESOURCE_PARSER" ]; then
        python3 "$RESOURCE_PARSER" "$CURRENT_USER"
    else
        log_error "Resource parser not found: $RESOURCE_PARSER"
        log_info "Default limits: 1 GPU, 16 CPUs, 32GB RAM"
    fi
    exit 0
fi

# Validate container name
if [[ -z "$CONTAINER_NAME" ]]; then
    log_error "Container name is required"
    print_usage
    exit 1
fi

# Check if container already exists
CONTAINER_TAG="${CONTAINER_NAME}._.$USER_ID"
if docker ps -a --filter "name=^${CONTAINER_TAG}$" --format '{{.Names}}' | grep -q "^${CONTAINER_TAG}$"; then
    log_error "Container '$CONTAINER_NAME' already exists"
    log_info "Use: mlc-open $CONTAINER_NAME (to open it)"
    log_info "Or:  mlc-remove $CONTAINER_NAME (to delete it first)"
    exit 1
fi

# Ensure workspace directory exists
mkdir -p "$WORKSPACE_DIR"

log_info "Creating container '$CONTAINER_NAME' for user '$CURRENT_USER'"
log_info "Framework: $FRAMEWORK ${VERSION:+v$VERSION}"
log_info "Workspace: $WORKSPACE_DIR"

# Get user's resource limits
if [ -f "$RESOURCE_PARSER" ] && [ -f "$CONFIG_FILE" ]; then
    log_info "Loading resource limits from configuration..."
    RESOURCE_LIMITS=$(python3 "$RESOURCE_PARSER" "$CURRENT_USER" --docker-args 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$RESOURCE_LIMITS" ]; then
        log_info "Resource limits applied:"
        echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    else
        log_warning "Could not parse resource limits, using defaults"
        RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
    fi
else
    log_warning "Resource configuration not found, using defaults"
    RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
fi

# GPU allocation
GPU_ARG=""
if [ "$CPU_ONLY" = true ]; then
    log_info "Creating CPU-only container (no GPU)"
else
    if [ -n "$REQUESTED_GPU" ]; then
        # Specific GPU requested
        log_info "Specific GPU requested: $REQUESTED_GPU"
        GPU_ARG="-g=$REQUESTED_GPU"
    else
        # Auto-allocate GPU (original mlc-create handles this)
        log_info "GPU will be auto-allocated by mlc-create"
    fi
fi

# Build arguments for original mlc-create
ORIGINAL_ARGS="$CONTAINER_NAME $FRAMEWORK"
if [ -n "$VERSION" ]; then
    ORIGINAL_ARGS="$ORIGINAL_ARGS $VERSION"
fi

ORIGINAL_ARGS="$ORIGINAL_ARGS -w=$WORKSPACE_DIR"

if [ -n "$DATA_DIR" ]; then
    ORIGINAL_ARGS="$ORIGINAL_ARGS -d=$DATA_DIR"
fi

if [ -n "$GPU_ARG" ]; then
    ORIGINAL_ARGS="$ORIGINAL_ARGS $GPU_ARG"
fi

# Call original mlc-create
log_info "Creating container with mlc-create..."

if [ -f "$ORIGINAL_MLC" ]; then
    # Execute the original script
    bash "$ORIGINAL_MLC" $ORIGINAL_ARGS
    MLC_EXIT_CODE=$?
    
    if [ $MLC_EXIT_CODE -ne 0 ]; then
        log_error "Container creation failed (exit code: $MLC_EXIT_CODE)"
        exit $MLC_EXIT_CODE
    fi
else
    log_error "Original mlc-create not found at: $ORIGINAL_MLC"
    log_error "Please ensure aime-ml-containers is installed"
    exit 1
fi

# Now apply resource limits to the created container
log_info "Applying resource limits to container..."

# Get current container config
if ! docker inspect "$CONTAINER_TAG" &>/dev/null; then
    log_error "Container $CONTAINER_TAG was not created successfully"
    exit 1
fi

# Update container with resource limits using docker update
# Note: Some limits can only be set at creation, so we'll recreate if needed
NEEDS_RECREATE=false

# Check if we can use docker update for all limits
if echo "$RESOURCE_LIMITS" | grep -q "shm-size"; then
    NEEDS_RECREATE=true
fi

if [ "$NEEDS_RECREATE" = true ]; then
    log_info "Recreating container with resource limits..."
    
    # Stop container if running
    docker stop "$CONTAINER_TAG" 2>/dev/null || true
    
    # Get current configuration
    CURRENT_IMAGE=$(docker inspect "$CONTAINER_TAG" --format='{{.Config.Image}}')
    CURRENT_CMD=$(docker inspect "$CONTAINER_TAG" --format='{{json .Config.Cmd}}' | sed 's/\[//g; s/\]//g; s/"//g')
    
    # Get all volume mounts
    VOLUME_ARGS=$(docker inspect "$CONTAINER_TAG" --format='{{range .Mounts}}-v {{.Source}}:{{.Destination}} {{end}}')
    
    # Get environment variables
    ENV_ARGS=$(docker inspect "$CONTAINER_TAG" --format='{{range .Config.Env}}--env {{.}} {{end}}')
    
    # Get labels
    LABEL_ARGS=$(docker inspect "$CONTAINER_TAG" --format='{{range $k,$v := .Config.Labels}}--label {{$k}}={{$v}} {{end}}')
    
    # Get user
    CONTAINER_USER=$(docker inspect "$CONTAINER_TAG" --format='{{.Config.User}}')
    
    # Get working directory
    WORKDIR=$(docker inspect "$CONTAINER_TAG" --format='{{.Config.WorkingDir}}')
    
    # Remove old container
    docker rm "$CONTAINER_TAG" 2>/dev/null || true
    
    # Create new container with resource limits
    docker run -dit \
        --name "$CONTAINER_TAG" \
        --user "$CONTAINER_USER" \
        --workdir "$WORKDIR" \
        $VOLUME_ARGS \
        $ENV_ARGS \
        $LABEL_ARGS \
        --network=host \
        --ipc=host \
        --privileged \
        --restart=unless-stopped \
        $RESOURCE_LIMITS \
        "$CURRENT_IMAGE" \
        bash
        
    if [ $? -ne 0 ]; then
        log_error "Failed to apply resource limits"
        exit 1
    fi
else
    # Use docker update for limits that support it
    UPDATE_ARGS=""
    for arg in $RESOURCE_LIMITS; do
        case $arg in
            --cpus=*)
                UPDATE_ARGS="$UPDATE_ARGS --cpus=${arg#*=}"
                ;;
            --memory=*)
                UPDATE_ARGS="$UPDATE_ARGS --memory=${arg#*=}"
                ;;
            --memory-swap=*)
                UPDATE_ARGS="$UPDATE_ARGS --memory-swap=${arg#*=}"
                ;;
            --pids-limit=*)
                UPDATE_ARGS="$UPDATE_ARGS --pids-limit=${arg#*=}"
                ;;
        esac
    done
    
    if [ -n "$UPDATE_ARGS" ]; then
        docker update $UPDATE_ARGS "$CONTAINER_TAG" &>/dev/null || log_warning "Some resource limits could not be applied"
    fi
fi

# Stop container (user will start it with mlc-open)
docker stop "$CONTAINER_TAG" &>/dev/null || true

log_success "Container '$CONTAINER_NAME' created successfully!"
echo ""
log_info "Next steps:"
echo "  1. Open your container:  ${GREEN}mlc-open $CONTAINER_NAME${NC}"
echo "  2. Your workspace is mounted at: /workspace"
echo "  3. Install packages with: pip install <package>"
echo ""
log_info "Useful commands:"
echo "  mlc-list           # List your containers"
echo "  mlc-stats          # Show resource usage"
echo "  mlc-stop $CONTAINER_NAME  # Stop this container"
echo ""
log_warning "Remember to save your work in /workspace - it persists across container restarts!"
echo ""
