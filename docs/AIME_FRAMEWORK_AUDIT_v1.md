# AIME Framework v1 - Complete Audit

**Date:** 2025-11-11
**Purpose:** Comprehensive audit to understand AIME framework for integration with DS01
**Submodule:** `/home/user/ds01-infra/aime-ml-containers` (commit: 9135cd9)

---

## 1. Executive Summary

AIME ML Containers (v1) is a **deprecated but functional** container management system providing:
- Framework-based container creation (PyTorch, TensorFlow, MXNet)
- Version-controlled base images from central repository
- Multi-user isolation via naming convention
- Label-based container identification
- Lifecycle management commands

**Current Status:** Deprecated in favor of v2, but v1 remains stable and well-tested.

**Key Insight for DS01:** AIME provides a solid foundation but was **NOT designed for**:
- Custom user-built images (always uses framework catalog)
- Resource limits/quotas
- GPU allocation management
- Multi-tier package customization

---

## 2. Architecture Overview

### 2.1 Core Commands (9 total)

| Command | Purpose | Used by DS01? | How? |
|---------|---------|---------------|------|
| `mlc-create` | Create container | ✅ **YES** | Wrapped by `mlc-create-wrapper.sh` |
| `mlc-open` | Enter container | ✅ **YES** | Called directly by `container-run` |
| `mlc-stats` | Show stats | ✅ **YES** | Wrapped by `mlc-stats-wrapper.sh` |
| `mlc-list` | List containers | ❌ **NO** | DS01 uses custom `container-list` |
| `mlc-stop` | Stop container | ❌ **NO** | DS01 uses custom `container-stop` |
| `mlc-start` | Start container | ❌ **NO** | Rarely needed (mlc-open auto-starts) |
| `mlc-remove` | Remove container | ❌ **NO** | DS01 uses custom `container-cleanup` |
| `mlc-update-sys` | Update system | ❌ **NO** | System admin only |
| `mlc-upgrade-sys` | Upgrade system | ❌ **NO** | System admin only |

ONE AIM OF THE PLANNED REFACTOR: to properly integrate and use all of rest of `mlc-*` commands in ds01 (either wrapped if needed, or directly called).
- `container list` should call `mlc-list` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01).
- `container stop` should call `mlc-stop` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01).
- new cmd: `container start` that calls `mlc-start` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01)
- `container cleanup` / `container remove` should call `mlc-remove` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01)

Also TODO: make sure I've downloaded and am using latest mlc!

### 2.2 Supporting Files

```
aime-ml-containers/
├── mlc-create              # Main container creation script (238 lines)
├── mlc-open                # Container entry script (94 lines)
├── mlc-list                # Container listing (48 lines)
├── mlc-stats               # Stats display (17 lines)
├── mlc-stop                # Container stop (91 lines)
├── mlc-start               # Container start (58 lines)
├── mlc-remove              # Container removal (92 lines)
├── mlc-update-sys          # System update
├── mlc-upgrade-sys         # System upgrade
├── ml_images.repo          # Framework catalog (76 frameworks × versions)
├── README.md               # User documentation
└── doc/
    └── README.html         # Additional docs
```

**No Python helper scripts** - AIME is pure Bash!

---

## 3. Deep Dive: `mlc-create` Workflow

This is the **critical script** for DS01 integration. Here's the complete workflow:

### 3.1 Input Validation Phase

```bash
# Lines 149-188: Argument parsing
CONTAINER_NAME=${ARGS[0]}      # Required: e.g., "my-project"
FRAMEWORK_NAME=${ARGS[1]}      # Required: "Pytorch", "Tensorflow", "Mxnet"
FRAMEWORK_VERSION=${ARGS[2]}   # Optional: defaults to latest

# Flags:
-i, --interactive    # Interactive mode (not used in current AIME v1)
-g=*, --gpus=*       # GPU spec: "all", "0", "0,1", etc. (default: "all")
-w=*, --workspace=*  # Workspace dir (default: $HOME/workspace)
-d=*, --data=*       # Optional data mount
```

### 3.2 Framework Image Lookup Phase

**Key Functions:**

```bash
read_repo() {
  # Reads ml_images.repo CSV file
  # Columns: framework, version, arch, repo, reserved
  # Filters by SUPPORTED_ARCH="CUDA_ADA" (Ada Lovelace GPUs)
  # Builds IMAGES associative array
}

find_image() {
  SEARCH_FRAMEWORK=$1  # e.g., "Pytorch"
  SEARCH_VERSION=$2    # e.g., "2.5.1"

  # Returns Docker Hub image like:
  # aimehub/pytorch-2.5.1-cuda12.1.1
}
```

**Image Repository Format** (`ml_images.repo`):

