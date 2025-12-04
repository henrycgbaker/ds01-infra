# User Scripts - Commands & Workflows

User-facing commands organised in a 5-layer modular architecture.

## Overview

This directory contains all user-facing DS01 commands, organised into **5 layers** that build from foundational Docker commands into complete workflow wizards.

## Layer System

### Design Philosophy

- **Single source of truth**: No code duplication between layers
- **Modular and reusable**: Each layer builds on the previous
- **Educational mode**: All L2+ commands support `--guided` flag
- **Flexible syntax**: Dispatchers enable `command subcommand` and `command-subcommand`
- **Consistent UI/UX**: Follow [ds01-UI_UX_GUIDE.md](../../ds01-UI_UX_GUIDE.md) for colors, layout, prompts

### Layer Breakdown

```
L4: WIZARDS              user-setup (complete onboarding)
                              ↓
L3: ORCHESTRATORS        container-deploy, container-retire, project-init
                              ↓
L2: ATOMIC               container-*, image-*, setup modules
                              ↓
L1: MLC (HIDDEN)         mlc commands (AIME MLC v2)
                              ↓
L0: DOCKER               docker run, build, etc.
```

## L4: Workflow Wizards

Complete onboarding experiences for first-time users.

### user-setup

**Purpose:** Complete first-time onboarding wizard
**Audience:** New users, students unfamiliar with containers
**Style:** Educational with detailed explanations

**Workflow:**
1. SSH key setup (`ssh-setup`)
2. Complete project initialization (`project-init`)
3. VS Code Remote-SSH configuration (`vscode-setup`)

**Features:**
- Educational content about SSH, containers, development workflows
- Guided prompts for each setup step
- Comprehensive instructions for connecting via VS Code
- Creates ready-to-use development environment

**Usage:**
```bash
user-setup

# Alternative commands (via dispatcher):
user setup
new-user         # Legacy alias
```

**What it creates:**
- SSH keypair in `~/.ssh/`
- Project directory at `~/workspace/<project>/`
- Git repository with ML .gitignore and Git LFS
- Custom Docker image: `ds01-<username>/<project>:latest`
- Container: `<project>._.username` with GPU allocation
- VS Code configuration instructions

**Code:** `user-setup` (285 lines, orchestrates 3 workflows)

## L3: Workflow Orchestrators

Multi-step workflows that compose L2 atomic modules.

### project-init

**Purpose:** Complete project setup workflow
**Audience:** Users creating new projects
**Style:** Streamlined (default) or educational (`--guided`)

**Workflow:**
1. Project directory creation (`dir-create`)
2. Git repository initialization (`git-init`)
3. README generation (`readme-create`)
4. Custom Docker image build (`image-create`)
5. Container creation (`container-create`)
6. Container startup (`container-run`)

**Modes:**
- **Default:** Minimal prompts, assumes user knows containers
- **Guided:** Educational explanations at each step

**Usage:**
```bash
project-init           # Streamlined mode
project-init --guided  # Educational mode

# Alternative commands (via dispatcher):
project init
project init --guided
new-project           # Legacy alias
```

**What it creates:**
- `~/workspace/<project>/` directory structure
- Git repo with `.gitignore`, `.gitattributes`, `README.md`
- `~/dockerfiles/<project>.Dockerfile`
- Docker image: `ds01-<username>/<project>:latest`
- Container: `<project>._.username`

**Code:** `project-init` (397 lines)

### Command Dispatchers

Enable flexible command syntax.

**container-dispatcher.sh** - Routes container subcommands
```bash
container create    # → container-create
container list      # → container-list
container stop      # → container-stop
```

**image-dispatcher.sh** - Routes image subcommands
```bash
image create        # → image-create
image list          # → image-list
image update        # → image-update
```

**project-dispatcher.sh** - Routes project subcommands
```bash
project init        # → project-init
project init --guided
```

**user-dispatcher.sh** - Routes user subcommands
```bash
user setup          # → user-setup
```

## L2: Atomic Commands

Single-purpose, reusable commands that work standalone or orchestrated.

### Container Management

**container-create** - Create container with resource limits
```bash
container-create [--guided] [--image <image>]

# Interactive prompts for:
# - Container name
# - Docker image selection
# - Resource allocation confirmation

# Calls: mlc-create-wrapper.sh → get_resource_limits.py → gpu_allocator.py → mlc-patched.py
```

**container-run** - Start and enter container
```bash
container-run [<container-name>]

# If no name: interactive selection
# Validates GPU still exists
# Calls: mlc-open (AIME command)
# Clears stopped timestamp in GPU allocator
```

**container-start** - Start container without entering shell
```bash
container-start [<container-name>]

# Similar to container-run but doesn't attach
# Useful for background containers
```

