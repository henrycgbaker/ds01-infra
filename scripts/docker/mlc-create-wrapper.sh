#!/bin/bash
# Enhanced MLC Create - container creation with resource limits
# /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh
#
# This wraps the original mlc-create and adds:
# - Automatic resource limits based on user/group
# - GPU allocation management
# - Simplified interface for students
#
# Installation: sudo ln -sf /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh /usr/local/bin/mlc-create

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
RESOURCE_PARSER="$SCRIPT_DIR/get_resource_limits.py"
ORIGINAL_MLC="$INFRA_ROOT/aime-ml-containers/mlc-create"

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

${BLUE}Quick Start:${NC}
  mlc-create my-project pytorch              # Latest PyTorch (2.5.1)
  mlc-create my-project tensorflow           # Latest TensorFlow (2.14.0)
  mlc-create my-project pytorch 2.4.0        # Specific version

${BLUE}Frameworks:${NC}
  pytorch, torch       → PyTorch (recommended for most deep learning)
  tensorflow, tf       → TensorFlow
  mxnet, mx            → MXNet

${BLUE}Options:${NC}
  -w=<path>      Workspace directory (default: ~/workspace)
  -d=<path>      Data directory (optional)
  -g=<id>        Request specific GPU 0-3 (admins only)
  --cpu-only     Create CPU-only container (no GPU)
  --show-limits  Show your resource limits
  --dry-run      Show what would be created without creating
  -h, --help     Show this help message

${BLUE}Examples:${NC}
  # Create PyTorch container
  mlc-create cv-project pytorch

  # Create with specific version
  mlc-create nlp-project pytorch 2.4.0

  # Create with custom workspace
  mlc-create analysis tensorflow -w=~/projects/analysis

  # Create CPU-only container
  mlc-create preprocessing pytorch --cpu-only

  # Check what would be created
  mlc-create test pytorch --dry-run

${BLUE}After Creation:${NC}
  mlc-open <name>     # Open container
  mlc-list            # List your containers
  mlc-stop <name>     # Stop container
  mlc-remove <name>   # Delete container

${BLUE}Need Help?${NC}
  - Docs: /home/shared/docs/getting-started.md
  - Office hours: Tuesdays 2-4pm
  - Email: datasciencelab@university.edu

EOF
}

# Pre-flight checks
preflight_checks() {
    # Check Docker is running
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running or you don't have permission"
        log_info "Try: sudo usermod -aG docker $USER (then logout/login)"
        exit 1
    fi
    
    # Check original mlc-create exists
    if [ ! -f "$ORIGINAL_MLC" ]; then
        log_error "Original mlc-create not found at: $ORIGINAL_MLC"
        log_error "Please ensure aime-ml-containers is installed"
        exit 1
    fi
    
    # Check disk space (warn if <10GB free)
    DISK_FREE=$(df -BG /var/lib/docker | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$DISK_FREE" -lt 10 ]; then
        log_warning "Low disk space: ${DISK_FREE}GB free in /var/lib/docker"
    fi
}

# Check if user wants help or show limits FIRST
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ $# -eq 0 ]]; then
    print_usage
    exit 0
fi

if [[ "$1" == "--show-limits" ]]; then
    CURRENT_USER=$(whoami)
    if [ -f "$RESOURCE_PARSER" ]; then
        python3 "$RESOURCE_PARSER" "$CURRENT_USER"
    else
        log_error "Resource parser not found: $RESOURCE_PARSER"
        log_info "Default limits: 1 GPU, 16 CPUs, 32GB RAM"
    fi
    exit 0
fi

# Initialize variables
CONTAINER_NAME=""
FRAMEWORK=""
VERSION=""
WORKSPACE_DIR="$HOME/workspace"
DATA_DIR=""
REQUESTED_GPU=""
CPU_ONLY=false
DRY_RUN=false

# Parse container name
CONTAINER_NAME="$1"
shift

# Parse framework (with case-insensitive mapping)
if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
    FRAMEWORK_INPUT="$1"
    case "${FRAMEWORK_INPUT,,}" in  # ,, converts to lowercase
        pytorch|torch)
            FRAMEWORK="Pytorch"
            ;;
        tensorflow|tf)
            FRAMEWORK="Tensorflow"
            ;;
        mxnet|mx)
            FRAMEWORK="Mxnet"
            ;;
        *)
            # Capitalize first letter for unknown frameworks
            FRAMEWORK="$(tr '[:lower:]' '[:upper:]' <<< ${FRAMEWORK_INPUT:0:1})${FRAMEWORK_INPUT:1}"
            ;;
    esac
    shift
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w=*|--workspace=*)
            WORKSPACE_DIR="${1#*=}"
            ;;
        -d=*|--data=*)
            DATA_DIR="${1#*=}"
            ;;
        -g=*|--gpu=*)
            REQUESTED_GPU="${1#*=}"
            ;;
        --cpu-only)
            CPU_ONLY=true
            ;;
        --show-limits)
            CURRENT_USER=$(whoami)
            if [ -f "$RESOURCE_PARSER" ]; then
                python3 "$RESOURCE_PARSER" "$CURRENT_USER"
            else
                log_error "Resource parser not found: $RESOURCE_PARSER"
            fi
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            # Assume it's a version number
            if [[ $1 =~ ^[0-9] ]]; then
                VERSION="$1"
            else
                log_error "Unknown argument: $1"
                print_usage
                exit 1
            fi
            ;;
    esac
    shift
