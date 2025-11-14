# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Instructions for Claude
- be concise.
- there's no need to produce audit.md docs, or sumary.md docs etc (unless explicitly asked).
- check/ideate/plan with user in-chat, but once clear TODO is ready just move directly the code implementations, update CLAUDE.md if necessary (and only produce further documentation requested if requested). No need to produce multiple documents for each piece of work!

## Overview

DS01 Infrastructure is a GPU-enabled container management system for multi-user data science workloads. It provides resource quotas, MIG (Multi-Instance GPU) support, priority-based allocation, and automatic lifecycle management on top of the base `aime-ml-containers` system.

**Key capabilities:**
- Dynamic MIG-aware GPU allocation with priority levels
- Per-user/group resource limits enforced via systemd cgroups and YAML config
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection for GPU/CPU/memory usage

## Architecture

### Four-Tier Hierarchical Design

**TIER 1: Base System** (`aime-ml-containers` **v2** at `/opt/aime-ml-containers`)
- **11 Core Commands**: `mlc create`, `mlc open`, `mlc list`, `mlc stats`, `mlc start`, `mlc stop`, `mlc remove`, `mlc export`, `mlc import`, `mlc update-sys`, `mlc -v/--version`
- **Python-based**: All logic in `mlc.py` (~2,400 lines), commands are thin wrappers
- **Container Image Repository**: 150+ framework versions (PyTorch, Tensorflow) via `ml_images.repo`
  - **Architectures**: CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
  - **Latest versions**: PyTorch 2.8.0, Tensorflow 2.16.1
- **Container Lifecycle**: Creation, starting, stopping, removal with framework-focused workflow
- **Naming Convention**: `$CONTAINER_NAME._.$USER_ID` for multi-user isolation
- **Label System**: Uses `aime.mlc.*` labels for container identification (v4: adds models directory)

**DS01 Integration with AIME v2:**
- ✅ **`mlc-patched.py`** - DS01-ENHANCED version of AIME's mlc.py
  - Location: `/opt/ds01-infra/scripts/docker/mlc-patched.py`
  - **Preserves 97.5%** of AIME v2 logic unchanged
  - **Adds:** `--image` flag for custom Docker images (bypasses catalog)
  - **Adds:** DS01 labels (`aime.mlc.DS01_MANAGED`, `aime.mlc.CUSTOM_IMAGE`)
  - **Adds:** Local image check (prevents pulling custom images from Docker Hub)
  - **Wrapped by:** `mlc-create-wrapper.sh` (adds resource limits, GPU allocation)
  - **Called by:** `container-create`
  - **Tested:** E2E workflow verified (Nov 13, 2025)
- ✅ **`mlc open`** - CALLED DIRECTLY by `container-run`
  - Works perfectly as-is (uses `docker exec`, auto-starts container)
  - Compatible with both AIME catalog and DS01 custom images
- ✅ **`mlc stats`** - WRAPPED by `/opt/ds01-infra/scripts/monitoring/mlc-stats-wrapper.sh`
  - Adds: GPU process information, resource limit display
  - Called by: `container-stats`

**DS01 Does NOT Use (6 of 9 commands - built custom alternatives):**
- ❌ **`mlc-list`** → DS01's `container-list` uses `docker ps` directly
  - Why: Needs DS01-specific labels (`ds01.*`), custom formatting, project names
- ❌ **`mlc-stop`** → DS01's `container-stop` uses `docker stop` directly
  - Why: Custom warnings, force/timeout options, process count display
- ❌ **`mlc-remove`** → DS01's `container-cleanup` uses `docker rm` directly
  - Why: Bulk operations, GPU state cleanup, safety checks
- ❌ **`mlc-start`** → DS01 uses `docker start` directly when needed
  - Why: Rarely used (container-run handles starting via mlc-open)
- ❌ **`mlc-update-sys`, `mlc-upgrade-sys`** → Not applicable to DS01

**Why Strategic Usage:**
DS01 uses MLC where it excels (framework management, entering containers) and builds custom where needs differ (resource quotas, GPU scheduling, bulk operations, educational features). See `/opt/ds01-infra/docs/COMMAND_LAYERS.md` for complete details.

- ✅ **Symlinks configured** in `/usr/local/bin/` for 2 wrapped commands

