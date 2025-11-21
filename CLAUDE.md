# CLAUDE.md

Instructions for AI assistants working with this repository.

## Guidelines

- Be concise
- No audit.md/summary.md docs unless explicitly requested
- If uncertain, discuss in-chat then implement directly
- Update CLAUDE.md if necessary, but don't create extra documentation unless requested
- Store tests in relevant `/testing` directory for reuse

## System Overview

DS01 Infrastructure: GPU-enabled container management for multi-user data science workloads.

**Core capabilities:**
- Dynamic MIG-aware GPU allocation with priority scheduling
- Per-user/group resource limits (YAML config + systemd cgroups)
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection

## Architecture Design Principles

### Tiered Hierarchical Design

DS01 uses a **modular, layered architecture** that wraps and enhances AIME MLC without replacing it:

**TIER 1: Base System** (`aime-ml-containers` v2)
- 11 core `mlc` commands providing container lifecycle management
- 150+ pre-built framework images (PyTorch 2.8.0, TensorFlow 2.16.1, etc.)
- Container naming: `{container-name}._.{user-id}` (AIME convention)
- **DS01 approach**: Wrap strategically (mlc-create, mlc-stats), use directly (mlc-open, mlc-list, mlc-stop, etc.)

**TIER 2: Atomic Unit Commands** (Single-purpose, modular, reusable)
- **Container Management** (8): `container-{create|run|start|stop|list|stats|remove|exit}`
  - Wrap AIME commands with DS01 UX (interactive GUI, --guided mode, GPU management)
  - Each command does ONE thing and does it well
- **Image Management** (4): `image-{create|list|update|delete}`
  - 4-phase workflow: Framework → Jupyter → Data Science → Use Case
  - Shows AIME base packages, supports pip version specifiers
- **Project Setup** (5): `{dir|git|readme|ssh|vscode}-{create|init|setup}`
- All support `--guided` flag for educational mode
- Can be used standalone or orchestrated

**TIER 3: Container Orchestrators** (Combine Tier 2 atomic commands)
- **Ephemeral container model**: Containers are temporary compute, workspaces persist
- `container-deploy`: Creates AND starts containers (container-create → container-start/run)
  - Prompts: "Start in background or open terminal?"
  - Supports `--background` and `--open` flags
  - Default behavior for quick deployment
- `container-retire`: Stops AND removes containers (container-stop → container-remove)
  - Immediately releases GPU for others
  - Preserves workspace files, Dockerfiles, and images
  - Encourages "good citizen" resource management

**TIER 4: Workflow Orchestrators** (Complete multi-step workflows)
- Dispatchers: Support both `command subcommand` and `command-subcommand` syntax
- `project-init`: dir-create → git-init → readme-create → image-create → container-deploy
- `user-setup` (Complete onboarding): Educational first-time onboarding (ssh-setup → project-init → vscode-setup)
   - Command variants: `user-setup`, `user setup`, `new-user`

**TIER 4: Workflow Wizards** (Complete onboarding)
- `user-setup`: Full onboarding (ssh-setup → project-init → vscode-setup)
- Educational focus for first-time users
- 69.4% code reduction vs original monolithic version

### Ephemeral Container Philosophy

DS01 embraces the **ephemeral container model** inspired by HPC, cloud platforms, and Kubernetes:

**Core Principle:** Containers = temporary compute sessions | Workspaces = permanent storage

**User Workflows:**
- **Quick Deploy**: `container-deploy my-project` → create + start in one command
- **Work Session**: Code, train models, experiment (files saved to workspace)
- **Quick Retire**: `container-retire my-project` → stop + remove + GPU freed immediately

**What's Ephemeral (removed):**
- Container instance (can be recreated anytime)
- GPU allocation (freed immediately on retire)

**What's Persistent (always safe):**
- Workspace files (`~/workspace/<project>/`)
- Dockerfiles (`~/dockerfiles/`)
- Docker images (blueprints for recreation)
- Project configuration

**Benefits:**
- **Resource Efficiency**: GPUs freed immediately, no stale allocations
- **Clear Mental Model**: "Shut down laptop when done" = `container-retire`
- **Cloud-Native Skills**: Prepares students for AWS/GCP/Kubernetes workflows
- **Simpler State**: Only running/removed states (no stopped-but-allocated limbo)

**For Users Who Need Persistence:**
- `container-stop --keep-container` flag available in Phase 2
- Default encourages best practices

### AIME v2 Integration

**mlc-patched.py**: Minimal modification (2.5% change) to support custom images
- Adds `--image` flag to bypass AIME catalog
- Validates local image existence
- Adds DS01 labels (`DS01_MANAGED`, `CUSTOM_IMAGE`)
- 97.5% of AIME logic preserved (easy to upgrade)

**Naming conventions:**
- Images: `ds01-{user-id}/{project-name}:latest`
- Containers: `{project-name}._.{user-id}` (AIME convention)
- Dockerfiles: `~/dockerfiles/{project-name}.Dockerfile`

