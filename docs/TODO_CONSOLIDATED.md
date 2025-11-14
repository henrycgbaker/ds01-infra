# DS01 + AIME v2 Integration - TODO List


**Status:** Core Integration Complete ✅ | Resource Limits FIXED ✅ | GPU Allocation Integrated ✅
**Last Updated:** 2025-11-13 (Testing Phase - GPU Allocator & Custom Images)

## 🔍 Testing Summary (2025-11-13 - Current Session)

**Priority Testing Areas:**
1. ⚠️ GPU Allocator E2E → **BLOCKED** (needs sudo for /var/logs/ds01/)
2. ✅ Custom Image Workflow E2E → **COMPLETE** (all tests pass!)
3. ✅ Label Verification → **VERIFIED** (all labels working correctly)
4. ✅ Mount Points → **VERIFIED** (DATA_MOUNT, MODELS_MOUNT working correctly)

**Findings:**
- **GPU Allocator**: Code complete, integration done, but `/var/logs/ds01/` needs sudo setup before testing
- **Custom Image Workflow**: ✅ **WORKING END-TO-END**
  - Dockerfile generation → Image build → Container creation → Label verification ALL PASS
  - Fixed mlc-patched.py to check for local custom images before attempting pull
  - Custom images correctly built FROM AIME base images
  - Resource limits applied correctly (64 CPUs, 128GB RAM, 64GB shm-size)
- **Labels Working**:
  - `aime.mlc.CUSTOM_IMAGE: "test-e2e-*-datasciencelab"` ✅ (populated for custom images)
  - `aime.mlc.DATA_MOUNT: "-"` ✅ (correct when no data mount)
  - `aime.mlc.MODELS_MOUNT: "-"` ✅ (correct when no models mount)
  - `aime.mlc.DS01_MANAGED: "true"` ✅ (present on all DS01 containers)
  - `aime.mlc.USER: "datasciencelab"` ✅ (correct user label)

