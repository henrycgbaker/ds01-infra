# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Instructions for Claude
- Be concise
- No audit.md/summary.md docs unless explicitly requested
- If uncertain, strategise/discuss/plan in-chat, then implement directly
- Update CLAUDE.md if necessary, but don't create extra documentation unless requested
- When writing a test for a given piece of functionality, always store a copy in relevant `/testing` directory (even if just in `/testing/scratch`, so that it can be reused later as part of a robust testing regime)

## Overview

DS01 Infrastructure is a GPU-enabled container management system for multi-user data science workloads. Provides resource quotas, MIG support, priority-based allocation, and automatic lifecycle management on top of `aime-ml-containers`.

**Key capabilities:**
- Dynamic MIG-aware GPU allocation with priority levels
- Per-user/group resource limits via systemd cgroups and YAML config
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection

## Architecture

### Three-Tier Hierarchical Design

**TIER 1: Base System** (`aime-ml-containers` v2 at `/opt/aime-ml-containers`)
- 11 core commands: `mlc create|open|list|stats|start|stop|remove|export|import|update-sys|--version`
- Python-based (mlc.py ~2,400 lines), 150+ framework images (PyTorch 2.8.0, TensorFlow 2.16.1)
- Container naming: `$CONTAINER_NAME._.$USER_ID` (multi-user isolation)

**DS01 Integration:**
- ✅ **Used (7 commands)**: `mlc-patched.py` (create with --image flag), `mlc open` (direct), `mlc stats` (wrapped), `mlc list` (wrapped), `mlc stop` (wrapped), `mlc remove` (wrapped), `mlc start` (wrapped)
- ❌ **Not used (2 commands)**: `mlc export/import` (no Python implementation in AIME v2)
- All wrapped commands add DS01 UX: interactive GUI, --guided mode, GPU management, safety checks
- See `/opt/ds01-infra/docs/COMMAND_LAYERS.md` for details

**TIER 2: Modular Unit Commands** (Single-purpose, parallely-isolated & modular, reusable)
- **Container Management** (8): `container-{create|run|start|stop|list|stats|remove|exit}`
  - Wrap AIME commands with DS01 UX (interactive GUI, --guided mode, GPU management)
- **Image Management** (4): `image-{create|list|update|delete}`
  - 4-phase workflow: Framework → Jupyter → Data Science → Use Case
  - Shows AIME base packages, supports pip version specifiers
- **Project Setup** (5): `{dir|git|readme|ssh|vscode}-{create|init|setup}`
- All support `--guided` flag for educational mode

**TIER 3: Workflow Orchestrators** (Multi-step workflows)
- Dispatchers: Support both `command subcommand` and `command-subcommand` syntax
- `project-init`: dir-create → git-init → readme-create → image-create → container-create → container-run
- `user-setup` (Complete onboarding): Educational first-time onboarding (ssh-setup → project-init → vscode-setup)
   - Command variants: `user-setup`, `user setup`, `new-user`

**Enhancement Layer:**
- Resource limits via YAML + systemd cgroups
- GPU allocation state management (MIG support)
- Container lifecycle automation
- Monitoring and metrics

### AIME v2 Integration

**mlc-patched.py** - Minimal modification (2.5% change) to support custom images:
- Adds `--image` flag to bypass catalog
- Validates local image existence
- Adds DS01 labels (`DS01_MANAGED`, `CUSTOM_IMAGE`)
- 97.5% of AIME logic preserved (easy to upgrade)

**Naming Conventions:**
- Images: `ds01-{user-id}/{project-name}:latest`
- Containers: `{project-name}._.{user-id}` (AIME convention)
- Dockerfiles: `~/dockerfiles/{project-name}.Dockerfile`

**Workflow:** image-create (4 phases) → builds custom image → container-create → mlc-patched.py → resource limits → GPU allocation

### Core Components

**Resource Management:**
- `config/resource-limits.yaml` - Central config (defaults, groups, user_overrides, policies)
- `scripts/docker/get_resource_limits.py` - YAML parser
- `scripts/docker/gpu_allocator.py` - Stateful GPU allocation with priority scheduling

**GPU Allocation:**
- MIG instances tracked separately (e.g., `0:0`, `0:1`, `0:2`)
- Priority: user_overrides (100) > admin (90) > researcher (50) > student (10)
- Least-allocated strategy with time-based reservations

**Systemd Integration:**
- 3-tier hierarchy: `ds01.slice` → `ds01-{group}.slice` → `ds01-{group}-{username}.slice`
- Group slices enforce limits, user slices enable granular monitoring
- Scripts: `setup-resource-slices.sh` (group), `create-user-slice.sh` (per-user, auto-invoked)

**State Management:**
- GPU state: `/var/lib/ds01/gpu-state.json`
- Container metadata: `/var/lib/ds01/container-metadata/{container}.json`
- Logs: `/var/logs/ds01/gpu-allocations.log`

### Important Paths

