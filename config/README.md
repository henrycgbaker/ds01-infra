# Configuration - Resource Limits & Policies

Central configuration for DS01 resource management.

## Overview

`resource-limits.yaml` is the **single source of truth** for:
- Per-user/group resource limits (GPU, CPU, memory)
- Container lifecycle policies (timeouts, auto-cleanup)
- GPU allocation priorities
- MIG configuration

## File Structure

```yaml
defaults:                    # Fallback for all users
  max_mig_instances: 1
  max_cpus: 8
  memory: "32g"
  # ... more defaults

groups:                      # Group-based limits
  students:
    members: [alice, bob]
    max_mig_instances: 1
    priority: 10
    # ... group settings

  researchers:
    members: [charlie, diana]
    max_mig_instances: 2
    priority: 50
    # ... group settings

user_overrides:              # Per-user exceptions
  special_user:
    max_mig_instances: 3
    priority: 100
    reason: "Thesis work"
    # ... user-specific overrides

gpu_allocation:              # GPU/MIG configuration
  enable_mig: true
  mig_profile: "2g.20gb"

policies:                    # System-wide policies
  allow_multi_container: true
  enforce_resource_limits: true
```

## Priority Order

Limits resolved with this precedence (highest to lowest):
1. **user_overrides.<username>** - Explicit per-user settings
2. **groups.<group>** - Group membership
3. **defaults** - System fallback

**Example:**
```yaml
defaults:
  max_mig_instances: 1
  memory: "32g"

groups:
  researchers:
    members: [alice]
    max_mig_instances: 2    # Alice inherits this
    memory: "64g"           # Alice inherits this

user_overrides:
  alice:
    max_mig_instances: 3    # Alice gets this (overrides group)
    # memory: "64g" inherited from group
```

**Alice's final limits:**
- max_mig_instances: 3 (from user_overrides)
- memory: "64g" (from group)
- Everything else from defaults

## Configuration Fields

### Resource Limits

**max_mig_instances** - Maximum GPUs/MIG instances
```yaml
max_mig_instances: 2        # Max 2 GPUs
max_mig_instances: null     # Unlimited (admin only)
```

**max_cpus** - CPU cores per container
```yaml
max_cpus: 16                # 16 CPU cores
```

**memory** - RAM per container
```yaml
memory: "64g"               # 64 GB RAM
memory: "128g"
```

**shm_size** - Shared memory (for PyTorch dataloader, etc.)
```yaml
shm_size: "16g"             # 16 GB shared memory
```

**max_containers_per_user** - Simultaneous containers
```yaml
max_containers_per_user: 3  # Max 3 containers running
```

### Lifecycle Policies

**idle_timeout** - Auto-stop after idle time
```yaml
idle_timeout: "48h"         # Stop if idle (CPU < 1%) for 48 hours
idle_timeout: "72h"         # 3 days
idle_timeout: null          # Never auto-stop
```

**max_runtime** - Maximum container runtime
```yaml
max_runtime: "168h"         # Stop after 7 days running
max_runtime: null           # No limit
```

**gpu_hold_after_stop** - Hold GPU after container stops
```yaml
gpu_hold_after_stop: "24h"  # Hold GPU for 24h after stop
gpu_hold_after_stop: null   # Hold indefinitely
gpu_hold_after_stop: "0h"   # Release immediately
```

**container_hold_after_stop** - Keep container after stop
```yaml
container_hold_after_stop: "12h"  # Remove 12h after stop
container_hold_after_stop: null   # Never auto-remove
container_hold_after_stop: "0h"   # Remove immediately
```

### Priority & Scheduling

**priority** - GPU allocation priority (1-100)
```yaml
priority: 10               # Student priority
priority: 50               # Researcher priority
priority: 100              # Admin priority
```

Higher priority users get:
- First choice of available GPUs
- Preference in allocation conflicts

### Documentation

**reason** - Justification for user override
```yaml
user_overrides:
  special_user:
    max_mig_instances: 3
    reason: "Thesis work - approved 2025-11-21 by Prof. Smith"
```

## Complete Example