```csv
Pytorch, 2.5.1, CUDA_ADA, aimehub/pytorch-2.5.1-aime-cuda12.1.1
Pytorch, 2.5.0, CUDA_ADA, aimehub/pytorch-2.5.0-cuda12.1
Tensorflow, 2.16.1, CUDA_ADA, aimehub/tensorflow-2.16.1-cuda12.3
Tensorflow, 2.15.0, CUDA_ADA, aimehub/tensorflow-2.15.0-cuda12.3
...
```

**Total Available:** 76 images (Pytorch: 35, Tensorflow: 36, Mxnet: 5)

### 3.3 Base Image Preparation Phase

```bash
# Lines 216-218: Pull base image
docker pull $IMAGE
# e.g., docker pull aimehub/pytorch-2.5.1-cuda12.1.1
```

Then AIME performs **one-time customization** (Lines 220-228):

```bash
# Run temporary container to customize
docker run \
  -v $WORKSPACE_MOUNT:$WORKSPACE \
  --name=$CONTAINER_TAG \
  --gpus=$GPUS \
  $IMAGE \
  bash -c "
    # Set custom prompt
    echo \"export PS1='[$CONTAINER_NAME] ...$ '\" >> ~/.bashrc

    # Install basic tools
    apt-get update -y > /dev/null
    apt-get install sudo git -q -y > /dev/null

    # Create user matching host UID/GID
    addgroup --gid $GROUP_ID $USER > /dev/null
    adduser --uid $USER_ID --gid $GROUP_ID $USER --disabled-password --gecos aime > /dev/null
    passwd -d $USER

    # Setup passwordless sudo
    echo \"$USER ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/${USER}_no_password
    chmod 440 /etc/sudoers.d/${USER}_no_password

    exit
  "

# Commit customized container as new image
docker commit $CONTAINER_TAG $IMAGE:$CONTAINER_TAG

# Remove temporary container
docker rm $CONTAINER_TAG
```

**What this does:**
1. Creates user inside container matching host UID/GID
2. Grants passwordless sudo
3. Installs git and sudo
4. Sets custom prompt
5. Saves as new image tag: `aimehub/pytorch-2.5.1:my-project._.1001`

### 3.4 Container Naming Convention

```bash
# Line 158: Container tag format
USER_ID=$(id -u)               # e.g., 1001
CONTAINER_TAG=$CONTAINER_NAME._.$USER_ID
# Result: "my-project._.1001"
```

**Why this matters:**
- Multi-user isolation: Each user gets their own container even with same name
- `mlc-open` automatically finds container: tries `name._.uid` first, then `name`

### 3.5 AIME Labels

```bash
# Line 222: Label prefix
CONTAINER_LABEL="aime.mlc"

# Lines 235: All labels applied
--label=$CONTAINER_LABEL=$USER                    # aime.mlc=username
--label=$CONTAINER_LABEL.NAME=$CONTAINER_NAME     # aime.mlc.NAME=my-project
--label=$CONTAINER_LABEL.USER=$USER               # aime.mlc.USER=username
--label=$CONTAINER_LABEL.VERSION=$MLC_VERSION     # aime.mlc.VERSION=3
--label=$CONTAINER_LABEL.WORK_MOUNT=$WORKSPACE_MOUNT  # aime.mlc.WORK_MOUNT=/home/user/workspace
--label=$CONTAINER_LABEL.DATA_MOUNT=$DATA_MOUNT   # aime.mlc.DATA_MOUNT=/path/to/data
--label=$CONTAINER_LABEL.FRAMEWORK=$FRAMEWORK_NAME-$FRAMEWORK_VERSION  # aime.mlc.FRAMEWORK=Pytorch-2.5.1
--label=$CONTAINER_LABEL.GPUS=$GPUS               # aime.mlc.GPUS=all
```

**Label Schema:**
- Base label: `aime.mlc=$USER` (filter for all mlc containers)
- Metadata: `aime.mlc.*` namespace
- All other AIME commands filter by `--filter=label=aime.mlc`

### 3.6 Container Lifecycle Management

```bash
# Lines 230-235: Final container creation
docker create -it \
  # Volumes
  $VOLUMES \                  # -v $WORKSPACE_MOUNT:/workspace [-v $DATA_MOUNT:/data]
  -w $WORKSPACE \             # Working directory = /workspace

  # Naming & Labels
  --name=$CONTAINER_TAG \     # my-project._.1001
  --label=... \               # All aime.mlc labels

  # User & Security
  --user $USER_ID:$GROUP_ID \ # Run as host user
  --tty --privileged --interactive \
  --group-add video \         # Access to /dev/video*
  --group-add sudo \          # Sudo group

  # GPU & Devices
  --gpus=$GPUS \              # GPU allocation
  --device /dev/video0 \      # Webcam access
  --device /dev/snd \         # Audio access

  # Networking & IPC
  --network=host \            # Host network mode
  --ipc=host \                # Shared IPC namespace
  -v /tmp/.X11-unix:/tmp/.X11-unix \  # X11 forwarding

  # Resource Limits (AIME doesn't set these!)
  --ulimit memlock=-1 \       # Unlimited locked memory
  --ulimit stack=67108864 \   # 64MB stack limit

  # Image & Command
  $IMAGE:$CONTAINER_TAG \     # The customized image
  bash -c "echo \"export PS1=...'\" >> ~/.bashrc; bash"
```

