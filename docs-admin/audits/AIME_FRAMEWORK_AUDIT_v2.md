# AIME Framework v2 - Complete Audit

**Date:** 2025-11-12 (Updated from v1 audit)
**Purpose:** Comprehensive audit to understand AIME framework for integration with DS01
**Submodule:** `/home/user/ds01-infra/aime-ml-containers` (commit: b7ad7d1)
**Version:** 2.1.2 (container version 4)

---

## 1. Executive Summary

AIME ML Containers (v2) is a **Python-based** container management system providing:
- Framework-based container creation (PyTorch, Tensorflow)
- Version-controlled base images from central repository
- Multi-user isolation via naming convention
- Label-based container identification
- Lifecycle management commands
- **NEW in v2:** Interactive mode, import/export, multi-architecture support

**Current Status:** Active development - Latest version with Blackwell GPU support.

**Major v1 → v2 Changes:**
- **Complete rewrite:** Bash scripts → Python (mlc.py ~2,400 lines)
- **Architecture flexibility:** CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
- **Interactive mode:** Can run without command-line arguments
- **New commands:** mlc export, mlc import
- **MXNet dropped:** Now only PyTorch and Tensorflow
- **Wrapper architecture:** All mlc-* commands are thin wrappers calling `mlc` Python script

**Key Insight for DS01:** AIME v2 provides a more robust foundation but still **NOT designed for**:
- Custom user-built images (always uses framework catalog)
- Resource limits/quotas
- GPU allocation management
- Multi-tier package customization

---

## 2. Architecture Overview

### 2.1 Core Commands (11 total - v2 architecture)

**v2 Command Structure:**
- Main entry point: `mlc` (Python script dispatcher)
- All commands: `mlc <subcommand>` or `mlc-<subcommand>` (wrapper scripts)
- Backend: All logic in `mlc.py` (~2,400 lines Python)

| Command | Purpose | Used by DS01? | How? | v2 Changes |
|---------|---------|---------------|------|------------|
| `mlc create` | Create container | ✅ **YES** | Wrapped by `mlc-create-wrapper.sh` | Now Python-based, interactive mode |
| `mlc open` | Enter container | ✅ **YES** | Called directly by `container-run` | Python-based, unchanged behavior |
| `mlc stats` | Show stats | ✅ **YES** | Wrapped by `mlc-stats-wrapper.sh` | Python-based, improved formatting |
| `mlc list` | List containers | ❌ **NO** | DS01 uses custom `container-list` | Python, more display options |
| `mlc stop` | Stop container | ❌ **NO** | DS01 uses custom `container-stop` | Python-based |
| `mlc start` | Start container | ❌ **NO** | Rarely needed (mlc-open auto-starts) | Python-based |
| `mlc remove` | Remove container | ❌ **NO** | DS01 uses custom `container-cleanup` | Python-based |
| `mlc export` | Export container | ❌ **NO** | Not used | **NEW in v2** |
| `mlc import` | Import container | ❌ **NO** | Not used | **NEW in v2** |
| `mlc update-sys` | Update system | ❌ **NO** | System admin only | Python-based |
| `mlc -v/--version` | Show version | ❌ **NO** | Not used | **NEW in v2** |

**v2 Architecture Notes:**
- All `mlc-*` commands are thin bash wrappers that call `mlc <subcommand> $@`
- Interactive mode: Running `mlc create` without args enters guided workflow
- Architecture flag: `-arch` or `MLC_ARCH` env variable for GPU architecture selection

**Integration Strategy for DS01:**
Same as v1 - continue wrapping only what DS01 needs to customize (create, open, stats). The Python rewrite doesn't change integration strategy, but provides more stability.

AN ADDITIONAL AIM OF THE PLANNED REFACTOR: to properly integrate and use ALL of the of `mlc-*` commands into ds01 framework:
- `container list` should call `mlc-list` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01).
- `container stop` should call `mlc-stop` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01).
- NEW CMDS: 
   - `container start` that calls `mlc-start` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01)
   - also wrap `mlc export` and `mlc import` in `container export` and `container import` customisable wrappers like all the others!