```yaml
# Default settings for all users
defaults:
  max_mig_instances: 1
  max_cpus: 8
  memory: "32g"
  shm_size: "8g"
  max_containers_per_user: 3
  idle_timeout: "48h"
  max_runtime: "168h"
  gpu_hold_after_stop: "24h"
  container_hold_after_stop: "12h"
  priority: 10

# Group-based limits
groups:
  students:
    members: [alice, bob, charlie]
    max_mig_instances: 1
    max_cpus: 8
    memory: "32g"
    idle_timeout: "48h"
    priority: 10

  researchers:
    members: [diana, eve, frank]
    max_mig_instances: 2
    max_cpus: 16
    memory: "64g"
    shm_size: "16g"
    idle_timeout: "72h"
    gpu_hold_after_stop: "48h"
    priority: 50

  admin:
    members: [grace]
    max_mig_instances: null       # Unlimited
    max_cpus: 32
    memory: "128g"
    shm_size: "32g"
    idle_timeout: null            # Never auto-stop
    max_runtime: null
    gpu_hold_after_stop: null     # Hold indefinitely
    container_hold_after_stop: null
    priority: 90

# Per-user exceptions
user_overrides:
  henry:                          # Thesis student
    max_mig_instances: 3
    memory: "96g"
    idle_timeout: "168h"          # 1 week
    gpu_hold_after_stop: "72h"    # 3 days
    priority: 100
    reason: "Thesis work - large model training - approved 2025-11-21"

  isabel:                         # Short job user
    idle_timeout: "24h"           # Short idle timeout
    gpu_hold_after_stop: "1h"     # Release GPU quickly
    container_hold_after_stop: "1h"
    reason: "Quick experiments - resource sharing"

# GPU/MIG configuration
gpu_allocation:
  enable_mig: true
  mig_profile: "2g.20gb"          # 3 instances per A100

# System policies
policies:
  allow_multi_container: true
  enforce_resource_limits: true
  log_allocations: true
```

## Special Values

**null** - Disables limit/timeout
```yaml
max_mig_instances: null     # Unlimited GPUs
idle_timeout: null          # Never auto-stop
gpu_hold_after_stop: null   # Hold indefinitely
```

**"0h"** - Immediate action
```yaml
gpu_hold_after_stop: "0h"   # Release GPU immediately on stop
container_hold_after_stop: "0h"  # Remove container immediately on stop
```

## Time Format

Use hours with "h" suffix:
- `"1h"` = 1 hour
- `"24h"` = 1 day
- `"48h"` = 2 days
- `"168h"` = 1 week

## MIG Configuration

**enable_mig** - Enable MIG tracking
```yaml
gpu_allocation:
  enable_mig: true
```

**mig_profile** - MIG instance type
```yaml
gpu_allocation:
  mig_profile: "2g.20gb"    # 3 instances per A100 80GB
  # Other options: "1g.10gb", "3g.40gb", "7g.80gb"
```

**MIG GPU IDs:**
- Physical GPU + instance: `"0:0"`, `"0:1"`, `"0:2"`
- Allocated independently

**Check MIG instances:**
```bash
nvidia-smi mig -lgi
```

## Testing Configuration

### Validate YAML Syntax

```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
# No output = valid YAML
```

### Test User Limits

```bash
# Check specific user
python3 scripts/docker/get_resource_limits.py alice

# Check multiple users
for user in alice bob charlie; do
    echo "=== $user ==="
    python3 scripts/docker/get_resource_limits.py $user
done
```

### Test Priority Resolution

```bash
# Should show: user_override > group > defaults
python3 scripts/docker/get_resource_limits.py alice --verbose
```

### Test Docker Args

```bash
# Get Docker-compatible arguments
python3 scripts/docker/get_resource_limits.py alice --docker-args
```

## Common Patterns

### Student Group

```yaml
students:
  members: [alice, bob, charlie]
  max_mig_instances: 1        # 1 GPU max
  max_cpus: 8                 # 8 cores
  memory: "32g"               # 32 GB
  idle_timeout: "48h"         # Stop after 2 days idle
  gpu_hold_after_stop: "12h"  # Release GPU in 12h
  priority: 10                # Low priority
```

### Researcher Group

```yaml
researchers:
  members: [diana, eve]
  max_mig_instances: 2        # 2 GPUs
  max_cpus: 16                # 16 cores
  memory: "64g"               # 64 GB
  shm_size: "16g"             # Larger shared memory
  idle_timeout: "72h"         # Stop after 3 days
  gpu_hold_after_stop: "48h"  # Hold GPU 2 days
  priority: 50                # Medium priority
```

