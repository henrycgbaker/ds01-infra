# DS01 Infrastructure - Container Management System

Multi-user GPU-enabled container infrastructure for data science workloads with resource quotas, automated lifecycle management, and user-friendly onboarding.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [User Onboarding Workflows](#user-onboarding-workflows)
- [System Architecture](#system-architecture)
- [Directory Structure](#directory-structure)
- [Command Reference](#command-reference)
- [Configuration](#configuration)
- [User Management](#user-management)
- [Docker Permissions](#docker-permissions)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## 🚀 Quick Start

### For New Users

```bash
# First-time setup with detailed explanations (recommended for beginners)
user-setup

# Or streamlined project setup for experienced users
project-init

# Alternative commands (all equivalent):
user setup          # Same as user-setup (via dispatcher)
new-user           # Legacy alias
```

### For Administrators

```bash
# Add user to docker group (required for Docker access)
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>

# Update system symlinks after changes
sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

# View all available commands
alias-list
```

---

## 👥 User Onboarding Workflows

DS01 provides a modular, tiered onboarding system:

### `user-setup` - Complete First-Time Onboarding

**Target audience**: First-time users, students new to Docker/containers
**Style**: Comprehensive wizard with detailed explanations

**What it does**:
- Orchestrates the complete onboarding flow:
  1. SSH key setup (`ssh-setup`)
  2. Project initialization (`project-init`)
  3. VS Code connection guide (`vscode-setup`)

**Features**:
- Educational mode with Docker concept explanations
- SSH key generation with remote access instructions
- Complete project setup with Git/LFS integration
- Custom Docker image creation with use case templates (General ML, CV, NLP, RL, Custom)
- Container setup and lifecycle management
- VS Code Remote-SSH configuration guide

**Use when**:
- Onboarding new students or researchers
- First-time system access
- Users unfamiliar with container workflows

```bash
user-setup
# Also accessible via: user setup, new-user (legacy)
```

### `project-init` - Project Setup

**Target audience**: Users setting up new projects (can be first-timers with `--guided`)
**Style**: Streamlined workflow with optional educational mode

**What it does**:
- Orchestrates project creation flow:
  1. Directory structure creation (`dir-create`)
  2. Git initialization (`git-init`)
  3. README generation (`readme-create`)
  4. Docker image creation (`image-create`)
  5. Container creation and startup

**Features**:
- Two modes: `project-init` (streamlined) or `project-init --guided` (educational)
- Modular architecture (58.5% reduction from previous monolithic version)
- Reusable components that work standalone or orchestrated
- Use case templates: General ML (default), Computer Vision, NLP, RL, Custom
- Image naming: `{project}-image` format

**Use when**:
- Creating new projects
- Setting up additional workspaces
- Quick project initialization

```bash
project-init                # Streamlined mode
project-init --guided       # Educational mode with explanations
# Also accessible via: project init, new-project (legacy)
```

### Modular Building Blocks (Tier 2)

All orchestrators are built from reusable modules that can also be used standalone:

| Module | Purpose | Supports --guided |
|--------|---------|-------------------|
| `ssh-setup` | SSH key generation & configuration | ✓ |
| `vscode-setup` | VS Code Remote-SSH setup guide | ✓ |
| `dir-create` | Create project directory structure | ✓ |
| `git-init` | Initialize Git repository with ML .gitignore | ✓ |
| `readme-create` | Generate project README with workflow docs | ✓ |
| `image-create` | Build custom Docker image | ✓ |
| `container-create` | Create container with resource limits | ✓ |
| `container-run` | Start and enter container | ✓ |

---

## 🏗️ System Architecture

### Four-Tier Hierarchical Design

DS01 uses a modular, hierarchical architecture that eliminates code duplication and enables flexible composition:

**TIER 1: Base System** (`aime-ml-containers` v1)
- 9 core `mlc-*` commands providing container lifecycle management
- Container image repository with framework versions (PyTorch, TensorFlow, MXNet)
- User isolation via UID/GID mapping (`$CONTAINER_NAME._.$USER_ID`)
- **DS01 Enhancement**: Wraps `mlc-create` and `mlc-stats` with resource limits and GPU allocation

**TIER 2: Modular Unit Commands** (Single-purpose, reusable)
- **Container Management** (7 commands): `container-create`, `container-run`, `container-stop`, `container-list`, `container-stats`, `container-cleanup`, `container-exit`
- **Image Management** (4 commands): `image-create`, `image-list`, `image-update`, `image-delete`
- **Project Setup Modules** (5 commands): `dir-create`, `git-init`, `readme-create`, `ssh-setup`, `vscode-setup`
- All commands support `--guided` flag for educational mode
- Can be used standalone or orchestrated by higher tiers

**TIER 3: Workflow Orchestrators** (Multi-step workflows)
- **`project-init`**: Orchestrates complete project setup (dir-create → git-init → readme-create → image-create → container-create → container-run)
- **Command Dispatchers**: Enable flexible syntax (`container list` or `container-list`)
- 58.5% code reduction through modularization

**TIER 4: Workflow Wizards** (Complete onboarding experiences)
- **`user-setup`**: Full onboarding wizard (ssh-setup → project-init → vscode-setup)
- 69.4% code reduction from original monolithic version
- Educational focus for first-time users

### Key Components

**Resource Management**:
- `config/resource-limits.yaml` - Central YAML configuration (defaults, groups, user overrides)
- `scripts/docker/get_resource_limits.py` - YAML parser returning per-user limits
- `scripts/docker/gpu_allocator.py` - MIG-aware GPU allocation with priority scheduling

**Container Lifecycle**:
- `scripts/docker/mlc-create-wrapper.sh` - Enhanced `mlc-create` with resource limits
- `scripts/monitoring/mlc-stats-wrapper.sh` - Enhanced `mlc-stats` with GPU process info
- Lifecycle automation: idle detection, auto-cleanup based on `idle_timeout` in YAML

**System Administration**:
- `scripts/system/add-user-to-docker.sh` - Add users to `docker` group
- `scripts/system/update-symlinks.sh` - Create symlinks for all 30+ commands in `/usr/local/bin/`
- `scripts/system/setup-resource-slices.sh` - Configure systemd cgroup slices from YAML

---

## 📁 Directory Structure

```
ds01-infra/
├── config/
│   ├── resource-limits.yaml          # Central resource configuration
│   ├── etc-mirrors/                  # System config mirrors
│   └── usr-mirrors/                  # User config templates
│
├── scripts/
│   ├── user/                         # User-facing commands
│   │   ├── user-setup                # Educational onboarding wizard
│   │   ├── new-project               # Streamlined project setup
│   │   ├── user-dispatcher.sh        # Routes user subcommands
│   │   ├── project-init              # Wrapper for new-project
│   │   ├── container-*               # Container management commands
│   │   └── image-*                   # Image management commands
│   │
│   ├── system/                       # System administration
│   │   ├── add-user-to-docker.sh     # Add user to docker-users group
│   │   ├── update-symlinks.sh        # Update command symlinks
│   │   └── setup-resource-slices.sh  # Configure systemd slices
│   │
│   ├── admin/                        # Admin utilities
│   │   ├── alias-list                # Display all commands
│   │   └── ...
│   │
│   ├── docker/                       # Container creation & GPU allocation
│   │   ├── mlc-create-wrapper.sh     # Enhanced container creation
│   │   ├── get_resource_limits.py    # YAML parser
│   │   └── gpu_allocator.py          # GPU allocation manager
│   │
│   ├── monitoring/                   # Metrics & auditing
│   │   ├── gpu-status-dashboard.py
│   │   └── collect-*-metrics.sh
│   │
│   └── maintenance/                  # Cleanup & housekeeping
│       └── cleanup-idle-containers.sh
│
├── README.md                         # This file
├── CLAUDE.md                         # AI assistant guidance
└── docs/                             # Additional documentation
```

See subdirectory READMEs for detailed documentation:
- [scripts/user/README.md](scripts/user/README.md) - User command reference
- [scripts/system/README.md](scripts/system/README.md) - System administration guide

---

## 🎯 Command Reference

### Tier 4: Workflow Wizards

| Command | Description | Supports --guided |
|---------|-------------|-------------------|
| `user-setup` | Complete first-time onboarding (SSH + project + VS Code) | Always guided |
| `user setup` | Same (via dispatcher) | Always guided |

**Legacy aliases**: `new-user` → `user-setup`

### Tier 3: Workflow Orchestrators

| Command | Description | Supports --guided |
|---------|-------------|-------------------|
| `project-init` | Complete project setup workflow | ✓ |
| `project init` | Same (via dispatcher) | ✓ |

**Legacy aliases**: `new-project` → `project-init`

### Tier 2: Modular Commands

**Container Management** (all support both `container <cmd>` and `container-<cmd>`):

| Command | Description | Supports --guided |
|---------|-------------|-------------------|
| `container-create` | Create container with resource limits | ✓ |
| `container-run` | Start and enter container | ✓ |
| `container-stop` | Stop running container | - |
| `container-list` | List all your containers | - |
| `container-stats` | Resource usage statistics | - |
| `container-cleanup` | Remove stopped containers | - |
| `container-exit` | Show exit information | ✓ |

**Image Management** (all support both `image <cmd>` and `image-<cmd>`):

| Command | Description | Supports --guided |
|---------|-------------|-------------------|
| `image-create` | Build custom Docker image | ✓ |
| `image-list` | List available images | - |
| `image-update` | Rebuild/update image | - |
| `image-delete` | Remove unused images | - |

**Project Setup Modules**:

| Command | Description | Supports --guided |
|---------|-------------|-------------------|
| `dir-create` | Create project directory structure | ✓ |
| `git-init` | Initialize Git with ML .gitignore | ✓ |
| `readme-create` | Generate project README | ✓ |
| `ssh-setup` | Configure SSH keys for remote access | ✓ |
| `vscode-setup` | VS Code Remote-SSH setup guide | ✓ |

### Tier 1: Base System

| Command | Description | DS01 Enhancement |
|---------|-------------|------------------|
| `mlc-create` | Create container (framework + version) | ✓ Adds resource limits & GPU allocation |
| `mlc-stats` | Show container resource usage | ✓ Adds GPU process info |
| `mlc-open` | Open shell to container | Used directly from base system |
| `mlc-list` | List all containers | Used directly from base system |
| `mlc-start` | Start container without shell | Used directly from base system |
| `mlc-stop` | Stop container | Used directly from base system |
| `mlc-remove` | Delete container | Used directly from base system |

### Admin Commands

| Command | Description |
|---------|-------------|
| `alias-list` | Display all available commands |
| `ds01-status` | System resource usage status |

**💡 All commands support `--help` for detailed usage**

---

## ⚙️ Configuration

### Resource Limits (`config/resource-limits.yaml`)

Central configuration file controlling all resource allocations.

**Priority order** (highest to lowest):
1. `user_overrides.<username>` - Per-user exceptions (priority 100)
2. `groups.<group>` - Group-based limits (priority varies)
3. `defaults` - Fallback for unspecified fields

**Key fields**:
```yaml
defaults:
  max_mig_instances: 1           # Max GPUs per user
  max_cpus: 8                    # CPU cores per container
  memory: "32g"                  # RAM per container
  shm_size: "8g"                 # Shared memory
  max_containers_per_user: 3     # Max simultaneous containers
  idle_timeout: "48h"            # Auto-stop after idle time
  priority: 10                   # Allocation priority (1-100)
```

**Testing changes**:
```bash
# Test for specific user
python3 scripts/docker/get_resource_limits.py <username>

# Changes take effect on next container creation (no restart needed)
```

---

## 👥 User Management

### Adding New Users

1. **Create Linux user**:
```bash
sudo adduser newstudent
sudo usermod -aG video newstudent  # GPU access
```

2. **Add to docker group**:
```bash
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh newstudent
```

3. **Add to resource config**:
```bash
vim /opt/ds01-infra/config/resource-limits.yaml

# Add to appropriate group:
groups:
  students:
    members: [alice, bob, newstudent]
```

4. **User logs out and back in** (for docker group membership to take effect)

5. **User runs onboarding**:
```bash
new-user  # First-time setup wizard
```

### Granting Additional Resources

```bash
vim /opt/ds01-infra/config/resource-limits.yaml

# Add user override:
user_overrides:
  thesis_student:
    max_mig_instances: 2
    memory: "64g"
    idle_timeout: "168h"  # 1 week
    priority: 100
    reason: "Thesis work - approved by Prof. Smith"
```

---

## 🔐 Docker Permissions

### Docker Group Configuration

DS01 uses the standard **`docker`** group for Docker socket access.

**How it works:**
- The Docker daemon creates a Unix socket at `/var/run/docker.sock`
- This socket is owned by `root:docker`
- Users in the `docker` group can access it without sudo

### Adding Users to Docker Group

**Automated (recommended)**:
```bash
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>
```

**Manual**:
```bash
# Add user to docker group
sudo usermod -aG docker <username>

# User must log out and back in
```

**Verify**:
```bash
groups | grep docker  # Should show docker
docker info           # Should work without sudo
```

### Troubleshooting Permission Errors

If users see "Docker permission error" during image build:

1. **Check group membership**:
```bash
groups  # Should include docker
```

2. **If not in group, admin adds them**:
```bash
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh $USER
```

3. **User logs out and back in** (group membership requires new session)

4. **Verify Docker access**:
```bash
docker info  # Should work without errors
```

---

## 🚀 Deployment

### Initial Setup

1. **Clone repository**:
```bash
cd /opt
sudo git clone <repository-url> ds01-infra
sudo chown -R root:ds-admin ds01-infra
sudo chmod -R g+rwX ds01-infra
```

2. **Install dependencies**:
```bash
sudo apt install python3-yaml
```

3. **Make scripts executable**:
```bash
cd /opt/ds01-infra
find scripts -type f -name "*.sh" -exec chmod +x {} \;
find scripts -type f -name "*.py" -exec chmod +x {} \;
```

4. **Set up systemd slices**:
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

6. **Create command symlinks**:
```bash
sudo scripts/system/update-symlinks.sh
```

7. **Configure resource limits**:
```bash
vim config/resource-limits.yaml
# Add your users and groups
```

### Updating Symlinks

After adding new commands or changing script locations:

```bash
sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh
```

This creates/updates symlinks in `/usr/local/bin/` for:
- `new-user` → `user-setup`
- `user-setup` → `user-setup`
- `user` → `user-dispatcher.sh`
- `new-project` → `new-project`
- `project-init` → `new-project`

---

## 📊 Monitoring

### Real-time Status

```bash
# GPU usage
nvidia-smi
nvitop

# Container status
container-list
docker stats

# System-wide resources
ds01-status
```

### Log Files

```bash
# GPU allocations
tail -f /var/log/ds01/gpu-allocations.log

# Container metadata
ls /var/lib/ds01/container-metadata/

# GPU state
cat /var/lib/ds01/gpu-state.json
```

### Health Checks

```bash
# Check systemd slices
systemctl status ds01.slice
systemd-cgtop | grep ds01

# Verify Docker permissions
groups | grep docker-users
docker info

# Test resource parser
python3 scripts/docker/get_resource_limits.py <username>
```

---

## 🐛 Troubleshooting

### Common Issues

#### Docker Permission Errors

**Symptom**: "You don't have permission to use Docker"

**Solution**:
```bash
# Admin adds user to group
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>

# User logs out and back in
exit
# SSH back in

# Verify
groups | grep docker-users
docker info
```

#### Command Not Found

**Symptom**: `new-user: command not found`

**Solution**:
```bash
# Update symlinks
sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

# Verify
ls -la /usr/local/bin/ | grep ds01
```

#### Image Build Fails

**Symptom**: Build errors during `new-user` or `new-project`

**Common causes**:
1. No Docker permissions (see above)
2. Network issues downloading base images
3. Disk space full

**Debug**:
```bash
# Check Docker access
docker info

# Check disk space
df -h

# Try manual build
cd ~/docker-images
docker build -t test-image -f <project>-image.Dockerfile .
```

#### Color Codes Not Rendering

**Symptom**: Seeing `\033[1m` in output instead of colors

**Cause**: Scripts must use `echo -e` to render ANSI color codes

**Fixed in**: All user-facing scripts now use `echo -e` for color output

---

## 🔄 Recent Changes

### November 2025 - Major Architecture Refactoring (Phases 1-6)

**Phase 1 [NEW]: Base System Integration Audit**
- Documented all 9 mlc-* commands from AIME MLC v1 base system
- Verified 2 wrapped commands (mlc-create, mlc-stats) with DS01 enhancements
- Confirmed 7 commands used directly from base system
- Established four-tier hierarchical architecture

**Phase 2-3: Modular Command Extraction**
- Created 5 new Tier 2 modules: `dir-create`, `git-init`, `readme-create`, `ssh-setup`, `vscode-setup`
- Added `--guided` flag support across all commands
- Consistent educational content for beginners
- Each module works standalone or orchestrated

**Phase 4: Orchestrator Refactoring**
- Refactored `project-init` from 958 → 397 lines (58.5% reduction)
- Eliminated 561 lines of duplicated code
- Now calls Tier 2 modules instead of duplicating logic
- Clean orchestrator pattern: prompts → delegates to modules

**Phase 5: Wizard Creation**
- Refactored `user-setup` from 932 → 285 lines (69.4% reduction)
- Orchestrates: ssh-setup → project-init → vscode-setup
- Clean Tier 4 wizard pattern achieved
- Total elimination of code duplication between user and project setup

**Phase 6: Exit Functionality Documentation Fix**
- Completely rewrote `container-exit` with accurate docker exec behavior
- Removed all misleading Ctrl+P, Ctrl+Q references (doesn't work with docker exec)
- Updated `container-aliases.sh` and `container-stop` with correct exit instructions
- Added deprecation notices to legacy files

**Phase 7: Documentation & Symlink Management**
- Comprehensive `update-symlinks.sh` covering all 30+ commands organized by tier
- Updated `README.md` with four-tier architecture
- Updated `CLAUDE.md` with complete base system integration
- Updated `REFACTORING_PLAN.md` documenting all completed phases

**Overall Results**:
- **>1,100 lines of code eliminated** through modularization
- **Zero code duplication**: Single source of truth for each operation
- **Enhanced user experience**: Consistent `--guided` mode across all commands
- **Accurate documentation**: All exit behavior correctly documented (docker exec, not attach)
- **Clean architecture**: Base System → Modules → Orchestrators → Wizards

**Command Changes**:
- `user-setup` is now the primary onboarding wizard (not just an alias)
- `project-init` is the primary project setup command
- `new-user` and `new-project` are legacy aliases for backwards compatibility
- All commands support flexible dispatcher syntax (`container list` or `container-list`)
- Docker group standardization: all scripts use standard `docker` group

**New Modules (Tier 2)**:
- `dir-create` - Project directory structure creation
- `git-init` - Git repository initialization with ML .gitignore
- `readme-create` - Project README generation
- `ssh-setup` - SSH key configuration for remote access
- `vscode-setup` - VS Code Remote-SSH setup guide

**Scripts Updated**:
- `scripts/system/update-symlinks.sh` - Now manages all 30+ commands by tier
- `scripts/user/project-init` - Modular orchestrator (58.5% smaller)
- `scripts/user/user-setup` - Modular wizard (69.4% smaller)
- `scripts/user/container-exit` - Accurate docker exec documentation
- `config/container-aliases.sh` - Fixed exit behavior documentation

---

## 📚 Additional Documentation

- **User Documentation**: See onboarding wizards (`new-user` or `new-project`)
- **CLAUDE.md**: Guidance for AI assistants working with this codebase
- **Subdirectory READMEs**:
  - [scripts/user/README.md](scripts/user/README.md)
  - [scripts/system/README.md](scripts/system/README.md)

---

## 📝 Contributing

When adding new features:

1. Update relevant README files
2. Update CLAUDE.md if changing architecture
3. Add `--help` output to new commands
4. Test with multiple user types (students, researchers, admins)
5. Update `scripts/system/update-symlinks.sh` if adding commands

---

**Last Updated**: November 2025
**Maintained by**: Data Science Lab Infrastructure Team