**TIER 2: Modular Unit Commands** (Single-purpose, reusable)
- **Container Management** (8 commands): `container-create`, `container-run`, `container-start`, `container-stop`, `container-list`, `container-stats`, `container-cleanup`, `container-exit`
  - `container-create` → calls `mlc-create-wrapper.sh` → `mlc-patched.py`
  - `container-run` → calls `mlc-open`
  - `container-start` → calls `mlc-start` (NEW - Nov 2025)
  - `container-stop` → calls `mlc-stop` (refactored Nov 2025)
  - `container-list` → calls `mlc-list` (refactored Nov 2025)
  - `container-cleanup` → calls `mlc-remove` + GPU cleanup (refactored Nov 2025)
  - `container-stats` → calls `mlc-stats-wrapper.sh`
  - All wrap AIME Tier 1 commands with DS01 UX (interactive GUI, --guided mode, GPU management)
- **Image Management** (4 commands): `image-create`, `image-list`, `image-update`, `image-delete`
  - `image-create` → 4-phase workflow (Framework, Jupyter, Data Science, Use Case)
  - `image-update` → categorized package display (Jupyter, Data Science, Use Case, Custom)
  - Both show AIME base contents before prompting for additions
  - **Package versioning**: Supports pip version specifiers (e.g., `pandas`, `pandas==1.5.3`, `pandas>=2.0.0`, `pandas~=1.5.0`)
- **Project Setup Modules** (5 commands): `dir-create`, `git-init`, `readme-create`, `ssh-setup`, `vscode-setup`
- **All support `--guided` flag** for educational mode with detailed explanations

**TIER 3: Workflow Orchestrators** (Multi-step workflows)
- **`project-init`**: Complete project setup workflow
  - Orchestrates: dir-create → git-init → readme-create → image-create → container-create → container-run
  - Eliminated 561 lines of duplication (58.5% reduction from original)
- **Command Dispatchers**: Route flexible command syntax
  - `container-dispatcher.sh`, `image-dispatcher.sh`, `project-dispatcher.sh`, `user-dispatcher.sh`
  - Support both forms: `command subcommand` and `command-subcommand`

**TIER 4: Workflow Wizards** (Complete onboarding experiences)
- **`user-setup`**: Educational first-time user onboarding
  - Orchestrates: ssh-setup → project-init → vscode-setup
  - 69.4% reduction from original (932 → 285 lines)
  - Target: Students new to Docker/containers
- Command variants: `user-setup`, `user setup`, `new-user`

**Enhancement Layer (DS01-specific):**
- Resource limit enforcement via YAML config
- GPU allocation state management and MIG support
- Systemd cgroup slices per user group
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection
- **Custom image workflow** built on AIME v2 base images

### AIME v2 Integration Strategy

**Problem Solved:** AIME v2's `mlc.py` only accepts framework+version from catalog, not custom images.

**Solution:** `mlc-patched.py` - A minimally modified version (2.5% change):
- Adds `--image` flag to bypass catalog and accept custom Docker images
- Validates image exists locally before container creation
- Preserves all AIME v2 container setup (UID/GID matching, labels, volumes)
- **97.5% of AIME logic unchanged** - easy to update with future AIME releases

**Custom Image Workflow (4-Phase):**
```
1. image-create my-project
   ↓
   Phase 1: Framework Selection
     → PyTorch (latest from AIME catalog)
     → Displays: aimehub/pytorch-2.8.0-aime-cuda12.6.3
     → Shows AIME base packages (torch, numpy, conda, etc.)
   ↓
   Phase 2: Core Python & Jupyter
     → jupyter, jupyterlab, ipykernel, ipywidgets (5 packages)
     → Default: Install (recommended)
   ↓
   Phase 3: Core Data Science
     → pandas, scipy, scikit-learn, matplotlib, seaborn (5 packages)
     → Default: Install (recommended)
   ↓
   Phase 4: Use-Case Specific
     → Computer Vision, NLP, RL, General ML, or Custom
     → Adds domain-specific packages
   ↓
   Generates Dockerfile:
     FROM aimehub/pytorch-2.8.0-aime-cuda12.6.3  # AIME base
     RUN pip install jupyter jupyterlab ...       # Phase 2: Jupyter
     RUN pip install pandas scipy ...             # Phase 3: Data Science
     RUN pip install timm opencv-python ...       # Phase 4: Use Case
     # Custom additional packages                 # Phase 5: User additions
   ↓
   Builds: my-project-{username}
   ↓
   Suggests: container-create my-project (doesn't auto-call)

2. container-create my-project
   ↓
   Selects existing image: my-project-{username}
   ↓
   mlc-create-wrapper.sh calls mlc-patched.py:
     python3 mlc-patched.py create my-project pytorch \
             --image my-project-{username} \         # Custom image
             -s -w ~/workspace
   ↓
   mlc-patched.py creates container with:
     - AIME setup (user creation, labels, volumes)
     - DS01 labels (DS01_MANAGED, CUSTOM_IMAGE)
   ↓
   wrapper applies resource limits via docker update
   ↓
   Container ready: AIME base + DS01 packages + Resource limits + GPU
   ↓
   Suggests: container-run my-project (doesn't auto-call)
```

