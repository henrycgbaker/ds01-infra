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
- Dynamic MIG-aware GPU allocation with access control (MIG vs full GPU)
- Per-user/group resource limits (YAML config + systemd cgroups)
- Container lifecycle automation (idle detection, auto-cleanup)
- Centralized event logging and monitoring

## Architecture Design Principles

### Layered Architecture (Implementation Hierarchy)

DS01 uses a **5-layer implementation hierarchy** with **4 user-facing interfaces**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LAYER HIERARCHY (Implementation)                     │
├─────────────────────────────────────────────────────────────────────────────┤
│   L4: WIZARDS (Complete Guided Workflows)                                   │
│   ├── user-setup           # SSH → project-init → vscode                    │
│   ├── project-init         # pyproject.toml → Dockerfile → requirements.txt │
│   └── project launch       # check image → image-create → container deploy  │
│                                                                             │
│   L3: ORCHESTRATORS (Multi-Step Container Sequences)                        │
│   ├── container deploy     # create + start                                 │
│   └── container retire     # stop + remove + free GPU                       │
│                                                                             │
│   L2: ATOMIC (Single-Purpose Commands)                                      │
│   ├── Container: create, start, attach, run, stop, remove, list, stats, exit│
│   └── Image:     create, list, update, delete                               │
│                                                                             │
│   L1: MLC (AIME Machine Learning Containers) ─────────────────── HIDDEN     │
│   └── mlc-create, mlc-open, mlc-stop, mlc-remove, mlc-list                  │
│                                                                             │
│   L0: DOCKER (Foundational Container Runtime)                               │
│   └── docker run, exec, stop, rm, build, images, ps, stats                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### User-Facing Interfaces

**DS01 ORCHESTRATION INTERFACE (DEFAULT)** - For all users
- L4 Wizards: `user-setup`, `project-init`, `project launch`
- L3 Orchestrators: `container deploy`, `container retire`
- Shared L2: `image-*`, `container-list`, `container-stats`
- Binary state model: containers are `running` or `removed` (no intermediate states)

**DS01 ATOMIC INTERFACE (ADMIN)** - For admins and power users
- Full L2 commands: `container-create`, `container-start`, `container-stop`, etc.
- Full state model: `created` → `running` → `stopped` → `removed`
- GPU hold timeout applies

**DOCKER INTERFACE (ADVANCED)** - Direct Docker commands
- Still subject to resource enforcement (cgroups + OPA)
- Containers placed in `ds01-{group}-{user}.slice`

**OTHER INTERFACE** - External tools (VS Code Dev Containers, Docker Compose, etc.)
- Allowed through OPA, subject to cgroup enforcement
- Visible in dashboard as "Other" category

### Command Design Principles

All user-facing commands must follow these patterns:

**Dispatcher Pattern (space-separated subcommands):**
- Use `command subcommand` format: `container deploy`, `code attach`, `image create`
- Hyphenated aliases also work: `container-deploy`, `code-attach`
- Dispatchers route to underlying scripts: `scripts/user/{command}-dispatcher.sh`

**Interactive by Default:**
- Commands without arguments launch interactive wizard/GUI
- Guide users through options with prompts
- Example: `container-deploy` with no args → interactive mode

**Help System (4 Tiers):**
| Flag | Type | Purpose |
|------|------|---------|
| `--help`, `-h` | Reference | Quick reference |
| `--info` | Reference | Full reference (all options) |
| `--concepts` | Education | Pre-run learning (what is X?) |
| `--guided` | Education | Interactive learning (during execution) |

Include `help` as a valid subcommand: `container help`

**Consistent Structure:**
```bash
command [subcommand] [args] [--options]
command                     # Interactive mode
command --help              # Quick reference
command --info              # Full reference
command --concepts          # Pre-run education
command --guided            # Interactive education
command subcommand --help   # Subcommand-specific help
```

### Conditional Output System

Commands detect context via `DS01_CONTEXT` environment variable:
- Orchestrators set `DS01_CONTEXT=orchestration` before calling atomic commands
- Atomic commands suppress "Next steps" output when called from orchestrators
- Users see interface-appropriate help based on entry point

### Universal Enforcement

ALL containers (from any interface) are subject to:
- Systemd cgroups (`ds01.slice` hierarchy)
- Docker wrapper (`/usr/local/bin/docker`) for per-user slice injection
- OPA authorization plugin (fail-open with logging)
- GPU allocation tracking via Docker labels

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
- Dockerfiles (`~/workspace/<project>/Dockerfile`)
- Docker images (blueprints for recreation)
- Project configuration (`pyproject.toml`, `requirements.txt`)

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
- Dockerfiles: `~/workspace/{project}/Dockerfile` (standard location)

**Project metadata (pyproject.toml):**
```toml
[project]
name = "my-thesis"
description = "Computer vision thesis project"

[tool.ds01]
type = "cv"  # ml, cv, nlp, rl, audio, ts, llm, custom
created = "2025-12-08"
author = "h_baker"
image = "ds01-12345/my-thesis:latest"
```