- `container cleanup` / `container remove` should call `mlc-remove` in a customisable wrapper (which also provides GUI for selection if called without arguments - as is currently in ds01)


### 2.2 Supporting Files (v2)

```
aime-ml-containers/
├── mlc                     # Main entry point (bash wrapper → mlc.py)
├── mlc.py                  # Core logic (~2,400 lines Python)
├── mlc-create              # Thin wrapper: calls 'mlc create $@'
├── mlc-open                # Thin wrapper: calls 'mlc open $@'
├── mlc-list                # Thin wrapper: calls 'mlc list $@'
├── mlc-stats               # Thin wrapper: calls 'mlc stats $@'
├── mlc-stop                # Thin wrapper: calls 'mlc stop $@'
├── mlc-start               # Thin wrapper: calls 'mlc start $@'
├── mlc-remove              # Thin wrapper: calls 'mlc remove $@'
├── mlc-export              # NEW: Export container (thin wrapper)
├── mlc-import              # NEW: Import container (thin wrapper)
├── mlc-update-sys          # System update (thin wrapper)
├── ml_images.repo          # Framework catalog (~150+ framework versions)
├── README.md               # User documentation (updated for v2)
├── aime-mlc-installation-guide.md  # Installation guide
└── LICENSE.txt             # MIT License
```

**v2 Architecture Change:**
- v1: Pure Bash scripts with logic embedded in each mlc-* file
- v2: Python-based core with bash wrappers for backward compatibility
- All business logic centralized in `mlc.py`
- Wrappers are 10-15 lines each, just forwarding to Python

---

## 3. Deep Dive: `mlc create` Workflow (v2)

This is the **critical command** for DS01 integration. V2 is Python-based with argparse.

### 3.1 Input Validation Phase (Python argparse)

```python
# mlc.py: Arguments defined via argparse (lines 84-157)
parser_create.add_argument('container_name', nargs='?', type=str)
parser_create.add_argument('framework', nargs='?', type=str)
parser_create.add_argument('version', nargs='?', type=str)

# Flags:
-s, --script         # Script mode (non-interactive, default is interactive)
-i, --info           # Show available frameworks/versions
-arch, --architecture # GPU architecture (CUDA_ADA, CUDA_AMPERE, etc.)
-g, --num_gpus       # GPU spec: "all", "0", "0,1", etc. (default: "all")
-w, --workspace_dir  # Workspace dir (default: $HOME/workspace)
-d, --data_dir       # Optional data mount
-m, --models_dir     # Optional models mount (NEW in container version 4)
```

**v2 Interactive Mode:**
- If arguments missing, enters interactive guided workflow
- Prompts for container name, framework selection, version, directories
- More user-friendly than v1

TOD0: WRAP THIS LIGHTLY IN MY DS01 `CONTAINER` COMMANDS

### 3.2 Framework Image Lookup Phase (v2)

**Python-based Implementation:**
- Reads `ml_images.repo` CSV file
- Filters by GPU architecture (auto-detected or specified via `-arch` flag)
- Supports `MLC_ARCH` environment variable
- Priority: `-arch` flag > `MLC_ARCH` env > auto-detection

**Image Repository Format** (`ml_images.repo`):

```csv
Pytorch, 2.8.0, CUDA_BLACKWELL, aimehub/pytorch-2.8.0-cuda12.8.0
Pytorch, 2.7.1, CUDA_BLACKWELL, aimehub/pytorch-2.7.1-cuda12.8.0
Pytorch, 2.7.1, CUDA_ADA, aimehub/pytorch-2.7.1-aime-cuda12.6.20
Pytorch, 2.7.1, CUDA_AMPERE, aimehub/pytorch-2.7.1-aime-cuda11.8.89
Pytorch, 2.6.0, ROCM6, aimehub/pytorch-2.6.0-rocm6.2.2
Tensorflow, 2.16.1, CUDA_ADA, aimehub/tensorflow-2.16.1-cuda12.3
Tensorflow, 2.15.0, CUDA_ADA, aimehub/tensorflow-2.15.0-cuda12.3
...
```

