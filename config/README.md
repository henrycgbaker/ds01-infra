# Configuration - Resource Limits & Policies

Central configuration for DS01 resource management.

## Overview

DS01 configuration follows a **three-tier pattern**:

| Tier | Directory | Purpose |
|------|-----------|---------|
| **Source of Truth** | `config/` root | Active configuration that DS01 reads |
| **Deploy Sources** | `config/deploy/` | Files to copy TO /etc/ (cron, systemd, etc.) |
| **Reference Mirrors** | `config/*-mirrors/` | Copies FROM /etc/ for version control |

### Source of Truth Files

| File | Purpose |
|------|---------|
| `resource-limits.yaml` | Main config (defaults, group settings, policies) |
| `groups/*.members` | Group member lists (one file per group) |
| `user-overrides.yaml` | Per-user exceptions |

Related files:
- `scripts/lib/error-messages.sh` - User-facing error message templates

## Directory Structure

```
config/
├── resource-limits.yaml     # Source of truth: main configuration
├── user-overrides.yaml      # Source of truth: per-user exceptions
├── groups/                  # Source of truth: group membership
│   ├── student.members      # Student group members
│   ├── researcher.members   # Researcher group members
│   └── admin.members        # Admin group members
├── deploy/                  # Deploy sources (files to copy TO /etc/)
│   ├── cron.d/              # Cron job definitions → /etc/cron.d/
│   ├── logrotate.d/         # Log rotation configs → /etc/logrotate.d/
│   ├── profile.d/           # Shell PATH configs → /etc/profile.d/
│   ├── systemd/             # Service unit files → /etc/systemd/system/
│   ├── docker/              # Docker daemon configs
│   └── opa/                 # OPA policy files
├── etc-mirrors/             # Reference mirrors (copies FROM /etc/)
│   ├── profile.d/           # Mirror of /etc/profile.d/ds01-*
│   ├── skel/                # Mirror of /etc/skel/.bashrc
│   ├── sudoers.d/           # Mirror of /etc/sudoers.d/ds01-*
│   ├── pam.d/               # Mirror of PAM configuration
│   └── cron.d/              # Mirror of /etc/cron.d/ds01-*
├── usr-mirrors/             # Reference mirrors (copies FROM /usr/)
│   └── local/lib/           # Mirror of /usr/local/lib/
└── README.md                # This file
```

## Three-Tier Pattern Explained

### 1. Source of Truth (config/ root)

These are the active configuration files that DS01 scripts read at runtime:

```bash
# Scripts read these directly
python3 scripts/docker/get_resource_limits.py alice
# Reads: config/resource-limits.yaml, config/groups/*.members, config/user-overrides.yaml
```

### 2. Deploy Sources (config/deploy/)

Files that need to be deployed to system directories. Use `deploy.sh` to copy them:

```bash
# Deploy all config files to /etc/
sudo /opt/ds01-infra/scripts/system/deploy.sh

# Manual deployment example
sudo cp config/deploy/cron.d/ds01-cleanup /etc/cron.d/ds01-cleanup
sudo cp config/deploy/profile.d/ds01-path.sh /etc/profile.d/ds01-path.sh
```

**Deploy directories:**
- `cron.d/` - Scheduled tasks (cleanup, monitoring)
- `logrotate.d/` - Log rotation rules
- `profile.d/` - Shell PATH configuration
- `systemd/` - Service definitions (proxy, monitors)
- `docker/` - Docker daemon configuration
- `opa/` - OPA authorization policies

### 3. Reference Mirrors (*-mirrors/)

Copies of files FROM /etc/ and /usr/ for version control. These let you:
- Track what's actually deployed on the system
- Detect drift between repo and system
- Restore system config from git

```bash
# Update mirrors from live system
cp /etc/profile.d/ds01-path.sh config/etc-mirrors/profile.d/
cp /etc/skel/.bashrc config/etc-mirrors/skel/

# Check for drift
diff config/deploy/profile.d/ds01-path.sh /etc/profile.d/ds01-path.sh
```

## Member File Format

Group member files use a simple text format (one username per line):

```
# config/groups/researcher.members
# ================================================
# Researcher Group Members
# ================================================
# Format: One username per line matching /home/<username>
# Comments start with #
# ================================================

204214@hertie-school.lan          # Silke Kaiser (student ID)
c.fusarbassini@hertie-school.lan  # Chiara Fusarbassini (staff)
```

**Benefits of modular member files:**
- Add comments to identify users
- Easier to audit group membership
- Git diffs show exactly who was added/removed
- No YAML syntax errors from editing member lists

## User Overrides File Format

Per-user exceptions are in `config/user-overrides.yaml`:

```yaml
# config/user-overrides.yaml
# Per-user resource limit overrides

204214@hertie-school.lan:
  idle_timeout: null               # No idle timeout
  max_runtime: null                # No runtime limit
  container_hold_after_stop: null  # Don't auto-remove
  # Reason: Thesis work - approved 2025-XX-XX

# h.baker@hertie-school.lan:
#   max_mig_instances: 4
#   allow_full_gpu: true
```

