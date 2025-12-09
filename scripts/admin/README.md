# Admin Tools - System Management & Dashboards

Administrative utilities for system management, monitoring, and user administration.

## Overview

Admin tools provide system administrators with:
- Unified system dashboards (GPU, containers, resources)
- User management utilities
- MIG partition configuration
- Log viewing and analysis
- Command alias management

## Primary Admin Interface

### dashboard

**Main admin dashboard** - Unified system monitoring interface.

**Purpose:** Single-pane-of-glass view of GPU allocation, container status, system resources, and alerts.

**Features:**
- GPU/MIG allocation with hierarchical container display
- Color-coded utilization bars (green <50%, yellow 50-80%, red >90%)
- System resources (CPU, RAM, Disk, Swap)
- Recent GPU allocations with timestamps
- Active alerts and warnings
- Per-user resource breakdown

**Usage:**
```bash
dashboard                    # Default compact view
dashboard --full             # All sections expanded
dashboard --watch / -w       # Watch mode (2s refresh)
dashboard --json             # JSON output for scripting

# Subcommands (modular sections)
dashboard gpu                # GPU/MIG utilization with containers
dashboard mig-config         # MIG partition configuration
dashboard system             # CPU, Memory, Disk utilization
dashboard containers         # All containers with stats
dashboard users              # Per-user resource breakdown
dashboard allocations [N]    # Recent N GPU allocations (default: 10)
dashboard temp               # GPU temperatures
dashboard alerts             # Active alerts and warnings
```

**Visual Features:**
- Full GPUs shown in cyan, MIG-enabled GPUs in green
- Allocated containers shown in yellow
- FREE slots shown in green
- Progress bars for all utilization metrics

---

## Log Management

### ds01-logs

**Log viewer and search utility.**

**Purpose:** View and search DS01 system logs with filtering and formatting.

**Features:**
- View multiple log types (GPU allocations, events, cleanup, errors)
- Filter by user, container, event type
- Tail mode for real-time monitoring
- JSON output for programmatic access

**Usage:**
```bash
ds01-logs                    # Interactive log selection
ds01-logs gpu                # GPU allocation logs
ds01-logs events             # Centralized event log
ds01-logs cleanup            # Cleanup automation logs
ds01-logs --user alice       # Filter by user
ds01-logs --tail             # Follow mode (like tail -f)
ds01-logs --json             # JSON output
```

**Log types:**
- `gpu` - GPU allocation/release events
- `events` - Centralized event log (JSONL)
- `container` - Container lifecycle events
- `cleanup` - Automated cleanup operations
- `idle` - Idle detection and warnings
- `runtime` - Max runtime enforcement
- `errors` - Error and warning logs

---

## User Management

### ds01-users

**User management utilities.**

**Purpose:** View and manage DS01 users, groups, and resource allocations.

**Features:**
- List all DS01 users with groups and limits
- Show user's active containers and GPU allocations
- Display resource usage vs. limits
- Export user data for auditing

**Usage:**
```bash
ds01-users                   # List all users
ds01-users alice             # Details for specific user
ds01-users --group researchers  # Filter by group
ds01-users --active          # Only users with active containers
ds01-users --json            # JSON output
```

**Output includes:**
- Username and group membership
- Resource limits (GPUs, CPUs, memory)
- Active containers and GPU allocations
- Current resource usage
- Warnings if approaching limits

---

## GPU Management

### ds01-mig-partition

**MIG partition configuration tool.**

**Purpose:** Configure NVIDIA Multi-Instance GPU (MIG) partitions on A100 GPUs.

**Features:**
- List current MIG configuration
- Create/destroy MIG instances
- Reset MIG partitions
- Validate MIG configuration
- Show available MIG profiles

**Usage:**
```bash
ds01-mig-partition status            # Show current MIG configuration
ds01-mig-partition list-profiles     # Available MIG profiles
ds01-mig-partition create 0 2g.20gb  # Create MIG instance on GPU 0
ds01-mig-partition destroy 0 0       # Destroy MIG instance 0 on GPU 0
ds01-mig-partition reset 0           # Reset GPU 0 (destroy all instances)
ds01-mig-partition validate          # Validate current configuration
```