**Key Benefit:** Users get AIME's 150+ pre-tested framework images PLUS DS01's package customization.

**Documentation:**
- Strategy: `/opt/ds01-infra/docs/MLC_PATCH_STRATEGY.md`
- Test Results: `/opt/ds01-infra/docs/INTEGRATION_TEST_RESULTS.md`

### Core Components

**Resource Management:**
- `config/resource-limits.yaml`: Central configuration defining defaults, groups, user overrides, and policies
- `scripts/docker/get_resource_limits.py`: Python parser that reads YAML and returns per-user limits
- `scripts/docker/gpu_allocator.py`: Stateful GPU allocation manager with priority-aware scheduling

**GPU Allocation Strategy:**
- MIG instances tracked separately from physical GPUs (e.g., GPU 0 split into `0:0`, `0:1`, `0:2`)
- Priority-based allocation: user_overrides (100) > admin (90) > researcher (50) > student (10)
- Least-allocated strategy: prefers GPUs with fewest containers and lowest priority users
- Reservations: Time-based GPU reservations via `user_overrides` in YAML

**Systemd Integration:**
- `scripts/system/setup-resource-slices.sh`: Creates systemd slices from YAML config
- Hierarchy: `ds01.slice` → `ds01-{group}.slice` → containers
- Enforces CPU quotas, memory limits, and task limits at cgroup level

**State Management:**
- GPU state: `/var/lib/ds01/gpu-state.json` (JSON file tracking allocations)
- Container metadata: `/var/lib/ds01/container-metadata/{container}.json`
- Allocation logs: `/var/logs/ds01/gpu-allocations.log`

**User Onboarding:**
- `scripts/user/user-setup` - Educational onboarding wizard (accessible via `new-user`, `user-setup`, `user setup`, `user new`)
- `scripts/user/new-project` - Streamlined project setup (accessible via `new-project`, `project init`)
- `scripts/user/user-dispatcher.sh` - Routes `user <subcommand>` to appropriate scripts
- `scripts/user/project-init` - Wrapper that executes `new-project`

### User Onboarding Workflows

DS01 provides two onboarding experiences with distinct purposes:

**`user-setup` (new-user) - Educational**:
- Target: First-time users, students new to Docker/containers
- Style: Comprehensive with detailed explanations of Docker concepts
- Features: SSH setup, Git/LFS integration, project structure options, Docker image creation, container setup
- Image naming: `{project}-image` (e.g., `my-thesis-image`)
- Use cases: 5 options with General ML as default (option 1)
- README generation: Comprehensive with workflow documentation
- Command variants: `new-user`, `user-setup`, `user setup`, `user new`

**`new-project` - Streamlined**:
- Target: Experienced users familiar with the system
- Style: Concise, minimal explanations
- Features: Same technical capabilities, efficient prompts
- Use when: Creating additional projects, user already onboarded
- Command variants: `new-project`, `project init`