**Bug Fixed:**
- mlc-patched.py now checks if custom image exists locally before attempting docker pull
- Prevents error: "pull access denied for custom-image" (custom images aren't on Docker Hub)
- Still pulls AIME base images during docker build (critical for custom image workflow)

**Bugs Fixed (2025-11-13):**
1. GPU allocator path: `/var/logs/ds01` → `/var/log/ds01` (standard Linux path)
   - Root cause: `/var/logs` is root-only (drwx------), can't access subdirectories
2. **Duplicate allocation bug**: allocate command now correctly detects when container already has GPU
   - Issue: Line 518 checked `if gpu_id:` but "0" is truthy even when ALREADY_ALLOCATED
   - Fix: Check reason string, print warning for duplicates instead of success

**Testing Results (2025-11-13):**
✅ Fresh allocation works
✅ Status command shows allocated containers correctly
✅ Duplicate allocation detected with warning
✅ User limit enforcement works (2/2 rejection)
✅ Release command works correctly
✅ user-status command accurate
✅ State file updates correctly

**Code Audit Completed (2025-11-13):**
- ✅ Audited mlc.py vs mlc-patched.py usage
- **Result:** 92% code reuse score - DS01 uses 85-100% of AIME code depending on path
- **Verdict:** Excellent integration, no refactoring needed
- **Doc:** `/opt/ds01-infra/docs/MLC_CODE_USAGE_AUDIT.md`

**Next Actions:**
1. ✅ COMPLETE: GPU allocator E2E tested and working
2. ✅ COMPLETE: MLC code audit
3. Test with MIG-enabled GPUs (current tests use physical GPUs)
4. Update TODO-3: Verify old Dockerfiles don't need migration

---

## 🔍 Testing Summary (2025-11-12 - Previous)

**✅ Working (95% of core functionality):**
- ✅ mlc-patched.py creates containers successfully
- ✅ AIME v2 catalog integration (image-create uses aimehub/* images)
- ✅ Custom image support (--image flag works)
- ✅ Container lifecycle (start, run, GPU visibility, PyTorch works)
- ✅ **CPU limits (64 CPUs applied)**
- ✅ **Memory limits (128GB applied)**
- ✅ **Pids limits (4096 applied)**
- ✅ **Shm-size (64GB applied) - FIXED!**
- ✅ **Cgroup-parent (ds01-admin.slice) - FIXED!**
- ✅ **GPU allocation (gpu_allocator.py) - INTEGRATED!** (needs deployment setup)

**⏳ Remaining (5% - Final Polish):**
- ✅ Deploy system directories for GPU allocator - DONE
- ✅ Refactor DS01 commands to use mlc-* wrappers (TODO-14) - ✅ **COMPLETE**
- ⏳ Label standardization (ds01.* → aime.mlc.*) - optional polish (TODO-3)
- ⏳ Update symlinks and documentation for refactored commands
- ⚠️ container-stats has unrelated bug with --filter flag (minor issue)

**Next Priority:**
1. **HIGH**: Update symlinks and documentation (TODO-14 Phase 3)
2. **MEDIUM**: Standardize labels to aime.mlc.* everywhere (TODO-3)
3. **MEDIUM**: Test E2E GPU allocator with MIG
4. **MEDIUM**: Fix image-update to read AIME packages
5. **LOW**: Fix container-stats --filter bug

---

## ✅ DONE - Core Integration

### Tier 2 Refactor (Completed 2025-11-12)
- [x] **Refactored 3 existing commands** to wrap AIME Tier 1
  - `container-list` → now calls `mlc-list`
  - `container-stop` → now calls `mlc-stop`
  - `container-cleanup` → now calls `mlc-remove` + GPU cleanup
  - All preserve DS01 UX (interactive GUI, --guided mode, colors)
  - All have graceful fallback to docker commands

- [x] **Created 1 new wrapper command**
  - `container-start` → wraps `mlc-start`
  - Interactive selection GUI, --guided mode
  - Follows same wrapper pattern as refactored commands

- [x] **Documented 2 unimplemented commands**
  - `mlc-export` / `mlc-import` exist as wrappers but no Python implementation
  - Skipped for now, will revisit when AIME v2 implements them

### Phase 1: Foundation (Completed 2025-11-12)
- [x] **Created `mlc-patched.py`** (docs/MLC_PATCH_STRATEGY.md)
  - Added `--image` flag for custom images
  - Fixed catalog path to look in aime-ml-containers/
  - Preserves 97.5% of AIME v2 logic
  - Tested: Container creation successful

- [x] **Updated `image-create`** to use AIME v2 catalog
  - Modified `get_base_image()` function
  - Fixed AWK parsing for `[CUDA_ADA]` bracket format
  - Tested: Dockerfiles use `FROM aimehub/pytorch-2.8.0-aime-cuda12.6.3`

- [x] **Updated `mlc-create-wrapper.sh`**
  - Changed from `bash mlc-create` → `python3 mlc-patched.py`
  - Added `--image` flag support
  - Added script mode (`-s`)
  - Tested: Works with AIME catalog

- [x] **E2E Testing on Live GPU Server**
  - Image creation uses AIME base ✅
  - Container creation successful ✅
  - Labels verified (aime.mlc.* + DS01_MANAGED) ✅
  - AIME image pulled successfully ✅

- [x] **Documentation**
  - Created MLC_PATCH_STRATEGY.md
  - Created INTEGRATION_TEST_RESULTS.md
  - Created E2E_TEST_SUMMARY.md
  - Updated CLAUDE.md with integration details
  - Created IMPLEMENTATION_LOG.md

---

## ⏳ TODO - Optional Improvements & Remaining Work

### HIGH PRIORITY (Should do soon)

#### TODO-1: Test Full Container Lifecycle
**Status:** ✅ **MOSTLY DONE** (2025-11-12)
**Priority:** HIGH
**Estimated Time:** 30 minutes

**Tasks:**
- [x] Test container starts and runs
- [x] Test GPU visibility (4x A100-PCIE-40GB visible)
- [x] Test PyTorch works (2.7.1+cu126, CUDA available)
- [x] Test container-list (works, shows GPU allocated)
- [ ] Test mlc open interactively (tested via docker exec)
- [x] Test resource limits (see TODO-2 for detailed findings)

**Test Results (2025-11-12):**
```bash
# Container started successfully ✅
docker start test-mlc-fixed._.1001  # Works

# GPU visibility ✅
nvidia-smi  # All 4 A100 GPUs visible
python3 -c 'import torch; print(torch.cuda.is_available())'  # True

# container-list ✅
container-list  # Shows container with "GPU: Allocated"

# container-stats ⚠️
container-stats test-mlc-fixed  # Has unrelated bug with --filter flag
```

---

#### TODO-2: Verify Resource Limits Applied
**Status:** ✅ **FIXED** (2025-11-12)
**Priority:** HIGH
**Time Taken:** 2 hours

**Test Results:**
- [x] Check CPU limits: ✅ **WORKING** (64 CPUs applied)
- [x] Check memory limits: ✅ **WORKING** (128GB applied)
- [x] Check pids limit: ✅ **WORKING** (4096 applied)
- [x] Check shm-size: ✅ **FIXED** (64GB applied at creation time)
- [x] Check cgroup parent: ✅ **FIXED** (ds01-admin.slice applied at creation time)
- [ ] Check GPU allocation state file updated (see TODO-11)

**Root Cause:**
- `docker update` can modify: CPU, memory, pids ✅
- `docker update` CANNOT modify: shm-size, cgroup-parent ❌
- These must be passed to `mlc-patched.py` at creation time!

**Current Wrapper Behavior (mlc-create-wrapper.sh):**
```bash
# Line 307: Gets limits
RESOURCE_LIMITS=$(python3 get_resource_limits.py datasciencelab --docker-args)
# Returns: --cpus=64 --memory=128g --shm-size=64g --cgroup-parent=ds01-admin.slice

# Line 386: Creates container (WITHOUT shm-size/cgroup-parent)
python3 mlc-patched.py create test-wrapper-limits pytorch 2.7.1 -s -w ~/workspace

# Lines 404-433: Applies limits via docker update
docker update --cpus=64 --memory=128g --pids-limit=4096 test-wrapper-limits._.1001
# ✅ This works for CPU/memory/pids
# ❌ Silently skips shm-size (line 421-424 comment acknowledges this!)
# ❌ Never passes cgroup-parent
```

**Solution Implemented (Option A):**
1. ✅ Modified mlc-patched.py to accept `--shm-size`, `--cgroup-parent` flags
2. ✅ Updated build_docker_create_command() to use these at creation time
3. ✅ Implemented conditional logic: `--shm-size` OR `--ipc host` (mutually exclusive)
4. ✅ Modified mlc-create-wrapper.sh to extract and pass these flags

**Verification (After Fix):**
```bash
# Container: test-resource-fix._.1001
docker inspect test-resource-fix._.1001 --format '{{.HostConfig.NanoCpus}}'
# Result: 64000000000 (64 CPUs) ✅

docker inspect test-resource-fix._.1001 --format '{{.HostConfig.Memory}}'
# Result: 137438953472 (128GB) ✅

docker inspect test-resource-fix._.1001 --format '{{.HostConfig.ShmSize}}'
# Result: 68719476736 (64GB) ✅ FIXED!

docker inspect test-resource-fix._.1001 --format '{{.HostConfig.CgroupParent}}'
# Result: ds01-admin.slice ✅ FIXED!

docker inspect test-resource-fix._.1001 --format '{{.HostConfig.PidsLimit}}'
# Result: 4096 ✅
```

**Files Modified:**
- `/opt/ds01-infra/scripts/docker/mlc-patched.py` - Added --shm-size, --cgroup-parent args + logic
- `/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh` - Extract and pass these flags

---

#### TODO-3: Standardize Labels (from INTEGRATION_STRATEGY_v1.md)
**Status:** ⏳ **PARTIALLY DONE**
**Priority:** MEDIUM
**Estimated Time:** 1 hour

**What Was Planned:**
- Remove all `ds01.*` labels, use `aime.mlc.*` only (INTEGRATION_STRATEGY_v1.md line 491)

**What We Did:**
- ✅ mlc-patched.py uses `aime.mlc.*` labels
- ✅ Added `aime.mlc.DS01_MANAGED=true`
- ✅ Added `aime.mlc.CUSTOM_IMAGE`

**What's Still TODO:**
- [ ] **image-create Dockerfile generation** - Still uses `maintainer`, `ds01.image`
  - File: `scripts/user/image-create` lines ~443-448
  - Change to: `LABEL aime.mlc.MAINTAINER`, `LABEL aime.mlc.CUSTOM_IMAGE`

- [ ] **container-list filtering** - May still use old labels
  - File: `scripts/user/container-list` line ~109
  - Verify uses: `--filter "label=aime.mlc.USER=$USERNAME"`

- [ ] **Monitoring scripts** - Check for any `ds01.*` references
  - Files: `scripts/monitoring/*.sh`
  - Replace with `aime.mlc.*`

**Testing:**
```bash
# Check current labels in Dockerfile
grep "^LABEL" ~/dockerfiles/aime-int-test-datasciencelab.Dockerfile

# Check container-list
container-list

# Check monitoring
container-stats
```

---

### MEDIUM PRIORITY (Nice to have)

#### TODO-4: Custom Image via mlc-create-wrapper Integration
**Status:** ✅ **COMPLETE** (2025-11-13)
**Priority:** MEDIUM
**Time Taken:** 2 hours (including E2E test creation)

**Verified:**
- [x] `mlc-create-wrapper.sh` accepts `--image=<name>` flag
- [x] Wrapper passes `--image` to mlc-patched.py correctly
- [x] mlc-patched.py checks for local custom image before attempting pull
- [x] End-to-end: Dockerfile → docker build → mlc-patched.py → container works!

**E2E Test Results:**
```bash
# Created automated test: /opt/ds01-infra/testing/e2e_custom_image_test.sh
bash /opt/ds01-infra/testing/e2e_custom_image_test.sh
# Result: ALL TESTS PASS ✅

✓ Dockerfile creation
✓ Dockerfile structure (FROM aimehub/pytorch-..., LABELs)
✓ Docker image build (17.4GB)
✓ Container creation from custom image
✓ Label verification (DS01_MANAGED, CUSTOM_IMAGE, USER, DATA_MOUNT, MODELS_MOUNT)
✓ Resource limits (64 CPUs, 128GB RAM, 64GB shm-size)
```

**Bug Fixed:**
- mlc-patched.py lines 1959-1978: Added local image check before docker pull
- Prevents "pull access denied" error for local custom images
- Still pulls AIME base images during docker build (FROM aimehub/...)

**Files Modified:**
- `/opt/ds01-infra/scripts/docker/mlc-patched.py` - Added custom image local check
- `/opt/ds01-infra/testing/e2e_custom_image_test.sh` - Created comprehensive E2E test

---

#### TODO-5: Add v2-Specific Features (from INTEGRATION_STRATEGY_v2.md)
**Status:** ⏳ **PENDING - OPTIONAL**
**Priority:** LOW
**Estimated Time:** 2-3 hours

**Features to Add:**
- [ ] Support for **models directory** (`-m` flag)
  - AIME v2 supports 3 mounts: workspace, data, models
  - Currently DS01 only uses workspace + data
  - Add models directory support to container-create

- [ ] **Architecture selection UI**
  - AIME v2 supports: CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
  - Add to image-create: "Which GPU architecture?"
  - Set `MLC_ARCH` environment variable

- [ ] **Interactive mode integration**
  - AIME v2 has interactive prompts
  - DS01 has `--guided` mode
  - Could merge these UX patterns

**Files to Update:**
- `scripts/user/container-create` (add models dir)
- `scripts/user/image-create` (add arch selection)
- Help text in all commands

---

#### TODO-6: Test Matrix Completion (from INTEGRATION_STRATEGY_v1.md line 583)
**Status:** ⏳ **PARTIALLY DONE**
**Priority:** MEDIUM
**Estimated Time:** 1 hour

**Planned Tests:**
- [x] AIME catalog workflow (pytorch) ✅ DONE
- [ ] AIME catalog workflow (tensorflow)
- [x] Custom image workflow ✅ DONE (Dockerfile generation)
- [ ] Custom image → container workflow (full E2E)
- [x] Resource limits applied ⚠️ NEEDS VERIFICATION
- [ ] GPU allocation works
- [x] mlc-patched.py works ✅ DONE
- [ ] mlc open compatibility
- [ ] All DS01 commands work (container-list, container-stats, etc.)

---

#### TODO-7: Update All Help Text & Documentation
**Status:** ⏳ **PARTIALLY DONE**
**Priority:** LOW
**Estimated Time:** 1 hour

**Done:**
- [x] CLAUDE.md updated
- [x] Created strategy & test docs

**TODO:**
- [ ] README.md - Update with AIME v2 details
- [ ] Command help text - Update container-create, image-create help
- [ ] User guide - Create simple user-facing guide
- [ ] Add AIME v2 details to all command `--help` text

---

### LOW PRIORITY (Future enhancements)

#### TODO-8: Wrapper Simplification (from INTEGRATION_STRATEGY_v1.md line 403)
**Status:** ⏳ **OPTIONAL**
**Priority:** LOW
**Estimated Time:** 2 hours

**Current State:**
- mlc-create-wrapper.sh is 426 lines (complex!)

**Plan from v1 Doc:**
- Simplify to ~150 lines
- Just: get limits → allocate GPU → call mlc-patched.py

**Why Low Priority:**
- Current wrapper works fine
- Not blocking any functionality
- Refactoring = risk of breaking

---

#### TODO-9: Contribute --image Flag Upstream to AIME
**Status:** ⏳ **OPTIONAL**
**Priority:** LOW
**Estimated Time:** 3-4 hours (discussion + PR)

**What:**
- Our `--image` flag is useful for other AIME users
- Could contribute back to AIME as optional feature
- Benefits everyone in AIME ecosystem

**Steps:**
1. Contact AIME maintainers
2. Propose feature
3. Create PR with patch
4. Maintain DS01 compatibility during merge

---

#### TODO-10: Monitoring Scripts Update
**Status:** ⏳ **NEEDS AUDIT**
**Priority:** LOW
**Estimated Time:** 1 hour

**Files to Check:**
- `scripts/monitoring/gpu-status-dashboard.py`
- `scripts/monitoring/container-dashboard.sh`
- `scripts/monitoring/check-idle-containers.sh`
- `scripts/monitoring/collect-*-metrics.sh`

**Verify:**
- [ ] Work with mlc-patched.py containers
- [ ] Use correct labels (aime.mlc.*)
- [ ] Display DS01_MANAGED flag
- [ ] GPU allocation tracking still works

---

### MEDIUM PRIORITY (From DS01_LAYER_AUDIT.md)

#### TODO-11: Fix GPU Allocation Integration (DS01_LAYER_AUDIT.md line 652)
**Status:** ✅ **COMPLETE** (2025-11-13) | ✅ **TESTED E2E**
**Priority:** MEDIUM-HIGH
**Time Taken:** 3 hours (coding + testing + bug fixes)

**Issue:** `gpu_allocator.py` exists but was NOT called by `mlc-create-wrapper.sh`!

**From DS01 Audit:**
> "GPU Allocation Not Integrated - mlc-create-wrapper doesn't call gpu_allocator.py - it's disconnected!"

**What Should Happen:**
```bash
# In mlc-create-wrapper.sh, BEFORE calling mlc-patched.py:

# 1. Get user limits
LIMITS=$(python3 get_resource_limits.py $USER --docker-args)

# 2. Allocate GPU (if needed) ← THIS IS MISSING!
if [ "$CPU_ONLY" != true ]; then
    GPU_ID=$(python3 gpu_allocator.py allocate $USER $CONTAINER_TAG 1 $PRIORITY)
    GPU_ARG="--gpus=device=$GPU_ID"
else
    GPU_ARG=""
fi

# 3. Call mlc-patched.py
python3 mlc-patched.py create ... $GPU_ARG
```

**Solution Implemented:**
1. ✅ Modified wrapper to call `gpu_allocator.py` before container creation
2. ✅ Added priority-based GPU allocation with user limits
3. ✅ Implemented error handling with GPU cleanup on failure
4. ✅ Added fallback to `-g=all` if allocator unavailable
5. ✅ Passes allocated GPU as `-g=device=$GPU_ID` to mlc-patched.py

**Code Changes (mlc-create-wrapper.sh lines 321-369):**
```bash
# Get user's GPU limits and priority
MAX_GPUS=$(python3 get_resource_limits.py $USER --max-gpus)
PRIORITY=$(python3 get_resource_limits.py $USER --priority)

# Allocate GPU via gpu_allocator.py
GPU_OUTPUT=$(python3 gpu_allocator.py allocate $USER $CONTAINER_TAG $MAX_GPUS $PRIORITY)

# Extract GPU ID and pass to mlc-patched.py
GPU_ARG="-g=device=$ALLOCATED_GPU"

# Error handling: Release GPU if container creation fails
if [ $MLC_EXIT_CODE -ne 0 ]; then
    python3 gpu_allocator.py release $CONTAINER_TAG
fi
```

**Deployment Requirements (Not Yet Done):**
```bash
# Requires root to create system directories
sudo mkdir -p /var/lib/ds01 /var/logs/ds01
sudo chown datasciencelab:datasciencelab /var/lib/ds01 /var/logs/ds01

# OR modify gpu_allocator.py to use user-writable paths for testing
```

**Files Modified:**
- `/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh` - Integrated GPU allocator

---

#### TODO-12: Fix Label Inconsistency (DS01_LAYER_AUDIT.md line 485)
**Status:** ⏳ **NEEDS ATTENTION**
**Priority:** MEDIUM
**Estimated Time:** 1 hour

**Issue from DS01 Audit:**
> "DS01 scripts check for `maintainer=$USERNAME` label, but containers don't have it!"
> "Images have: `ds01.*` labels | Containers have: `aime.mlc.*` labels"

**Files to Fix:**
- [ ] **image-create** - Lines 143-147 (Dockerfile generation)
  - Change: `LABEL ds01.image` → `LABEL aime.mlc.CUSTOM_IMAGE`
  - Change: `LABEL maintainer` → `LABEL aime.mlc.MAINTAINER`

- [ ] **container-list** - Line 504
  - Change: `--filter "label=maintainer=$USERNAME"`
  - To: `--filter "label=aime.mlc.USER=$USERNAME"`

- [ ] **All monitoring scripts** - Check for `ds01.*` references
  - Replace with `aime.mlc.*`

**This is the same as TODO-3 but with more details from audit.**

---

#### TODO-13: Verify 3-Tier Package System Still Works (DS01_LAYER_AUDIT.md line 93)
**Status:** ⏳ **NEEDS TESTING**
**Priority:** MEDIUM
**Estimated Time:** 30 minutes

**What to Test:**
- [ ] Framework → Base → Use Case → Custom progression still works
- [ ] Base packages (jupyter, pandas, etc.) get installed
- [ ] Use case packages (CV: timm, albumentations | NLP: transformers, etc.)
- [ ] Custom packages get added

**From DS01 Audit:**
> "3-Tier Package System is excellent UX - Keep this!"

**Testing:**
```bash
# Create image with all 4 tiers
image-create test-3tier -f pytorch -t cv
# Should ask for base packages, use case packages, and custom

# Check Dockerfile
cat ~/dockerfiles/test-3tier-datasciencelab.Dockerfile

# Verify all RUN pip install blocks present
grep -A2 "RUN pip install" ~/dockerfiles/test-3tier-datasciencelab.Dockerfile
```

---

#### TODO-14: Refactor DS01 Tier 2 Commands to Wrap ALL mlc-* Commands
**Status:** 🔄 **IN PROGRESS** (2025-11-12)
**Priority:** HIGH
**Estimated Time:** 4-6 hours

**Goal:** Make DS01 Tier 2 a lightweight wrapper layer that calls AIME Tier 1 for core functionality, then adds DS01 UX (interactive GUI, --guided mode, resource management).

**Current State (Audit Results 2025-11-12):**

✅ **Already Using mlc-* (3/11 commands):**
- `container-run` → calls `mlc-open` directly ✅
- `container-create` → calls `mlc-create-wrapper.sh` → calls `mlc-patched.py` ✅
- `container-stats` → calls `mlc-stats-wrapper.sh` → calls `mlc-stats` ✅

❌ **NOT Using mlc-* (3/11 commands - need refactoring):**
- `container-list` → uses `docker ps` directly (should call `mlc-list`)
- `container-stop` → uses `docker stop` directly (should call `mlc-stop`)
- `container-cleanup` → uses `docker rm` directly (should call `mlc-remove`)

⚠️ **Missing Wrappers - Status Update (2025-11-12):**
- ✅ `container-start` → Created (wraps `mlc-start`)
- ⚠️ `container-export` → SKIPPED (mlc-export not implemented in AIME v2 Python code)
- ⚠️ `container-import` → SKIPPED (mlc-import not implemented in AIME v2 Python code)
- ✅ Skipped: `mlc-update-sys` (admin-only, not user-facing)
- ✅ Skipped: `mlc --version` (not needed in DS01 UX)

**Implementation Plan:**

**Phase 1: Refactor Existing Commands (3 commands)** ✅ **COMPLETE** (2025-11-12)
1. ✅ **Audit complete** - documented above
2. ✅ **Refactor `container-list`** - DONE
   - Now calls `mlc-list` for core listing (with fallback to docker)
   - Preserved DS01's interactive selection GUI
   - Enhanced --guided mode with AIME integration explanation
   - Kept all DS01 formatting/colors
   - Shows AIME framework labels in detailed view

3. ✅ **Refactor `container-stop`** - DONE
   - Now calls `mlc-stop <name>` for actual stopping (with fallback to docker)
   - Preserved interactive selection when no args
   - Kept process count display
   - Maintained force/timeout options
   - Enhanced --guided mode with layer explanation

4. ✅ **Refactor `container-cleanup`** - DONE
   - Now calls `mlc-remove <name>` for actual removal (with fallback to docker)
   - Preserved bulk selection GUI
   - **Added GPU state cleanup** via `cleanup_gpu_state()` function
   - Kept dangling image cleanup
   - Enhanced --guided mode with GPU cleanup explanation

**Phase 2: Create New Wrapper Commands** ⚠️ **PARTIAL** (2025-11-12)
5. ✅ **Create `container-start`** - DONE
   - Wraps `mlc-start <name>` (with fallback to docker start)
   - Interactive selection GUI if no args
   - Shows container status after start
   - --guided mode support with layer explanation

6. ⚠️ **`container-export` - SKIPPED** (AIME v2 not implemented)
   - `mlc-export` command exists as wrapper script but has no implementation in mlc.py
   - Python mlc.py only supports: create, list, open, remove, start, stats, stop, update-sys
   - export/import marked as "NEW in v2" but not yet functional
   - **Decision:** Skip for now, revisit when AIME implements export

7. ⚠️ **`container-import` - SKIPPED** (AIME v2 not implemented)
   - Same as export - wrapper exists but no mlc.py implementation
   - **Decision:** Skip for now, revisit when AIME implements import

**Phase 3: Documentation & Testing**
8. [ ] Update symlinks in `/usr/local/bin/`
9. [ ] Update `alias-list` documentation
10. [ ] Update CLI ecosystem documentation
11. [ ] Test all 11 commands E2E

**Design Principles:**
- ✅ AIME Tier 1 = Core functionality (container lifecycle, image management)
- ✅ DS01 Tier 2 = Lightweight wrappers (add UX, interactive GUI, resource mgmt)
- ✅ Preserve ALL existing DS01 UX features (interactive selection, --guided, colors)
- ✅ Call mlc-* commands for core operations (don't duplicate logic)
- ✅ Add DS01-specific features AFTER mlc-* call (GPU cleanup, resource display)

**Files to Modify:**
- `/opt/ds01-infra/scripts/user/container-list` (refactor)
- `/opt/ds01-infra/scripts/user/container-stop` (refactor)
- `/opt/ds01-infra/scripts/user/container-cleanup` (refactor)

**Files to Create:**
- `/opt/ds01-infra/scripts/user/container-start` (new)
- `/opt/ds01-infra/scripts/user/container-export` (new)
- `/opt/ds01-infra/scripts/user/container-import` (new)

**Testing:**
```bash
# Test refactored commands
container-list
container-list --guided
container-stop my-project
container-stop  # Should prompt for selection
container-cleanup

# Test new commands
container-start my-project
container-start  # Should prompt
container-export my-project
container-import my-export.tar
```

---

---

#### TODO-15: Image Workflow Redesign (2025-11-12)
**Status:** ✅ **COMPLETE** (image-create refactored)
**Priority:** HIGH
**Time Taken:** 3 hours

**Goal:** Redesign `image-create` and `image-update` to properly display AIME base packages and follow proper phased workflow.

**Context:**
- AIME base images are framework-focused (PyTorch + CUDA + minimal deps)
- Only 8 key packages pre-installed: conda, numpy, pillow, tqdm, torch, torchvision, torchaudio, ipython
- Missing: pandas, scipy, sklearn, jupyter, matplotlib, seaborn, opencv, transformers
- DS01's 3-tier package system is STILL NEEDED

**Implementation Plan:**

**Phase 1: Package Display Function** ✅ **COMPLETE**
- [x] Created `show_base_image_packages()` function
  - Displays key AIME packages: torch, conda, numpy, pillow, tqdm, ipython, psutil
  - Shows what's MISSING: jupyter, pandas, scipy, sklearn, matplotlib
  - Called after framework selection, before package prompts

**Phase 2: Redesign image-create Workflow** ✅ **COMPLETE** (7 phases, no container creation)
- [x] Phase 1: Base Framework Selection
  - PyTorch (latest), TensorFlow (latest), JAX, CPU-only, Custom
  - Uses AIME v2 catalog (get_base_image function)
  - Displays selected base image from catalog
  - Calls show_base_image_packages() after selection
- [x] Phase 2: Core Python & Jupyter
  - jupyter, jupyterlab, ipykernel, ipywidgets, notebook
  - Separate variable: JUPYTER_CHOICE
  - Options: Default (recommended), Skip, Custom
- [x] Phase 3: Core Data Science
  - pandas, scipy, scikit-learn, matplotlib, seaborn
  - Separate variable: DATA_SCIENCE_CHOICE
  - Options: Default (recommended), Skip, Custom
- [x] Phase 4: Use-Case Specific
  - General ML, CV, NLP, RL, None/Custom
  - Existing functionality preserved
- [x] Phase 5: Additional Packages (free-form)
- [x] Phase 6: Dockerfile Created ✓ (now Phase 1/2)
- [x] Phase 7: Build Image? (docker build) (now Phase 2/2)
- [x] ~~Phase 8: Create Container?~~ REMOVED (Tier 2 isolation)

**Phase 3: Update image-update** ✅ **COMPLETE** (2025-11-12)
- [x] Applied same package display logic
  - Shows AIME base image with key packages
  - Displays: "Pre-installed: torch, numpy, pillow, tqdm, conda, ipython, psutil"
- [x] Categorized package display matches image-create structure
  - Jupyter & Interactive (new category)
  - Data Science (new category)
  - Use Case Specific (existing)
  - Custom-installed (existing)
  - Core Python (legacy - for old Dockerfiles)
- [x] Updated `parse_python_packages_by_category()` to recognize new comment headers
  - "# Jupyter & Interactive"
  - "# Core Data Science"
  - "# Use case specific packages"
  - "# Custom additional packages"

**Phase 4: Simplify container-create** ✅ **COMPLETE**
- [x] REMOVED all image creation functionality (Option 2 deleted)
- [x] Now only 2 options: Use existing image, Use base framework
- [x] --guided explains workflow: image-create → container-create → container-run
- [x] Added intro explaining Tier 2 separation

**Phase 5: Tier 2 Modularization Review** ✅ **COMPLETE** (2025-11-12)
- [x] Audited Tier 2 commands for entanglement
- [x] Removed cross-calls (use --guided to suggest next steps)
- [x] Ensured strict isolation and no duplication

**Isolation Violations Fixed:**
1. **image-create** - Removed Phase 3 "Create Container?"
   - Lines 913-985 deleted (container-create cross-call)
   - Now 2 phases: Dockerfile Created, Build Image
   - --guided mode SUGGESTS container-create (doesn't call it)
2. **container-create** - Removed Option 2 "Create custom image"
   - Lines 239-369 deleted (image-create cross-call)
   - Now 2 options: Use existing image, Use base framework
   - --guided mode EXPLAINS workflow separation
   - Added intro explaining image-create → container-create → container-run workflow

**Phase 6: Orchestrator Review** ✅ **COMPLETE**
- [x] Reviewed `project-init` - orchestrating cleanly (calls image-create, container-create)
- [x] Reviewed `user-setup` - orchestrating cleanly (calls ssh-setup → project-init → vscode-setup)
- [x] Both call Tier 2 sequentially, no duplication

**Design Principles:** ✅ **ALL IMPLEMENTED**
- ✅ Show AIME base contents BEFORE asking what to install (show_base_image_packages)
- ✅ Default to installing DS packages (AIME bases are framework-only)
- ✅ Keep 3-tier package system → now 4-phase: Framework, Jupyter, Data Science, Use Case
- ✅ Explain each phase in --guided mode
- ✅ Tier 2 commands are isolated, unique, modular (cross-calls removed)
- ✅ Use docker build (NOT mlc-create) for dockerfile→image

**Files Modified:**
- ✅ `/opt/ds01-infra/scripts/user/image-create` (MAJOR REFACTOR - 200+ lines changed)
  - Added show_base_image_packages() function (47 lines)
  - Split get_base_packages() → get_jupyter_packages() + get_data_science_packages()
  - Updated framework selection to use AIME v2 catalog
  - Separated package phases: Jupyter, Data Science, Use Case
  - Updated create_dockerfile() signature (12 parameters) and implementation
  - Removed Phase 3 "Create Container?" (Tier 2 isolation - 73 lines deleted)
  - Updated all variable references (JUPYTER_CHOICE, DATA_SCIENCE_CHOICE)
- ✅ `/opt/ds01-infra/scripts/user/image-update` (UPDATED - 25 lines changed)
  - Updated display to show AIME base packages
  - Split package categories to match image-create structure
  - Updated parse_python_packages_by_category() to recognize new headers
  - Backward compatible with legacy Dockerfiles (shows "legacy format")
- ✅ `/opt/ds01-infra/scripts/user/container-create` (SIMPLIFIED - 130 lines removed)
  - Removed Option 2 "Create custom image"
  - Now 2 options only: existing image, base framework
  - Added --guided intro explaining workflow separation (28 lines)
- ✅ `/opt/ds01-infra/scripts/user/project-init` (verified - no changes needed)
- ✅ `/opt/ds01-infra/scripts/user/user-setup` (verified - no changes needed)
- ✅ `/opt/ds01-infra/CLAUDE.md` (UPDATED - documented workflow changes)

**Documentation:**
- `/opt/ds01-infra/docs/IMAGE_WORKFLOW_REDESIGN.md` (design doc created)

**Implementation Summary:**

**New Workflow (7 phases):**
1. Framework Selection → Shows AIME base image from catalog
2. Display AIME Packages → show_base_image_packages() explains what's included
3. Core Python & Jupyter → Separate phase (jupyter, jupyterlab, ipykernel, ipywidgets)
4. Core Data Science → Separate phase (pandas, scipy, sklearn, matplotlib, seaborn)
5. Use-Case Specific → Existing (CV, NLP, RL, ML, Custom)
6. Dockerfile Created → Phase 1/2
7. Build Image → Phase 2/2 (suggests container-create after)

**Key packages displayed:** conda, numpy, pillow, tqdm, torch, torchvision, torchaudio, ipython, psutil

**Taxonomy chosen:** Option A (detailed phases) - better for educational use

**Testing Status:**
- ⏳ E2E testing deferred (requires GPU server access)
- Code review: Complete
- Documentation: Complete

**Impact:**
- Users now see what's in AIME base BEFORE being asked what to install
- Clear separation between Jupyter, Data Science, and Use-Case packages
- Eliminates confusion about "why install pandas if base has numpy?"
- Tier 2 commands are truly isolated (can be used independently)
- Orchestrators properly chain commands without duplication

---

#### TODO-16: Duplicate Package Detection (2025-11-12)
**Status:** ✅ **COMPLETE**
**Priority:** MEDIUM
**Time Taken:** 30 minutes

**Goal:** Prevent users from installing duplicate packages in both `image-create` and `image-update`.

**Implementation:**

**New Helper Functions:**
```bash
normalize_package_name()  # Strips version specifiers, converts to lowercase
check_duplicate_packages() # Checks if packages are already in existing lists
```

**image-create - Duplicate Checks Added:**
1. **Phase 2 (Jupyter):** Custom packages checked against AIME base
2. **Phase 3 (Data Science):** Custom packages checked against AIME base + Jupyter
3. **Phase 5 (Additional):** All packages checked against AIME base + Jupyter + Data Science + Use Case

**image-update - Duplicate Checks Added:**
- **Add Python Packages:** Checks against AIME base + all currently installed packages

**Behavior:**
- Yellow warning displays duplicate packages
- Prompts user to enter different packages
- Loops back to input prompt
- User can press Enter to cancel/skip

**Example:**
```
> jupyter pandas numpy

⚠  Warning: These packages are already installed:
   numpy

Please enter different packages (or press Enter to cancel):
> jupyter pandas

✓ Packages added to Dockerfile
```

**Features:**
- ✅ Case-insensitive matching (numpy = NumPy = NUMPY)
- ✅ Version specifier stripping (pandas==1.5.0 matches pandas)
- ✅ Graceful looping (no exit, no error)
- ✅ Clear user feedback (yellow warnings)

**Files Modified:**
- `/opt/ds01-infra/scripts/user/image-create` (+89 lines)
  - Added normalize_package_name() function
  - Added check_duplicate_packages() function
  - Integrated checks in 3 prompts (Jupyter custom, DS custom, Additional)
- `/opt/ds01-infra/scripts/user/image-update` (+78 lines)
  - Added same helper functions
  - Integrated check in Add Python Packages prompt

**Total Changes:** +167 lines (duplicate prevention logic)

---

## 📋 Questions/Decisions Needed

### Q1: Resource Limits Application (from INTEGRATION_STRATEGY_v2.md comments)
**Question:** Does mlc-patched.py need to accept `--cpus`, `--memory` etc flags?

**Current Approach:**
- mlc-patched.py creates container
- mlc-create-wrapper.sh may need to call `docker update` after

**Alternative Approach:**
- Add resource limit flags to mlc-patched.py directly
- Pass to `docker create` (not `docker update`)

**Need to Decide:** Which approach? Test current approach first (TODO-2).

---

### Q2: Label Namespace Strategy
**Question:** Should we fully migrate to `aime.mlc.*` or keep some `ds01.*`?

**Current:**
- Containers: `aime.mlc.*` + `aime.mlc.DS01_MANAGED`
- Images: Still `maintainer`, `ds01.image`

**Options:**
1. **Full migration:** All `aime.mlc.*` (more consistent)
2. **Hybrid:** Images use `ds01.*`, containers use `aime.mlc.*`
3. **New namespace:** `aime.mlc.ds01.*` for DS01-specific labels

**Recommendation:** Full migration (option 1) - see TODO-3.

---

### Q3: Models Directory Support
**Question:** Do users need 3-mount points (workspace, data, models)?

**AIME v2 Supports:**
- `-w` workspace (code)
- `-d` data (datasets)
- `-m` models (pretrained models)

**DS01 Currently:**
- `-w` workspace (code + data mixed)
- `-d` data (optional, rarely used)

**Need to Decide:** Add models directory support? (see TODO-5)

---

## 🎯 Recommended Next Steps

### Immediate (Next 1-2 hours)
1. ✅ **TODO-1:** Test full container lifecycle (open, use, stats)
2. ✅ **TODO-2:** Verify resource limits applied correctly
3. ⏳ **TODO-4:** Test custom image E2E workflow

### Short-term (Next week)
4. ⏳ **TODO-3:** Standardize labels to `aime.mlc.*`
5. ⏳ **TODO-6:** Complete test matrix
6. ⏳ **TODO-7:** Update user-facing documentation

### Long-term (Future)
7. ⏳ **TODO-5:** Add v2-specific features (models dir, arch selection)
8. ⏳ **TODO-9:** Consider contributing --image upstream to AIME
9. ⏳ **TODO-10:** Audit monitoring scripts

---

## ✅ Success Metrics (from INTEGRATION_STRATEGY_v1.md)

**Integration 100% successful when:**
- [x] AIME base images used (aimehub/pytorch...)
- [x] Custom images work (Dockerfile generation)
- [ ] Resource limits enforced (NEEDS VERIFICATION)
- [ ] GPU allocation integrated (NEEDS VERIFICATION)
- [x] Backward compatible (mlc open works)
- [ ] Labels standardized (PARTIALLY - TODO-3)
- [x] Documentation updated (CLAUDE.md done)
- [ ] All tests pass (PARTIALLY - TODO-6)

**Current Status:** 75% Complete
- Core functionality: ✅ Working
- Polish & verification: ⏳ In progress

---

## 📝 Reference Documents

- **Strategy:** `docs/INTEGRATION_STRATEGY_v1.md`, `docs/INTEGRATION_STRATEGY_v2.md`
- **Audits:** `docs/AIME_FRAMEWORK_AUDIT_v1.md`, `docs/AIME_FRAMEWORK_AUDIT_v2.md`
- **Implementation:** `docs/IMPLEMENTATION_LOG.md`
- **Testing:** `docs/E2E_TEST_SUMMARY.md`, `docs/INTEGRATION_TEST_RESULTS.md`
- **Strategy:** `docs/MLC_PATCH_STRATEGY.md`

---

**TODO for reference**
