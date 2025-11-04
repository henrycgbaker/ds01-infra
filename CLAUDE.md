# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

DS01 Infrastructure is a GPU-enabled container management system for multi-user data science workloads. It provides resource quotas, MIG (Multi-Instance GPU) support, priority-based allocation, and automatic lifecycle management on top of the base `aime-ml-containers` system.

**Key capabilities:**
- Dynamic MIG-aware GPU allocation with priority levels
- Per-user/group resource limits enforced via systemd cgroups and YAML config
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection for GPU/CPU/memory usage

## Architecture

### Three-Layer Design

1. **Base System**: `aime-ml-containers` (external dependency at `/opt/aime-ml-containers`)
   - Provides core `mlc-*` CLI commands (`mlc-create`, `mlc-open`, `mlc-list`, etc.)
   - Handles container image repository and basic lifecycle

2. **Enhancement Layer**: `ds01-infra` (this repository)
   - Wraps base system with resource limit enforcement
   - Manages GPU allocation state and reservations
   - Implements systemd cgroup slices per user group

3. **User Interface**: Enhanced CLI commands
   - `mlc-create-wrapper.sh`: Wraps original `mlc-create` with automatic resource limits
   - `ds01-run`: Standalone launcher with resource enforcement
   - `ds01-status`: System-wide resource usage dashboard
   - User-facing scripts: `container-*` commands for simplified management

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

# Deploy config file changes (no root required)
# Edit config/resource-limits.yaml, changes take effect on next container creation

# Manually update systemd slices after config changes
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload

# Install wrapper scripts (makes enhanced commands available system-wide)
sudo ln -sf /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh /usr/local/bin/mlc-create
sudo ln -sf /opt/ds01-infra/scripts/user/ds01-run /usr/local/bin/ds01-run
sudo ln -sf /opt/ds01-infra/scripts/user/ds01-status /usr/local/bin/ds01-status
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
│   ├── container-*                    # Simplified container management commands
│   ├── image-*                        # Image management commands
│   ├── ds01-run                       # Standalone container launcher
│   ├── ds01-status                    # Resource usage dashboard
│   └── student-setup.sh               # Interactive onboarding wizard
├── system/              # System administration
│   └── setup-resource-slices.sh       # Creates systemd cgroup slices
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

## Dependencies

**System packages (must be installed on server):**
- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- yq (YAML parser for bash scripts)
- systemd (for cgroup slices)
- nvidia-smi (GPU monitoring)

**Base system:**
- `aime-ml-containers` at `/opt/aime-ml-containers`
- Original `mlc-create` script must be functional

**Python packages:**
- PyYAML (for config parsing)
- Standard library only (subprocess, json, datetime, pathlib)
