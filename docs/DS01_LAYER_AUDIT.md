# DS01 Infrastructure Layer - Complete Audit

**Date:** 2025-11-11
**Purpose:** Comprehensive audit of DS01's current implementation to understand custom image workflow and container management
**Repository:** `/home/user/ds01-infra`

---

## 1. Executive Summary

DS01 is a **lightweight GPU resource management layer** built on top of base systems. Current implementation:

### Current Architecture (Before AIME Integration)
```
TIER 1: Base System
  - Docker + NVIDIA Container Toolkit
  - NO AIME framework usage!

TIER 2: DS01 Docker Layer
  - image-create (custom Dockerfile generation)
  - mlc-create-wrapper (resource limits + GPU allocation)
  - get_resource_limits.py (YAML parser)
  - gpu_allocator.py (GPU state management)

TIER 3: DS01 User Commands
  - container-create, container-run, container-list, etc.
  - image-create, image-update, image-list, etc.

TIER 4: DS01 Orchestrators
  - project-init (dir → git → image → container)
  - user-setup (ssh → project → vscode)
```

### Key Finding

**DS01 does NOT currently use AIME framework at all!**

The current implementation:
- Uses generic Docker base images (pytorch/pytorch, tensorflow/tensorflow)
- Builds custom images via Dockerfile
- Does NOT leverage AIME's framework catalog
- Reinvents container creation logic

**This is the core issue** - DS01 should be using AIME base images as starting point!

---

## 2. Current Image Creation Workflow

### 2.1 `image-create` - Full Analysis

**Location:** `/home/user/ds01-infra/scripts/user/image-create` (949 lines!)

**Purpose:** Interactive wizard to create custom Docker images

#### Phase 1: User Input Collection

```bash
interactive_mode() {
  # 1. Image name
  read -p "Image name: " IMAGE_NAME
  FULL_IMAGE_NAME="${IMAGE_NAME}-${USERNAME}"  # e.g., my-project-john

  # 2. Framework selection
  echo "1) PyTorch 2.5.1"
  echo "2) TensorFlow 2.14.0"
  echo "3) JAX"
  read -p "Framework [1-3]: " FW_CHOICE

  # 3. Base package selection (NEW 3-tier system)
  echo "Install base data science packages?"
  echo "1) Yes - defaults (jupyter, pandas, sklearn, etc.)"
  echo "2) No - skip"
  echo "3) Custom - specify manually"
  read -p "Choice: " BASE_PKG_CHOICE

  # 4. Use case selection
  echo "1) None/Custom"
  echo "2) General ML (xgboost, lightgbm)"
  echo "3) Computer Vision (timm, albumentations)"
  echo "4) NLP (transformers, datasets)"
  echo "5) RL (gymnasium, stable-baselines3)"
  read -p "Use case: " UC_CHOICE

  # 5. Additional packages
  read -p "Additional packages: " ADDITIONAL_PACKAGES

  # 6. System packages
  read -p "System packages (apt): " SYSTEM_PACKAGES
}
```

**Package Selection Logic (3-Tier):**

1. **Framework Base** (from Docker Hub, NOT AIME!)
   ```bash
   get_base_image() {
     case $framework in
       tensorflow|tf) echo "tensorflow/tensorflow:2.14.0-gpu" ;;
       jax)           echo "nvcr.io/nvidia/jax:23.10-py3" ;;
       *)             echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime" ;;
     esac
   }
   ```

2. **Base Packages** (if user selects)
   ```bash
   get_base_packages() {
     echo "jupyter jupyterlab ipykernel ipywidgets \
           numpy pandas matplotlib seaborn scikit-learn \
           scipy tqdm tensorboard Pillow python-dotenv"
   }
   ```

3. **Use Case Packages**
   ```bash
   get_usecase_packages() {
     case $usecase in
       cv)  echo "timm albumentations opencv-python-headless torchvision" ;;
       nlp) echo "transformers datasets tokenizers accelerate sentencepiece" ;;
       rl)  echo "gymnasium stable-baselines3 tensorboard" ;;
       ml)  echo "xgboost lightgbm catboost optuna" ;;
     esac
   }
   ```

4. **User Additional Packages** (custom)

#### Phase 2: Dockerfile Generation

