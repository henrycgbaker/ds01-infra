#!/bin/bash
# Enhanced MLC Create - container creation with resource limits
# /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh
#
# This wraps mlc-patched.py (DS01-enhanced AIME v2) and adds:
# - Automatic resource limits based on user/group
# - GPU allocation management
# - Custom image support (built via image-create)
# - Simplified interface for students
#
# Installation: sudo ln -sf /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh /usr/local/bin/mlc-create

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
RESOURCE_PARSER="$SCRIPT_DIR/get_resource_limits.py"
MLC_PATCHED="$SCRIPT_DIR/mlc-patched.py"  # DS01-enhanced AIME v2
ORIGINAL_MLC="$INFRA_ROOT/aime-ml-containers/mlc-create"  # Fallback for v1

# Source username sanitization library for LDAP/SSSD support
source "$INFRA_ROOT/scripts/lib/username-utils.sh"

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
    
    # Check mlc-patched.py exists (DS01-enhanced AIME v2)
    if [ ! -f "$MLC_PATCHED" ]; then
        log_error "mlc-patched.py not found at: $MLC_PATCHED"
        log_error "DS01 infrastructure may not be properly installed"
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
CUSTOM_IMAGE=""  # Custom Docker image (bypasses AIME catalog)
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
        --image=*)
            CUSTOM_IMAGE="${1#*=}"
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
    log_info "Use container-remove to remove it first, or choose a different name"
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

# Get user's resource limits and group
if [ -f "$RESOURCE_PARSER" ] && [ -f "$CONFIG_FILE" ]; then
    log_info "Loading resource limits from configuration..."
    RESOURCE_LIMITS=$(python3 "$RESOURCE_PARSER" "$CURRENT_USER" --docker-args 2>/dev/null)
    USER_GROUP=$(python3 "$RESOURCE_PARSER" "$CURRENT_USER" --group 2>/dev/null || echo "student")

    if [ $? -eq 0 ] && [ -n "$RESOURCE_LIMITS" ]; then
        log_info "Resource limits applied:"
        echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    else
        log_warning "Could not parse resource limits, using defaults"
        RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
        USER_GROUP="student"
    fi
else
    log_warning "Resource configuration not found, using defaults"
    RESOURCE_LIMITS="--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096"
    USER_GROUP="student"
fi

# Ensure user-specific cgroup slice exists
# Username is sanitized for systemd compatibility (LDAP users may have @ and . chars)
USER_SLICE_SCRIPT="$SCRIPT_DIR/../system/create-user-slice.sh"
SANITIZED_USER=$(sanitize_username_for_slice "$CURRENT_USER")
if [ -f "$USER_SLICE_SCRIPT" ]; then
    log_info "Ensuring user slice exists: ds01-${USER_GROUP}-${SANITIZED_USER}.slice"
    if sudo "$USER_SLICE_SCRIPT" "$USER_GROUP" "$CURRENT_USER" 2>/dev/null; then
        log_info "User slice ready"
    else
        log_warning "Could not create user slice (will use group slice instead)"
        # Fall back to group slice if user slice creation fails
        RESOURCE_LIMITS=$(echo "$RESOURCE_LIMITS" | sed "s/ds01-${USER_GROUP}-${SANITIZED_USER}.slice/ds01-${USER_GROUP}.slice/")
    fi
else
    log_warning "User slice script not found, using group slice"
    # Fall back to group slice
    RESOURCE_LIMITS=$(echo "$RESOURCE_LIMITS" | sed "s/ds01-${USER_GROUP}-${SANITIZED_USER}.slice/ds01-${USER_GROUP}.slice/")
fi

# GPU allocation via gpu_allocator_v2.py (DS01 priority-based, stateless)
GPU_ARG=""
ALLOCATED_GPU=""

if [ "$CPU_ONLY" = true ]; then
    log_info "Creating CPU-only container (no GPU)"