**container-stop** - Stop running container
```bash
container-stop [<container-name>]

# Interactive selection if no name
# Calls: mlc-stop (AIME command)
# Marks container as stopped in GPU allocator
# GPU held for gpu_hold_after_stop duration
# Prompts: "Remove container now?"
```

**container-list** - List your containers
```bash
container-list [--all]

# Shows: Name, Status, GPU, Created, Runtime
# Without --all: shows only your containers
# With --all: shows all users' containers (if permissions allow)
```

**container-stats** - Resource usage statistics
```bash
container-stats [<container-name>]

# Shows: CPU, Memory, GPU utilization, Network I/O
# Wraps: mlc-stats with DS01 enhancements
```

**container-remove** - Remove stopped container
```bash
container-remove [<container-name>]

# Interactive selection if no name
# Releases GPU allocation
# Deletes container metadata
# Calls: mlc-remove (AIME command)
```

**container-exit** - Show container exit information
```bash
container-exit [--guided]

# Educational: Explains how to exit containers
# Key point: docker exec requires exit command (NOT Ctrl+P, Ctrl+Q)
# Guided mode: Detailed explanations of container behavior
```

### Image Management

**image-create** - Build custom Docker image
```bash
image-create [--guided] [--project-name <name>]

# 4-phase workflow:
# Phase 1: Framework selection (PyTorch, TensorFlow, JAX, etc.)
# Phase 2: Jupyter Lab configuration
# Phase 3: Data science packages (pandas, scikit-learn, etc.)
# Phase 4: Use case templates (ML, CV, NLP, RL, Custom)

# Creates: ~/dockerfiles/<project>.Dockerfile
# Builds: ds01-<username>/<project>:latest
# Shows: Base packages from AIME image
# Supports: pip version specifiers (e.g., torch>=2.0)
```

**image-list** - List available images
```bash
image-list [--all]

# Shows your images (ds01-<username>/*)
# With --all: shows all DS01 images
# Format: Repository, Tag, Size, Created
```

**image-update** - Rebuild/update existing image
```bash
image-update [<image-name>]

# Interactive selection if no name
# Rebuilds from existing Dockerfile
# Useful after modifying Dockerfile
```

**image-delete** - Remove unused images
```bash
image-delete [<image-name>]

# Interactive selection if no name
# Checks if image in use by containers
# Warns before deletion
```

### Project Setup Modules

**dir-create** - Create project directory structure
```bash
dir-create [--guided] [--project-name <name>]

# Creates: ~/workspace/<project>/
# Structure:
#   - data/
#   - notebooks/
#   - src/
#   - tests/
#   - outputs/
```

**git-init** - Initialize Git repository
```bash
git-init [--guided] [--project-path <path>]

# Initializes Git in project directory
# Adds ML-specific .gitignore (checkpoints, data, outputs, etc.)
# Configures Git LFS for large files (*.pt, *.h5, *.safetensors)
# Makes initial commit
```

**readme-create** - Generate project README
```bash
readme-create [--guided] [--project-name <name>]

# Generates: ~/workspace/<project>/README.md
# Includes: Project structure, workflow instructions, container commands
# Customizable: Prompts for project description
```

**ssh-setup** - Configure SSH keys
```bash
ssh-setup [--guided]

# Generates SSH keypair if not exists
# Shows public key for adding to remote systems
# Provides connection instructions
# Educational mode: Explains SSH key authentication
```

**vscode-setup** - VS Code Remote-SSH guide
```bash
vscode-setup [--guided]

# Provides step-by-step VS Code setup instructions
# SSH connection configuration
# Remote-SSH extension installation
# Container attachment via Remote-Containers extension
# Educational content about development workflows
```

**shell-setup** - Configure shell PATH for DS01 commands
```bash
shell-setup                # Fix PATH configuration
shell-setup --check        # Verify PATH
shell-setup --guided       # Educational mode
shell-setup --force        # Reconfigure even if already correct

# If commands not accessible:
/opt/ds01-infra/scripts/user/shell-setup
```

**Purpose:** Configure shell PATH for DS01 commands
**Category:** L2 Atomic - Setup Module

**Problem:** Domain users may not have `/usr/local/bin` in PATH

**Technical:**
- Adds PATH config to `~/.bashrc` and `~/.zshrc`
- Idempotent (safe to run multiple times)
- Complements system-wide `/etc/profile.d/` configuration

## Command Flags

### Help System (4 Tiers)

DS01 uses a 4-tier help system: 2 reference modes (traditional CLI) + 2 educational modes (for new users).

| Flag | Type | Purpose |
|------|------|---------|
| `-h`, `--help` | Reference | Quick reference - usage, main options |
| `--info` | Reference | Full reference - all options, more examples |
| `--concepts` | Education | Pre-run learning - what is an image? framework comparison |
| `--guided` | Education | Interactive learning - explanations during workflow |

**When to use:**
- Know what you're doing? → Just run the command, or `--help`
- Need all options? → `--info`
- New to containers? → `--concepts` first
- Learning step-by-step? → `--guided`

