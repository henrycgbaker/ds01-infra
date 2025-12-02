# AIME + DS01 Integration Strategy

**Date:** 2025-11-11
**Purpose:** Comprehensive integration plan to merge AIME framework with DS01 infrastructure
**Goal:** Maximum AIME reuse + Minimal DS01 patches = Unified robust system

---

## 1. Executive Summary

### Current State

```
DS01 (Current):
┌─────────────────────────────────────┐
│ image-create                         │
│   ↓                                  │
│ FROM pytorch/pytorch:2.5.1  ❌       │ Not using AIME!
│   ↓                                  │
│ Build custom Dockerfile              │
│   ↓                                  │
│ mlc-create-wrapper                   │
│   ↓                                  │
│ AIME mlc-create (fails on custom!) ❌ │
└─────────────────────────────────────┘
```

### Target State

```
DS01 (Integrated):
┌──────────────────────────────────────────┐
│ Tier 1: AIME Framework (Base System)     │
│   • ml_images.repo (76 frameworks)       │
│   • mlc-create-patched ✨ NEW            │
│   • mlc-open (unchanged)                 │
|   * the rest of mlc-* commands           |
│   • aime.mlc.* labels                    │
├──────────────────────────────────────────┤
│ Tier 2: DS01 Modular Commands            │
│   • image-create (uses AIME base) ✨      │
│   • container-create (calls patched) ✨   │
│   • resource limits (get_resource_*.py)  │
│   • GPU allocation (gpu_allocator.py)    │
|   * all Tier 2 call on Tier 1 mlc-* commands
├──────────────────────────────────────────┤
│ Tier 3: DS01 Orchestrators               │
│   • project-init                         │
│   • user-setup                           │
│   • All existing workflows               │
└──────────────────────────────────────────┘
= Tier 1 is the engine: AIME `mlc-*` commands
= Tier 2 is light CLI layer over them
= Tier 3 is orchestration layer
```
TO CHANGE: make sure all Tier 1 AIME functionality is leveraged by ds01! Currently the AIME audit suggests it is not all being used at present.

### Unified Workflow

