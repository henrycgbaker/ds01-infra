# DS01 Command Layers - Complete Reference

This document explains the three layers of container management commands in DS01 and how they relate to each other.

## Overview

DS01 has **three distinct command layers**:
1. **Docker Native Commands** - Core Docker CLI
2. **Base System (AIME MLC)** - Framework-focused container management
3. **DS01 Custom Commands** - Multi-user GPU infrastructure with resource management

Each layer builds on the previous one, adding functionality specific to DS01's needs.

---

## Layer 1: Docker Native Commands

The foundation. These are standard Docker CLI commands that interact directly with the Docker daemon.

### Core Container Lifecycle

| Command | Purpose | Example |
|---------|---------|---------|
| `docker create` | Create container (doesn't start it) | `docker create --name my-container ubuntu` |
| `docker start` | Start a stopped container | `docker start my-container` |
| `docker stop` | Stop a running container | `docker stop my-container` |
| `docker restart` | Restart a container | `docker restart my-container` |
| `docker rm` | Remove a stopped container | `docker rm my-container` |
| `docker exec` | Execute command in running container | `docker exec -it my-container bash` |
| `docker attach` | Attach to running container's main process | `docker attach my-container` |

### Container Inspection

| Command | Purpose | Example |
|---------|---------|---------|
| `docker ps` | List running containers | `docker ps` |
| `docker ps -a` | List all containers (including stopped) | `docker ps -a` |
| `docker inspect` | Detailed container info (JSON) | `docker inspect my-container` |
| `docker logs` | View container logs | `docker logs my-container` |
| `docker stats` | Live resource usage stats | `docker stats my-container` |
| `docker top` | View processes in container | `docker top my-container` |

### Image Management

| Command | Purpose | Example |
|---------|---------|---------|
| `docker pull` | Download image from registry | `docker pull pytorch/pytorch:2.5.1-cuda11.8` |
| `docker build` | Build image from Dockerfile | `docker build -t my-image .` |
| `docker images` | List local images | `docker images` |
| `docker rmi` | Remove image | `docker rmi my-image` |
| `docker commit` | Create image from container | `docker commit my-container my-image` |

### Resource Management

| Command | Purpose | Example |
|---------|---------|---------|
| `docker update` | Update container resource limits | `docker update --cpus=4 --memory=8g my-container` |
| `docker run` | Create and start container in one command | `docker run -it --gpus all ubuntu` |

**Key Points:**
- DS01 and MLC both use these commands under the hood
- These require `docker` group membership or root access
- DS01 users are added to `docker` group for access

---

## Layer 2: Base System (AIME MLC v1)

A framework-focused container management layer built on top of Docker. Focuses on **machine learning framework versions** (PyTorch, TensorFlow, MXNet) and basic multi-user support.

### What AIME MLC Provides

**Core Value Proposition:**
- **Framework version management**: Easy access to specific ML framework versions
- **Image repository**: Pre-built images for common frameworks (`ml_images.repo`)
- **User isolation**: Container naming with UID/GID (`$CONTAINER_NAME._.$USER_ID`)
- **Simple lifecycle**: Streamlined create/open/stop/remove workflow

### AIME MLC Commands

| Command | What It Does | Docker Commands It Wraps | DS01 Usage |
|---------|-------------|--------------------------|------------|
| **mlc-create** | Creates container with specific framework/version | `docker pull` → `docker run` → `docker commit` → `docker create` | ✅ **WRAPPED** by `mlc-create-wrapper.sh` |
| **mlc-open** | Opens shell to container (auto-starts if needed) | `docker start` → `docker exec` | ✅ **CALLED DIRECTLY** by `container-run` |
| **mlc-list** | Lists user's containers with framework info | `docker ps -a --filter label=aime.mlc` | ❌ **NOT USED** - DS01 built custom |
| **mlc-stats** | Shows CPU/memory usage of running containers | `docker stats --format` | ✅ **WRAPPED** by `mlc-stats-wrapper.sh` |
| **mlc-start** | Starts container without opening shell | `docker start` | ❌ **NOT USED** - DS01 uses `docker start` directly |
| **mlc-stop** | Stops running container (with confirmation) | `docker stop` | ❌ **NOT USED** - DS01 built custom |
| **mlc-remove** | Deletes container and its committed image | `docker rm` → `docker rmi` | ❌ **NOT USED** - DS01 built custom |
| **mlc-update-sys** | Updates MLC system via git pull | Git operations | ❌ **NOT USED** - Not needed |
| **mlc-upgrade-sys** | Upgrades from MLC v1 to v2 | Git operations | ❌ **NOT USED** - DS01 uses v1 intentionally |

### AIME MLC Features

**Container Naming:**
- Format: `$CONTAINER_NAME._.$USER_ID`
- Example: `my-project._.1001`
- Enables multi-user isolation on same host

**Labels:**
- `aime.mlc` - Marks container as MLC-managed
- `aime.mlc.USER` - Container owner username
- `aime.mlc.FRAMEWORK` - Framework and version (e.g., "Pytorch-2.5.1")
- `aime.mlc.NAME` - User-friendly container name

**Entry Method:**
- Uses `docker exec` to enter containers
- **Important**: Ctrl+P, Ctrl+Q does NOT work (only works with `docker attach`)
- Typing `exit` leaves shell but container keeps running
- Auto-stops container when last shell exits AND no processes running

**Workspace Mounting:**
- Mounts user's workspace directory as `/workspace` inside container
- Supports optional data directory mounting

### Why DS01 Uses Only 3 of 9 MLC Commands

**✅ Commands DS01 Uses:**

1. **mlc-create** - WRAPPED because:
   - Excellent framework version selection
   - Good image repository management
   - But needs DS01 enhancements (resource limits, GPU allocation)

2. **mlc-open** - CALLED DIRECTLY because:
   - Works perfectly as-is
   - Handles container starting and exec correctly
   - Uses `docker exec` which is what DS01 wants

3. **mlc-stats** - WRAPPED because:
   - Good basic stats display
   - But needs GPU process information added

**❌ Commands DS01 Does NOT Use:**

| MLC Command | Why DS01 Built Custom |
|-------------|----------------------|
| **mlc-list** | • Needs DS01-specific labels (`ds01.user`, `ds01.project`)<br>• Custom display format with project names<br>• Different filtering logic<br>• Enhanced status information |
| **mlc-stop** | • Needs custom warnings about stopping vs exiting<br>• Force/timeout options<br>• Confirmation prompts with process count<br>• Integration with DS01 lifecycle |
| **mlc-remove** | • Needs bulk operations (remove multiple containers)<br>• DS01-specific safety checks<br>• GPU allocation release<br>• Container metadata cleanup |
| **mlc-start** | • DS01 uses `docker start` directly when needed<br>• Not commonly used in DS01 workflow (`container-run` handles starting) |
| **mlc-update-sys** | • Not applicable to DS01 (doesn't manage MLC installation) |
| **mlc-upgrade-sys** | • DS01 intentionally uses MLC v1 (v2 incompatible) |

---

## Layer 3: DS01 Custom Commands

A **multi-user GPU infrastructure layer** built on top of Docker and selectively using AIME MLC. Adds resource management, GPU allocation, systemd integration, and user-friendly workflows.

### What DS01 Adds

**Core Value Proposition:**
- **Resource quotas**: Per-user/group limits from YAML config
- **GPU allocation**: MIG-aware GPU scheduling with priorities
- **Systemd integration**: Cgroup-based resource enforcement
- **Lifecycle automation**: Idle detection, auto-cleanup
- **User onboarding**: Guided wizards for beginners
- **Modular architecture**: Reusable components with `--guided` mode

### DS01 Container Commands

| DS01 Command | What It Does | Underlying Implementation | Why Custom |
|--------------|--------------|---------------------------|------------|
| **container-create** | Creates container with DS01 resource limits | Calls `mlc-create-wrapper.sh` → `mlc-create` + `docker update` | Adds resource limits, GPU allocation, systemd slice integration |
| **container-run** | Starts and enters container | Calls `mlc-open` from base system | Thin wrapper with --guided mode, exit instructions |
| **container-list** | Lists user's containers with DS01 info | Uses `docker ps -a --filter name=._.$USER_ID` | Needs DS01 labels, custom formatting, project names |
| **container-stop** | Stops running container with warnings | Uses `docker stop` or `docker kill` | Custom warnings, force/timeout options, process count checks |
| **container-cleanup** | Removes stopped containers | Uses `docker rm` | Bulk operations, safety checks, GPU state cleanup |
| **container-stats** | Shows resource usage with GPU info | Calls `mlc-stats-wrapper.sh` | Adds DS01 resource limit display |
| **container-exit** | Shows information about exiting containers | Educational command (no Docker calls) | Explains docker exec behavior, exit vs stop |

### DS01 Container Command Details

#### container-create
**Purpose**: Create container with framework selection + DS01 resource management

**What it does:**
1. Validates container name and checks for conflicts
2. Prompts for framework (pytorch/tensorflow) if not provided
3. Calls `mlc-create-wrapper.sh` which:
   - Gets user's resource limits from YAML (`get_resource_limits.py`)
   - Calls base `mlc-create` with framework/version
   - Applies DS01 resource limits via `docker update` (CPUs, memory, PIDs)
   - Allocates GPU via `gpu_allocator.py` (MIG-aware)
   - Assigns to systemd slice for cgroup enforcement

**Docker commands used:**
- Via `mlc-create`: `docker pull`, `docker run`, `docker commit`, `docker create`
- Directly: `docker update`, `docker inspect`, `docker stop`

**Supports:** `--guided` mode with explanations of containers, images, and resources

---

#### container-run
**Purpose**: Start and enter a container

**What it does:**
1. Checks if container exists
2. Calls `mlc-open` from base system (handles starting and `docker exec`)
3. Shows exit instructions after leaving

**Docker commands used:**
- Via `mlc-open`: `docker start`, `docker exec`

**Supports:** `--guided` mode explaining exit behavior

**Key behavior:**
- Container keeps running after you exit (uses `docker exec`)
- Type `exit` or Ctrl+D to leave
- Ctrl+P, Ctrl+Q does NOT work (that's for `docker attach`)

---

#### container-list
**Purpose**: List all your containers with status and details

**What it does:**
1. Finds all containers matching user's UID pattern (`._.$USER_ID`)
2. For each container:
   - Gets status (running/stopped)
   - Gets image name
   - Gets uptime or stopped duration
   - Formats display with colors
3. Shows summary (X running, Y stopped, Z total)

**Docker commands used:**
- `docker ps -a --filter name=._.$USER_ID` - Find user's containers
- `docker ps --format` - Check if running
- `docker inspect` - Get detailed info

**Why custom:**
- Needs to show project names (not full container tags)
- Custom formatting and colors
- DS01-specific labels
- Different filtering logic than `mlc-list`

**Does NOT use:** `mlc-list` (different filtering and display needs)

---

#### container-stop
**Purpose**: Stop a running container (terminates all processes)

**What it does:**
1. Checks if container exists and is running
2. Shows container info (name, uptime, image, process count)
3. Warns about process termination
4. Asks for confirmation
5. Stops container (graceful or force)

**Docker commands used:**
- `docker ps -a --format "{{.Names}}"` - Check existence
- `docker ps --format "{{.Names}}"` - Check if running
- `docker ps --format "{{.Status}}"` - Get uptime
- `docker inspect` - Get image info
- `docker exec ps aux` - Count processes
- `docker stop -t $timeout` - Graceful stop
- `docker kill` - Force stop

**Why custom:**
- Custom warnings about exit vs stop
- Shows process count before stopping
- Force/timeout options
- Confirmation prompts
- Educational messages

**Does NOT use:** `mlc-stop` (needs custom warnings and DS01-specific logic)

---

#### container-cleanup
**Purpose**: Remove stopped containers to free disk space

**What it does:**
1. Finds all stopped containers for user
2. Shows list with size information
3. Asks for confirmation (or uses --all flag)
4. Removes containers
5. Optionally cleans up GPU state and metadata

**Docker commands used:**
- `docker ps -a --filter name=._.$USER_ID` - Find user's containers
- `docker ps --format "{{.Names}}"` - Check which are stopped
- `docker rm` - Remove containers
- `docker system df` - Show disk usage

**Why custom:**
- Bulk operations (remove multiple containers)
- DS01-specific safety checks
- GPU allocation state cleanup
- Container metadata cleanup
- Interactive or batch mode

**Does NOT use:** `mlc-remove` (needs bulk operations and DS01 integration)

---

#### container-stats
**Purpose**: Show resource usage for running containers

**What it does:**
1. Calls `mlc-stats-wrapper.sh` which:
   - Calls base `mlc-stats` for CPU/memory info
   - Adds GPU process information (via `nvidia-smi`)
   - Shows user's resource limits (from YAML)
   - Provides quick action tips

**Docker commands used:**
- Via `mlc-stats`: `docker stats --format`
- Directly: `docker ps`, `docker inspect`, `docker exec`

**Why wrapped:**
- Base `mlc-stats` doesn't show GPU usage
- Need to display resource limits from DS01 config
- Custom formatting and tips

---

#### container-exit
**Purpose**: Educational command explaining exit behavior

**What it does:**
1. Shows information about how to exit containers
2. Explains docker exec vs docker attach behavior
3. Clarifies exit (keep running) vs container-stop (terminate)
4. Provides workflow examples

**Docker commands used:** None (informational only)

**Why exists:**
- Common user confusion about exit behavior
- DS01 uses `docker exec` (not `docker attach`)
- Ctrl+P, Ctrl+Q misconception
- Exit vs stop clarification

---

### DS01 vs MLC: Comparison

| Feature | AIME MLC | DS01 |
|---------|----------|------|
| **Target users** | Single user or manual multi-user | Automatic multi-user with quotas |
| **Resource limits** | None (uses all available) | Per-user/group quotas from YAML |
| **GPU allocation** | Manual (`--gpus` flag) | Automatic MIG-aware scheduling |
| **Priority scheduling** | First-come-first-served | Priority levels (admin > researcher > student) |
| **Lifecycle automation** | Manual | Automatic (idle detection, cleanup) |
| **Monitoring** | Basic (mlc-stats) | Enhanced (GPU processes, resource limits) |
| **Cgroup integration** | None | Systemd slices per group |
| **User onboarding** | None | Guided wizards (`user-setup`, `project-init`) |
| **Container labels** | `aime.mlc.*` | `aime.mlc.*` + `ds01.*` |
| **Exit behavior** | Auto-stops when inactive | Configurable idle timeout |

---

## Command Usage Flowchart

```
User wants to create container
        ↓
    container-create (DS01 Tier 2)
        ↓
    mlc-create-wrapper.sh (DS01 Tier 1 wrapper)
        ↓
    ┌─────────────────────────────────┐
    │ Gets user limits from YAML      │
    │ Allocates GPU                   │
    └─────────────────────────────────┘
        ↓
    mlc-create (AIME MLC base)
        ↓
    ┌─────────────────────────────────┐
    │ docker pull (get framework)     │
    │ docker run (setup user)         │
    │ docker commit (save image)      │
    │ docker create (final container) │
    └─────────────────────────────────┘
        ↓
    Back to mlc-create-wrapper.sh
        ↓
    ┌─────────────────────────────────┐
    │ docker update (apply limits)    │
    │ docker stop (stop for user)     │
    └─────────────────────────────────┘
        ↓
    Container ready
```

```
User wants to enter container
        ↓
    container-run (DS01 Tier 2)
        ↓
    mlc-open (AIME MLC base)
        ↓
    ┌─────────────────────────────────┐
    │ docker start (if stopped)       │
    │ docker exec -it bash            │
    └─────────────────────────────────┘
        ↓
    User inside container
    (types 'exit')
        ↓
    Container keeps running
```

```
User wants to list containers
        ↓
    container-list (DS01 Tier 2)
        ↓
    [Does NOT call mlc-list]
        ↓
    ┌─────────────────────────────────┐
    │ docker ps -a (find containers)  │
    │ docker inspect (get details)    │
    │ Format with DS01 labels         │
    └─────────────────────────────────┘
        ↓
    Custom DS01 display
```

---

## Why DS01 Built Custom Commands Instead of Using MLC

### The Core Issue: Different Design Goals

**AIME MLC's Goal:**
- Framework version management for ML developers
- Single user or manual multi-user setups
- Simple create/open/stop/remove workflow
- No resource management or scheduling

**DS01's Goal:**
- Multi-user GPU infrastructure for data science lab
- Automatic resource quotas and fair scheduling
- Priority-based GPU allocation (students vs researchers vs admins)
- Lifecycle automation (idle detection, cleanup)
- Educational onboarding for students new to containers

### Specific Reasons by Command

**mlc-list → container-list:**
- MLC shows: Container name, framework, status
- DS01 needs: Project names, GPU allocation, systemd slice, idle time
- DS01 uses different label system (`ds01.*` in addition to `aime.mlc.*`)
- Custom formatting for multi-user display

**mlc-stop → container-stop:**
- MLC: Simple stop with basic confirmation
- DS01 needs:
  - Educational warnings (exit vs stop difference)
  - Process count display
  - Force/timeout options
  - Integration with idle timeout system
  - GPU state cleanup

**mlc-remove → container-cleanup:**
- MLC: Removes one container at a time
- DS01 needs:
  - Bulk operations (remove all stopped containers)
  - Disk usage display
  - GPU allocation cleanup
  - Container metadata cleanup
  - Safety checks (prevent removing running containers)

**mlc-start → Not used:**
- DS01 workflow uses `container-run` which calls `mlc-open` (handles starting)
- When direct starting needed, uses `docker start` directly
- Simpler and more explicit than wrapping another command

---

## Container Naming Conventions

### AIME MLC Naming

**Format:** `$CONTAINER_NAME._.$USER_ID`

**Examples:**
- User input: `my-project`
- User ID: `1001`
- Container tag: `my-project._.1001`

**Why:** Enables multiple users to have containers with same logical name

### DS01 Naming (Same as MLC)

DS01 inherits this naming convention from MLC for compatibility.

**User-facing name:** `my-project`
**Internal Docker name:** `my-project._.1001`

Commands handle the translation:
- User types: `container-run my-project`
- Script translates to: `my-project._.1001`
- Docker sees: `my-project._.1001`

---

## Labels: How Each Layer Marks Containers

### Docker Native Labels

None by default. All labels are application-specific.

### AIME MLC Labels

| Label | Example Value | Purpose |
|-------|---------------|---------|
| `aime.mlc` | `username` | Marks container as MLC-managed |
| `aime.mlc.NAME` | `my-project` | User-friendly container name |
| `aime.mlc.USER` | `jsmith` | Container owner username |
| `aime.mlc.VERSION` | `3` | MLC version |
| `aime.mlc.FRAMEWORK` | `Pytorch-2.5.1` | ML framework and version |
| `aime.mlc.WORK_MOUNT` | `/home/jsmith/workspace` | Workspace directory path |
| `aime.mlc.DATA_MOUNT` | `/data/shared` | Data directory path (if used) |
| `aime.mlc.GPUS` | `all` | GPU allocation setting |

### DS01 Additional Labels

DS01 adds its own labels while keeping MLC labels:

| Label | Example Value | Purpose |
|-------|---------------|---------|
| `ds01.user` | `jsmith` | Container owner (DS01 tracking) |
| `ds01.project` | `my-thesis` | Project name |
| `ds01.image` | `my-thesis-image` | Custom image name |
| `ds01.created` | `2025-11-05T10:30:00` | Creation timestamp |
| `ds01.group` | `students` | User's resource group |
| `ds01.slice` | `ds01-students.slice` | Systemd cgroup slice |

**Why both label systems:**
- MLC labels: Required for base system commands to work
- DS01 labels: Enable custom filtering, sorting, and lifecycle management

---

## Resource Management Comparison

### Docker Native

**Flags at creation:**
- `--cpus=4` - CPU limit
- `--memory=8g` - Memory limit
- `--memory-swap=8g` - Swap limit
- `--shm-size=4g` - Shared memory
- `--pids-limit=1024` - Process limit
- `--gpus all` or `--gpus device=0` - GPU access

**After creation:**
- `docker update --cpus=4 --memory=8g $container` - Update limits
- Note: `--shm-size` and `--gpus` CANNOT be updated after creation

### AIME MLC

**No resource management:**
- Uses whatever user requests
- No quotas or limits
- No fair scheduling
- Manual GPU allocation via `--gpus` flag

### DS01

**Comprehensive resource management:**
1. **YAML configuration** (`resource-limits.yaml`):
   - Default limits for all users
   - Group-based limits (students, researchers, admins)
   - Per-user overrides
   - Priority levels (1-100)

2. **Automatic application:**
   - `mlc-create-wrapper.sh` reads user's limits
   - Applies via `docker update` after container creation
   - Assigns to systemd cgroup slice

3. **GPU allocation:**
   - `gpu_allocator.py` manages MIG-aware scheduling
   - Priority-based allocation
   - Reservation support
   - Automatic cleanup on container removal

4. **Systemd integration:**
   - Cgroup slices per group (`ds01-students.slice`)
   - Enforces CPU quotas, memory limits, task limits
   - Hierarchy: `ds01.slice` → `ds01-{group}.slice` → containers

---

## When to Use Each Layer

### Use Docker Commands Directly When:
- Debugging container issues
- Need specific Docker features not exposed by higher layers
- System administration tasks
- Building custom automation scripts

**Example:** `docker logs my-project._.1001` to debug startup issues

### Use AIME MLC Commands When:
- Quickly testing a new ML framework version
- Need simple framework selection
- Working outside DS01 infrastructure
- Don't need resource quotas or GPU scheduling

**Example:** `mlc-create test-pytorch pytorch 2.5.1` for quick testing

### Use DS01 Commands When:
- Normal user workflow on DS01 system
- Need resource quota enforcement
- Want guided/educational mode
- Bulk operations (cleanup, listing)
- GPU allocation required

**Example:** `container-create my-project pytorch` for production work

---

## Summary Table

| Layer | Commands | Primary Use Case | Resource Management | GPU Scheduling |
|-------|----------|------------------|---------------------|----------------|
| **Docker** | `docker create/start/stop/rm/exec/ps` | Direct container control | Manual flags | Manual `--gpus` |
| **AIME MLC** | `mlc-create/open/list/stop/remove` | Framework version management | None | Manual `-g=` flag |
| **DS01** | `container-create/run/list/stop/cleanup` | Multi-user GPU infrastructure | Automatic from YAML | Automatic MIG-aware |

---

## Conclusion

DS01 strategically uses AIME MLC where it excels (framework management via `mlc-create`, entering containers via `mlc-open`) and builds custom implementations where DS01 needs differ (resource quotas, GPU scheduling, bulk operations, educational features).

This three-layer architecture provides:
- **Flexibility**: Use the right tool for each task
- **Compatibility**: Works with Docker and MLC ecosystems
- **Functionality**: DS01-specific features without reinventing everything
- **Maintainability**: Clear separation between layers

**The actual usage:**
- **3 of 9 MLC commands** used by DS01 (mlc-create wrapped, mlc-open called directly, mlc-stats wrapped)
- **6 of 9 MLC commands** not used (DS01 built custom alternatives for specific needs)
- **All Docker commands** available for direct use when needed
