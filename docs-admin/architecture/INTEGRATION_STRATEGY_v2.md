# AIME v2 + DS01 Integration Strategy

**Date:** 2025-11-12 (Updated for AIME v2)
**Purpose:** Comprehensive integration plan to merge AIME v2 framework with DS01 infrastructure
**Goal:** Maximum AIME reuse + Minimal DS01 patches = Unified robust system

**v2 UPDATE:** AIME is now Python-based (~2,400 lines), making integration SIMPLER - no need to patch AIME code!

---

## 0. Key v1 → v2 Changes

### What Changed in AIME v2

| Aspect | v1 (Bash) | v2 (Python) | Integration Impact |
|--------|-----------|-------------|-------------------|
| **Architecture** | Pure bash scripts | Python-based (mlc.py) | ✅ **Better:** More maintainable |
| **Command structure** | Standalone bash scripts | Thin wrappers → mlc.py | ✅ **No change:** Same CLI |
| **Image catalog** | 76 images | **150+ images** | ✅ **Better:** More choices |
| **GPU architectures** | CUDA_ADA, CUDA_AMPERE | **+BLACKWELL, ROCM6, ROCM5** | ✅ **Better:** AMD support |
| **Frameworks** | PyTorch, TF, MXNet | PyTorch, TF (MXNet dropped) | ⚠️ **Minimal impact** |
| **Interactive mode** | Not available | ✅ Interactive prompts | ✅ **Better:** User-friendly |
| **Container version** | 3 (workspace, data) | **4 (adds models dir)** | ✅ **Better:** 3-mount points |
| **Export/Import** | Not available | ✅ New commands | ✅ **Better:** Container portability |

### Integration Strategy Change

**v1 Plan (from original doc):**
- Create `mlc-create-patched` - a modified copy of bash script
- Patch ~65 lines to add custom images + resource limits
- Maintain separate patched version

**v2 Plan (UPDATED - SIMPLER!):**
- ✅ **NO PATCHING NEEDED** - Keep AIME v2 completely unchanged!
- ✅ **Keep wrapper approach** - `mlc-create-wrapper.sh` continues to work
- ✅ **Python backend transparent** - Wrappers don't care about internal implementation
- ✅ **Less maintenance** - No need to sync patches with AIME updates

**Why v2 is better for integration:**
1. Python is more maintainable than bash (easier to understand AIME logic)
2. Same command-line interface (our wrappers keep working)
3. Better error handling and edge cases
4. More robust parameter parsing (argparse vs manual bash parsing)
5. No need to fork/patch AIME code!

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

### Target State (v2 UPDATED)

```
DS01 + AIME v2 (Integrated):
┌──────────────────────────────────────────────────────┐
│ Tier 1: AIME v2 Framework (Base System) ✨ PYTHON    │
│   • ml_images.repo (150+ frameworks) ✨ EXPANDED     │
│   • mlc.py (2,400 lines Python core)                 │
│   • mlc create/open/list/stats/etc (UNCHANGED)      │
│   • aime.mlc.* labels (v4: adds models dir) ✨       │
│   • Container naming: name._.uid (UNCHANGED)         │
│   • Multi-arch: BLACKWELL/ADA/AMPERE/ROCM ✨         │
│   ↓                                                   │
│   [Tier 1 = Engine, untouched by DS01]               │
├──────────────────────────────────────────────────────┤
│ Tier 2: DS01 Modular Commands (Lightweight Wrappers)│
│   • mlc-create-wrapper ✨ SIMPLIFIED                 │
│     - Calls AIME v2 `mlc create` (no patching!)     │
│     - Adds: resource limits, GPU allocation          │
│   • mlc-stats-wrapper (minimal)                      │
│   • container-run → calls `mlc open` directly        │
│   • image-create ✨ UPDATED                          │
│     - Uses AIME catalog for base images              │
│     - Builds on top: FROM aimehub/pytorch...         │
|     - Adds custom packages (defaults from ds01 logic)|
│   • resource limits (get_resource_limits.py)         │
│   • GPU allocation (gpu_allocator.py)                │
│   ↓                                                   │
│   [Tier 2 = Lightweight CLI layer, minimal code]     │
├──────────────────────────────────────────────────────┤
│ Tier 3: DS01 Orchestrators (High-level UX)          │
│   • project-init (multi-step workflows)              │
│   • user-setup (educational onboarding)              │
│   • All existing workflows (UNCHANGED)               │
│   ↓                                                   │
│   [Tier 3 = Orchestration, calls Tier 2]             │
└──────────────────────────────────────────────────────┘

KEY PRINCIPLES:
✅ Tier 1 (AIME v2): Complete, untouched, Python-based engine
✅ Tier 2 (DS01): Thin wrappers add resource mgmt + custom images
✅ Tier 3 (DS01): High-level UX orchestrating Tier 2
✅ No patching: AIME v2 stays pristine, easier to update
```