```
USER: image-create my-cv-project
┌─────────────────────────────────────────────────────────┐
│ 1. Framework Selection → Looks up in ml_images.repo     │
│    Result: aimehub/pytorch-2.5.1-aime-cuda12.1.1 ✅     │
├─────────────────────────────────────────────────────────┤
│ 2. Generate Dockerfile                                  │
│    FROM aimehub/pytorch-2.5.1-aime-cuda12.1.1 ✅        │
│    RUN pip install jupyter pandas ... (DS01 3-tier)     │
├─────────────────────────────────────────────────────────┤
│ 3. Build Custom Image                                   │
│    docker build -t my-cv-project-john-image             │
│    Result: AIME base + DS01 customization ✅            │
└─────────────────────────────────────────────────────────┘

USER: container-create my-cv-project
┌─────────────────────────────────────────────────────────┐
│ 1. Detect Custom Image Exists                           │
│    docker images | grep my-cv-project-john-image ✅     │
├─────────────────────────────────────────────────────────┤
│ 2. Get Resource Limits                                  │
│    get_resource_limits.py john --docker-args            │
│    → --cpus=16 --memory=32g --shm-size=16g ...          │
├─────────────────────────────────────────────────────────┤
│ 3. Allocate GPU                                         │
│    gpu_allocator.py allocate john my-cv-project 1 10    │
│    → GPU 0:1 (MIG instance) ✅                          │
├─────────────────────────────────────────────────────────┤
│ 4. Create Container (mlc-create-patched)                │
│    mlc-create-patched my-cv-project pytorch \           │
│      --image=my-cv-project-john-image \                 │
│      --cpus=16 --memory=32g --shm-size=16g \            │
│      --gpu=0:1 --cgroup-parent=ds01-student.slice ✅    │
├─────────────────────────────────────────────────────────┤
│ Container Created! ✅                                    │
│   • Based on AIME framework                             │
│   • Customized with DS01 packages                       │
│   • Resource limits enforced                            │
│   • GPU allocated fairly                                │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Integration Principles

### Principle 1: Maximum AIME Reuse

✅ **Use AIME for:**
- Framework catalog (`ml_images.repo`)
- Base image selection
- Container naming convention (`name._.uid`)
- Label system (`aime.mlc.*`)
- User environment setup (UID/GID matching)
- Lifecycle management (`mlc-open` unchanged)

❌ **Don't reinvent AIME:**
- No custom framework catalog
- No custom naming scheme
- No custom label namespace

### Principle 2: Minimal DS01 Patches

✅ **Add to AIME only what's essential:**
- Custom image support (bypass catalog)
- Resource limit application (at creation)
- GPU allocation integration

❌ **Don't over-engineer:**
- Keep patches small (<100 lines)
- Document every deviation
- Maintain AIME compatibility

### Principle 3: Preserve DS01 UX

✅ **Keep what works:**
- 3-tier package system (framework → base → use case → custom)
- Interactive wizards (`--guided` mode)
- Phase-based workflows (1/3, 2/3, 3/3)
- Clear educational prompts

❌ **Don't break existing:**
- All current DS01 commands work unchanged
- No breaking changes to user workflows
- Backward compatible (can recreate old containers)

---

## 3. Core Changes Required

### Change 1: AIME Base Images in DS01

**File:** `scripts/user/image-create`

**Before:**
```bash
get_base_image() {
    case $framework in
        tensorflow|tf) echo "tensorflow/tensorflow:2.14.0-gpu" ;;
        pytorch|*)     echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime" ;;
    esac
}
```

**After:**
```bash
get_base_image() {
    local framework="$1"
    local version="$2"

    # Look up in AIME catalog
    local AIME_REPO="/opt/aime-ml-containers/ml_images.repo"

    if [ ! -f "$AIME_REPO" ]; then
        log_error "AIME catalog not found: $AIME_REPO"
        log_info "Falling back to Docker Hub images"
        case $framework in
            tensorflow|tf) echo "tensorflow/tensorflow:2.14.0-gpu" ;;
            pytorch|*)     echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime" ;;
        esac
        return
    fi

    # Parse AIME catalog (CSV format)
    # Framework, Version, Arch, Repo
    local framework_capital=$(echo "$framework" | sed 's/\b\(.\)/\u\1/')  # Capitalize
    local arch="CUDA_ADA"  # For Ada Lovelace GPUs (RTX 40xx, A100, etc.)

    local image=$(awk -F', ' \
        -v fw="$framework_capital" \
        -v ver="$version" \
        -v arch="$arch" \
        '$1 == fw && $2 == ver && $3 == arch {print $4; exit}' \
        "$AIME_REPO")

    if [ -n "$image" ]; then
        echo "$image"
        log_success "Using AIME image: $image"
    else
        # Fallback: get latest version for framework
        image=$(awk -F', ' \
            -v fw="$framework_capital" \
            -v arch="$arch" \
            '$1 == fw && $3 == arch {print $4; exit}' \
            "$AIME_REPO")

        if [ -n "$image" ]; then
            echo "$image"
            log_warning "Version $version not found, using: $image"
        else
            log_error "Framework '$framework' not found in AIME catalog"
            exit 1
        fi
    fi
}
```

**Lines Changed:** ~15 lines
**Risk:** Low (fallback to Docker Hub if AIME unavailable)

---

### Change 2: Create `mlc-create-patched`

**File:** `scripts/docker/mlc-create-patched` (NEW)

**Strategy:** Copy `aime-ml-containers/mlc-create` → `scripts/docker/mlc-create-patched` and make minimal edits

#### Patch Section 1: Add Custom Image Support

**Lines 44-46 (add new flags):**
```bash
CONTAINER_NAME=${ARGS[0]}
FRAMEWORK_NAME=${ARGS[1]}
FRAMEWORK_VERSION=${ARGS[2]}
CUSTOM_IMAGE=""          # NEW: Support --image flag
DS01_RESOURCE_LIMITS=""  # NEW: Support --cpus, --memory, etc.
```

**Lines 20-42 (add argument parsing):**
```bash
for i in "$@"
do
case $i in
    # ... existing AIME flags ...

    --image=*)                           # NEW
    CUSTOM_IMAGE="${i#*=}"
    ;;
    --cpus=*|--memory=*|--shm-size=*|--pids-limit=*|--cgroup-parent=*)  # NEW
    DS01_RESOURCE_LIMITS="$DS01_RESOURCE_LIMITS $i"
    ;;
esac
done
```

**Lines 176-188 (modify image resolution):**
```bash
# NEW: Check if custom image provided
if [ -n "$CUSTOM_IMAGE" ]; then
    log_info "[DS01] Using custom image: $CUSTOM_IMAGE"

    # Validate image exists
    if ! docker image inspect "$CUSTOM_IMAGE" &>/dev/null; then
        echo -e "\nError: Custom image not found: $CUSTOM_IMAGE"
        echo -e "Build it first with: image-create"
        exit -3
    fi

    IMAGE="$CUSTOM_IMAGE"