**Important:** AIME creates container in **stopped state**. User must use `mlc-open` to start it.

---

## 4. What AIME Does NOT Provide

### 4.1 No Custom Image Support

```bash
# AIME ALWAYS uses ml_images.repo
IMAGE=$(find_image $FRAMEWORK_NAME $FRAMEWORK_VERSION)

# If framework not in repo → ERROR and EXIT
if [[ $IMAGE == "" ]]; then
  echo "Error: unavailable framework version"
  exit -3
fi
```

**Cannot pass custom Docker image** - it MUST be a framework from the catalog.

### 4.2 No Resource Limits

AIME does **NOT** set:
- CPU limits (`--cpus`)
- Memory limits (`--memory`)
- Shared memory (`--shm-size`)
- PID limits (`--pids-limit`)
- Cgroup parent

Only sets:
- `--ulimit memlock=-1` (unlimited locked memory for CUDA)
- `--ulimit stack=67108864` (64MB stack)

### 4.3 No GPU Allocation Management

```bash
# Line 11: Default GPU allocation
GPUS="all"  # All GPUs available to container!
```

AIME just passes `--gpus=$GPUS` to Docker. No:
- GPU allocation tracking
- MIG instance awareness
- Priority-based allocation
- Fair sharing

### 4.4 No Package Customization

Base images from `aimehub/*` come with:
- Framework (PyTorch/TensorFlow/MXNet)
- CUDA toolkit
- cuDNN
- Python 3.x

**Does NOT include:**
- Jupyter Lab
- NumPy, Pandas, Scikit-learn
- Domain-specific packages (timm, transformers, etc.)
- User-specified packages

Users must install packages **inside running container** via pip/apt.

### 4.5 No State Management

AIME is **stateless** - no tracking of:
- Which GPUs are allocated
- Container resource usage
- Idle containers
- User quotas

---

## 5. Integration Points for DS01

### 5.1 What to Keep from AIME

✅ **Framework catalog system** (`ml_images.repo`)
- 76 pre-tested framework images
- Architecture-aware selection (CUDA_ADA for Ada GPUs)
- Version management

✅ **Container naming convention** (`name._.uid`)
- Multi-user isolation
- Predictable container discovery

✅ **Label system** (`aime.mlc.*`)
- Container identification
- Metadata storage
- Filtering in docker commands

✅ **Base image preparation workflow**
- User creation with matching UID/GID
- Passwordless sudo setup
- Git installation

✅ **`mlc-open` behavior**
- Auto-start if stopped
- Auto-stop if inactive
- Simple `docker exec` entry

### 5.2 What DS01 Must Add/Replace

🔧 **Custom image support**
- Accept user-built images (not just framework catalog)
- Allow Dockerfile-based customization
- Support both: AIME base → custom layers

🔧 **Resource limits**
- CPU/memory/GPU quotas from `resource-limits.yaml`
- Cgroup integration
- Fair scheduling

🔧 **GPU allocation**
- MIG-aware allocation
- Priority-based scheduling
- State tracking (`gpu-state.json`)

🔧 **Package customization**
- Framework → Base packages → Use case packages → User packages
- Dockerfile generation
- Image build workflow

---

## 6. Critical Code Sections for Patching

### 6.1 Image Resolution (Lines 108-129)

**Current:**
```bash
function find_image {
  SEARCH_FRAMEWORK=$1
  SEARCH_VERSION=$2

  # Search ml_images.repo only
  for K in "${!FRAMEWORK_ENTRIES[@]}"; do
    if [[ $K == $SEARCH_FRAMEWORK ]]; then
      # ... find matching version
      echo $image
      return
    fi
  done
}
```

**Needs to become:**
```bash
function find_image {
  SEARCH_FRAMEWORK=$1
  SEARCH_VERSION=$2
  CUSTOM_IMAGE=$3  # NEW: optional custom image name

  # Option 1: Custom image provided → use it
  if [ -n "$CUSTOM_IMAGE" ]; then
    # Validate image exists locally
    if docker image inspect "$CUSTOM_IMAGE" &>/dev/null; then
      echo "$CUSTOM_IMAGE"
      return 0
    else
      log_error "Custom image not found: $CUSTOM_IMAGE"
      return 1
    fi
  fi

  # Option 2: Use AIME framework catalog
  for K in "${!FRAMEWORK_ENTRIES[@]}"; do
    # ... existing logic
  done
}
```