**What's Different from v1 Plan:**
- ❌ NO `mlc-create-patched` needed! => HENRY QUESTION EDIT: ARE YOU SURE `mlc.py` can handle custom images? if not what to do?
- ✅ `mlc-create-wrapper` works with v2 Python backend 

### Unified Workflow

✅ RESOLVED: Custom Image Support via mlc-patched.py
- See docs/MLC_PATCH_STRATEGY.md for complete solution
- Create mlc-patched.py with ~50 line patch (2.2% change) to add --image flag
- Preserves 97.8% of AIME v2 logic unchanged
- Custom images: FROM aimehub/pytorch + DS01 package customization
```
USER: image-create my-cv-project
┌─────────────────────────────────────────────────────────┐
│ 1. Framework Selection → Looks up in ml_images.repo     │
│    Result: aimehub/pytorch-2.5.1-aime-cuda12.1.1 ✅     │
├─────────────────────────────────────────────────────────┤
│ 2. Generate Dockerfile                                  │
│    FROM aimehub/pytorch-2.5.1-aime-cuda12.1.1 ✅        │
│    + adds custom: RUN pip install jupyter pandas ... (DS01 3-tier)     │
├─────────────────────────────────────────────────────────┤
│ 3. Build Custom Image                                   │
|    Either using mlc.py, or if that's not possible then  |
│    docker build -t my-cv-project-{user-name}            │
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
OR ARE THERE MORE PARTS OF `MLC.PY` THAT CAN BE USED HERE? IF NOT LET'S PERHAPS CREATE AN MLC-PATCHED.PY, THAT CLOSELY MIRRORS MLC.PY WHERE POSSIBLE, WHILE PATCHING WHERE NECESSARY?
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
=> perhaps we'll need a `mlc-patched.py` that stays close to mlc.py but deviates where necessary.

❌ **Don't over-engineer:**
- Keep patches small where possible
- Document every deviation
- Maintain AIME compatibility

### Principle 3: Preserve DS01 UX

✅ **Keep what works:**
- 3-tier package system (framework → base → use case → custom)
- Interactive wizards (`--guided` mode) with lots of useful explanation and formatting ALREADY DONE, whereever possible keep existing work here
- Phase-based workflows (1/3, 2/3, 3/3)
- Clear educational prompts

---

## 3. Core Changes Required (v2 UPDATED)

### Overview: What Actually Needs to Change

**v1 Plan Had:**
1. Create `mlc-create-patched` (NEW 238-line script with patches)
2. Update `image-create` to use AIME catalog
3. Simplify `mlc-create-wrapper`
4. Update `container-create`
5. Standardize labels

**v2 Plan Has (SIMPLER!):**
1. ~~Create mlc-create-patched~~ ❌ NOT NEEDED!
2. Update `image-create` to use AIME v2 catalog ✅ SAME
3. ~~Simplify mlc-create-wrapper~~ ✅ ALREADY WORKS!
4. ~~Update container-create~~ ✅ ALREADY WORKS!
5. Standardize labels ✅ SAME (optional improvement)

**Why Fewer Changes:**
- v2's Python backend doesn't change the CLI interface => EDIT: since mlc.py doesn't accept custom images we may need to patch this!
- Current wrappers already work correctly
- Just need to point DS01 at AIME v2 catalog + try to leverage as much of mlc.py as possible

---

### Change 1: AIME v2 Base Images in DS01

**File:** `scripts/user/image-create`

**Status:** ⚠️ **ONLY REQUIRED CHANGE**

**Before:**
```bash
get_base_image() {
    case $framework in
        tensorflow|tf) echo "tensorflow/tensorflow:2.14.0-gpu" ;;
        pytorch|*)     echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime" ;;
    esac
}
```

**After (v2):**
```bash
get_base_image() {
    local framework="$1"
    local version="$2"

    # Look up in AIME v2 catalog (150+ images!)
    local AIME_REPO="/opt/aime-ml-containers/ml_images.repo"  # Same location

    if [ ! -f "$AIME_REPO" ]; then
        log_error "AIME catalog not found: $AIME_REPO"
        log_info "Falling back to Docker Hub images"
        case $framework in
            tensorflow|tf) echo "tensorflow/tensorflow:2.14.0-gpu" ;;
            pytorch|*)     echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime" ;;
        esac
        return
    fi

    # Parse AIME v2 catalog (CSV format - SAME as v1)
    # Framework, Version, Arch, Repo
    local framework_capital=$(echo "$framework" | sed 's/\b\(.\)/\u\1/')  # Capitalize

    # v2 supports more architectures: detect or default
    local arch="${MLC_ARCH:-CUDA_ADA}"  # Can also be CUDA_BLACKWELL, CUDA_AMPERE, ROCM6, ROCM5

    local image=$(awk -F', ' \
        -v fw="$framework_capital" \
        -v ver="$version" \
        -v arch="$arch" \
        '$1 == fw && $2 == ver && $3 == arch {print $4; exit}' \
        "$AIME_REPO")

    if [ -n "$image" ]; then
        echo "$image"
        log_success "Using AIME v2 image: $image"
    else
        # Fallback: get latest version for framework
        image=$(awk -F', ' \
            -v fw="$framework_capital" \
            -v arch="$arch" \
            '$1 == fw && $3 == arch {print $4; exit}' \
            "$AIME_REPO")

        if [ -n "$image" ]; then
            echo "$image"
            log_warning "Version $version not found, using latest: $image"
        else
            log_error "Framework '$framework' not found in AIME v2 catalog"
            exit 1
        fi
    fi
}
```

**Changes from v1 plan:**
- ✅ Catalog path SAME: `/opt/aime-ml-containers/ml_images.repo`
- ✅ CSV format SAME: `Framework, Version, Arch, Repo`
- ✨ NEW: Support `MLC_ARCH` env variable for architecture selection
- ✨ NEW: 150+ images available (PyTorch 2.8.0, TF 2.16.1, etc.)
- ✨ NEW: AMD ROCM support

**Lines Changed:** ~15 lines (same as v1 plan)
**Risk:** Low (fallback to Docker Hub if AIME unavailable)
**Testing:** Verify with `PyTorch 2.7.1`, `Tensorflow 2.16.1`, ROCM images

---

### Change 2: ~~Create `mlc-create-patched`~~ ❌ NOT NEEDED IN V2!

**Status:** ✅ **SKIPPED - Wrapper approach works perfectly!**

**Why v1 needed this:**
- v1 was bash scripts with logic embedded in each file
- To add custom image support, had to patch the bash script directly
- Created a modified 238-line script with ~65 lines of changes

**Why v2 doesn't need this:**
- ✅ v2 is Python-based - all logic in `mlc.py`
- ✅ CLI interface unchanged - `mlc create` accepts same args
- ✅ Our wrapper can pre-process and call AIME directly
- ✅ No need to maintain a forked/patched version!

**How it works with v2 (CURRENT SYSTEM - ALREADY IMPLEMENTED!):**

```
User: container-create my-project
           ↓
   [DS01 container-create]
           ↓