else
    # ORIGINAL AIME LOGIC: Look up in ml_images.repo
    IMAGE=$(find_image $FRAMEWORK_NAME $FRAMEWORK_VERSION)

    if [[ $IMAGE == "" ]]; then
        # ... existing error handling ...
    fi
fi
```

#### Patch Section 2: Apply DS01 Resource Limits

**Lines 230-235 (modify docker create):**
```bash
# Parse DS01 resource limits
RESOURCE_ARGS=""
if [ -n "$DS01_RESOURCE_LIMITS" ]; then
    RESOURCE_ARGS="$DS01_RESOURCE_LIMITS"
    log_info "[DS01] Applying resource limits: $RESOURCE_ARGS"
fi

# ORIGINAL AIME docker create + DS01 additions
OUT=$(docker create -it \
    $VOLUMES \
    -w $WORKSPACE \
    --name=$CONTAINER_TAG \

    # AIME labels (keep all)
    --label=$CONTAINER_LABEL=$USER \
    --label=$CONTAINER_LABEL.NAME=$CONTAINER_NAME \
    --label=$CONTAINER_LABEL.USER=$USER \
    --label=$CONTAINER_LABEL.VERSION=$MLC_VERSION \
    --label=$CONTAINER_LABEL.WORK_MOUNT=$WORKSPACE_MOUNT \
    --label=$CONTAINER_LABEL.DATA_MOUNT=$DATA_MOUNT \
    --label=$CONTAINER_LABEL.FRAMEWORK=$FRAMEWORK_NAME-$FRAMEWORK_VERSION \
    --label=$CONTAINER_LABEL.GPUS=$GPUS \

    # DS01 labels (add these)
    --label=$CONTAINER_LABEL.DS01_MANAGED=true \          # NEW
    --label=$CONTAINER_LABEL.CUSTOM_IMAGE=$CUSTOM_IMAGE \ # NEW (if used)

    # User & security (AIME)
    --user $USER_ID:$GROUP_ID \
    --tty --privileged --interactive \
    --group-add video \
    --group-add sudo \

    # GPU & devices (AIME)
    --gpus=$GPUS \
    --device /dev/video0 \
    --device /dev/snd \

    # Networking & IPC (AIME)
    --network=host \
    --ipc=host \
    -v /tmp/.X11-unix:/tmp/.X11-unix \

    # Resource limits (AIME defaults)
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \

    # DS01 resource limits (NEW - applied at creation!)
    $RESOURCE_ARGS \

    # Image & command
    $IMAGE:$CONTAINER_TAG \
    bash -c "echo \"export PS1='[$CONTAINER_NAME] \\\`whoami\\\`@\\\`hostname\\\`:\\\${PWD#*}$ '\" >> ~/.bashrc; bash")
```

#### Documentation Header

**Lines 1-30:**
```bash
#!/bin/bash
#
# mlc-create-patched - DS01-enhanced AIME container creation
#
# BASED ON: aime-ml-containers/mlc-create v3
# MODIFIED BY: DS01 Infrastructure
# DATE: 2025-11-11
#
# ==================== DS01 MODIFICATIONS ====================
#
# This script is a MINIMALLY MODIFIED version of AIME's mlc-create.
# Original AIME code is preserved wherever possible.
#
# DS01 ADDITIONS:
#   1. Custom image support (--image flag)
#      - Allows using user-built Docker images
#      - Falls back to AIME catalog if not specified
#
#   2. Resource limits (--cpus, --memory, --shm-size, etc.)
#      - Applied at container creation (not post-update)
#      - Integrated with resource-limits.yaml
#
#   3. GPU allocation integration
#      - Receives specific GPU ID from gpu_allocator.py
#      - Supports MIG instances (e.g., --gpus=device=0:1)
#
# COMPATIBILITY:
#   - 100% backward compatible with original mlc-create
#   - All AIME commands (mlc-open, etc.) work unchanged
#   - Uses same naming convention (name._.uid)
#   - Uses same label system (aime.mlc.*)
#
# DEVIATIONS FROM AIME:
#   Lines 108-128: Custom image support added
#   Lines 176-195: Image resolution modified
#   Lines 230-250: Resource limits added to docker create
#
# TOTAL CHANGES: ~65 lines added/modified out of 238
#
# UPSTREAM: To contribute back to AIME, these changes could be
#           upstreamed as optional flags (--image, --cpus, etc.)
#
# ===========================================================