else
    if [ -n "$REQUESTED_GPU" ]; then
        # Admin-requested specific GPU (bypasses allocator)
        log_info "Specific GPU requested: $REQUESTED_GPU"
        GPU_ARG="-g=$REQUESTED_GPU"
    else
        # Priority-based GPU allocation via gpu_allocator_v2.py (stateless)
        GPU_ALLOCATOR="$SCRIPT_DIR/gpu_allocator_v2.py"

        if [ -f "$GPU_ALLOCATOR" ] && [ -f "$RESOURCE_PARSER" ]; then
            # Get user's GPU limits and priority
            MAX_GPUS=$(python3 "$RESOURCE_PARSER" "$CURRENT_USER" --max-gpus 2>/dev/null || echo "1")
            PRIORITY=$(python3 "$RESOURCE_PARSER" "$CURRENT_USER" --priority 2>/dev/null || echo "10")

            # Convert "unlimited" to a large number for allocator
            if [ "$MAX_GPUS" = "unlimited" ] || [ "$MAX_GPUS" = "null" ]; then
                MAX_GPUS=999
            fi

            log_info "Allocating GPU via gpu_allocator_v2.py (priority: $PRIORITY, max: $MAX_GPUS)..."

            # Allocate GPU
            # Temporarily disable set -e to capture exit code (otherwise script exits before we can handle error)
            set +e
            ALLOC_OUTPUT=$(python3 "$GPU_ALLOCATOR" allocate "$CURRENT_USER" "$CONTAINER_TAG" "$MAX_GPUS" "$PRIORITY" 2>&1)
            ALLOC_EXIT=$?
            set -e

            if [ $ALLOC_EXIT -eq 0 ] && echo "$ALLOC_OUTPUT" | grep -q "✓ Allocated"; then
                # Extract friendly GPU ID (for logging: "1.1", "2.0", etc.)
                ALLOCATED_GPU=$(echo "$ALLOC_OUTPUT" | grep -oP '(?<=GPU/MIG )\S+(?= to)')

                # Extract Docker ID (MIG UUID for MIG instances, gpu index for full GPUs)
                DOCKER_ID=$(echo "$ALLOC_OUTPUT" | grep "^DOCKER_ID=" | cut -d= -f2)

                if [ -n "$ALLOCATED_GPU" ] && [ -n "$DOCKER_ID" ]; then
                    # Use Docker ID (UUID for MIG) instead of friendly ID
                    GPU_ARG="-g=device=$DOCKER_ID"
                    log_success "GPU $ALLOCATED_GPU allocated successfully"

                    # Check soft limits (warn at 80%+)
                    CURRENT_GPU_COUNT=$(python3 "$SCRIPT_DIR/gpu-state-reader.py" user "$CURRENT_USER" 2>/dev/null | grep -c "gpu_slot" || echo "0")
                    # Ensure CURRENT_GPU_COUNT is a valid integer
                    CURRENT_GPU_COUNT="${CURRENT_GPU_COUNT//[^0-9]/}"
                    CURRENT_GPU_COUNT="${CURRENT_GPU_COUNT:-0}"
                    if [ "$MAX_GPUS" != "999" ] && [ "$MAX_GPUS" -gt 0 ] 2>/dev/null; then
                        GPU_PERCENT=$((CURRENT_GPU_COUNT * 100 / MAX_GPUS))
                        if [ "$GPU_PERCENT" -ge 100 ]; then
                            log_warning "GPU limit reached ($CURRENT_GPU_COUNT/$MAX_GPUS). This is your last available GPU."
                        elif [ "$GPU_PERCENT" -ge 80 ]; then
                            log_warning "GPU usage high ($CURRENT_GPU_COUNT/$MAX_GPUS, ${GPU_PERCENT}%). Consider retiring idle containers."
                        fi
                    fi
                else
                    log_error "GPU allocator returned success but couldn't parse GPU ID"
                    log_error "Output: $ALLOC_OUTPUT"
                    exit 1
                fi
            else
                # Use friendly error messages
                ERROR_MESSAGES="$SCRIPT_DIR/../lib/error-messages.sh"
                echo ""  # Blank line before error
                if [ -f "$ERROR_MESSAGES" ]; then
                    source "$ERROR_MESSAGES"
                    show_limit_error "$ALLOC_OUTPUT" "$CURRENT_USER" "$CONTAINER_TAG"
                else
                    # Fallback if error-messages.sh not found
                    log_error "GPU allocation failed: $ALLOC_OUTPUT"
                    echo ""
                    echo "Your allocation may have been rejected due to resource limits."
                    echo "Run 'check-limits' to see your current usage."
                fi
                exit 1
            fi
        else
            # Fallback if allocator not available
            log_warning "GPU allocator not found, using default GPU allocation"
            GPU_ARG="-g=all"
        fi
    fi
fi

# Extract shm-size and cgroup-parent from resource limits for mlc-patched.py
# These must be passed AT CREATION TIME (cannot be updated via docker update)
SHM_SIZE=""
CGROUP_PARENT=""
for arg in $RESOURCE_LIMITS; do
    case $arg in
        --shm-size=*)
            SHM_SIZE="${arg#*=}"
            ;;
        --cgroup-parent=*)
            CGROUP_PARENT="${arg#*=}"
            ;;
    esac
done

# Build arguments for mlc-patched.py (DS01-enhanced AIME v2)
MLC_ARGS="create $CONTAINER_NAME"

# Add framework (optional if custom image provided)
if [ -n "$FRAMEWORK" ]; then
    MLC_ARGS="$MLC_ARGS $FRAMEWORK"
fi