**Key Conventions**:
- Image naming: Always `{project}-image` (not `{username}-{project}`)
- Docker group: Use standard `docker` group for Docker socket access
- Use case order: General ML, Computer Vision, NLP, RL, Custom
- Color output: All scripts use `echo -e` for ANSI color codes
- Shebang: Must be on line 1 (#!/bin/bash)

### Important Paths

Standard deployment paths (when installed on server):
- Config: `/opt/ds01-infra/config/resource-limits.yaml`
- Scripts: `/opt/ds01-infra/scripts/`
- State: `/var/lib/ds01/`
- Logs: `/var/logs/ds01/`
- **Dockerfiles**: `~/dockerfiles/` (centralized, per-user)
  - Alternative: `~/workspace/<project>/Dockerfile` (with `--project-dockerfile` flag)

Config mirrors for system files (deployed separately):
- `config/etc-mirrors/systemd/system/` → `/etc/systemd/system/`
- `config/etc-mirrors/cron.d/` → `/etc/cron.d/`
- `config/etc-mirrors/logrotate.d/` → `/etc/logrotate.d/`

## Common Commands

### Development/Testing

```bash
# Test resource limit parser for a user
python3 scripts/docker/get_resource_limits.py <username>
python3 scripts/docker/get_resource_limits.py <username> --docker-args
python3 scripts/docker/get_resource_limits.py <username> --group

# Test GPU allocator
python3 scripts/docker/gpu_allocator.py status
python3 scripts/docker/gpu_allocator.py allocate <user> <container> <max_gpus> <priority>
python3 scripts/docker/gpu_allocator.py user-status <user>
python3 scripts/docker/gpu_allocator.py release <container>

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

### Deployment (Server-Side)

```bash
# Initial setup (requires root)
sudo scripts/system/setup-resource-slices.sh

# Create command symlinks (makes commands available system-wide)
sudo scripts/system/update-symlinks.sh

# Add users to docker group
sudo scripts/system/add-user-to-docker.sh <username>

# Deploy config file changes (no root required)
# Edit config/resource-limits.yaml, changes take effect on next container creation

# Manually update systemd slices after config changes
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

### Monitoring

```bash
# GPU allocation status
python3 scripts/monitoring/gpu-status-dashboard.py

# Container-level resource usage
scripts/monitoring/container-dashboard.sh

# Check idle containers (for cleanup eligibility)
scripts/monitoring/check-idle-containers.sh

# System-wide status
scripts/user/ds01-status

# View allocation logs
tail -f /var/logs/ds01/gpu-allocations.log
```

### User Management

```bash
# Add user to a group (edit config file)
vim config/resource-limits.yaml
# Add username to groups.<group>.members array

# Create user override (temporary high-priority allocation)
vim config/resource-limits.yaml
# Add entry under user_overrides with desired limits + priority

# View user's current allocations
python3 scripts/docker/gpu_allocator.py user-status <username>
```

## YAML Configuration Structure

`config/resource-limits.yaml` has the following priority order (highest to lowest):
1. `user_overrides.<username>` - Per-user exceptions (priority 100)
2. `groups.<group>` - Group-based limits (priority varies)
3. `defaults` - Fallback for any unspecified fields

**Key fields:**
- `max_mig_instances`: Max simultaneous MIG instances (or GPUs) per user
- `max_cpus`, `memory`, `shm_size`: Per-container compute limits
- `max_containers_per_user`: Max simultaneous containers
- `idle_timeout`: Auto-stop after X hours of GPU inactivity (e.g., "48h")
- `gpu_hold_after_stop`: How long to hold GPU after container stopped (e.g., "24h", null = indefinite)
- `priority`: Allocation priority (1-100, higher = more priority)
- `max_tasks`: Systemd task limit for the group's cgroup slice

**Special values:**
- `null` for max_mig_instances = unlimited (admin only)
- `null` for idle_timeout = no timeout
- MIG vs full GPU: determined by MIG partition size in `gpu_allocation.mig_profile`

## MIG (Multi-Instance GPU) Configuration

MIG is configured in `gpu_allocation` section:
- `enable_mig: true` - Enables MIG tracking
- `mig_profile: "2g.20gb"` - Profile type (3 instances per A100)
- Allocation tracks MIG instances as `"physical_gpu:instance"` (e.g., `"0:0"`, `"0:1"`)

GPU allocator (`gpu_allocator.py`) auto-detects MIG instances via `nvidia-smi mig -lgi`.

## Script Organization

```
scripts/
├── docker/              # Container creation and GPU allocation
│   ├── mlc-create-wrapper.sh          # Enhanced mlc-create with resource limits
│   ├── get_resource_limits.py         # YAML parser for user limits
│   ├── gpu_allocator.py               # MIG-aware GPU allocation manager
│   └── container-startup.sh           # Container initialization hooks
├── user/                # User-facing utilities
│   ├── user-setup                     # Educational onboarding wizard (new-user)
│   ├── new-project                    # Streamlined project setup
│   ├── user-dispatcher.sh             # Routes 'user <subcommand>' to scripts
│   ├── project-init                   # Wrapper that executes new-project
│   ├── container-*                    # Simplified container management commands
│   ├── image-*                        # Image management commands
│   ├── ds01-run                       # Standalone container launcher
│   └── ds01-status                    # Resource usage dashboard
├── system/              # System administration
│   ├── setup-resource-slices.sh       # Creates systemd cgroup slices
│   ├── add-user-to-docker.sh          # Add users to docker-users group
│   └── update-symlinks.sh             # Update command symlinks in /usr/local/bin
├── monitoring/          # Metrics and auditing
│   ├── gpu-status-dashboard.py        # GPU allocation report generator
│   ├── check-idle-containers.sh       # Identifies idle containers for cleanup
│   ├── collect-*-metrics.sh           # Metric collection (GPU, CPU, memory, disk)
│   └── audit-*.sh                     # System/container/docker auditing
├── maintenance/         # Cleanup and housekeeping
│   └── cleanup-idle-containers.sh     # Auto-stop idle containers
└── backup/              # Backup scripts
```

## Important Implementation Details

### GPU Allocation Flow

**On Container Creation:**
1. User runs `mlc-create` (wrapper) or `ds01-run`
2. `get_resource_limits.py` reads user's group/overrides from YAML
3. Wrapper calls `gpu_allocator.py allocate <user> <container> <max_gpus> <priority>`
4. Allocator checks:
   - User's current GPU count vs limit
   - Active reservations (user_overrides with reservation_start/end)
   - Available GPUs/MIG instances
5. Allocator scores GPUs by (priority_diff, container_count, memory_percent)
6. Best GPU is allocated, state saved to `/var/lib/ds01/gpu-state.json`
7. Container metadata saved with allocation timestamp
8. Container launched with `--gpus device=X` or `--gpus device=X:Y` (MIG)

**On Container Stop:**
1. User runs `container-stop <name>`
2. Container stopped via `mlc-stop`
3. `gpu_allocator.py mark-stopped <container>` called
4. Stopped timestamp recorded in metadata (`/var/lib/ds01/container-metadata/<container>.json`)
5. GPU remains allocated, hold timer starts
6. User shown warning about GPU hold time and cleanup option

**On Container Restart:**
1. User runs `container-run <name>`
2. Container starts via `mlc-open`
3. GPU allocator clears `stopped_at` timestamp
4. GPU allocation continues normally

**Automatic GPU Release (Stale Cleanup):**
1. Cron job runs hourly: `/opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh`
2. Calls `gpu_allocator.py release-stale`
3. For each stopped container:
   - Checks if container still exists (releases if deleted)
   - Checks if container restarted (clears stopped timestamp)
   - Compares elapsed time vs `gpu_hold_after_stop` from config
   - Releases GPU if hold timeout exceeded
4. Logs releases to `/var/log/ds01/gpu-stale-cleanup.log`

**Manual GPU Release:**
1. User runs `container-cleanup <name>`
2. Container removed via `mlc-remove`
3. `gpu_allocator.py release <container>` called
4. GPU immediately freed, metadata deleted

### Resource Limit Application

**At creation time:**
- `mlc-create-wrapper.sh` passes resource args to original `mlc-create`
- Some limits (cpus, memory, pids) applied via `docker update` post-creation
- shm-size must be set at creation (cannot be updated after)

**At runtime:**
- Systemd cgroups enforce slice-level quotas (CPUs, memory, tasks)
- Containers run with `--cgroup-parent=ds01-{group}.slice`

### Container Lifecycle

**Creation:**
1. Wrapper validates name, workspace, framework
2. Checks for existing container with same name
3. Calls original `mlc-create` from aime-ml-containers
4. Applies resource limits via `docker update`
5. Stops container (user starts it later with `mlc-open`)

**Monitoring:**
- Cron jobs run metric collection scripts every 5 minutes
- `check-idle-containers.sh` detects containers with no GPU activity
- Idle timeout enforced by `cleanup-idle-containers.sh` (runs daily)
- Stale GPU cleanup runs hourly via `cleanup-stale-gpu-allocations.sh`

**Cleanup:**
- Manual container removal: `container-cleanup <name>` (releases GPU immediately)
- Automatic idle stop: `cleanup-idle-containers.sh` stops containers exceeding idle_timeout (GPU held per config)
- Automatic GPU release: `cleanup-stale-gpu-allocations.sh` releases GPUs after hold timeout
- Manual GPU release: `gpu_allocator.py release <container>` updates state

## Testing Changes

When modifying resource allocation logic:

1. **YAML changes**: Test with multiple user types
   ```bash
   for user in student1 researcher1 datasciencelab; do
       python3 scripts/docker/get_resource_limits.py $user
   done
   ```

2. **GPU allocator changes**: Use dry-run mode
   ```bash
   python3 scripts/docker/gpu_allocator.py status
   python3 scripts/docker/gpu_allocator.py allocate testuser testcontainer 1 10
   python3 scripts/docker/gpu_allocator.py release testcontainer
   ```

3. **Wrapper changes**: Use `--dry-run` flag
   ```bash
   scripts/docker/mlc-create-wrapper.sh test-container pytorch --dry-run
   ```

4. **Systemd slice changes**: Verify slice creation
   ```bash
   sudo scripts/system/setup-resource-slices.sh
   systemctl status ds01.slice
   systemd-cgtop | grep ds01
   ```

## Security Considerations

- User isolation: Containers run with user's UID/GID (handled by aime-ml-containers)
- GPU pinning: Enforced via `--gpus device=X` to prevent cross-user GPU access
- Cgroup limits: Prevent resource exhaustion via systemd slices
- Workspace permissions: Each user's workspace is mounted read-write only to their containers

**Do not:**
- Store secrets in YAML config (config is readable by all users)
- Allow users to override cgroup-parent (bypasses resource limits)
- Disable GPU device isolation in production

## Codebase Conventions

- **Bash scripts**: Use `set -e` (exit on error), include usage functions
- **Python scripts**: Use argparse or manual CLI parsing, provide `main()` function
- **YAML config**: Use `null` for unlimited/disabled, include comments for complex sections
- **Logging**: Structured logs with pipe-delimited format: `timestamp|event|user|container|gpu_id|reason`
- **Colors in output**: Use GREEN/YELLOW/RED variables, reset with NC (No Color)
- **Color rendering**: ALWAYS use `echo -e` for ANSI color codes (not plain `echo`)
- **Shebang**: Must be on line 1 (#!/bin/bash) with no leading whitespace or comments
- **Docker group**: Use standard `docker` group for Docker socket access
- **Image naming**: Always `{project}-image` format (e.g., `my-thesis-image`)
- **Command dispatchers**: Support both forms: `command subcommand` and `command-subcommand`
- **Flag conventions**: All commands support `-h`, `--help`, and `--info` for help; Tier 2 commands support `--guided`
- **Interactive selection**: Source `/opt/ds01-infra/scripts/lib/interactive-select.sh` for menu prompts when args missing

## Dependencies

**System packages (must be installed on server):**
- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- yq (YAML parser for bash scripts)
- systemd (for cgroup slices)
- nvidia-smi (GPU monitoring)
- git (for version control in projects)
- git-lfs (optional, for large file tracking)

**Base system:**
- `aime-ml-containers` at `/opt/aime-ml-containers`
- Original `mlc-create` script must be functional

**Python packages:**
- PyYAML (for config parsing)
- Standard library only (subprocess, json, datetime, pathlib)

**Groups:**
- `docker` group must exist for Docker permissions (standard Docker setup)
- Users must be added to `docker` group for Docker socket access

## Recent Changes (November 2025)

**GPU Hold After Stop - Hybrid Allocation Strategy (November 13, 2025):** ✅ **COMPLETE**
- **Problem**: GPUs were released immediately on container stop, forcing users to re-compete for allocation on restart
- **Solution**: Implemented hybrid strategy - hold GPU for configurable time after stop, then auto-release
- **Added** `gpu_hold_after_stop` parameter to `resource-limits.yaml`:
  - Students: 1h (default)
  - Researchers: 2h
  - Admins: 3h (configurable, can be set to `null` for indefinite hold)
- **Enhanced** `gpu_allocator.py` with timestamp tracking:
  - New `mark_stopped(container)` function - records stop timestamp in metadata
  - New `release_stale_allocations()` function - auto-releases GPUs after timeout expires
  - Handles edge cases: restarted containers (clears timestamp), deleted containers (immediate release)
  - Duration parsing: Supports `24h`, `48h`, `null` (indefinite) formats
- **Updated** `container-stop` script:
  - Calls `mark-stopped` after successful container stop
  - Shows GPU hold warning with user's specific timeout
  - Encourages cleanup to free GPU immediately (good citizenship message)
- **Created** automated cleanup infrastructure:
  - Script: `/opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh`
  - Cron job: `/etc/cron.d/ds01-gpu-cleanup` (runs hourly at :15 past the hour)
  - Logs to: `/var/log/ds01/gpu-stale-cleanup.log`
- **Updated** `get_resource_limits.py` to parse and display new parameter
- **Benefits**:
  - Users can restart containers without losing GPU allocation (within timeout window)
  - Fair sharing - GPUs automatically released if not restarted within timeout
  - Configurable per user group - admins get longer hold, students get shorter
  - Transparent - users see clear warnings about hold duration and cleanup options
- **Documentation**: Updated CLAUDE.md GPU allocation flow, monitoring, and cleanup sections

**Image Workflow Redesign (November 12, 2025):** ✅ **COMPLETE**
- **Redesigned** `image-create` with 4-phase package selection (Jupyter, Data Science, Use Case, Additional)
- **Added** `show_base_image_packages()` - displays what's pre-installed in AIME base images
- **Split** package functions: `get_jupyter_packages()` + `get_data_science_packages()`
- **Updated** `image-update` to match new package categorization
- **Fixed** Tier 2 isolation - removed all cross-calls between commands
  - `image-create` no longer calls `container-create` (suggests it instead)
  - `container-create` no longer calls `image-create` (suggests it instead)
- **Verified** orchestrators (`project-init`, `user-setup`) still work correctly
- **Key insight:** AIME base images are framework-focused (PyTorch + CUDA + minimal deps)
  - Only 8 key packages: conda, numpy, pillow, tqdm, torch, torchvision, torchaudio, ipython
  - Missing: jupyter, pandas, scipy, sklearn, matplotlib, seaborn, opencv, transformers
  - DS01's package installation workflow is ESSENTIAL (not redundant)

**AIME v2 Integration (November 12, 2025):** ✅ **COMPLETE**
- **Upgraded** from AIME v1 (bash-based) to AIME v2 (Python-based, 150+ images)
- **Created** `mlc-patched.py` - DS01-enhanced version of AIME's mlc.py
  - Adds `--image` flag for custom Docker images (bypasses catalog)
  - Preserves 97.5% of AIME v2 logic unchanged (~60 lines added to 2,400-line script)
  - Validates custom images exist before container creation
  - Adds DS01 labels: `aime.mlc.DS01_MANAGED`, `aime.mlc.CUSTOM_IMAGE`
- **Updated** `image-create` to use AIME v2 catalog (`ml_images.repo`)
  - Now looks up 150+ pre-built framework images (PyTorch 2.8.0, TensorFlow 2.16.1)
  - Supports CUDA_BLACKWELL, CUDA_ADA, CUDA_AMPERE, ROCM6, ROCM5
  - Dockerfiles: `FROM aimehub/pytorch-...` (AIME base) + DS01 packages
- **Updated** `mlc-create-wrapper.sh` to call `mlc-patched.py`
  - Changed: `bash mlc-create` → `python3 mlc-patched.py`
  - Passes `--image` flag when custom image exists
  - Maintains resource limits & GPU allocation integration
- **Tested** E2E on live GPU server - all integration points working
- **Key benefit:** Users get AIME's pre-tested images + DS01's package customization
- **Documentation:** `docs/MLC_PATCH_STRATEGY.md`, `docs/INTEGRATION_TEST_RESULTS.md`

**Tier 2 Command Refactor (November 12, 2025):** ✅ **COMPLETE**
- **Refactored 3 existing commands** to wrap AIME Tier 1:
  - `container-list` → now calls `mlc-list` for container discovery
  - `container-stop` → now calls `mlc-stop` for stopping containers
  - `container-cleanup` → now calls `mlc-remove` for removal + GPU state cleanup
  - All preserve DS01 UX: interactive GUI selection, --guided mode, colors, safety checks
  - Graceful fallback to docker commands if mlc-* unavailable
- **Created 1 new wrapper command**:
  - `container-start` → wraps `mlc-start` to start stopped containers
  - Interactive selection GUI when no args provided
  - --guided mode with layer architecture explanation
- **Architecture achieved**:
  - AIME Tier 1 (`mlc-*`) = Core container lifecycle operations
  - DS01 Tier 2 (`container-*`) = Lightweight wrappers adding DS01-specific UX
  - Design principle: Call AIME for core functionality, add DS01 value-adds (GPU management, interactive menus, safety checks)
- **Coverage**: 7/9 functional AIME commands now wrapped (100% of user-facing commands)
- **Skipped**: `mlc-export`/`mlc-import` (exist as wrappers but no Python implementation in AIME v2)
- **Documentation:** `docs/TODO_CONSOLIDATED.md` (TODO-14), updated `scripts/system/update-symlinks.sh`

**Dockerfile Storage & Phased Workflows (November 11, 2025):**
- **Directory Migration**: Renamed `~/docker-images/` → `~/dockerfiles/` for accurate terminology
  - Migration script: `/opt/ds01-infra/scripts/system/migrate-dockerfiles.sh`
  - Automatically updates metadata files with new paths
  - All existing images and containers continue to work
- **Phased Workflows**: Both `image-create` and `image-update` now have 3-phase interactive workflows:
  - **Phase 1**: Dockerfile created/updated
  - **Phase 2**: Build/Rebuild image? (user confirms)
  - **Phase 3**: Create/Recreate container? (user confirms)
  - Each phase can be skipped, allowing granular control
- **Hybrid Dockerfile Storage**:
  - Default: Centralized at `~/dockerfiles/` (one Dockerfile/image → many projects)
  - Optional: `--project-dockerfile` flag stores in `~/workspace/<project>/Dockerfile`
  - Clear separation: Dockerfile (recipe) → Image (blueprint) → Container (instance)
- **Terminology Audit**: Verified correct usage throughout:
  - Dockerfile = Recipe (text file with build instructions)
  - Image = Blueprint (built from Dockerfile, stored by Docker)
  - Container = Running instance (where actual work happens)
- **Scripts Updated**: `image-create`, `image-update`, `image-delete` use `DOCKERFILES_DIR`
- **Empty pip install Protection**: `image-update` now detects and removes empty RUN blocks to prevent build errors

**CLI Ecosystem Overhaul (November 10, 2025):**
- Added `--info` flag support: All dispatchers and Tier 2 commands now accept `--info` as alias for `--help`
- Completed `--guided` flag coverage: All 16 Tier 2 commands now support educational beginner mode
- New interactive GUI library: Commands prompt user to select containers/images when no argument provided
- Interactive selection: `image-update`, `image-delete`, `container-run`, `container-stop`, `container-cleanup`
- Deprecated redundant scripts: Moved `create-custom-image.sh`, `manage-images.sh`, `student-setup.sh` to `_deprecated/`
- Updated symlinks: Added 14 new commands (container-dashboard, gpu-dashboard, audit-*, etc.)
- Fixed documentation: Corrected alias-list errors, removed misleading Ctrl+P/Ctrl+Q references
- New shared library: `/opt/ds01-infra/scripts/lib/interactive-select.sh` for reusable selection functions

## Recent Changes (November 2025 - Previous)

**User Onboarding Overhaul:**
- New dual onboarding workflows: `user-setup` (educational) and `new-project` (streamlined)
- Command dispatcher pattern: `user setup`, `user new` route to appropriate scripts
- Flexible command syntax: support both `command subcommand` and `command-subcommand`
- Standardized Docker group: all scripts use `docker-users` (not `docker`)
- Consistent image naming: `{project}-image` format throughout
- General ML as default use case (option 1 in wizards)
- Fixed color code rendering: all scripts now use `echo -e` for ANSI codes

**New Scripts:**
- `scripts/system/add-user-to-docker.sh` - Helper for adding users to docker group
- `scripts/system/update-symlinks.sh` - Automates symlink management in /usr/local/bin
- `scripts/user/user-dispatcher.sh` - Routes user subcommands to appropriate scripts
- `scripts/user/new-project` - Streamlined project setup (renamed from new-project-setup)
- `scripts/user/user-setup` - Educational onboarding (renamed from new-user-setup.sh)

**Deleted Scripts:**
- `scripts/user/new-user-setup.sh` - Replaced by `user-setup`
- `scripts/user/new-project-setup` - Replaced by `new-project`

**Bug Fixes:**
- Fixed shebang placement (must be line 1, no preceding comments)
- Fixed all heredocs to use proper color code format
- Fixed Docker permission error handling in onboarding scripts
- Fixed success messages appearing on failed builds

**Major Refactoring (November 2025 - Phases 1-6):**
- **Phase 1 [NEW]**: Audited base system integration
  - Documented all 9 mlc-* commands and their DS01 integration
  - Verified actual usage: 3 of 9 commands used (1 wrapped, 1 called directly, 1 wrapped)
  - Confirmed 6 commands NOT used (DS01 built custom alternatives)
  - Created comprehensive documentation: `docs/COMMAND_LAYERS.md`
- **Phase 2**: Extracted modular commands
  - Created `dir-create`, `git-init`, `readme-create` from project-init
  - All new commands support --guided flag
- **Phase 3**: Added --guided flags across all commands
  - Enhanced educational content for beginners
  - Consistent --guided behavior throughout system
- **Phase 4**: Refactored orchestrators
  - Reduced `project-init` from 958 to 397 lines (58.5% reduction)
  - Eliminated 561 lines of duplicated code
  - Now calls Tier 2 modules instead of duplicating logic
- **Phase 5**: Created wizards
  - New `ssh-setup` and `vscode-setup` Tier 2 modules
  - Refactored `user-setup` from 932 to 285 lines (69.4% reduction)
  - Clean Tier 4 orchestrator pattern achieved
- **Phase 6**: Fixed exit functionality/documentation
  - Completely rewrote `container-exit` with accurate docker exec behavior
  - Removed all misleading Ctrl+P, Ctrl+Q references (doesn't work with docker exec)
  - Updated `container-aliases.sh` and `container-stop` with correct exit instructions
  - Added deprecation notices to legacy files (`new-project`, `project-init-beginner`)

**Results:**
- Total code reduction: >1,100 lines eliminated through modularization
- Zero code duplication: Single source of truth for each operation
- Enhanced user experience: Consistent --guided mode across all commands
- Accurate documentation: All exit behavior now correctly documented
- Clean architecture: Four-tier hierarchy (Base → Modules → Orchestrators → Wizards)