# Original AIME copyright notice
# AIME MLC - Machine Learning Container Management
# Copyright (c) AIME GmbH and affiliates
# MIT LICENSE
```

**Total Patch Size:**
- Header documentation: ~30 lines
- Custom image support: ~25 lines
- Resource limits: ~10 lines
- **Total: ~65 lines** added to 238-line script = **27% addition**

---

### Change 3: Integrate GPU Allocation

**File:** `scripts/docker/mlc-create-wrapper.sh` → **REPLACE with simpler version**

**Current:** 426 lines (too complex!)

**New:** ~150 lines (streamlined)

**Responsibilities:**
1. Parse user input
2. Get resource limits (via `get_resource_limits.py`)
3. Allocate GPU (via `gpu_allocator.py`)
4. Call `mlc-create-patched` with all arguments
5. Handle errors gracefully

**New Workflow:**
```bash
#!/bin/bash
# mlc-create-wrapper.sh - Simplified DS01 wrapper for mlc-create-patched

# 1. Get resource limits
LIMITS=$(python3 get_resource_limits.py $USER --docker-args)
# → --cpus=16 --memory=32g --shm-size=16g --cgroup-parent=ds01-student.slice

# 2. Allocate GPU (if needed)
if [ "$CPU_ONLY" != true ]; then
    GPU_ID=$(python3 gpu_allocator.py allocate $USER $CONTAINER_TAG 1 $PRIORITY)
    GPU_ARG="--gpus=device=$GPU_ID"
else
    GPU_ARG=""
fi

# 3. Call mlc-create-patched with everything
if [ -n "$CUSTOM_IMAGE" ]; then
    # Using custom image
    bash mlc-create-patched $CONTAINER_NAME pytorch \
        --image=$CUSTOM_IMAGE \
        $LIMITS \
        $GPU_ARG \
        -w=$WORKSPACE_DIR
else
    # Using AIME catalog
    bash mlc-create-patched $CONTAINER_NAME $FRAMEWORK $VERSION \
        $LIMITS \
        $GPU_ARG \
        -w=$WORKSPACE_DIR
fi

# 4. Done! (no post-processing needed)
```

**Lines Changed:** Entire file rewritten (simpler!)
**Risk:** Medium (but old wrapper didn't work for custom images anyway)

---

### Change 4: Update `container-create`

**File:** `scripts/user/container-create`

**Minimal changes needed:**

**Line 29 (update MLC wrapper path):**
```bash
MLC_WRAPPER="$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh"
MLC_PATCHED="$INFRA_ROOT/scripts/docker/mlc-create-patched"  # NEW: Can call directly
```

**Lines 651-665 (update wrapper call):**
```bash
# Determine if using custom image or framework
if [ -n "$IMAGE_NAME" ]; then
    # Custom image exists - pass it to wrapper
    WRAPPER_ARGS+=("--image=$IMAGE_NAME")
fi

# Call wrapper (wrapper will call mlc-create-patched)
if bash "$MLC_WRAPPER" "${WRAPPER_ARGS[@]}"; then
    # Success!
else
    # Error handling