## Main Config Structure (resource-limits.yaml)

```yaml
defaults:                    # Fallback for all users
  max_mig_instances: 1
  max_cpus: 8
  memory: "32g"
  # ... more defaults

groups:                      # Group-based limits (members in separate files)
  student:
    # Members: config/groups/student.members
    allow_full_gpu: false
    max_mig_per_container: 3

  researcher:
    # Members: config/groups/researcher.members
    allow_full_gpu: true
    max_mig_instances: 8
    # ... group settings

gpu_allocation:              # GPU/MIG configuration
  mig_instances_per_gpu: 4

policies:                    # System-wide policies
  high_demand_threshold: 0.8
  high_demand_idle_reduction: 0.5
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

**max_mig_instances** - Maximum GPUs/MIG instances (total across all containers)
```yaml
max_mig_instances: 2        # Max 2 GPUs total
max_mig_instances: null     # Unlimited (admin only)
```

**max_mig_per_container** - Maximum MIG-equivalents per single container
```yaml
max_mig_per_container: 1    # 1 MIG per container (default for students)
max_mig_per_container: 4    # 4 MIGs per container (= 1 full GPU)
max_mig_per_container: null # Unlimited (admin only)
```

**allow_full_gpu** - Can user request full GPUs (vs MIG partitions only)
```yaml
allow_full_gpu: false       # Students: MIG only
allow_full_gpu: true        # Researchers/admins: can use full GPUs
```

**mig_instances_per_gpu** - How many MIGs equal one full GPU (in gpu_allocation section)
```yaml
gpu_allocation:
  mig_instances_per_gpu: 4  # 1 full GPU = 4 MIG-equivalents
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

### Add New User to a Group

1. **Add to group member file:**
```bash
# Edit the appropriate member file
nano config/groups/researcher.members
```

```
# Add line to file:
newuser@hertie-school.lan    # New User Name
```

2. **Test:**
```bash
python3 scripts/docker/get_resource_limits.py newuser@hertie-school.lan
```

3. **No restart needed** - changes take effect immediately

### Change Group Limits

1. **Modify group settings in resource-limits.yaml:**
```yaml
groups:
  researcher:
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
python3 scripts/docker/get_resource_limits.py diana@hertie-school.lan
```

### Add User Override

1. **Add override to user-overrides.yaml:**
```yaml
# config/user-overrides.yaml
newspecial@hertie-school.lan:
  max_mig_instances: 4
  priority: 100
  # Reason: Special project - approved by PI
```

2. **Test:**
```bash
python3 scripts/docker/get_resource_limits.py newspecial@hertie-school.lan
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

### sudoers.d - Privileged Operations

**File:** `/opt/ds01-infra/config/etc-mirrors/sudoers.d/ds01-user-management`
**Deploy to:** `/etc/sudoers.d/ds01-user-management`

**Purpose:** Allow docker group members to:
- Create their own systemd user slices (for container cgroups)
- Add users to the docker group (for first-time setup)

**Deployment:**
```bash
sudo cp /opt/ds01-infra/config/etc-mirrors/sudoers.d/ds01-user-management /etc/sudoers.d/ds01-user-management
sudo chmod 440 /etc/sudoers.d/ds01-user-management
```

### pam.d - First-Login Docker Group

**File:** `/opt/ds01-infra/config/etc-mirrors/pam.d/ds01-docker-group`
**Deploy to:** Append to `/etc/pam.d/common-session`

**Purpose:** Auto-add users to docker group on first login

**Deployment:**
```bash
# Add this line to /etc/pam.d/common-session:
session optional pam_exec.so /opt/ds01-infra/scripts/system/pam-add-docker-group.sh
```

### cron.d - Scheduled Tasks

**File:** `/opt/ds01-infra/config/etc-mirrors/cron.d/ds01-docker-group`
**Deploy to:** `/etc/cron.d/ds01-docker-group`

**Purpose:** Hourly scan to add new users to docker group

**Deployment:**
```bash
sudo cp /opt/ds01-infra/config/etc-mirrors/cron.d/ds01-docker-group /etc/cron.d/ds01-docker-group
sudo chmod 644 /etc/cron.d/ds01-docker-group
```

## Permissions & Security

### Directory Structure Permissions

DS01 infrastructure uses restrictive permissions to limit user access:

```
/opt/ds01-infra/                    # 751 (owner rwx, docker group r-x, others --x)
├── scripts/                         # 751
│   ├── *.sh, *.py                  # 750 (owner rwx, docker group r-x, others ---)
│   └── lib/                        # 751
│       ├── username-utils.sh       # 640 (owner rw, docker group r, others ---)
│       └── username_utils.py       # 640
├── config/                          # 751
│   └── resource-limits.yaml        # 640
└── aime-ml-containers/             # 751
    └── *.py, *.repo                # 640