### Admin/Power User

```yaml
admin:
  members: [grace]
  max_mig_instances: null     # Unlimited GPUs
  max_cpus: 32                # 32 cores
  memory: "128g"              # 128 GB
  idle_timeout: null          # Never auto-stop
  max_runtime: null           # No runtime limit
  gpu_hold_after_stop: null   # Hold GPU indefinitely
  priority: 90                # High priority
```

### Thesis Student (Override)

```yaml
user_overrides:
  henry:
    max_mig_instances: 3      # Special allocation
    memory: "96g"
    idle_timeout: "168h"      # 1 week
    priority: 100             # Highest priority
    reason: "Thesis work - large model training - approved 2025-11-21"
```

### Quick Job User (Override)

```yaml
user_overrides:
  isabel:
    idle_timeout: "24h"             # Short idle
    gpu_hold_after_stop: "1h"       # Quick release
    container_hold_after_stop: "1h" # Fast cleanup
    reason: "Quick experiments - resource sharing optimization"
```

## Modifying Configuration

### Add New User

1. **Add to group:**
```yaml
groups:
  students:
    members: [alice, bob, charlie, newstudent]  # Add newstudent
```

2. **Test:**
```bash
python3 scripts/docker/get_resource_limits.py newstudent
```

3. **No restart needed** - changes take effect immediately

### Change Group Limits

1. **Modify group settings:**
```yaml
groups:
  researchers:
    max_mig_instances: 3  # Changed from 2
    memory: "96g"         # Changed from 64g
```

2. **Update systemd slices:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

3. **Test:**
```bash
python3 scripts/docker/get_resource_limits.py diana
```

### Add User Override

1. **Add override:**
```yaml
user_overrides:
  newspecial:
    max_mig_instances: 4
    priority: 100
    reason: "Special project - approved by PI"
```

2. **Test:**
```bash
python3 scripts/docker/get_resource_limits.py newspecial
```

## Troubleshooting

### User Gets Wrong Limits

**Check user exists in config:**
```bash
grep username config/resource-limits.yaml
```

**Check priority resolution:**
```bash
python3 scripts/docker/get_resource_limits.py username --verbose
```

**Common issues:**
- Typo in username
- User not in any group
- Group missing from `groups` section
- YAML syntax error

### YAML Syntax Error

**Validate:**
```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

**Common errors:**
- Incorrect indentation (use spaces, not tabs)
- Missing colon after key
- Unquoted strings with special characters
- Inconsistent list format

**Fix:**
```yaml
# Wrong
groups:
students:  # Missing indent
  members: [alice, bob]

# Correct
groups:
  students:  # Proper indent
    members: [alice, bob]
```

### Changes Not Applied

**Resource limits:** Take effect immediately (no restart)
```bash
python3 scripts/docker/get_resource_limits.py username
```

**Systemd slices:** Need update
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

## System Configuration Mirrors

DS01 tracks system configuration files in git for version control and reproducibility.

### profile.d - Shell PATH Configuration

**File:** `/opt/ds01-infra/config/etc-mirrors/profile.d/ds01-path.sh`
**Deploy to:** `/etc/profile.d/ds01-path.sh`

**Purpose:** System-wide PATH configuration for login shells

**Deployment:**
```bash
sudo cp /opt/ds01-infra/config/etc-mirrors/profile.d/ds01-path.sh /etc/profile.d/ds01-path.sh
sudo chmod 644 /etc/profile.d/ds01-path.sh
```

### skel - New User Template

**File:** `/opt/ds01-infra/config/etc-mirrors/skel/.bashrc`
**Deploy to:** `/etc/skel/.bashrc`

**Purpose:** Template bashrc for new users with DS01 PATH configuration

**Deployment:**
```bash
sudo cp /opt/ds01-infra/config/etc-mirrors/skel/.bashrc /etc/skel/.bashrc
sudo chmod 644 /etc/skel/.bashrc
```

**Maintenance:** When Ubuntu updates `/etc/skel/.bashrc`, merge DS01 additions

## Related Documentation

- [Root README](../README.md) - System overview
- [scripts/docker/README.md](../scripts/docker/README.md) - How limits are enforced
- [scripts/system/README.md](../scripts/system/README.md) - Systemd slice configuration
- [scripts/maintenance/README.md](../scripts/maintenance/README.md) - Lifecycle automation