**Standard deployment:**
- Config: `/opt/ds01-infra/config/resource-limits.yaml`
- Scripts: `/opt/ds01-infra/scripts/`
- State: `/var/lib/ds01/`
- Logs: `/var/logs/ds01/`
- Dockerfiles: `~/dockerfiles/` (or `~/workspace/<project>/` with --project-dockerfile)

**Config mirrors** (deployed separately):
- `config/etc-mirrors/systemd/system/` → `/etc/systemd/system/`
- `config/etc-mirrors/cron.d/` → `/etc/cron.d/`
- `config/etc-mirrors/logrotate.d/` → `/etc/logrotate.d/`

## Common Commands

### Development/Testing
```bash
# Test resource limits
python3 scripts/docker/get_resource_limits.py <username>
python3 scripts/docker/get_resource_limits.py <username> --docker-args

# Test GPU allocator
python3 scripts/docker/gpu_allocator.py status
python3 scripts/docker/gpu_allocator.py allocate <user> <container> <max_gpus> <priority>
python3 scripts/docker/gpu_allocator.py release <container>

# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

### Deployment
```bash
# Initial setup (requires root)
sudo scripts/system/setup-resource-slices.sh
sudo scripts/system/update-symlinks.sh
sudo scripts/system/add-user-to-docker.sh <username>

# Update systemd slices after config changes
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

### Monitoring
```bash
# System status
ds01-dashboard                                    # Admin dashboard
python3 scripts/docker/gpu_allocator.py status    # GPU allocation status
systemd-cgtop | grep ds01                         # Per-user cgroups

# Cron job logs (automated cleanup)
tail -f /var/log/ds01/idle-cleanup.log           # Idle timeout enforcement
tail -f /var/log/ds01/runtime-enforcement.log    # Max runtime enforcement
tail -f /var/log/ds01/gpu-stale-cleanup.log      # GPU release automation
tail -f /var/log/ds01/container-stale-cleanup.log # Container removal

# Allocation logs
tail -f /var/log/ds01/gpu-allocations.log        # GPU allocation events
```

## YAML Configuration

Priority order (highest to lowest):
1. `user_overrides.<username>` - Per-user exceptions (priority 100)
2. `groups.<group>` - Group-based limits (priority varies)
3. `defaults` - Fallback

**Key fields:**
- `max_mig_instances`: Max GPUs/MIG instances per user
- `max_cpus`, `memory`, `shm_size`: Per-container compute limits
- `max_containers_per_user`: Max simultaneous containers
- `idle_timeout`: Auto-stop after GPU inactivity (e.g., "48h")
- `gpu_hold_after_stop`: Hold GPU after stop (e.g., "24h", null = indefinite)
- `container_hold_after_stop`: Auto-remove container after stop (e.g., "12h", null = never)
- `priority`: Allocation priority (1-100)

**Special values:**
- `null` for max_mig_instances = unlimited (admin only)
- `null` for timeouts = disabled

## MIG Configuration

Configured in `gpu_allocation` section:
- `enable_mig: true` - Enables MIG tracking
- `mig_profile: "2g.20gb"` - Profile type (3 instances per A100)
- Tracked as `"physical_gpu:instance"` (e.g., `"0:0"`, `"0:1"`)
- Auto-detected via `nvidia-smi mig -lgi`

## GPU Allocation Flow

**Container Creation:**
1. `container-create` → `mlc-create-wrapper.sh`
2. `get_resource_limits.py` reads user limits from YAML
3. `gpu_allocator.py allocate` checks limits, reservations, availability
4. GPU allocated (least-allocated strategy), state saved
5. Container launched with `--gpus device=X` (or `device=X:Y` for MIG)

**Container Stop:**
1. `container-stop` → `mlc-stop`
2. `gpu_allocator.py mark-stopped` records timestamp
3. GPU held for `gpu_hold_after_stop` duration
4. Interactive prompt: "Remove container now?" (encourages cleanup)

**Automatic Cleanup (Cron-based):**
Cron jobs run as root and check ALL containers against each owner's specific resource limits:

1. **Max Runtime** (:45/hour) - `enforce-max-runtime.sh`
   - Stops containers exceeding owner's `max_runtime` limit
   - Warns at 90% of limit, stops at 100%

2. **Idle Timeout** (:30/hour) - `check-idle-containers.sh`
   - Stops containers idle (CPU < 1%) beyond owner's `idle_timeout`
   - Warns at 80% of idle time
   - Respects `.keep-alive` file to prevent auto-stop

3. **GPU Release** (:15/hour) - `cleanup-stale-gpu-allocations.sh`
   - Releases GPUs from stopped containers after owner's `gpu_hold_after_stop` timeout
   - Handles restarted containers (clears stopped timestamp)

4. **Container Removal** (:30/hour) - `cleanup-stale-containers.sh`
   - Removes stopped containers after owner's `container_hold_after_stop` timeout
   - Skips containers without metadata (conservative)