### Specific Flags

**container-create:**
- `--image <image>` - Specify Docker image

**container-list:**
- `--all` - Show all users' containers

**image-create:**
- `--project-name <name>` - Specify project name

**dir-create, git-init, readme-create:**
- `--project-name <name>` - Specify project name
- `--project-path <path>` - Specify project directory

## Workflows

### First-Time User Setup

```bash
# Complete onboarding
user-setup

# Or manually:
ssh-setup           # 1. SSH keys
project-init        # 2. Project + container
vscode-setup        # 3. VS Code connection
```

### Creating New Project

```bash
# Streamlined
project-init

# Or guided (educational)
project-init --guided

# Or manually:
dir-create my-project
cd ~/workspace/my-project
git-init
readme-create
image-create
container-create
container-run
```

### Daily Container Usage

```bash
# Start container
container-run my-project

# Inside container: work on project

# Exit container
exit

# Stop container (optional - auto-stops on idle)
container-stop my-project
```

### Managing Containers

```bash
# List your containers
container-list

# Check resource usage
container-stats my-project

# Stop container
container-stop my-project

# Remove stopped container
container-remove my-project
```

### Managing Images

```bash
# Build new image
image-create

# List images
image-list

# Update image after modifying Dockerfile
image-update my-project-image

# Remove unused image
image-delete old-project-image
```

## Resource Limits

All containers are created with resource limits from `/opt/ds01-infra/config/resource-limits.yaml`.

**Check your limits:**
```bash
get-limits           # Shows your resource limits
get-limits --verbose # Detailed breakdown
```

**Limits applied:**
- Max GPUs/MIG instances
- CPU cores
- RAM
- Shared memory
- Max simultaneous containers
- Idle timeout
- GPU hold duration
- Container hold duration

**See:** [config/README.md](../../config/README.md) for configuration details

## Container Lifecycle Automation

### Idle Detection

Containers idle (CPU < 1%) beyond `idle_timeout` are automatically stopped.

**Prevent auto-stop:**
```bash
# Inside container, create keep-alive file
touch ~/.keep-alive
```

### Runtime Enforcement

Containers exceeding `max_runtime` are automatically stopped with warning at 90%.

### GPU Release

GPUs released from stopped containers after `gpu_hold_after_stop` timeout.

### Container Removal

Stopped containers removed after `container_hold_after_stop` timeout.

**See:** [scripts/maintenance/README.md](../maintenance/README.md) for automation details

## Troubleshooting

### Container Creation Fails

**Symptom:** "No GPUs available"

**Check:**
```bash
# View your resource limits
get-limits

# Check GPU allocation status
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status
```

**Solution:** Wait for GPU to become available or contact admin

### Container Won't Start

**Symptom:** "GPU X not found"

**Cause:** Container was created with GPU that no longer exists (MIG reconfiguration, etc.)

**Solution:**
```bash
# Remove old container
container-remove my-project

# Create new container
container-create
```

### Image Build Fails

**Symptom:** Permission denied during image-create

**Check:**
```bash
# Verify docker group membership
groups | grep docker

# Test docker access
docker info
```

**Solution:**
```bash
# Admin adds you to docker group
sudo /opt/ds01-infra/scripts/system/add-user-to-docker.sh $USER

# Log out and back in
exit
```

### Command Not Found

**Symptom:** `container-create: command not found`

**Solution:**
```bash
# Update symlinks (admin)
sudo /opt/ds01-infra/scripts/system/update-symlinks.sh
```

## Advanced Usage

### Custom Dockerfile

```bash
# Edit Dockerfile after creation
vim ~/dockerfiles/my-project.Dockerfile

# Rebuild image
image-update my-project-image

# Recreate container
container-remove my-project
container-create --image ds01-$USER/my-project:latest
```

### Multiple Projects

```bash
# Create multiple projects
project-init  # project1
project-init  # project2
project-init  # project3

# Each gets own:
# - Directory: ~/workspace/project1/
# - Image: ds01-username/project1:latest
# - Container: project1._.username

# Switch between containers:
container-run project1
container-run project2
```

### Shared Images

```bash
# Use someone else's image (if they shared it)
container-create --image ds01-alice/shared-project:latest

# Your container gets their environment
# But your own workspace and GPU allocation
```

## Related Documentation

- [Root README](../../README.md) - System overview
- [ds01-UI_UX_GUIDE.md](../../ds01-UI_UX_GUIDE.md) - **UI/UX design guide** (philosophy, colors, layout)
- [scripts/docker/README.md](../docker/README.md) - Container creation internals, GPU allocation
- [scripts/system/README.md](../system/README.md) - Admin operations, user management
- [scripts/maintenance/README.md](../maintenance/README.md) - Lifecycle automation, cleanup
- [config/README.md](../../config/README.md) - Resource limits configuration