```bash
create_dockerfile() {
  local dockerfile="$DOCKERFILES_DIR/${image_name}.Dockerfile"

  cat > "$dockerfile" << DOCKERFILEEOF
# DS01 Custom Image: $image_name
# Created: $(date)
# Framework: $framework
# Author: $USERNAME

FROM $base_image  # e.g., pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime

LABEL maintainer="$USERNAME"
LABEL maintainer.id="$USER_ID"
LABEL ds01.image="$image_name"
LABEL ds01.framework="$framework"
LABEL ds01.created="$(date -Iseconds)"

WORKDIR /workspace

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \\
    git curl wget vim htop \\
    $system_pkgs \\
    && rm -rf /var/lib/apt/lists/*

# Core Python packages
RUN pip install --no-cache-dir \\
    jupyter jupyterlab ipykernel numpy pandas \\
    matplotlib seaborn scikit-learn scipy tqdm ...

# Use case specific packages
RUN pip install --no-cache-dir \\
    $usecase_packages

# Additional user packages
RUN pip install --no-cache-dir \\
    $additional

# Configure Jupyter
RUN jupyter lab --generate-config && \\
    echo "c.ServerApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_lab_config.py

# IPython kernel
RUN python -m ipykernel install --user \\
    --name=$image_name \\
    --display-name="$image_name ($framework)"

ENV PYTHONUNBUFFERED=1
ENV CUDA_DEVICE_ORDER=PCI_BUS_ID
ENV HF_HOME=/workspace/.cache/huggingface
ENV TORCH_HOME=/workspace/.cache/torch

CMD ["/bin/bash"]
DOCKERFILEEOF
}
```

**Dockerfile Storage:**
- Default: `~/dockerfiles/<image-name>.Dockerfile`
- Optional: `~/workspace/<project>/Dockerfile` (with `--project-dockerfile` flag)

#### Phase 3: Build Image

```bash
# Build with Docker
docker build -t "$FULL_IMAGE_NAME" -f "$DOCKERFILE" "$(dirname $DOCKERFILE)/"

# Save metadata
mkdir -p "$HOME/ds01-config/images"
cat > "$HOME/ds01-config/images/${FULL_IMAGE_NAME}.info" << EOF
Image: $FULL_IMAGE_NAME
Framework: $FRAMEWORK
Use Case: $USECASE
Created: $(date)
Dockerfile: $DOCKERFILE
Packages: ...
EOF
```

#### Phase 4: Optionally Create Container

```bash
# Prompt user
read -p "Create container now? [Y/n]: " CONTAINER_CONFIRM

if [[ "$CONTAINER_CONFIRM" =~ ^[Yy]$ ]]; then
  container-create "$IMAGE_NAME"  # Calls Tier 3 command
fi
```

---

## 3. Current Container Creation Workflow

### 3.1 `container-create` - Full Analysis

**Location:** `/home/user/ds01-infra/scripts/user/container-create` (759 lines!)

**Purpose:** Create container from image (custom or framework) with DS01 resource limits

#### Step 1: Interactive Image Selection

```bash
echo "Select image source:"
echo "1) Use existing image"
echo "2) Create custom image"
echo "3) Use base framework (PyTorch/TensorFlow)"
read -p "Choice: " IMAGE_CHOICE

case $IMAGE_CHOICE in
  1) # List available images
     docker images --format "{{.Repository}}" | grep "$USERNAME-"
     read -p "Select: " IMG_SELECTION
     ;;

  2) # Create new custom image
     # Calls image-create internally
     "$SCRIPT_DIR/image-create" ...
     ;;

  3) # Use framework directly
     echo "1) PyTorch"
     echo "2) TensorFlow"
     read -p "Framework: " FW_CHOICE
     IMAGE_OR_FRAMEWORK="pytorch"  # or "tensorflow"
     ;;
esac
```

#### Step 2: Container Name & Workspace

```bash
CONTAINER_NAME=$(echo "$CONTAINER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
CONTAINER_TAG="${CONTAINER_NAME}._.${USER_ID}"  # AIME naming convention!

if [ -z "$WORKSPACE_DIR" ]; then
  WORKSPACE_DIR="$HOME/workspace/$CONTAINER_NAME"
fi

mkdir -p "$WORKSPACE_DIR"
```

#### Step 3: Call MLC Wrapper

```bash
# Build arguments for mlc-create-wrapper
WRAPPER_ARGS=("$CONTAINER_NAME" "$FRAMEWORK")
WRAPPER_ARGS+=("-w=$WORKSPACE_DIR")

if [ "$CPU_ONLY" = true ]; then
  WRAPPER_ARGS+=("--cpu-only")
fi

# Call wrapper
bash "$MLC_WRAPPER" "${WRAPPER_ARGS[@]}"
```

### 3.2 `mlc-create-wrapper` - Full Analysis

**Location:** `/home/user/ds01-infra/scripts/docker/mlc-create-wrapper.sh` (426 lines)

**Purpose:** Wrap AIME's mlc-create to add resource limits