**Container Restart:**
1. `container-run`/`container-start` → validates GPU still exists (nvidia-smi check)
2. If GPU missing: clear error message with recreation steps
3. If GPU available: `mlc-open` starts container, clears stopped timestamp

## Script Organization

```
scripts/
├── docker/              # Container creation, GPU allocation
│   ├── mlc-create-wrapper.sh, mlc-patched.py
│   ├── get_resource_limits.py, gpu_allocator.py
├── user/                # User-facing commands
│   ├── container-*, image-*, {dir|git|readme|ssh|vscode}-*
│   ├── user-setup, new-project, *-dispatcher.sh
├── system/              # System administration
│   ├── setup-resource-slices.sh, create-user-slice.sh
│   ├── add-user-to-docker.sh, update-symlinks.sh
├── monitoring/          # Metrics and auditing
│   ├── gpu-status-dashboard.py, check-idle-containers.sh
│   ├── collect-*-metrics.sh, audit-*.sh
├── maintenance/         # Cleanup and housekeeping
│   ├── enforce-max-runtime.sh, check-idle-containers.sh
│   ├── cleanup-stale-gpu-allocations.sh
│   └── cleanup-stale-containers.sh

testing/
├── cleanup-automation/  # Automated cleanup system tests
│   ├── README.md        # Complete testing guide
│   ├── FINDINGS.md      # Bug analysis documentation
│   ├── SUMMARY.md       # Executive summary
│   └── test-*.sh        # Test scripts
```

## Testing Changes

1. **YAML changes**: Test with multiple user types
   ```bash
   for user in student1 researcher1 datasciencelab; do
       python3 scripts/docker/get_resource_limits.py $user
   done
   ```

2. **GPU allocator**: Use dry-run mode
   ```bash
   python3 scripts/docker/gpu_allocator.py status
   python3 scripts/docker/gpu_allocator.py allocate testuser testcontainer 1 10
   python3 scripts/docker/gpu_allocator.py release testcontainer
   ```

3. **Systemd slices**: Verify creation
   ```bash
   sudo scripts/system/setup-resource-slices.sh
   systemctl status ds01.slice
   systemd-cgtop | grep ds01
   ```

4. **Cleanup automation**: Unit tests and integration tests
   ```bash
   # Run unit tests (fast, no containers needed)
   testing/cleanup-automation/test-functions-only.sh

   # Test with short timeouts (set in resource-limits.yaml):
   # idle_timeout: 0.01h (36s), max_runtime: 0.02h (72s)
   # Then run scripts manually and verify behavior
   bash scripts/monitoring/check-idle-containers.sh
   bash scripts/maintenance/enforce-max-runtime.sh

   # Monitor cron logs
   tail -f /var/log/ds01/{idle-cleanup,runtime-enforcement}.log
   ```

   See `testing/cleanup-automation/README.md` for comprehensive testing guide

## Security Considerations

- User isolation: Containers run with user's UID/GID (AIME handles this)
- GPU pinning: `--gpus device=X` prevents cross-user access
- Cgroup limits: Prevent resource exhaustion
- Workspace permissions: User-specific mounts

**Do not:**
- Store secrets in YAML (readable by all users)
- Allow cgroup-parent override (bypasses limits)
- Disable GPU isolation in production

## Codebase Conventions

- **Bash**: Use `set -e`, include usage functions
- **Python**: Use argparse, provide `main()` function
- **YAML**: Use `null` for unlimited/disabled, add comments
- **Logging**: Pipe-delimited format: `timestamp|event|user|container|gpu_id|reason`
- **Colors**: Use `echo -e` for ANSI codes (not plain `echo`)
- **Shebang**: Must be line 1 (#!/bin/bash), no leading whitespace
- **Docker group**: Standard `docker` group for socket access
- **Image naming**: `{project}-image` format (e.g., `my-thesis-image`)
- **Flags**: All commands support `-h`, `--help`, `--info`; Tier 2 support `--guided`
- **Interactive selection**: Source `/opt/ds01-infra/scripts/lib/interactive-select.sh`

### Python Heredocs in Bash (Critical)

When embedding Python in bash scripts via heredocs:

**WRONG** (variable substitution fails):
```bash
python3 - <<PYEOF
if '$var' in config:  # Bash substitutes but Python sees literal string!
PYEOF
```

**CORRECT** (use environment variables):
```bash
VAR="$var" python3 - <<'PYEOF'  # Note quoted delimiter
import os
var = os.environ['VAR']
if var in config:  # Works correctly
PYEOF
```

**Key points**:
- Use quoted heredoc delimiter `<<'PYEOF'` to prevent bash substitution
- Pass bash variables as environment variables
- Check for `None` before dict operations: `if config['key'] is not None:`
- See `testing/cleanup-automation/FINDINGS.md` for bug details

## Dependencies

**System:**
- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- yq, systemd, nvidia-smi, git

**Base system:**
- `aime-ml-containers` at `/opt/aime-ml-containers`

**Groups:**
- `docker` group for Docker socket access