**Common MIG profiles:**
- `1g.10gb` - 1/7th GPU, 10GB memory (7 instances per A100)
- `2g.20gb` - 2/7th GPU, 20GB memory (3 instances per A100)
- `3g.40gb` - 3/7th GPU, 40GB memory (2 instances per A100)
- `7g.80gb` - Full GPU, 80GB memory (1 instance per A100)

**Warning:** Changing MIG configuration requires stopping all containers using affected GPUs.

---

## Command Management

### alias-create

**Command alias creator.**

**Purpose:** Create custom command aliases for frequently used DS01 operations.

**Usage:**
```bash
alias-create myalias "container-list --all | grep alice"
alias-create gpu-check "dashboard gpu && nvidia-smi"
```

**Aliases are stored in:** `/etc/profile.d/ds01-aliases.sh`

---

### alias-list

**List all DS01 command aliases.**

**Purpose:** Show all custom command aliases with their definitions.

**Usage:**
```bash
alias-list                   # Show all aliases
alias-list --search gpu      # Filter by keyword
```

---

## System Information

### help

**DS01 help system.**

**Purpose:** Display help information for DS01 commands and concepts.

**Usage:**
```bash
help                         # Main help menu
help containers              # Container command help
help gpu                     # GPU allocation help
help resources               # Resource limits help
help troubleshooting         # Troubleshooting guide
```

---

### version

**DS01 version information.**

**Purpose:** Display DS01 infrastructure version and component versions.

**Usage:**
```bash
version                      # Show version info
version --full               # Include component versions (Docker, AIME, etc.)
```

**Output includes:**
- DS01 infrastructure version
- Last deployment date
- Git commit hash
- Docker version
- NVIDIA driver/CUDA version
- AIME MLC version

---

## Emergency Tools

### bypass-enforce-containers.sh

**Emergency enforcement bypass.**

**Purpose:** Temporarily disable container resource enforcement for emergency situations.

**WARNING:** This bypasses all resource limits. Use only in emergencies.

**Usage:**
```bash
sudo bypass-enforce-containers.sh enable   # Disable enforcement
sudo bypass-enforce-containers.sh disable  # Re-enable enforcement
sudo bypass-enforce-containers.sh status   # Check current state
```

**When to use:**
- System maintenance requiring elevated access
- Emergency recovery from resource limit issues
- Testing without enforcement

**Always re-enable enforcement after use.**

---

## Common Admin Workflows

### Daily System Check

```bash
# 1. System overview
dashboard

# 2. Check for alerts
dashboard alerts

# 3. Review recent activity
ds01-logs events --tail 50

# 4. Check resource usage
ds01-users --active
```

### Investigating User Issues

```bash
# 1. User details
ds01-users alice

# 2. User's containers
container-list --all | grep alice

# 3. User's logs
ds01-logs --user alice

# 4. Check limits
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py alice
```

### GPU Troubleshooting

```bash
# 1. GPU status
dashboard gpu

# 2. Physical GPU check
nvidia-smi

# 3. Allocation state
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status

# 4. Recent GPU events
ds01-logs gpu --tail 100
```

### MIG Reconfiguration

```bash
# 1. Check current config
ds01-mig-partition status

# 2. Stop affected containers
# (Manual: identify and stop containers on target GPU)

# 3. Reset MIG
sudo ds01-mig-partition reset 0

# 4. Create new instances
sudo ds01-mig-partition create 0 2g.20gb

# 5. Validate
ds01-mig-partition validate

# 6. Restart containers
# (Users can restart their containers)
```

---

## Access Control

All admin tools require:
- Membership in `ds01-admin` Linux group, OR
- Listed in `resource-limits.yaml` `groups.admin.members`, OR
- Root access

Regular users cannot access admin tools.

---

## Related Documentation

- [Root README](../../README.md) - System architecture
- [scripts/monitoring/README.md](../monitoring/README.md) - Monitoring tools
- [scripts/user/README.md](../user/README.md) - User commands
- [config/README.md](../../config/README.md) - Resource configuration