**Project-centric workflow:**
```
project init my-thesis --type=cv     # Creates pyproject.toml, Dockerfile, requirements.txt
project launch my-thesis             # Builds image (if needed) → deploys container
# ... work in container ...
container retire my-thesis           # Cleanup
```

### Core Components

**Resource Management:**
- `config/resource-limits.yaml` - Central config (defaults, groups, user_overrides, policies)
- `scripts/docker/get_resource_limits.py` - YAML parser
- `scripts/docker/gpu_allocator_v2.py` - Stateless GPU allocation with file locking (race-safe)
- `scripts/docker/gpu-availability-checker.py` - Available GPU queries with access control

**Centralized Logging:**
- `scripts/docker/event-logger.py` - Append-only JSON event log
- `/var/log/ds01/events.jsonl` - All events (GPU allocation, container lifecycle, health checks)
- `scripts/monitoring/ds01-events` - Query tool for event log

## Documentation Structure

**Root level (you are here):**
- `README.md` - System architecture, installation, admin guide
- `CLAUDE.md` - This file (concise AI assistant reference)
- `ds01-UI_UX_GUIDE.md` - **UI/UX design guide** (philosophy, colors, layout, prompts, patterns)

**Module-specific READMEs (detailed docs):**
- `scripts/docker/README.md` - Resource management, GPU allocation, container creation
- `scripts/user/README.md` - User commands, workflows, tier system details
- `scripts/admin/README.md` - Admin tools, system dashboards, user management
- `scripts/lib/README.md` - Shared libraries (dockerfile-generator, context, utilities)
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
- User projects: `~/workspace/{project}/` (includes Dockerfile, requirements.txt)

**Base system:**
- AIME MLC: `/opt/aime-ml-containers`

## Essential Conventions

**Bash:**
- Use `set -e`, include usage functions
- Use `echo -e` for ANSI color codes (not plain `echo`)
- Shebang must be line 1 (no leading whitespace)
- **See `ds01-UI_UX_GUIDE.md` for comprehensive UI/UX design standards**
- **Exit code capture with `set -e`:** When capturing exit codes from command substitutions, temporarily disable `set -e`:
  ```bash
  set +e
  OUTPUT=$(some_command 2>&1)
  EXIT_CODE=$?
  set -e
  ```
  Without this, the script exits immediately on failure, skipping error handling code.

**Python:**
- Use argparse, provide `main()` function
- For heredocs in bash: Use quoted delimiter `<<'PYEOF'` and pass variables via environment

### User Commands (Recommended)

**L4 Wizards (Complete guided workflows):**
```bash
user-setup                                     # Full user onboarding
project init my-thesis                         # Create new project
project init my-thesis --type=cv               # With use-case preset
project init --guided                          # With explanations

# Launch project (smart: builds image if needed, deploys container)
project launch my-project                      # Interactive project selection
project launch my-project --open               # Launch and open terminal
project launch my-project --rebuild            # Force rebuild image
```

**L3 Orchestrators (Multi-step sequences):**
```bash
# Deploy container (direct: requires image to exist)
container deploy my-project                    # Interactive mode
container deploy my-project --open             # Create and open terminal
container deploy my-project --project=NAME     # Mount specific project workspace
container deploy my-project --workspace=/path  # Mount custom path

# Retire container (stop + remove + free GPU)
container retire my-project                    # Interactive mode
container retire my-project --force            # Skip confirmations
container retire my-project --images           # Also remove Docker image
```

**L2 Atomic Commands (Admin/Advanced):**
```bash
# Container lifecycle (manual control)
container-create my-project                    # Create only
container-start my-project                     # Start in background
container-run my-project                       # Start and enter (L2)
container-stop my-project                      # Stop only
container-remove my-project                    # Remove only

# Container inspection (shared with L3)
container-list                                 # View all containers
container-stats                                # Resource usage
```