# Add version (optional)
if [ -n "$VERSION" ]; then
    MLC_ARGS="$MLC_ARGS $VERSION"
fi

# Add script mode flag (non-interactive)
MLC_ARGS="$MLC_ARGS -s"

# Add workspace directory
MLC_ARGS="$MLC_ARGS -w $WORKSPACE_DIR"

# Add data directory (optional)
if [ -n "$DATA_DIR" ]; then
    MLC_ARGS="$MLC_ARGS -d $DATA_DIR"
fi

# Add custom image (DS01-specific: bypasses AIME catalog)
if [ -n "$CUSTOM_IMAGE" ]; then
    MLC_ARGS="$MLC_ARGS --image $CUSTOM_IMAGE"
    log_info "Using custom image: $CUSTOM_IMAGE"
fi

# Add GPU argument (optional)
if [ -n "$GPU_ARG" ]; then
    MLC_ARGS="$MLC_ARGS $GPU_ARG"
fi

# Add resource limits that must be set at creation time (DS01 patch)
if [ -n "$SHM_SIZE" ]; then
    MLC_ARGS="$MLC_ARGS --shm-size=$SHM_SIZE"
    log_info "Setting shm-size: $SHM_SIZE"
fi

if [ -n "$CGROUP_PARENT" ]; then
    MLC_ARGS="$MLC_ARGS --cgroup-parent=$CGROUP_PARENT"
    log_info "Setting cgroup-parent: $CGROUP_PARENT"
fi

# Add DS01 labels for stateless GPU tracking
ALLOCATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MLC_ARGS="$MLC_ARGS --ds01-label ds01.managed=true"
MLC_ARGS="$MLC_ARGS --ds01-label ds01.user=$CURRENT_USER"
MLC_ARGS="$MLC_ARGS --ds01-label ds01.user.sanitized=$SANITIZED_USER"
MLC_ARGS="$MLC_ARGS --ds01-label ds01.created_at=$ALLOCATED_AT"

if [ -n "$ALLOCATED_GPU" ]; then
    MLC_ARGS="$MLC_ARGS --ds01-label ds01.gpu.allocated=$ALLOCATED_GPU"
    MLC_ARGS="$MLC_ARGS --ds01-label ds01.gpu.allocated_at=$ALLOCATED_AT"

    if [ -n "$DOCKER_ID" ]; then
        MLC_ARGS="$MLC_ARGS --ds01-label ds01.gpu.uuid=$DOCKER_ID"
    fi

    if [ -n "$PRIORITY" ]; then
        MLC_ARGS="$MLC_ARGS --ds01-label ds01.gpu.priority=$PRIORITY"
    fi
fi

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - No containers will be created"
    echo ""
    log_info "Would execute:"
    echo "  python3 $MLC_PATCHED $MLC_ARGS"
    echo ""
    log_info "Would apply resource limits:"
    echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    echo ""
    log_info "Container would be named: $CONTAINER_TAG"
    exit 0
fi

# Source container logger
if [ -f "$SCRIPT_DIR/../lib/container-logger.sh" ]; then
    source "$SCRIPT_DIR/../lib/container-logger.sh"
fi

# Call mlc-patched.py (DS01-enhanced AIME v2)
log_info "Creating container with mlc-patched.py (AIME v2)..."

# Log operation start
if command -v log_container_operation &>/dev/null; then
    log_container_operation "create_start" "$CURRENT_USER" "$CONTAINER_TAG" "${ALLOCATED_GPU:-none}" "pending" "Starting container creation"
fi

# Capture output to suppress verbose logging (only show errors)
# Debug: Show command being executed (helps troubleshoot argument parsing issues)
if [ -n "${DS01_DEBUG:-}" ]; then
    log_info "DEBUG: Executing command:"
    echo "  python3 $MLC_PATCHED $MLC_ARGS"
fi

# Temporarily disable set -e to capture exit code and allow error handling
set +e
MLC_OUTPUT=$(python3 "$MLC_PATCHED" $MLC_ARGS 2>&1)
MLC_EXIT_CODE=$?
set -e