fi
```

**Lines Changed:** ~10 lines
**Risk:** Low (just passing image name)

---

### Change 5: Standardize Labels

**Files:** Multiple

**Strategy:** Remove all `ds01.*` labels, use `aime.mlc.*` only

**Changes:**

1. **image-create Dockerfile generation** (lines 443-448):
   ```dockerfile
   # BEFORE:
   LABEL maintainer="$USERNAME"
   LABEL maintainer.id="$USER_ID"
   LABEL ds01.image="$image_name"

   # AFTER:
   LABEL aime.mlc.MAINTAINER="$USERNAME"
   LABEL aime.mlc.MAINTAINER_ID="$USER_ID"
   LABEL aime.mlc.CUSTOM_IMAGE="$image_name"
   ```

2. **container-list** (line 109):
   ```bash
   # BEFORE:
   docker ps -a --filter "label=maintainer=$USERNAME"

   # AFTER:
   docker ps -a --filter "label=aime.mlc.USER=$USERNAME"
   ```

3. **All monitoring scripts:**
   Replace `ds01.*` label checks with `aime.mlc.*`

**Lines Changed:** ~30 lines across 6 files
**Risk:** Low (just label renaming)

---

## 4. Implementation Roadmap

### Phase 1: Foundation (1-2 hours)

✅ **Task 1.1:** Create `mlc-create-patched`
- Copy `aime-ml-containers/mlc-create` to `scripts/docker/mlc-create-patched`
- Add header documentation
- Test: `bash mlc-create-patched test pytorch 2.5.1` (should work like original)

✅ **Task 1.2:** Add custom image support to `mlc-create-patched`
- Add `--image` flag parsing
- Modify image resolution logic
- Test: `bash mlc-create-patched test pytorch --image=pytorch/pytorch:2.5.1`

✅ **Task 1.3:** Add resource limits to `mlc-create-patched`
- Add `--cpus`, `--memory`, etc. flag parsing
- Pass to `docker create`
- Test: `bash mlc-create-patched test pytorch --cpus=8 --memory=16g`

**Deliverable:** Working `mlc-create-patched` that accepts custom images + resource limits

---

### Phase 2: Integration (2-3 hours)

✅ **Task 2.1:** Update `image-create` to use AIME catalog
- Modify `get_base_image()` function
- Add AIME catalog lookup
- Test: `image-create test-img` (should use AIME base)

✅ **Task 2.2:** Simplify `mlc-create-wrapper`
- Rewrite to call `mlc-create-patched` directly
- Integrate GPU allocator
- Test: `bash mlc-create-wrapper test-container pytorch`

✅ **Task 2.3:** Update `container-create`
- Pass custom image to wrapper
- Test full workflow: `container-create test`

**Deliverable:** End-to-end workflow works (image-create → container-create)

---

### Phase 3: Polish (1-2 hours)

✅ **Task 3.1:** Standardize labels
- Update all scripts to use `aime.mlc.*`
- Remove `ds01.*` labels
- Test: `docker inspect` shows correct labels

✅ **Task 3.2:** Update documentation
- README.md
- Command help text

✅ **Task 3.3:** Test matrix
- [ ] AIME catalog workflow (pytorch, tensorflow)
- [ ] Custom image workflow
- [ ] Resource limits applied
- [ ] GPU allocation works
- [ ] All DS01 commands work

**Deliverable:** Production-ready integrated system

---

### Phase 4: Validation (1 hour)

✅ **Task 4.1:** User acceptance testing
- Run through `user-setup` wizard
- Create project with custom image
- Verify resource limits
- Check GPU allocation

✅ **Task 4.2:** Backward compatibility
- Test that old containers still work
- Verify `mlc-open` works on old + new containers
- Check monitoring scripts work

**Deliverable:** Validated, production-ready system

---

## 5. Testing Matrix

### Test Case 1: AIME Framework (Catalog Only)

```bash
# Should work like original AIME
mlc-create-patched pytorch-test Pytorch 2.5.1

# Verify:
docker inspect pytorch-test._.$(id -u) | grep -i "aime.mlc"
docker inspect pytorch-test._.$(id -u) | grep -i "aimehub/pytorch"
```

**Expected:** Container created from AIME base image

---

### Test Case 2: Custom Image (DS01 Workflow)

```bash
# Create custom image
image-create my-cv-project -f pytorch -t cv

# Verify base image
docker history my-cv-project-john-image | grep aimehub

# Create container from custom image
container-create my-cv-project

# Verify:
docker inspect my-cv-project._.$(id -u) | grep "aime.mlc.CUSTOM_IMAGE"
```

**Expected:** Container created from custom image, still uses AIME labels

---

### Test Case 3: Resource Limits

```bash
# Create container
container-create test-limits

# Verify:
docker inspect test-limits._.$(id -u) --format '{{.HostConfig.NanoCpus}}'
# Should show: 16000000000 (16 CPUs)

docker inspect test-limits._.$(id -u) --format '{{.HostConfig.Memory}}'
# Should show: 34359738368 (32 GB)

docker inspect test-limits._.$(id -u) --format '{{.HostConfig.ShmSize}}'
# Should show: 17179869184 (16 GB) - set at creation!

docker inspect test-limits._.$(id -u) --format '{{.HostConfig.CgroupParent}}'
# Should show: ds01-student.slice
```

**Expected:** All limits applied correctly at creation time

---

### Test Case 4: GPU Allocation

```bash
# Create container
container-create gpu-test

# Check allocation state
python3 scripts/docker/gpu_allocator.py status
# Should show: gpu-test._.1001 → GPU 0:1