```

**Key Principles:**
- **Directories:** `751` = owner can do anything, docker group can read/traverse, others can only traverse (no listing)
- **Scripts:** `750` = owner can execute, docker group can read (needed to run), others cannot access
- **Config files:** `640` = owner read/write, docker group read-only, others no access

**Group Ownership:** All DS01 files owned by `datasciencelab:docker`

### User Access Model

Users must be in the `docker` group to:
- Read/execute DS01 scripts
- Run Docker commands
- Deploy containers

**Docker Group Auto-Assignment:**

| Method | When | Description |
|--------|------|-------------|
| PAM session | Every login | Auto-adds on first login |
| Cron job | Hourly | Scans /home for missing users |
| user-setup | On demand | Wizard requests access |

### Systemd Slice Permissions

Users can create their own cgroup slices via sudo:

```bash
# Allowed by /etc/sudoers.d/ds01-user-management
sudo /opt/ds01-infra/scripts/system/create-user-slice.sh <group> <username>
```

**Security:** Script only creates slices under `ds01-*.slice` hierarchy

### Log File Permissions

```
/var/log/ds01/
├── gpu-allocator.lock              # 666 (all users can acquire lock)
├── gpu-allocations.log             # 644 (root writes, all read)
├── docker-group-additions.log      # 644
└── events.jsonl                    # 644
```

## User Identifier Format for Group Membership

When adding users to `groups.*.members` or `user_overrides`, you must use the **exact format
that matches their home directory** at `/home/<username>`.

### Identifier Formats by User Type

| User Type | Home Dir Format | Config Format | Example |
|-----------|-----------------|---------------|---------|
| **Staff/Faculty** | `/home/firstname.lastname@domain` | `firstname.lastname@domain` | `h.baker@hertie-school.lan` |
| **Students** | `/home/studentID@domain` | `studentID@domain` | `204214@hertie-school.lan` |
| **System/Local** | `/home/shortname` | `shortname` | `datasciencelab` |

### Why This Matters

The system captures the username via `os.getlogin()` at container creation time, which returns
the format the user actually logged in as. This is stored in the `ds01.user` container label
and matched against the config.

### How to Find a User's Correct Format

```bash
# Check their home directory
ls -la /home/ | grep -i "username"

# Get their UID to confirm identity
id "username@hertie-school.lan"

# Test config matching
python3 scripts/docker/get_resource_limits.py "username@hertie-school.lan"
```

### Common Mistakes

**Wrong:** Using a different LDAP alias that doesn't match the login format
```yaml
# WRONG - s.kaiser is a different LDAP entry, never logged in
members: [s.kaiser@hertie-school.lan]

# CORRECT - 204214 is how the user actually logs in
members: [204214@hertie-school.lan]
```

**Tip:** Always verify with `ls /home/` to see what format the user actually uses.

### Example Configuration

```yaml
groups:
  researcher:
    # Staff use name format, students use ID format
    members:
      - 204214@hertie-school.lan         # Student (Silke Kaiser)
      - c.fusarbassini@hertie-school.lan # Staff (Chiara)
      - h.baker@hertie-school.lan        # Staff (H. Baker)

  admin:
    members:
      - datasciencelab                   # System account (no domain)

user_overrides:
  204214@hertie-school.lan:              # Must match /home/204214@hertie-school.lan
    idle_timeout: null
```

---

## LDAP/SSSD Username Support

DS01 supports LDAP/SSSD usernames containing special characters (e.g., `h.baker@hertie-school.lan`).

### Username Sanitization

Usernames are sanitized for systemd slice compatibility:

| Original | Sanitized |
|----------|-----------|
| `h.baker@hertie-school.lan` | `h-baker-at-hertie-school-lan` |
| `john.doe` | `john-doe` |
| `alice` | `alice` (unchanged) |

**Sanitization rules:**
- `@` → `-at-`
- `.` → `-`
- Other special chars → `-`
- Multiple hyphens collapsed
- Leading/trailing hyphens trimmed

### Config Lookup Behavior

YAML config supports **both** original and sanitized usernames:

```yaml
user_overrides:
  # Either format works:
  h.baker@hertie-school.lan:    # Original format (recommended)
    max_mig_instances: 2

  # OR
  h-baker-at-hertie-school-lan: # Sanitized format (also works)
    max_mig_instances: 2
```

The system tries original username first, then falls back to sanitized form.

### Sanitization Library

**Bash:** `/opt/ds01-infra/scripts/lib/username-utils.sh`
```bash
source /opt/ds01-infra/scripts/lib/username-utils.sh
sanitize_username_for_slice "h.baker@hertie-school.lan"
# Output: h-baker-at-hertie-school-lan
```

**Python:** `/opt/ds01-infra/scripts/lib/username_utils.py`
```python
from username_utils import sanitize_username_for_slice
sanitize_username_for_slice("h.baker@hertie-school.lan")
# Output: 'h-baker-at-hertie-school-lan'
```

## Related Documentation

- [Root README](../README.md) - System overview
- [scripts/docker/README.md](../scripts/docker/README.md) - How limits are enforced
- [scripts/system/README.md](../scripts/system/README.md) - Systemd slice configuration
- [scripts/maintenance/README.md](../scripts/maintenance/README.md) - Lifecycle automation