**v2 Catalog Expansion:**
- **150+ images** (massive expansion from v1's 76)
- **5 GPU architectures:** CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
- **2 frameworks:** PyTorch, Tensorflow (MXNet dropped)
- **Latest versions:** PyTorch 2.8.0, Tensorflow 2.16.1
- **AMD GPU support:** ROCM6 and ROCM5 images added

### 3.3 Base Image Preparation Phase (v2)

TODO: I NEED TO WRAP THIS FOR MY WORKFLOW THAT ALLOWS CUSTOM IMAGES (USING IMAGE INHERITANCE TO BUILD UPON AIME'S BASE IMAGES WITH DS01 `image create` & `image update` LOGIC)

**Same workflow as v1, now Python-based:**

1. **Pull base image** from Docker Hub
   ```bash
   docker pull aimehub/pytorch-2.7.1-cuda12.6.20
   ```

2. **Customize in temporary container** (Python subprocess calls):
   - Install sudo, git
   - Create user matching host UID/GID
   - Grant passwordless sudo
   - Set custom PS1 prompt with container name

3. **Commit as tagged image:**
   ```bash
   docker commit <temp_container> aimehub/pytorch-2.7.1:my-project._.1001
   ```

4. **Remove temporary container**

**Result:** Customized image with user account matching host, ready for creation as persistent container.

### 3.4 Container Naming Convention (v2)

**Unchanged from v1:**

```python
# Python: mlc.py
user_id = os.getuid()  # e.g., 1001
container_tag = f"{container_name}._.{user_id}"
# Result: "my-project._.1001"
```

**Multi-user isolation:**
- Each user gets unique container even with same name
- User 1001: `my-project._.1001`
- User 1002: `my-project._.1002`
- `mlc open` auto-finds by appending `._.{uid}`

### 3.5 AIME Labels (v2)

**Unchanged label schema from v1:**

```python
# Python: mlc.py (line ~1429)
container_label = "aime.mlc"

# Labels applied:
--label=aime.mlc={user_name}                       # aime.mlc=username
--label=aime.mlc.NAME={container_name}             # aime.mlc.NAME=my-project
--label=aime.mlc.USER={user_name}                  # aime.mlc.USER=username
--label=aime.mlc.MLC_VERSION={mlc_container_version}  # aime.mlc.MLC_VERSION=4
--label=aime.mlc.WORK_MOUNT={workspace_mount}      # aime.mlc.WORK_MOUNT=/home/user/workspace
--label=aime.mlc.DATA_MOUNT={data_mount}           # aime.mlc.DATA_MOUNT=/path/to/data
--label=aime.mlc.MODELS_MOUNT={models_mount}       # aime.mlc.MODELS_MOUNT=/path/to/models (NEW in v4)
--label=aime.mlc.FRAMEWORK={framework}-{version}   # aime.mlc.FRAMEWORK=Pytorch-2.7.1
--label=aime.mlc.GPUS={num_gpus}                   # aime.mlc.GPUS=all
```

**v2 Changes:**
- `MLC_VERSION=4` (was 3 in v1) - adds models directory support
- Added `aime.mlc.MODELS_MOUNT` label
- All filtering still uses `--filter=label=aime.mlc`
- Label structure backward compatible

### 3.6 Container Lifecycle Management (v2)

**Python-based docker create command (via subprocess):**

```python
# mlc.py: build_docker_create_command() function
docker create -it \
  # Volumes (v2 adds models directory)
  -v {workspace_mount}:/workspace \
  -v {data_mount}:/data \              # Optional
  -v {models_mount}:/models \          # Optional, NEW in v2
  -w /workspace \                       # Working directory

  # Naming & Labels
  --name={container_tag} \              # my-project._.1001
  --label=aime.mlc=... \                # All aime.mlc.* labels

  # User & Security
  --user {user_id}:{group_id} \         # Run as host user
  --tty --privileged --interactive \
  --group-add video \                   # Access to /dev/video*
  --group-add sudo \                    # Sudo group

  # GPU & Devices
  --gpus={num_gpus} \                   # GPU allocation (still "all" by default)
  --device /dev/video0 \                # Webcam access
  --device /dev/snd \                   # Audio access

  # Networking & IPC
  --network=host \                      # Host network mode
  --ipc=host \                          # Shared IPC namespace
  -v /tmp/.X11-unix:/tmp/.X11-unix \    # X11 forwarding

  # Resource Limits (v2 STILL doesn't set CPU/memory!)
  --ulimit memlock=-1 \                 # Unlimited locked memory
  --ulimit stack=67108864 \             # 64MB stack limit

  # Image & Command
  {image}:{container_tag} \             # The customized image
  bash
```

**v2 Changes:**
- Models directory support (`-m/--models_dir` flag)
- Python subprocess instead of bash script
- **Still no CPU/memory/GPU limits** - DS01 must add these
- DS01 must also add customisation logic currently found in `image create` & `image update` -> integrate that with this workflow.

**Important:** AIME v2 creates container in **stopped state** (same as v1). User must use `mlc open` to start it.

---

## 4. What AIME v2 Does NOT Provide

### 4.1 No Custom Image Support (unchanged from v1)

**AIME v2 ALWAYS uses ml_images.repo catalog:**

```python
# Python logic in mlc.py
# If framework not in catalog → error message and exit
if not found_in_repo:
    print(f"{ERROR}Error: unavailable framework version{RESET}")
    sys.exit(-3)
```

**Cannot pass custom Docker image** - it MUST be a framework from the catalog (PyTorch or Tensorflow).
- No support for user-built images
- No Dockerfile-based customization
- Cannot use pre-built images from other registries

==> **DS01 Impact:** CRITICAL: HOW TO HANDLE THIS THEN SO THAT USERS CAN CUSTOMISE THEIR IMAGE PACKAGES USING `image create` & `image update` ?? THIS IS UNRESOLVED?

### 4.2 No Resource Limits (unchanged from v1)

**AIME v2 does NOT set:**
- CPU limits (`--cpus`)
- Memory limits (`--memory`)
- Shared memory (`--shm-size`)
- PID limits (`--pids-limit`)
- Cgroup parent

**Only sets:**
- `--ulimit memlock=-1` (unlimited locked memory for CUDA)
- `--ulimit stack=67108864` (64MB stack)

**DS01 Impact:** Must continue wrapping mlc create to add resource limits.

### 4.3 No GPU Allocation Management (unchanged from v1)

**Default GPU allocation:**
```python
# mlc.py default
num_gpus = "all"  # All GPUs available to container!
```

**AIME v2 just passes `--gpus={num_gpus}` to Docker. No:**
- GPU allocation tracking
- MIG instance awareness
- Priority-based allocation
- Fair sharing
- Per-user GPU quotas

**DS01 Impact:** Must continue using gpu_allocator.py for smart GPU assignment.

### 4.4 No Package Customization (unchanged from v1)

**Base images from `aimehub/*` include:**
- Framework only (PyTorch or Tensorflow)
- CUDA toolkit / ROCM
- cuDNN / MIOpen
- Python 3.x
- Basic system tools (added during customization: sudo, git)

**Does NOT include:**
- JupyterLab
- NumPy, Pandas, Scikit-learn
- Domain-specific packages (timm, transformers, etc.)
- User-specified packages

==> **DS01 Impact:**: HANDLE THIS THEN SO THAT USERS CAN CUSTOMISE THEIR IMAGE PACKAGES USING `image create` & `image update` ?? THIS IS UNRESOLVED?
   - as currently implemented in ds01's image create: have hierachy of defaults: base default pkgs > jupyter &interactive defaults pkgs > use case default pkgs > user specified custom pkgs
   - if this cannot be implemented cleanly then fall back to: userssnstall packages inside running container via pip/apt -> commit the container to a new image? but this is inferior than having a way to edit dockerfiles directly to rebuild from them

### 4.5 No State Management (unchanged from v1)

**AIME v2 is stateless** - no tracking of:
- Which GPUs are allocated to which containers
- Container resource usage over time
- Idle containers eligible for cleanup
- User quotas and current usage
- Container creation/deletion history

**DS01 Impact:** Must continue maintaining:
- `/var/lib/ds01/gpu-state.json`
- `/var/lib/ds01/container-metadata/`
- `/var/log/ds01/gpu-allocations.log`

---

## 5. Integration Points for DS01 (v2)

### 5.1 What to Keep from AIME v2

✅ **Expanded framework catalog** (`ml_images.repo`)
- **150+ pre-tested framework images** (up from 76 in v1)
- **5 GPU architectures:** CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
- Flexible architecture selection via `-arch` flag or `MLC_ARCH` env
- Latest framework versions (PyTorch 2.8.0, Tensorflow 2.16.1)
- **AMD GPU support** via ROCM images

✅ **Container naming convention** (`name._.uid`)
- Unchanged from v1
- Multi-user isolation
- Predictable container discovery

✅ **Label system** (`aime.mlc.*`)
- Container version 4 (adds models directory)
- Backward compatible with v1 labels
- All DS01 filtering continues to work

✅ **Base image preparation workflow**
- User creation with matching UID/GID
- Passwordless sudo setup
- Git installation
- Now Python-based for better maintainability

✅ **`mlc open` behavior**
- Auto-start if stopped
- Auto-stop when no sessions active
- Simple `docker exec` entry
- Unchanged from v1

✅ **Interactive mode (NEW in v2)**
- Guided container creation workflow
- Could be useful for educational purposes in DS01 ( I think ds01 does this better though; more robust)

### 5.2 What DS01 Must Continue to Add/Replace (unchanged from v1)

🔧 **Custom image support**
- Accept user-built images (not just framework catalog)
- Allow Dockerfile-based customization
- DS01's `image-create` & `image-update` workflow

🔧 **Resource limits**
- CPU/memory/GPU quotas from `resource-limits.yaml`
- Cgroup integration via systemd slices
- Fair scheduling enforcement

🔧 **GPU allocation**
- MIG-aware allocation via `gpu_allocator.py`
- Priority-based scheduling
- State tracking (`gpu-state.json`)

🔧 **Package customization**
- Tier package selection (Framework → Base Data Science defaults → Use case -> user-specified) - TAKE THIS FROM DS01 AS PRESENTLY IMPLEMENTED IN THE GUI
- Dockerfile generation
- Image build workflow with `image-create`

🔧 **Lifecycle automation**
- Idle detection and auto-cleanup
- Monitoring and metrics collection
- Container lifecycle policies

---

## 6. Critical Code Sections for Patching (v2)

**v2 Architecture Change:** AIME is now Python-based, so patching approach differs from v1.

### 6.1 Current DS01 Wrapper Strategy (continues to work with v2)

**DS01's current approach:**
```bash
# /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh
# Wraps the mlc create command (now calls mlc.py)

# 1. Get resource limits from DS01 config
RESOURCE_LIMITS=$(python3 get_resource_limits.py $USER --docker-args)

# 2. Allocate GPU using DS01's allocator
GPU_ALLOCATION=$(python3 gpu_allocator.py allocate ...)

# 3. Call original mlc create with modifications
# (then apply additional limits via docker update)
```

**This wrapper strategy still works with v2** because:
- `mlc create` still accepts same arguments
- Still creates containers in stopped state
- DS01 can still apply limits after creation via `docker update`

### 6.2 No Changes Needed for v2 Integration

**Current wrapper approach continues to work:**
- ✅ Wrapper intercepts `mlc create` call
- ✅ Calls `get_resource_limits.py` to read YAML config
- ✅ Calls `gpu_allocator.py` to assign GPU
- ✅ Invokes original AIME create (now Python-based)
- ✅ Applies additional limits via `docker update`

**Benefits of v2 Python implementation:**
- More maintainable AIME codebase
- Better error handling
- Interactive mode (could be useful)
- No breaking changes for DS01 integration

---

## 7. Integration Strategy for v2 (UPDATED)

### Current Approach: Wrapper Strategy (CONTINUES TO WORK)

**DS01's current wrapper strategy remains valid with v2:**

✅ **Wrapper intercepts AIME commands**
- `mlc-create-wrapper.sh` wraps `mlc create`
- `mlc-stats-wrapper.sh` wraps `mlc stats`
- `container-run` calls `mlc open` directly (no wrapper needed)

✅ **DS01 adds resource management layer**
- Reads `resource-limits.yaml` via `get_resource_limits.py`
- Allocates GPUs via `gpu_allocator.py`
- Applies limits via `docker update` after AIME creation

✅ **No changes needed for v2 upgrade**
- Python backend is transparent to wrappers
- Same command-line interface
- Same container creation workflow
- Better maintainability from AIME's Python rewrite

### Future Enhancement Opportunities

**v2 opens new possibilities:**

1. **Interactive mode integration**
   - Could adapt AIME's interactive mode for DS01's `user-setup` 
   - Educational prompts for framework selection
   - Currently DS01 has its own interactive workflows
   - (DS01 IS ALREADY VERY INTERACTIVE, JUST TAKE WHAT'S THERE WITH ALL THE GUIs AND ADAPT IT TO INTEGRATE PROPERLY WITH AIME!)

2. **Architecture flexibility**
   - Support for AMD GPUs via ROCM images
   - Easy switching between GPU architectures
   - Could be useful for multi-GPU-type clusters
   - EDIT: NOT NEEDED, I HAVE A100S ONLY

3. **Models directory support**
   - Container version 4 adds `/models` mount point
   - Could separate code, data, and models more cleanly
   - Consider updating DS01 workflows to use this!

---

## 8. Testing v2 Integration

**Verify current wrappers work with v2:**

1. ✅ **Test wrapper with framework from catalog**
   ```bash
   /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh test1 pytorch 2.7.1
   # Should work with new Python backend
   ```

2. ✅ **Verify resource limits applied**
   ```bash
   docker inspect test1 | grep -i cpus
   docker inspect test1 | grep -i memory
   # Should show limits from resource-limits.yaml
   ```

3. ✅ **Check GPU allocation**
   ```bash
   python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status
   # Should show GPU assigned to test1
   ```

4. ✅ **Test mlc open integration**
   ```bash
   /opt/ds01-infra/scripts/user/container-run test1
   # Should call mlc open correctly (now Python-based)
   ```

5. ✅ **Verify labels compatibility**
   ```bash
   docker inspect test1 --format '{{json .Config.Labels}}' | jq | grep aime.mlc
   # Should show MLC_VERSION=4, models mount
   ```

---

## 9. Conclusion

### AIME v2 Limitations (unchanged from v1)
- ❌ No custom image support
- ❌ No resource limits
- ❌ No GPU management
- ❌ No package customization workflow
- ❌ No state management

### v2 Impact on DS01

**⚠️ NO ACTION REQUIRED:**
- Current integration strategy remains optimal
- Wrappers don't need updates for v2
- DS01 resource management layer unchanged

## 10. v1 → v2 Migration Checklist

**For existing DS01 deployments:**

- [x] Update aime-ml-containers submodule to v2 commit
- [x] Update audit documentation (this file)
- [ ] Test `mlc-create-wrapper.sh` with v2 backend
- [ ] Test `mlc-stats-wrapper.sh` with v2 backend
- [ ] Test `container-run` → `mlc open` integration
- [ ] Verify resource limits still applied correctly
- [ ] Verify GPU allocation still works
- [ ] Check all labels (MLC_VERSION should be 4)
- [ ] Update symlinks if needed (v2 adds mlc-export, mlc-import)

**No code changes expected** - wrapper strategy is version-agnostic.