# Verify in container
docker exec gpu-test._.$(id -u) nvidia-smi
# Should show only allocated GPU

# Release
docker stop gpu-test._.$(id -u)
python3 scripts/docker/gpu_allocator.py release gpu-test._.$(id -u)
```

**Expected:** GPU allocated, tracked, and released properly

---

### Test Case 5: mlc-open (Compatibility)

```bash
# Create via new system
container-create compat-test

# Open via AIME command (unchanged)
mlc-open compat-test

# Verify:
# - Container starts
# - Shell opens
# - User is correct UID/GID
# - Workspace mounted
```

**Expected:** AIME's `mlc-open` works with DS01-created containers

---

### Test Case 6: Full Workflow (End-to-End)

```bash
# User onboarding workflow
user-setup

# Follow prompts:
# - Create project: my-thesis
# - Framework: PyTorch
# - Use case: Computer Vision
# - Additional: wandb

# Verify:
# 1. Image created from AIME base
docker images | grep my-thesis-john-image

# 2. Container created with limits
docker inspect my-thesis._.$(id -u)

# 3. GPU allocated
python3 scripts/docker/gpu_allocator.py user-status john

# 4. Can enter container
container-run my-thesis

# 5. Packages installed
pip list | grep -E "torch|timm|wandb"
```

**Expected:** Entire workflow works seamlessly

---

## 6. Risk Assessment

### High Risk (must test thoroughly)

1. **mlc-create-patched stability**
   - Risk: Breaks existing AIME workflows
   - Mitigation: Keep original logic intact, add only optional features
   - Test: Both AIME catalog and custom image paths

2. **Resource limits at creation**
   - Risk: `shm-size` not applied correctly
   - Mitigation: Pass ALL limits to docker create, not docker update
   - Test: Verify shm-size in containers

3. **GPU allocator integration**
   - Risk: GPU not allocated or tracked
   - Mitigation: Extensive logging, state file validation
   - Test: Full allocation/release cycle

### Medium Risk

4. **Label migration**
   - Risk: Scripts break when looking for old labels
   - Mitigation: Comprehensive grep for all label references
   - Test: All container-list, container-stats, etc.

5. **Image catalog lookup**
   - Risk: Framework name mismatch (pytorch vs Pytorch)
   - Mitigation: Case-insensitive lookup, clear error messages
   - Test: Various framework name formats

### Low Risk

6. **Documentation updates**
   - Risk: Docs out of sync
   - Mitigation: Update docs incrementally with code changes

7. **Backward compatibility**
   - Risk: Old containers don't work
   - Mitigation: AIME labels preserved, same naming
   - Test: Create old-style container, verify mlc-open works

---

## 7. Rollback Plan

If integration fails:

1. **Restore scripts**
   ```bash
   git checkout main -- scripts/docker/mlc-create-wrapper.sh
   git checkout main -- scripts/user/image-create
   git checkout main -- scripts/user/container-create
   ```

2. **Remove mlc-create-patched**
   ```bash
   rm scripts/docker/mlc-create-patched
   ```

3. **Restore symlinks**
   ```bash
   # If any symlinks were changed
   sudo rm /usr/local/bin/mlc-create
   sudo ln -s /opt/aime-ml-containers/mlc-create /usr/local/bin/
   ```

4. **Existing containers continue to work**
   - They use docker directly, not dependent on scripts

---


## 9. Success Criteria

✅ **Integration successful if:**

1. **AIME base images used**
   - All new containers use `aimehub/*` images
   - 76 framework versions available

2. **Custom images work**
   - Users can build on AIME base
   - Dockerfile workflow preserved

3. **Resource limits enforced**
   - All limits from YAML applied
   - shm-size set at creation (not after)

4. **GPU allocation integrated**
   - `gpu_allocator.py` called before container creation
   - State tracking works

5. **Backward compatible**
   - `mlc-open` works on all containers
   - Old and new containers coexist

6. **Labels standardized**
   - All use `aime.mlc.*` namespace
   - No `ds01.*` labels remain

7. **Documentation updated**
   - README reflects new workflow

8. **All tests pass**
   - Test matrix completed
   - User acceptance successful

---

# QUESTIONS FROM HENRY
- does mlc-create-patched pass to mlc.py?
- how does the custom image vs AIME images workflow differ
- can i use image inheritance to make it cleaner? so the parent AIME images are handled according to AIME workflow, then ds01 takes over and inherits the image to add custom packages, resource allocation? or is that already happening?
    - Build image chains: AIME -> ds01


---