#### Current Approach (Has Limitations!)

```bash
#!/bin/bash
# mlc-create-wrapper.sh

ORIGINAL_MLC="/opt/aime-ml-containers/mlc-create"

# Get user's resource limits
RESOURCE_LIMITS=$(python3 get_resource_limits.py $CURRENT_USER --docker-args)
# Returns: "--cpus=16 --memory=32g --shm-size=16g --cgroup-parent=ds01-student.slice"

# Call original mlc-create
bash "$ORIGINAL_MLC" $CONTAINER_NAME $FRAMEWORK $VERSION -w=$WORKSPACE_DIR

# AFTER creation, apply resource limits
docker update --cpus=16 --memory=32g ... $CONTAINER_TAG
```

**The Problem:**

1. **Can't pass custom images** to AIME's `mlc-create`
   - AIME only accepts framework names from catalog
   - If you pass a custom image name, AIME says "framework not found"

2. **Some limits can't be updated** after creation
   - `--shm-size` MUST be set at creation time
   - `docker update` can't change it later

3. **GPU allocation is missing**
   - Current wrapper doesn't call `gpu_allocator.py`
   - Just passes `-g=all` to AIME

---

## 4. Resource Management System

### 4.1 `get_resource_limits.py`

**Purpose:** Parse `resource-limits.yaml` and return user-specific limits

```python
class ResourceLimitParser:
    def get_user_limits(self, username):
        # 1. Check user_overrides (priority 100)
        if username in user_overrides:
            return user_overrides[username]

        # 2. Check groups (student/researcher/admin)
        for group_name, group_config in groups.items():
            if username in group_config['members']:
                return merge(defaults, group_config)

        # 3. Fallback to default_group
        return merge(defaults, groups[default_group])

    def get_docker_args(self, username):
        limits = self.get_user_limits(username)
        return [
            f'--cpus={limits["max_cpus"]}',
            f'--memory={limits["memory"]}',
            f'--shm-size={limits["shm_size"]}',
            f'--pids-limit={limits["pids_limit"]}',
            f'--cgroup-parent=ds01-{group}.slice'
        ]
```

**Example Output:**
```bash
$ python3 get_resource_limits.py john --docker-args
--cpus=16 --memory=32g --memory-swap=32g --shm-size=16g --pids-limit=4096 --cgroup-parent=ds01-student.slice
```

### 4.2 `resource-limits.yaml`

**Structure:**
```yaml
defaults:
  max_mig_instances: 2
  max_cpus: 16
  memory: 32g
  shm_size: 16g
  max_containers_per_user: 3
  idle_timeout: 48h
  priority: 1

groups:
  student:
    members: []
    max_mig_instances: 2
    priority: 10

  researcher:
    members: []
    max_mig_instances: 8
    max_cpus: 32
    memory: 64g
    priority: 50

  admin:
    members: [datasciencelab]
    max_mig_instances: null  # unlimited
    priority: 90

user_overrides:
  # Temporary high-priority allocations
  # john_doe:
  #   max_mig_instances: 1
  #   priority: 100
```

### 4.3 `gpu_allocator.py`

**Purpose:** State-based GPU allocation with priority and MIG support

```python
class GPUAllocator:
    def __init__(self):
        self.state_file = "/var/lib/ds01/gpu-state.json"
        self.state = self.load_state()

    def allocate(self, username, container, max_gpus, priority):
        # 1. Check user's current GPU count vs limit
        user_gpus = self.get_user_allocations(username)
        if len(user_gpus) >= max_gpus:
            raise Exception(f"User already has {len(user_gpus)} GPUs")

        # 2. Check for active reservations (priority 100)
        reserved = self.check_reservations()

        # 3. Find best GPU using scoring
        available_gpus = self.get_available_gpus()
        scored_gpus = []
        for gpu in available_gpus:
            score = self.score_gpu(gpu, priority)
            scored_gpus.append((gpu, score))

        # Sort by score (lower = better)
        scored_gpus.sort(key=lambda x: x[1])
        best_gpu = scored_gpus[0][0]

        # 4. Record allocation
        self.state['allocations'][container] = {
            'user': username,
            'gpu': best_gpu,
            'priority': priority,
            'allocated_at': datetime.now()
        }
        self.save_state()

        return best_gpu  # e.g., "0" or "0:1" (MIG)

    def score_gpu(self, gpu_id, user_priority):
        # Lower score = better choice
        gpu_info = self.state['gpus'][gpu_id]

        # 1. Priority difference (want similar or higher priority neighbors)
        max_priority = max([a['priority'] for a in gpu_info['allocations']])
        priority_diff = abs(max_priority - user_priority)

        # 2. Container count (prefer less busy GPUs)
        container_count = len(gpu_info['allocations'])

        # 3. Memory usage (if tracked)
        memory_pct = gpu_info.get('memory_used_pct', 0)

        return (priority_diff * 100) + (container_count * 10) + memory_pct
```