**Shell Configuration:**
```bash
shell-setup                # Fix PATH configuration
shell-setup --check        # Verify PATH
shell-setup --guided       # With explanations

# If commands not accessible:
/opt/ds01-infra/scripts/user/shell-setup
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

**Deploy commands to /usr/local/bin (after editing scripts):**
```bash
sudo deploy   # Copies all DS01 commands to /usr/local/bin
```

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
- `max_mig_instances`: Max GPUs/MIG instances per user total
- `max_gpus_per_container`: Max GPUs per single container
- `allow_full_gpu`: Can user access full (non-MIG) GPUs? (default: false)
- `max_cpus`, `memory`, `shm_size`: Per-container compute limits
- `max_containers_per_user`: Max simultaneous containers
- `idle_timeout`: Auto-stop after GPU inactivity (e.g., "2h")
- `gpu_hold_after_stop`: Hold GPU after stop (e.g., "0.25h", null = indefinite)
- `container_hold_after_stop`: Auto-remove container after stop (e.g., "0.5h", null = never)

**Group access control:**
- `student`: MIG only (`allow_full_gpu: false`)
- `researcher`: MIG or full GPU (`allow_full_gpu: true`)
- `admin`: Unlimited access

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
├── docker/              # L0/L1 - Container creation, GPU allocation
│   ├── mlc-create-wrapper.sh, mlc-patched.py    # L1 (HIDDEN)
│   ├── get_resource_limits.py, gpu_allocator_v2.py
│   ├── docker-wrapper.sh                         # Universal enforcement (cgroup + label injection)
│   ├── container-init.sh                         # Container initialization handler
│   ├── gpu-state-reader.py, event-logger.py
├── user/                # L2/L3/L4 - User-facing commands
│   ├── L2 (Atomic): container-{create|start|attach|run|stop|remove|list|stats|exit}
│   ├── L2 (Atomic): image-{create|list|update|delete}
│   ├── L2 (Atomic): {dir|git|readme|ssh|vscode}-*
│   ├── L3 (Orchestrators): container-{deploy|retire}
│   ├── L4 (Wizards): user-setup, project-init, project-launch, *-dispatcher.sh
│   └── v1-backup/       # Backup of container workflow scripts before refactor
├── admin/               # Admin tools (see scripts/admin/README.md)
│   ├── dashboard        # Main admin dashboard (GPU, containers, system status)
│   ├── ds01-logs        # Log viewer and search
│   ├── ds01-users       # User management utilities
│   ├── ds01-mig-partition  # MIG configuration tool
│   ├── alias-create, alias-list  # Command alias management
│   ├── help, version    # System information
│   └── bypass-enforce-containers.sh  # Emergency bypass
├── lib/                 # Shared libraries (see scripts/lib/README.md)
│   ├── init.sh          # Standard bash initialization (paths, colors, utilities)
│   ├── ds01_core.py     # Core Python utilities (duration parsing, container utils)
│   ├── username_utils.py  # Python username sanitization
│   ├── dockerfile-generator.sh  # Shared Dockerfile generation (used by project-init, image-create)
│   ├── ds01-context.sh          # Context detection for conditional output
│   ├── interactive-select.sh    # Container selection UI
│   ├── container-session.sh     # Unified handler for start/run/attach
│   ├── container-logger.sh      # Centralized event logging wrapper
│   ├── error-messages.sh        # User-friendly error messages
│   ├── aime-images.sh           # AIME base image resolution
│   ├── project-metadata.sh      # pyproject.toml parsing/creation
│   ├── username-utils.sh        # Username sanitization for systemd
│   └── validate-resource-limits.sh  # Resource limit validation
├── system/              # System administration
│   ├── setup-docker-cgroups.sh, setup-opa-authz.sh  # Universal enforcement
│   ├── setup-resource-slices.sh, create-user-slice.sh
│   ├── add-user-to-docker.sh, deploy-commands.sh
├── monitoring/          # Metrics and auditing
│   ├── ds01-health-check, detect-bare-metal.py
│   ├── ds01-events, validate-state.py      # Event log and state validation
│   ├── gpu-utilization-monitor.py          # Real-time GPU usage tracking
│   ├── mig-utilization-monitor.py          # MIG instance utilization
│   ├── container-dashboard.sh              # Container resource dashboard
│   ├── gpu-status-dashboard.py, check-idle-containers.sh
│   ├── collect-*-metrics.sh, audit-*.sh
├── maintenance/         # Cleanup and housekeeping
│   ├── enforce-max-runtime.sh, check-idle-containers.sh
│   ├── cleanup-stale-gpu-allocations.sh
│   └── cleanup-stale-containers.sh
├── backup/              # System backup and restore
│   ├── backup.sh                            # Backup script
│   └── restore-datasciencelab-sudo.sh       # Restore script

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
dashboard                                # Default snapshot view
dashboard interfaces                     # Containers grouped by interface
dashboard users                          # Per-user breakdown
dashboard monitor                        # Watch mode (1s refresh)

# GPU utilization (actual usage, not just allocation)
gpu-utilization-monitor                  # Current GPU utilization snapshot
gpu-utilization-monitor --json           # JSON output
mig-utilization-monitor                  # MIG instance utilization

# Check system health
ds01-health-check                        # Full health check
ds01-events                              # View centralized event log
ds01-events user alice                   # Events for specific user
```

**User self-service:**
```bash
check-limits                             # Show your resource limits and usage (with soft limit warnings)
gpu-queue position $USER                 # Check GPU queue position (if waiting)
```

**Resource alerts & queue (cron-managed):**
- `resource-alert-checker` - Generates alerts at 80% of limits (GPU, containers)
- `gpu-queue` - GPU request queue for users waiting for availability
- Alerts shown on login via `ds01-login-check`

See [scripts/monitoring/README.md](scripts/monitoring/README.md) for full details.

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
