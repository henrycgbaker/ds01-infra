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

**TIER 1: Base System** (`aime-ml-containers` v1 at `/opt/aime-ml-containers`)
- **9 Core Commands**: `mlc-create`, `mlc-open`, `mlc-list`, `mlc-stats`, `mlc-start`, `mlc-stop`, `mlc-remove`, `mlc-update-sys`, `mlc-upgrade-sys`
- **Container Image Repository**: Framework versions (PyTorch, TensorFlow, MXNet) via `ml_images.repo`
- **Container Lifecycle**: Creation, starting, stopping, removal with framework-focused workflow
- **Naming Convention**: `$CONTAINER_NAME._.$USER_ID` for multi-user isolation
- **Label System**: Uses `aime.mlc.*` labels for container identification

**DS01 Usage of Base System (3 of 9 commands):**
- ✅ **`mlc-create`** - WRAPPED by `/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh`
  - Adds: Resource limits from YAML, GPU allocation, systemd slice integration
  - Called by: `container-create`
- ✅ **`mlc-open`** - CALLED DIRECTLY by `container-run`
  - Works perfectly as-is (uses `docker exec`, auto-starts container)
  - No wrapping needed
- ✅ **`mlc-stats`** - WRAPPED by `/opt/ds01-infra/scripts/monitoring/mlc-stats-wrapper.sh`
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
- **Container Management** (7 commands): `container-create`, `container-run`, `container-stop`, `container-list`, `container-stats`, `container-cleanup`, `container-exit`
  - `container-create` → calls `mlc-create-wrapper.sh`
  - `container-run` → calls `mlc-open`
  - Others use Docker API directly for fine-grained DS01 control
- **Image Management** (4 commands): `image-create`, `image-list`, `image-update`, `image-delete`
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

1. User runs `mlc-create` (wrapper) or `ds01-run`
2. `get_resource_limits.py` reads user's group/overrides from YAML
3. Wrapper calls `gpu_allocator.py allocate <user> <container> <max_gpus> <priority>`
4. Allocator checks:
   - User's current GPU count vs limit
   - Active reservations (user_overrides with reservation_start/end)
   - Available GPUs/MIG instances
5. Allocator scores GPUs by (priority_diff, container_count, memory_percent)
6. Best GPU is allocated, state saved to `/var/lib/ds01/gpu-state.json`
7. Container launched with `--gpus device=X` or `--gpus device=X:Y` (MIG)

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

**Cleanup:**
- Manual: `mlc-remove <name>` (from base system)
- Automatic: `cleanup-idle-containers.sh` stops containers exceeding idle_timeout
- GPU release: `gpu_allocator.py release <container>` updates state

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