**Workflow:** image-create (4 phases) → builds custom image → container-deploy (create + start) → mlc-patched.py → resource limits → GPU allocation

### Core Components

**Resource Management:**
- `config/resource-limits.yaml` - Central config (defaults, groups, user_overrides, policies)
- `scripts/docker/get_resource_limits.py` - YAML parser
- `scripts/docker/gpu_allocator.py` - Stateful GPU allocation with priority scheduling

## Documentation Structure

**Root level (you are here):**
- `README.md` - System architecture, installation, admin guide
- `CLAUDE.md` - This file (concise AI assistant reference)

**Module-specific READMEs (detailed docs):**
- `scripts/docker/README.md` - Resource management, GPU allocation, container creation
- `scripts/user/README.md` - User commands, workflows, tier system details
- `scripts/system/README.md` - System administration, deployment, user management
- `scripts/monitoring/README.md` - Monitoring tools, dashboards, metrics collection
- `scripts/maintenance/README.md` - Cleanup automation, cron jobs, lifecycle management
- `config/README.md` - YAML configuration, resource limits, policy reference
- `testing/README.md` - Testing overview, test suites, validation procedures

## Key Paths

**Standard deployment:**
- Config: `/opt/ds01-infra/config/resource-limits.yaml`
- Scripts: `/opt/ds01-infra/scripts/`
- State: `/var/lib/ds01/` (gpu-state.json, container-metadata/)
- Logs: `/var/log/ds01/` (gpu-allocations.log, cron logs)
- User dockerfiles: `~/dockerfiles/`

**Base system:**
- AIME MLC: `/opt/aime-ml-containers`

## Essential Conventions

**Bash:**
- Use `set -e`, include usage functions
- Use `echo -e` for ANSI color codes (not plain `echo`)
- Shebang must be line 1 (no leading whitespace)

**Python:**
- Use argparse, provide `main()` function
- For heredocs in bash: Use quoted delimiter `<<'PYEOF'` and pass variables via environment

### User Commands (Recommended)

**Tier 3 Orchestrators (Ephemeral Model):**
```bash
# Deploy container (create + start)
container-deploy my-project                    # Interactive mode
container-deploy my-project --open             # Create and open terminal
container-deploy my-project --background       # Create and start in background
container-deploy my-project --guided           # Beginner mode with explanations

# Retire container (stop + remove + free GPU)
container-retire my-project                    # Interactive mode
container-retire my-project --force            # Skip confirmations
container-retire my-project --images           # Also remove Docker image
```

**Tier 2 Atomic Commands (Advanced/Step-by-Step):**
```bash
# Container lifecycle (manual control)
container-create my-project                    # Create only
container-start my-project                     # Start in background
container-run my-project                       # Start and enter
container-stop my-project                      # Stop only
container-remove my-project                    # Remove only

# Container inspection
container-list                                 # View all containers
container-stats                                # Resource usage
```

### Development/Testing
```bash
python3 scripts/docker/get_resource_limits.py <username>
```

**GPU allocator:**
```bash
python3 scripts/docker/gpu_allocator.py status
python3 scripts/docker/gpu_allocator.py allocate <user> <container> <max_gpus> <priority>
```

**Validate YAML:**
```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

See module-specific READMEs for detailed testing procedures.

## Common Operations

**Add user to docker:**
```bash
sudo scripts/system/add-user-to-docker.sh <username>
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
├── docker/              # Container creation, GPU allocation (Tier 1)
│   ├── mlc-create-wrapper.sh, mlc-patched.py
│   ├── get_resource_limits.py, gpu_allocator.py
├── user/                # User-facing commands (Tier 2, 3, 4)
│   ├── Tier 2 (Atomic): container-{create|start|run|stop|remove|list|stats|exit}
│   ├── Tier 2 (Atomic): image-{create|list|update|delete}
│   ├── Tier 2 (Atomic): {dir|git|readme|ssh|vscode}-*
│   ├── Tier 3 (Orchestrators): container-{deploy|retire}
│   ├── Tier 4 (Workflows): user-setup, project-init, *-dispatcher.sh
│   └── v1-backup/       # Backup of container workflow scripts before refactor
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

**Setup systemd slices:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

**Monitor system:**
```bash
ds01-dashboard                           # Admin dashboard
python3 scripts/docker/gpu_allocator.py status
tail -f /var/log/ds01/gpu-allocations.log
```

## Security Notes

- User isolation via AIME's UID/GID mapping
- GPU pinning via `--gpus device=X` prevents cross-user access
- Systemd cgroups prevent resource exhaustion
- Never store secrets in YAML (readable by all users)
- Never allow cgroup-parent override (bypasses limits)

## Dependencies

- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- systemd, nvidia-smi, git, yq
- `aime-ml-containers` at `/opt/aime-ml-containers`
- `docker` group for Docker socket access