if [ $MLC_EXIT_CODE -ne 0 ]; then
    echo ""
    log_error "Container creation failed (exit code: $MLC_EXIT_CODE)"
    echo ""

    # Log failure
    if command -v log_container_operation &>/dev/null; then
        log_container_operation "create_failed" "$CURRENT_USER" "$CONTAINER_TAG" "${ALLOCATED_GPU:-none}" "failed" "mlc-patched.py exit code $MLC_EXIT_CODE"
    fi

    # Show detailed diagnostic information
    echo -e "${YELLOW}═══ Diagnostic Information ═══${NC}"
    echo ""

    # Show GPU allocation details
    if [ -n "$ALLOCATED_GPU" ]; then
        echo -e "${BLUE}GPU Allocation:${NC}"
        echo "  Allocated GPU: $ALLOCATED_GPU"
        echo "  Docker ID: ${DOCKER_ID:-unknown}"
        echo "  Priority: ${PRIORITY:-unknown}"
        echo ""
    fi

    # Show resource limits being applied
    echo -e "${BLUE}Resource Limits:${NC}"
    echo "$RESOURCE_LIMITS" | tr ' ' '\n' | sed 's/^/  /'
    echo ""

    # Show the command that was attempted
    echo -e "${BLUE}Command Attempted:${NC}"
    echo "  python3 $MLC_PATCHED $MLC_ARGS"
    echo ""

    # Show mlc-patched.py error output (full output, last 30 lines)
    if [ -n "$MLC_OUTPUT" ]; then
        echo -e "${BLUE}mlc-patched.py Output:${NC}"
        echo "$MLC_OUTPUT" | tail -30 | sed 's/^/  /'
        echo ""
    else
        echo -e "${BLUE}mlc-patched.py Output:${NC}"
        echo "  (no output captured)"
        echo ""
        # Exit code 2 usually means Python/argparse error
        if [ "$MLC_EXIT_CODE" -eq 2 ]; then
            echo -e "${YELLOW}Note: Exit code 2 often indicates a Python argument parsing error.${NC}"
            echo "Checking if mlc-patched.py can be executed..."
            echo ""
            if python3 "$MLC_PATCHED" --help &>/dev/null; then
                echo "  mlc-patched.py is accessible and working"
            else
                echo "  mlc-patched.py may have an issue - check file permissions and Python imports"
            fi
            echo ""
        fi
    fi

    # Show helpful troubleshooting steps
    echo -e "${YELLOW}═══ Troubleshooting Steps ═══${NC}"
    echo ""
    echo "1. Check Docker daemon:"
    echo "   docker info"
    echo ""
    echo "2. Check GPU availability:"
    echo "   python3 $GPU_ALLOCATOR status"
    echo ""
    echo "3. Check GPU allocator logs:"
    echo "   tail -20 /var/log/ds01/gpu-allocations.log"
    echo ""
    echo "4. Verify custom image exists (if using --image):"
    if [ -n "$CUSTOM_IMAGE" ]; then
        echo "   docker images | grep '$CUSTOM_IMAGE'"
    else
        echo "   (not using custom image)"
    fi
    echo ""
    echo "5. Check for Python import errors:"
    echo "   python3 $MLC_PATCHED --help"
    echo ""

    # Release allocated GPU if one was allocated
    if [ -n "$ALLOCATED_GPU" ] && [ -f "$GPU_ALLOCATOR" ]; then
        log_info "Releasing allocated GPU $ALLOCATED_GPU..."
        python3 "$GPU_ALLOCATOR" release "$CONTAINER_TAG" &>/dev/null || true
    fi

    echo ""
    exit $MLC_EXIT_CODE
fi

# Apply resource limits to the created container
log_info "Applying resource limits to container..."

# Verify container was created
if ! docker inspect "$CONTAINER_TAG" &>/dev/null; then
    echo ""
    log_error "Container $CONTAINER_TAG was not created successfully"
    log_error "mlc-patched.py reported success but container does not exist in Docker"
    echo ""

    echo -e "${YELLOW}═══ Diagnostic Information ═══${NC}"
    echo ""

    # Show mlc-patched.py output for debugging
    if [ -n "$MLC_OUTPUT" ]; then
        echo -e "${BLUE}mlc-patched.py output:${NC}"
        echo "$MLC_OUTPUT" | tail -30 | sed 's/^/  /'
        echo ""
    fi

    # List all containers to see if a similar name exists
    echo -e "${BLUE}Existing containers for user:${NC}"
    docker ps -a --filter "label=ds01.user=$CURRENT_USER" --format "  {{.Names}} ({{.Status}})" 2>/dev/null || echo "  (none found)"
    echo ""

    echo -e "${YELLOW}═══ Troubleshooting Steps ═══${NC}"
    echo ""
    echo "1. Check Docker daemon status:"
    echo "   docker info"
    echo ""
    echo "2. Check Docker logs for errors:"
    echo "   sudo journalctl -u docker --since '5 minutes ago' | tail -20"
    echo ""
    echo "3. Try listing all containers:"
    echo "   docker ps -a"
    echo ""

    # Release allocated GPU if one was allocated
    if [ -n "$ALLOCATED_GPU" ] && [ -f "$GPU_ALLOCATOR" ]; then
        log_info "Releasing allocated GPU $ALLOCATED_GPU..."
        python3 "$GPU_ALLOCATOR" release "$CONTAINER_TAG" &>/dev/null || true
    fi

    echo ""
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