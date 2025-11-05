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
# First-time setup with detailed explanations (recommended)
new-user

# Or streamlined setup for experienced users
new-project

# Alternative commands (all equivalent):
user setup
user new
user-setup
```

### For Administrators

```bash
# Add user to Docker group
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>

# Update system symlinks after changes
sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

# View all available commands
alias-list
```

---

## 👥 User Onboarding Workflows

DS01 provides two complementary onboarding experiences:

### `new-user` - Educational Onboarding

**Target audience**: First-time users, students new to Docker/containers
**Style**: Comprehensive with detailed explanations

**Features**:
- Step-by-step wizard with explanations of Docker concepts
- SSH key setup with educational context
- Git repository initialization and LFS setup
- Project structure options (data science layout vs blank)
- Custom Docker image creation with use case templates
- Container setup and VS Code integration instructions
- Comprehensive README generation with workflow documentation

**Use when**:
- Onboarding new students or researchers
- Users unfamiliar with container workflows
- Setting up first project on the system

```bash
new-user
# Also accessible via: user-setup, user setup, user new
```

### `new-project` - Streamlined Setup

**Target audience**: Experienced users familiar with the system
**Style**: Concise, minimal explanations

**Features**:
- Quick project setup wizard
- Same technical capabilities as `new-user`
- Assumes familiarity with Docker/containers
- Minimal prompts, efficient workflow

**Use when**:
- Creating additional projects
- User already completed `new-user` onboarding
- Fast project initialization needed

```bash
new-project
# Also accessible via: project init
```

### Workflow Comparison

| Feature | new-user | new-project |
|---------|----------|-------------|
| SSH Setup | ✓ with explanations | ✓ streamlined |
| Git Integration | ✓ with LFS education | ✓ quick setup |
| Docker Concepts | ✓ explained | assumed knowledge |
| Use Case Templates | 5 options (General ML default) | 5 options (General ML default) |
| Image Naming | `{project}-image` | `{project}-image` |
| README Generation | ✓ comprehensive | ✓ concise |
| Container Creation | ✓ guided | ✓ efficient |

---

## 🏗️ System Architecture

### Three-Layer Design

1. **Base System**: `aime-ml-containers` (external dependency)
   - Core `mlc-*` CLI commands
   - Container image repository
   - User isolation via UID/GID mapping

2. **Enhancement Layer**: `ds01-infra` (this repository)
   - Resource limits and GPU allocation
   - Systemd cgroup integration
   - Lifecycle automation
   - User-friendly command wrappers

3. **User Interface**: Simplified commands
   - `new-user` / `new-project` - Onboarding wizards
   - `container-*` commands - Container management
   - `image-*` commands - Image management
   - Dispatcher scripts for flexible command syntax

### Key Components

**User Onboarding**:
- `scripts/user/user-setup` - Educational onboarding wizard (`new-user`)
- `scripts/user/new-project` - Streamlined project setup
- `scripts/user/user-dispatcher.sh` - Routes `user setup`, `user new` to user-setup
- `scripts/user/project-init` - Wrapper for `new-project`

**Container Management**:
- `scripts/user/container-*` - User-facing container commands
- `scripts/docker/mlc-create-wrapper.sh` - Enhanced container creation
- `scripts/docker/gpu_allocator.py` - MIG-aware GPU allocation

**System Administration**:
- `scripts/system/add-user-to-docker.sh` - Add users to docker-users group
- `scripts/system/update-symlinks.sh` - Update command symlinks
- `scripts/system/setup-resource-slices.sh` - Configure systemd slices

**Resource Management**:
- `config/resource-limits.yaml` - Central resource configuration
- `scripts/docker/get_resource_limits.py` - YAML parser for user limits

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

### User Setup Commands

| Command | Description |
|---------|-------------|
| `new-user` | First-time onboarding with detailed explanations (recommended) |
| `user-setup` | Same as `new-user` |
| `user setup` | Same as `new-user` (via dispatcher) |
| `user new` | Same as `new-user` (via dispatcher) |
| `new-project` | Streamlined project setup for experienced users |
| `project init` | Same as `new-project` |

### Container Commands

All container commands support both forms: `container <subcommand>` or `container-<subcommand>`

| Command | Description |
|---------|-------------|
| `container create` | Create new container |
| `container run` | Start and attach to container |
| `container stop` | Stop running container |
| `container list` | List all containers |
| `container stats` | Resource usage statistics |
| `container cleanup` | Remove stopped containers |

### Image Commands

| Command | Description |
|---------|-------------|
| `image create` | Create custom Docker image |
| `image list` | List available images |
| `image update` | Rebuild/update an image |
| `image delete` | Remove unused images |

### Admin Commands

| Command | Description |
|---------|-------------|
| `alias-list` | Display all available commands |
| `ds01-dashboard` | System overview dashboard |
| `ds01-status` | Resource usage status |

Run any command with `--help` for detailed usage.

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

2. **Add to docker-users group**:
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

4. **User logs out and back in** (for group membership to take effect)

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

DS01 uses the **`docker-users`** group (not `docker`) for Docker permissions.

**Why `docker-users` instead of `docker`?**
- Aligns with security best practices
- Separate from system docker group
- Easier to manage multi-user environments

### Adding Users to Docker Group

**Automated (recommended)**:
```bash
sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>
```

**Manual**:
```bash
# Create group if needed
sudo groupadd docker-users

# Add user
sudo usermod -aG docker-users <username>

# User must log out and back in
```

**Verify**:
```bash
groups | grep docker-users  # Should show docker-users
docker info                 # Should work without sudo
```

### Troubleshooting Permission Errors

If users see "Docker permission error" during image build:

1. **Check group membership**:
```bash
groups  # Should include docker-users
```

2. **If not in group, admin adds them**:
```bash
sudo usermod -aG docker-users $USER
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

4. **Create docker-users group**:
```bash
sudo groupadd docker-users
```

5. **Set up systemd slices**:
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
tail -f /var/logs/ds01/gpu-allocations.log

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

### November 2025 - User Onboarding Overhaul

**New Features**:
- Dual onboarding workflows: `new-user` (educational) and `new-project` (streamlined)
- Command dispatcher pattern: `user setup`, `user new` route to `user-setup`
- Flexible command syntax: both `container list` and `container-list` work
- Docker group standardization: all scripts use `docker-users` group
- Image naming convention: `{project}-image` (not `{username}-{project}`)
- General ML as default use case (option 1)
- Fixed color code rendering throughout all scripts

**Scripts Added**:
- `scripts/user/user-dispatcher.sh` - Routes user subcommands
- `scripts/system/add-user-to-docker.sh` - Helper for Docker permissions
- `scripts/system/update-symlinks.sh` - Automates symlink management

**Scripts Renamed**:
- `new-user-setup.sh` → `user-setup` (simpler name)
- `new-project-setup` → `new-project` (consistent naming)

**Bug Fixes**:
- Fixed shebang line in `user-setup` (must be line 1)
- Fixed color codes requiring `echo -e` throughout
- Fixed Docker permission error handling
- Fixed success messages appearing on build failures

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