**State File Example:**
```json
{
  "gpus": {
    "0": {
      "type": "A100",
      "mig_enabled": true,
      "mig_instances": ["0:0", "0:1", "0:2"],
      "allocations": [
        {"container": "proj1._.1001", "user": "john", "priority": 10, "mig": "0:0"},
        {"container": "proj2._.1002", "user": "jane", "priority": 50, "mig": "0:1"}
      ]
    }
  }
}
```

---

## 5. Current Label System

### 5.1 DS01 Labels (Should be Removed!)

```dockerfile
# In image-create Dockerfile generation
LABEL maintainer="$USERNAME"
LABEL maintainer.id="$USER_ID"
LABEL ds01.image="$image_name"
LABEL ds01.framework="$framework"
LABEL ds01.created="$(date -Iseconds)"
```

### 5.2 Container Labels (Inconsistent!)

Currently, containers don't get DS01 labels because `mlc-create-wrapper` calls AIME's `mlc-create`, which only adds `aime.mlc.*` labels.

**Issue:** DS01 scripts check for `maintainer=$USERNAME` label, but containers don't have it!

```bash
# In container-list
docker ps -a --filter "label=maintainer=$USERNAME"  # Won't find AIME containers!
```

---

## 6. Dockerfile Storage

**Recent Change (Nov 11, 2025):** Moved from `~/docker-images/` → `~/dockerfiles/`

**Two Storage Modes:**

1. **Centralized** (default)
   ```
   ~/dockerfiles/
   ├── my-cv-project-john.Dockerfile
   ├── nlp-exp-john.Dockerfile
   └── thesis-model-jane.Dockerfile
   ```

2. **Per-project** (with `--project-dockerfile` flag)
   ```
   ~/workspace/
   ├── my-cv-project/
   │   └── Dockerfile
   └── nlp-exp/
       └── Dockerfile
   ```

**Rationale:** Centralized = one Dockerfile can support multiple projects, Per-project = project-specific customization

---

## 7. Image Update Workflow

### 7.1 `image-update` - Analysis

**Location:** `/home/user/ds01-infra/scripts/user/image-update` (40636 bytes!)

**Purpose:** Update existing Dockerfile, rebuild image, optionally recreate container

**3-Phase Workflow:**

```bash
# Phase 1: Edit Dockerfile
echo "Phase 1/3: Edit Dockerfile"
echo "Location: $DOCKERFILE"
read -p "Edit now? [Y/n]: " EDIT_CONFIRM

if [[ "$EDIT_CONFIRM" =~ ^[Yy]$ ]]; then
  ${EDITOR:-vim} "$DOCKERFILE"
fi

# Phase 2: Rebuild Image
echo "Phase 2/3: Rebuild Image?"
read -p "Rebuild? [Y/n]: " REBUILD_CONFIRM

if [[ "$REBUILD_CONFIRM" =~ ^[Yy]$ ]]; then
  docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" .
fi

# Phase 3: Recreate Container
echo "Phase 3/3: Recreate Container?"
echo "This will stop and remove old container, then create new one."
read -p "Recreate? [Y/n]: " RECREATE_CONFIRM

if [[ "$RECREATE_CONFIRM" =~ ^[Yy]$ ]]; then
  docker stop "$CONTAINER_NAME._.${USER_ID}"
  docker rm "$CONTAINER_NAME._.${USER_ID}"
  container-create "$CONTAINER_NAME" "$IMAGE_NAME"
fi
```

**Smart Features:**

1. **Detects changes**
   ```bash
   # Compare Dockerfile timestamp vs image creation time
   if [ "$DOCKERFILE_MODIFIED" -gt "$IMAGE_CREATED" ]; then
     echo "⚠ Dockerfile newer than image - rebuild recommended"
   fi
   ```

2. **Empty pip install protection**
   ```bash
   # Remove empty RUN blocks to prevent build errors
   sed -i '/^RUN pip install --no-cache-dir \\$/,/^$/{ /^$/d; }' "$DOCKERFILE"
   ```

---

## 8. Issues with Current Implementation

### 8.1 Not Using AIME Base Images

**Current:**
```dockerfile
FROM pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime
```

**Should be:**
```dockerfile
FROM aimehub/pytorch-2.5.1-aime-cuda12.1.1
```