### 6.2 Container Creation (Lines 226-235)

**Current:**
```bash
# No resource limits!
docker create -it $VOLUMES -w $WORKSPACE \
  --name=$CONTAINER_TAG \
  --label=... \
  --user $USER_ID:$GROUP_ID \
  --gpus=$GPUS \
  ...
```

**Needs to become:**
```bash
# Get DS01 resource limits
RESOURCE_LIMITS=$(python3 get_resource_limits.py $USER --docker-args)
GPU_ALLOCATION=$(python3 gpu_allocator.py allocate $USER $CONTAINER_TAG ...)

# Apply limits
docker create -it $VOLUMES -w $WORKSPACE \
  --name=$CONTAINER_TAG \
  --label=... \
  --user $USER_ID:$GROUP_ID \
  --gpus=device=$GPU_ALLOCATION \  # Specific GPU, not "all"
  $RESOURCE_LIMITS \                # --cpus, --memory, --shm-size, --cgroup-parent
  ...
```

---

## 7. Recommended Approach: Minimal Patch

### Option A: Patch `mlc-create` directly (NOT RECOMMENDED)
- Modify AIME submodule code
- Creates upstream conflict
- Hard to update AIME in future

### Option B: Create `mlc-create-patched` (RECOMMENDED)
- Copy `mlc-create` → `mlc-create-patched`
- Make minimal changes for custom images + resource limits
- Document all deviations
- Keep original AIME intact for reference

### Option C: Wrapper approach (CURRENT DS01 - INSUFFICIENT)
- Current `mlc-create-wrapper.sh` can't pass custom images to AIME
- AIME rejects non-catalog frameworks
- Requires patching anyway

---

## 8. Patch Strategy

**Minimal changes required:**

1. **Add custom image parameter** (15 lines)
   - New flag: `--image=<custom-image>`
   - Modify `find_image()` to accept custom images
   - Skip ml_images.repo lookup if custom image provided

2. **Add resource limit parameters** (20 lines)
   - Call `get_resource_limits.py` before docker create
   - Inject `--cpus`, `--memory`, `--cgroup-parent` into docker create

3. **Add GPU allocation** (25 lines)
   - Call `gpu_allocator.py allocate` before docker create
   - Use `--gpus=device=X` instead of `--gpus=all`
   - Record allocation in state file

4. **Update labels** (5 lines)
   - Keep `aime.mlc.*` labels for compatibility
   - No need for `ds01.*` labels (use AIME namespace)

**Total patch size: ~65 lines of changes to 238-line script**

---

## 9. Testing Requirements

Before deploying patched version:

1. ✅ **AIME base workflow still works**
   ```bash
   mlc-create-patched test1 pytorch 2.5.1
   # Should work identically to original
   ```

2. ✅ **Custom image workflow works**
   ```bash
   mlc-create-patched test2 pytorch --image=my-custom-image
   # Should accept custom image
   ```

3. ✅ **Resource limits applied**
   ```bash
   docker inspect test2 | grep -i memory
   docker inspect test2 | grep -i cpus
   # Should show limits from resource-limits.yaml
   ```

4. ✅ **GPU allocation tracked**
   ```bash
   python3 gpu_allocator.py status
   # Should show GPU assigned to test2
   ```

5. ✅ **Labels preserved**
   ```bash
   docker inspect test2 --format '{{json .Config.Labels}}' | jq
   # Should show all aime.mlc.* labels
   ```

---

## 10. Conclusion

### AIME Strengths
- ✅ Stable, battle-tested framework
- ✅ Excellent framework catalog (76 images)
- ✅ Clean multi-user isolation
- ✅ Simple, understandable bash scripts
- ✅ Good label-based organization

### AIME Limitations (for DS01)
- ❌ No custom image support
- ❌ No resource limits
- ❌ No GPU management
- ❌ No package customization workflow

### Integration Recommendation

**Create `mlc-create-patched`** that:
1. **Preserves 95% of AIME logic**
2. **Adds custom image support** (check if custom image exists → use it, else use AIME catalog)
3. **Integrates DS01 resource limits** (call get_resource_limits.py + gpu_allocator.py)
4. **Documents all deviations** (in comments and README)
5. **Remains AIME-compatible** (can still use AIME catalog without changes)

This gives us **maximum AIME reuse** with **minimal DS01 additions**.

---

**Next Steps:** Proceed to DS01 audit to understand current implementation details.