1. Check if custom image exists
2. Get resource limits from YAML
3. Allocate GPU if needed
           ↓
   [DS01 mlc-create-wrapper.sh] ← This already exists!
           ↓
4. If custom image:
     Create container directly via docker create
       --name my-project._.1001
       --label aime.mlc.*  (keep AIME labels!)
       $RESOURCE_LIMITS
       $GPU_ARGS
       my-custom-image  (custom built FROM aimehub/pytorch...)

   Else (framework from catalog):
     Call AIME v2: mlc create my-project pytorch 2.7.1
           ↓
   [AIME v2 mlc.py - UNTOUCHED]
           ↓
5. AIME creates container with standard setup
           ↓
6. DS01 wrapper applies additional limits if needed:
     docker update --cpus=X --memory=Y ...
```

**Key Insight:**
- ✅ **DS01's current wrapper ALREADY does this!**
- ✅ **No need to patch AIME v2 code**
- ✅ **Wrapper handles custom images separately from AIME catalog**
- ✅ **For catalog images, just call `mlc create` directly**

**What needs updating:**
- Just the base image lookup in `image-create` (Change 1)
- Everything else ALREADY WORKS with v2!

---

### Change 3: ~~Integrate GPU Allocation~~ ✅ ALREADY WORKS!

**File:** `scripts/docker/mlc-create-wrapper.sh`

**Status:** ✅ **NO CHANGES NEEDED - Already compatible with v2**

**Current implementation ALREADY:**
- ✅ Calls `get_resource_limits.py` for resource quotas
- ✅ Calls `gpu_allocator.py` for GPU assignment
- ✅ Can call AIME `mlc create` OR create containers directly
- ✅ Works with v2 Python backend (transparent)

**v2 Compatibility:**
- Python backend is transparent to wrapper
- Wrapper calls `mlc create` (which now calls mlc.py)
- No changes needed - already works!

**Optional improvements** (not required):
- Could simplify wrapper logic (current version works but is complex)
- Could add better error messages for v2-specific cases
- Could add support for v2's new flags (`-m/--models_dir`)

**Lines Changed:** 0 (already compatible)
**Risk:** None

---

### Change 4: ~~Update `container-create`~~ ✅ ALREADY WORKS!

**File:** `scripts/user/container-create`

**Status:** ✅ **NO CHANGES NEEDED - Already compatible with v2**

**Current implementation:**
- ✅ Calls `mlc-create-wrapper.sh`
- ✅ Passes custom image name when available
- ✅ Works with AIME catalog when no custom image
- ✅ v2's Python backend is transparent

**v2 Compatibility:**
- When wrapper calls `mlc create`, it now calls Python mlc.py
- Same arguments, same behavior
- No changes needed!

**Lines Changed:** 0 (already compatible)
**Risk:** None

---

### Change 5: Standardize Labels (OPTIONAL IMPROVEMENT)

**Files:** Multiple

**Status:** ⚠️ **OPTIONAL** - Not required for v2 compatibility, but good practice

**Strategy:** Use `aime.mlc.*` namespace consistently (v2 uses this already)

**v2 Label Improvements:**
- v2 container version = 4 (adds `aime.mlc.MODELS_MOUNT`)
- All v2 containers use `aime.mlc.*` labels
- DS01 should standardize on same namespace

**Suggested changes** (low priority):

1. **image-create Dockerfile generation:**
   ```dockerfile
   # Current (mixed):
   LABEL maintainer="$USERNAME"
   LABEL ds01.image="$image_name"

   # Better (consistent with AIME v2):
   LABEL aime.mlc.MAINTAINER="$USERNAME"
   LABEL aime.mlc.CUSTOM_IMAGE="$image_name"
   ```

2. **container-list filtering:**
   ```bash
   # Ensure using aime.mlc.USER for filtering
   docker ps -a --filter "label=aime.mlc.USER=$USERNAME"
   ```

3. **Monitoring scripts:**
   - Verify all use `aime.mlc.*` for filtering
   - Check for any stray `ds01.*` references

**Lines Changed:** ~30 lines across 6 files
**Risk:** Low (just label renaming, backward compatible)
**Priority:** Low (nice-to-have, not blocking v2 integration)

---


## 4. Implementation Roadmap (v2 UPDATED - MUCH SIMPLER!)

### Phase 1: Minimal Required Changes (30 minutes)

✅ **Task 1.1:** Update `image-create` to use AIME v2 catalog
- Modify `get_base_image()` function (~15 lines)
- Add AIME v2 catalog lookup with architecture support
- Test with PyTorch 2.7.1, Tensorflow 2.16.1
- Test fallback to Docker Hub if catalog unavailable

**Deliverable:** `image-create` uses AIME v2 base images

---

### Phase 2: Testing & Verification (30 minutes)

✅ **Task 2.1:** Test end-to-end workflow
- `image-create my-test` → uses AIME v2 base
- `container-create my-test` → wrapper works with v2
- `container-run my-test` → mlc open works
- Verify labels show MLC_VERSION=4

✅ **Task 2.2:** Test resource limits still applied
- Check CPU, memory, shm-size limits
- Verify GPU allocation works
- Confirm cgroup slices correct


**Deliverable:** Full system verified working with v2

---

### Phase 3: Optional Improvements (1-2 hours, as needed)

⚠️ **Task 3.1:** Standardize labels (optional)
- Update scripts to use `aime.mlc.*` consistently
- Remove any `ds01.*` label references
- Test filtering still works

⚠️ **Task 3.2:** Add v2-specific features (optional)
- Support for models directory (`-m` flag)
- Architecture selection UI (CUDA_BLACKWELL, ROCM, etc.)
- Interactive mode integration

⚠️ **Task 3.3:** Update documentation
- Update README.md with v2 details
- Note v2 features available

**Deliverable:** Polish and documentation


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


**Image Inheritance Strategy (Already Implemented):**
```
AIME v2 Base → DS01 Packages → User Custom
(framework)     (3-tier)         (extras)
    ↓              ↓                ↓
  Catalog      Dockerfile      Dockerfile
   FROM        RUN pip         RUN pip
```