**Why?**
- AIME images are tested, optimized, and maintained
- Support 76 framework × version combinations
- Architecture-aware (CUDA_ADA for Ada GPUs)
- DS01 currently uses generic Docker Hub images

### 8.2 Can't Pass Custom Images to AIME

**Current flow:**
```
User: "Create container from my-custom-image"
   ↓
container-create: calls mlc-create-wrapper with "my-custom-image"
   ↓
mlc-create-wrapper: calls AIME mlc-create with "my-custom-image"
   ↓
AIME mlc-create: "Framework 'my-custom-image' not found!" → ERROR
```

**Root cause:** AIME's `find_image()` only searches `ml_images.repo`, doesn't accept arbitrary Docker images

### 8.3 Resource Limits Applied Too Late

**Current:**
```bash
# 1. Create container (no shm-size!)
bash "$ORIGINAL_MLC" $CONTAINER_NAME $FRAMEWORK $VERSION

# 2. Try to update limits
docker update --shm-size=16g $CONTAINER_TAG  # ERROR: Can't update shm-size!
```

**Problem:** Some limits MUST be set at creation, not after.

### 8.4 Inconsistent Label Usage

**Images have:** `ds01.*` labels
**Containers have:** `aime.mlc.*` labels
**Scripts check for:** Both, inconsistently

**Should standardize on:** `aime.mlc.*` labels for everything

### 8.5 GPU Allocation Not Integrated

`mlc-create-wrapper` doesn't call `gpu_allocator.py` - it's disconnected!

**Should:**
```bash
# Before calling mlc-create
GPU_ID=$(python3 gpu_allocator.py allocate $USER $CONTAINER_TAG ...)

# Pass to mlc-create
bash "$ORIGINAL_MLC" ... -g=$GPU_ID
```

---

## 9. What Works Well in DS01

### 9.1 ✅ 3-Tier Package System

Framework → Base → Use Case → Custom is **excellent UX**:
- Users understand the progression
- Covers 90% of use cases
- Easy to extend

**Keep this!**

### 9.2 ✅ Interactive Wizards

`image-create` and `container-create` have great interactive modes:
- Guided prompts
- Educational explanations (with `--guided` flag)
- Sensible defaults
- Clear progress indicators (Phase 1/3, 2/3, 3/3)

**Keep this!**

### 9.3 ✅ Resource Limits Architecture

- `resource-limits.yaml` is well-designed
- Priority system is robust
- Group hierarchy (defaults → groups → user_overrides) is flexible
- `get_resource_limits.py` is clean and testable

**Keep this!**

### 9.4 ✅ GPU Allocator Design

- State-based tracking
- MIG-aware
- Priority-based scoring
- Reservation support

**Keep this!**

### 9.5 ✅ Dockerfile Storage Strategy

Centralized `~/dockerfiles/` with per-project option is smart:
- Reduces duplication (one Dockerfile → many containers)
- Still allows project-specific customization
- Easy to version control

**Keep this!**

---

## 10. Summary: What Needs to Change

### Critical Changes

1. **✅ Start with AIME base images** instead of Docker Hub
   - `FROM aimehub/pytorch-2.5.1` not `FROM pytorch/pytorch:2.5.1`

2. **✅ Create mlc-create-patched** that accepts custom images
   - Check if custom image provided → use it
   - Else → use AIME catalog

3. **✅ Integrate GPU allocation** into container creation
   - Call `gpu_allocator.py` BEFORE creating container
   - Pass specific GPU ID to mlc-create-patched

4. **✅ Apply resource limits** at creation time
   - Pass all limits to mlc-create-patched
   - Don't rely on `docker update` afterward

5. **✅ Standardize on aime.mlc labels**
   - Remove `ds01.*` labels
   - Use `aime.mlc.*` everywhere for compatibility

### Keep Unchanged

1. ✅ **image-create workflow** (just change FROM line)
2. ✅ **3-tier package system** (framework → base → use case → custom)
3. ✅ **Interactive wizards** (excellent UX)
4. ✅ **Resource management** (YAML parser, GPU allocator)
5. ✅ **Tier 2/3/4 architecture** (modular commands → orchestrators → wizards)

---

## 11. Conclusion

DS01 has **excellent architecture** and **great UX**, but is currently **not using AIME framework**.

The integration is straightforward:

1. **Change image-create** to use AIME base images (1 line change!)
2. **Create mlc-create-patched** to accept custom images + apply DS01 limits
3. **Connect GPU allocator** to container creation workflow
4. **Standardize labels** on AIME namespace

This gives us **best of both worlds**:
- AIME's battle-tested framework catalog
- DS01's resource management and UX

**Next Step:** Create detailed integration strategy document.
