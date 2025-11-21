# DS01 Infrastructure

Multi-user GPU-enabled container management system for data science workloads with resource quotas, automated lifecycle management, and user-friendly workflows.

## Overview

DS01 Infrastructure provides a **layered, modular architecture** that wraps and enhances [AIME ML Containers](https://github.com/aime-team/aime-ml-containers) with:

- **GPU resource management**: MIG-aware allocation with priority scheduling
- **Per-user resource limits**: Configurable via YAML + systemd cgroups
- **Automated lifecycle management**: Idle detection, auto-cleanup, runtime enforcement
- **User-friendly workflows**: Educational onboarding wizards and modular commands
- **Monitoring and metrics**: Comprehensive logging and dashboards

## Quick Start

**For new users:**
```bash
user-setup          # Complete onboarding: SSH + project + VS Code setup
```

**For administrators:**
```bash
# Add user to docker group (required)
sudo scripts/system/add-user-to-docker.sh <username>

# Update command symlinks
sudo scripts/system/update-symlinks.sh

# View system status
ds01-dashboard
```

## Architecture

### Tiered Hierarchical Design

DS01 uses a **4-tier modular architecture** that wraps AIME MLC strategically rather than replacing it:

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 4: Workflow Wizards                                        │
│ Complete onboarding experiences (user-setup)                     │
├─────────────────────────────────────────────────────────────────┤
│ TIER 3: Workflow Orchestrators                                  │
│ Multi-step workflows (project-init)                             │
├─────────────────────────────────────────────────────────────────┤
│ TIER 2: Modular Unit Commands                                   │
│ Single-purpose, reusable (container-*, image-*, setup modules)  │
├─────────────────────────────────────────────────────────────────┤
│ TIER 1: Base System (aime-ml-containers v2)                     │
│ Core mlc commands + 150+ framework images                       │
└─────────────────────────────────────────────────────────────────┘
        ↓ Enhanced with ↓
┌─────────────────────────────────────────────────────────────────┐
│ DS01 Enhancement Layer                                          │
│ • Resource limits (YAML + systemd cgroups)                      │
│ • GPU allocation (MIG-aware, priority scheduling)               │
│ • Lifecycle automation (idle detection, auto-cleanup)           │
│ • Monitoring & metrics                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Design principles:**
- **Wrap, don't replace**: Use AIME's proven container management
- **Modular and reusable**: Single-purpose commands compose into workflows
- **Educational mode**: All Tier 2+ commands support `--guided` flag
- **Single source of truth**: No code duplication between tiers

**See detailed architecture docs:**
- [scripts/user/README.md](scripts/user/README.md) - Command tiers and user workflows
- [scripts/docker/README.md](scripts/docker/README.md) - Container creation and GPU allocation
- [config/README.md](config/README.md) - Resource limits and configuration

### AIME Integration

**Base system** (`aime-ml-containers` v2):
- 11 core `mlc` commands for container lifecycle
- 150+ pre-built framework images (PyTorch, TensorFlow, JAX, etc.)
- Container naming: `{container-name}._.{user-id}`

**DS01 enhancements:**
- `mlc-patched.py` adds `--image` flag for custom images (2.5% code change)
- Wrappers add resource limits, GPU allocation, interactive UX
- Direct usage of most mlc commands (mlc-open, mlc-list, mlc-stop, etc.)

**Image workflow:**
1. `image-create` builds custom image (4 phases: Framework → Jupyter → Data Science → Use Case)
2. `container-create` calls `mlc-patched.py` with `--image` flag
3. Resource limits applied via systemd cgroups
4. GPU allocated via priority scheduling
5. Container launched with AIME isolation + DS01 management

## Directory Structure

```
ds01-infra/
├── README.md                    # This file (overview + quick start)
├── CLAUDE.md                    # AI assistant reference
│
├── config/                      # Configuration
│   ├── README.md                # Configuration guide
│   ├── resource-limits.yaml     # Central resource config
│   ├── etc-mirrors/             # System config templates
│   └── usr-mirrors/             # User config templates
│
├── scripts/
│   ├── docker/                  # Resource management, GPU allocation
│   │   ├── README.md            # Detailed implementation docs
│   │   ├── mlc-patched.py       # AIME patch for custom images
│   │   ├── mlc-create-wrapper.sh
│   │   ├── get_resource_limits.py
│   │   └── gpu_allocator.py
│   │
│   ├── user/                    # User-facing commands
│   │   ├── README.md            # User command reference
│   │   ├── user-setup           # Tier 4: Complete onboarding wizard
│   │   ├── project-init         # Tier 3: Project setup orchestrator
│   │   ├── container-*          # Tier 2: Container management
│   │   ├── image-*              # Tier 2: Image management
│   │   └── {dir|git|...}-*      # Tier 2: Setup modules
│   │
│   ├── system/                  # System administration
│   │   ├── README.md            # Admin operations guide
│   │   ├── setup-resource-slices.sh
│   │   ├── add-user-to-docker.sh
│   │   └── update-symlinks.sh
│   │
│   ├── monitoring/              # Monitoring & metrics
│   │   ├── README.md            # Monitoring guide
│   │   ├── gpu-status-dashboard.py
│   │   └── collect-*-metrics.sh
│   │
│   ├── maintenance/             # Cleanup automation
│   │   ├── README.md            # Maintenance automation guide
│   │   ├── check-idle-containers.sh
│   │   ├── enforce-max-runtime.sh
│   │   └── cleanup-*.sh
│   │
│   └── lib/                     # Shared libraries
│
└── testing/                     # Test suites
    ├── README.md                # Testing overview
    ├── cleanup-automation/      # Cleanup system tests
    └── validation/              # Integration tests
```

## Installation

### Prerequisites

- Ubuntu/Debian Linux
- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- AIME ML Containers v2 at `/opt/aime-ml-containers`

### Initial Setup

1. **Clone repository:**
```bash
sudo git clone <repo-url> /opt/ds01-infra
cd /opt/ds01-infra
```

2. **Make scripts executable:**
```bash
find scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
```

3. **Configure resource limits:**
```bash
sudo vim config/resource-limits.yaml
# Add your users and groups
```

4. **Setup systemd slices:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

5. **Create command symlinks:**
```bash
sudo scripts/system/update-symlinks.sh
```

6. **Add users to docker group:**
```bash
sudo scripts/system/add-user-to-docker.sh <username>
# User must log out and back in
```

**See detailed installation guide:** [scripts/system/README.md](scripts/system/README.md)

## Configuration

### Resource Limits

Central configuration: `config/resource-limits.yaml`

**Priority order** (highest to lowest):
1. `user_overrides.<username>` - Per-user exceptions (priority 100)
2. `groups.<group>` - Group-based limits (priority varies)
3. `defaults` - Fallback values

**Example:**
```yaml
defaults:
  max_mig_instances: 1           # Max GPUs per user
  max_cpus: 8
  memory: "32g"
  max_containers_per_user: 3
  idle_timeout: "48h"            # Auto-stop after idle
  priority: 10

groups:
  researchers:
    members: [alice, bob]
    max_mig_instances: 2
    memory: "64g"
    priority: 50

user_overrides:
  charlie:                       # Special exception
    max_mig_instances: 3
    priority: 100
    reason: "Thesis work - approved 2025-11-15"
```

**Testing changes:**
```bash
# Test configuration for specific user
python3 scripts/docker/get_resource_limits.py <username>

# Changes take effect immediately (no restart needed)
```

**See full configuration guide:** [config/README.md](config/README.md)

## User Management

### Adding New Users

```bash
# 1. Create Linux user
sudo adduser newstudent
sudo usermod -aG video newstudent

# 2. Add to docker group
sudo scripts/system/add-user-to-docker.sh newstudent

# 3. Add to resource config
sudo vim config/resource-limits.yaml
# Add to appropriate group

# 4. User logs out and back in

# 5. User runs onboarding
user-setup  # As the new user
```

### Granting Additional Resources

Edit `config/resource-limits.yaml`:
```yaml
user_overrides:
  thesis_student:
    max_mig_instances: 2
    memory: "64g"
    idle_timeout: "168h"  # 1 week
    priority: 100
    reason: "Thesis work - approved by Prof. Smith"
```

## Monitoring

### Real-time Status

```bash
# Admin dashboard
ds01-dashboard

# GPU allocation status
python3 scripts/docker/gpu_allocator.py status

# Container resource usage
systemd-cgtop | grep ds01

# NVIDIA GPU monitoring
nvidia-smi
nvitop
```

### Logs

```bash
# GPU allocations
tail -f /var/log/ds01/gpu-allocations.log

# Automated cleanup (cron jobs)
tail -f /var/log/ds01/idle-cleanup.log
tail -f /var/log/ds01/runtime-enforcement.log
tail -f /var/log/ds01/gpu-stale-cleanup.log
tail -f /var/log/ds01/container-stale-cleanup.log

# State files
cat /var/lib/ds01/gpu-state.json
ls /var/lib/ds01/container-metadata/
```

**See monitoring guide:** [scripts/monitoring/README.md](scripts/monitoring/README.md)

## Common Commands

### User Commands

| Command | Description |
|---------|-------------|
| `user-setup` | Complete first-time onboarding wizard |
| `project-init` | Create new project (directory, git, image, container) |
| `container-create` | Create container with resource limits |
| `container-run` | Start and enter container |
| `container-list` | List your containers |
| `container-stop` | Stop running container |
| `image-create` | Build custom Docker image |

**See user command reference:** [scripts/user/README.md](scripts/user/README.md)

### Admin Commands

| Command | Description |
|---------|-------------|
| `ds01-dashboard` | System resource usage dashboard |
| `alias-list` | List all available commands |
| `scripts/system/add-user-to-docker.sh` | Add user to docker group |
| `scripts/system/update-symlinks.sh` | Update command symlinks |
| `scripts/system/setup-resource-slices.sh` | Configure systemd slices |

**See admin guide:** [scripts/system/README.md](scripts/system/README.md)

## Troubleshooting

### Docker Permission Errors

**Symptom:** "Permission denied" when running docker commands

**Solution:**
```bash
# Admin adds user to docker group
sudo scripts/system/add-user-to-docker.sh <username>

# User must log out and back in
exit
# SSH back in

# Verify
groups | grep docker
docker info
```

### Command Not Found

**Symptom:** `user-setup: command not found`

**Solution:**
```bash
sudo scripts/system/update-symlinks.sh
```

### Container Won't Start

**Symptom:** Container fails to start or GPU not accessible

**Check:**
1. User in docker group: `groups | grep docker`
2. GPU allocation state: `python3 scripts/docker/gpu_allocator.py status`
3. Container logs: `docker logs <container-name>`
4. Resource limits: `python3 scripts/docker/get_resource_limits.py <username>`

## Module Documentation

**Detailed documentation for each subsystem:**

- **[scripts/docker/README.md](scripts/docker/README.md)** - Resource management, GPU allocation, container creation internals
- **[scripts/user/README.md](scripts/user/README.md)** - User commands, tier system, workflow details
- **[scripts/system/README.md](scripts/system/README.md)** - System administration, deployment, user management
- **[scripts/monitoring/README.md](scripts/monitoring/README.md)** - Monitoring tools, dashboards, metrics collection
- **[scripts/maintenance/README.md](scripts/maintenance/README.md)** - Cleanup automation, cron jobs, lifecycle management
- **[config/README.md](config/README.md)** - Configuration reference, YAML syntax, policy details
- **[testing/README.md](testing/README.md)** - Testing procedures, test suites, validation

## Contributing

When making changes:

1. Read relevant module README for implementation details
2. Update CLAUDE.md if changing architecture
3. Update module README if changing implementation
4. Test with multiple user types
5. Update symlinks if adding commands: `sudo scripts/system/update-symlinks.sh`

## License

Internal use for Data Science Lab infrastructure.

---

**Last Updated:** November 2025
**Documentation:** See module-specific READMEs for detailed information