done

# Auto-select version if not specified
if [[ -z "$VERSION" ]]; then
    case "$FRAMEWORK" in
        Pytorch)
            VERSION="2.5.1"
            ;;
        Tensorflow)
            VERSION="2.14.0"
            ;;
        Mxnet)
            VERSION="1.8.0-nvidia"
            ;;
        *)
            # Let mlc-create handle version requirement
            VERSION=""
            ;;
    esac
fi

# Default framework if not specified
if [[ -z "$FRAMEWORK" ]]; then
    FRAMEWORK="Pytorch"
    VERSION="2.5.1"
    log_info "No framework specified, defaulting to Pytorch 2.5.1"
fi

# Get current user
CURRENT_USER=$(whoami)
USER_ID=$(id -u)

# Validate container name
if [[ -z "$CONTAINER_NAME" ]]; then
    log_error "Container name is required"
    print_usage
    exit 1
fi

# Validate container name format (alphanumeric, hyphens, underscores only)
if [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid container name: $CONTAINER_NAME"
    log_info "Use only letters, numbers, hyphens, and underscores"
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

# Validate GPU ID if specified
if [ -n "$REQUESTED_GPU" ]; then
    if [[ ! "$REQUESTED_GPU" =~ ^[0-3]$ ]]; then
        log_error "Invalid GPU ID: $REQUESTED_GPU (must be 0-3)"
        exit 1
    fi
fi

# Run pre-flight checks
preflight_checks

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
        log_info "Specific GPU requested: $REQUESTED_GPU"
        GPU_ARG="-g=$REQUESTED_GPU"
    else
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

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - No containers will be created"
    echo ""
    log_info "Would execute:"
    echo "  bash $ORIGINAL_MLC $ORIGINAL_ARGS"
    echo ""
    log_info "Would apply resource limits:"
    echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    echo ""
    log_info "Container would be named: $CONTAINER_TAG"
    exit 0
fi

# Call original mlc-create
log_info "Creating container with mlc-create..."

bash "$ORIGINAL_MLC" $ORIGINAL_ARGS
MLC_EXIT_CODE=$?

if [ $MLC_EXIT_CODE -ne 0 ]; then
    log_error "Container creation failed (exit code: $MLC_EXIT_CODE)"
    exit $MLC_EXIT_CODE
fi

# Apply resource limits to the created container
log_info "Applying resource limits to container..."

# Verify container was created
if ! docker inspect "$CONTAINER_TAG" &>/dev/null; then
    log_error "Container $CONTAINER_TAG was not created successfully"
    exit 1
fi

# Build docker update command
UPDATE_CMD="docker update"

for arg in $RESOURCE_LIMITS; do
    case $arg in
        --cpus=*)
            UPDATE_CMD="$UPDATE_CMD --cpus=${arg#*=}"
            ;;
        --memory=*)
            UPDATE_CMD="$UPDATE_CMD --memory=${arg#*=}"
            ;;
        --memory-swap=*)
            UPDATE_CMD="$UPDATE_CMD --memory-swap=${arg#*=}"
            ;;
        --pids-limit=*)
            UPDATE_CMD="$UPDATE_CMD --pids-limit=${arg#*=}"
            ;;
        --shm-size=*)
            # shm-size cannot be updated after creation
            # It would need to be passed to original mlc-create, but that doesn't support it
            # Just skip it silently
            ;;
    esac
done

# Apply the update
if $UPDATE_CMD "$CONTAINER_TAG" &>/dev/null; then
    log_info "Resource limits applied successfully"
else
    log_warning "Some resource limits could not be applied"
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
log_warning "Remember: Save your work in /workspace - it persists across container restarts!"
echo ""