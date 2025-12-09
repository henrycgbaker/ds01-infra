# Docker Scripts - Resource Management & GPU Allocation

Container creation, resource limit enforcement, and GPU allocation management.

## Overview

This directory contains the **core DS01 enhancement layer** that wraps AIME MLC with:
- Custom image support (mlc-patched.py)
- Resource limit enforcement (get_resource_limits.py, mlc-create-wrapper.sh)
- GPU allocation and scheduling (gpu_allocator.py)
- MIG-aware GPU management

## Key Components

### Container Creation

**mlc-patched.py** - AIME MLC v2 patch for custom images
- Adds `--image` flag to bypass AIME catalog
- Validates local Docker image existence
- Adds DS01 labels: `DS01_MANAGED=true`, `CUSTOM_IMAGE=<image-name>`
- **2.5% code modification** - 97.5% of AIME logic preserved
- Makes upgrading to new AIME versions easier

**mlc-create-wrapper.sh** - Enhanced container creation
- Entry point for `container-create` command
- Reads user resource limits from YAML
- Allocates GPU via `gpu_allocator.py`
- Calls `mlc-patched.py` with appropriate flags
- Sets up systemd cgroup hierarchy
- Creates container metadata in `/var/lib/ds01/container-metadata/`

**Usage:**
```bash
# Called by container-create command
scripts/docker/mlc-create-wrapper.sh <container-name> <image-name> <user>
```

### Resource Management

**get_resource_limits.py** - YAML configuration parser
- Reads `/opt/ds01-infra/config/resource-limits.yaml`
- Resolves user limits with priority: user_overrides > groups > defaults
- Returns Docker-compatible resource arguments

**Usage:**
```bash
# Test resource limits for a user
python3 scripts/docker/get_resource_limits.py <username>

# Get Docker CLI arguments
python3 scripts/docker/get_resource_limits.py <username> --docker-args
```

**Output:**
```
User: alice
Group: researchers
Priority: 50
Max MIG Instances: 2
Max CPUs: 16
Memory: 64g
Shared Memory: 16g
Max Containers: 3
Idle Timeout: 72h
GPU Hold After Stop: 24h
Container Hold After Stop: 12h
```

**ds01-resource-query.py** - Runtime resource query tool
- Queries current resource usage and limits
- Used by monitoring scripts and user commands
- Shows active containers, GPU allocations, resource consumption

### GPU Allocation

**gpu_allocator.py** - Core GPU allocation manager
- **Stateful allocation** with priority-based scheduling
- **MIG-aware**: Tracks physical GPUs and MIG instances separately
- **Least-allocated strategy**: Balances load across GPUs
- **Time-based reservations**: Hold GPUs after container stop
- **State persistence**: `/var/lib/ds01/gpu-state.json`

**Key operations:**
- `allocate` - Request GPU for container
- `release` - Free GPU from container
- `mark-stopped` - Record container stop time
- `clear-stopped` - Clear stop timestamp (on restart)
- `status` - Show current allocations
- `validate` - Check GPU availability

**Usage:**
```bash
# Show current allocations
python3 scripts/docker/gpu_allocator.py status

# Allocate GPU
python3 scripts/docker/gpu_allocator.py allocate \
    --user alice \
    --container my-project \
    --max-gpus 2 \
    --priority 50

# Release GPU
python3 scripts/docker/gpu_allocator.py release --container my-project

# Mark container stopped (holds GPU)
python3 scripts/docker/gpu_allocator.py mark-stopped --container my-project

# Clear stopped timestamp (on restart)
python3 scripts/docker/gpu_allocator.py clear-stopped --container my-project

# Validate GPU still exists
python3 scripts/docker/gpu_allocator.py validate \
    --container my-project \
    --gpu "0"
```

**State file** (`/var/lib/ds01/gpu-state.json`):
```json
{
  "allocations": {
    "my-project._.alice": {
      "user": "alice",
      "gpu_id": "0",
      "allocated_at": "2025-11-21T10:30:00",
      "priority": 50,
      "stopped_at": null
    }
  },
  "last_updated": "2025-11-21T10:30:00"
}
```

**gpu-allocator-smart.py** - Enhanced allocator with predictive features
- Experimental version with load prediction
- Not currently used in production

**gpu-state-reader.py** - Read-only state viewer
- Safely reads GPU state without modification
- Used by monitoring dashboards

### MIG Support

**mig-config-parser.py** - MIG configuration parser
- Parses `nvidia-smi mig -lgi` output
- Extracts MIG instance details
- Used by gpu_allocator.py for MIG-aware allocation

**MIG configuration** (in `config/resource-limits.yaml`):
```yaml
gpu_allocation:
  enable_mig: true
  mig_profile: "2g.20gb"  # 3 instances per A100
```

**MIG GPU IDs:**
- Physical GPU + instance: `0:0`, `0:1`, `0:2`
- Tracked separately in allocation state
- Each instance allocated independently

### Utility Scripts

**docker-wrapper.sh** - Universal enforcement wrapper
- Intercepts all Docker commands at `/usr/local/bin/docker`
- Injects per-user systemd cgroup (`ds01-{group}-{user}.slice`)
- Injects ownership labels (`ds01.user`, `ds01.managed`)
- Ensures all containers (from any interface) are subject to resource limits
- Transparently passes through to `/usr/bin/docker`

**container-init.sh** - Container initialization handler
- DS01-specific container setup on first start
- Configures workspace mounts and permissions
- Sets up user environment variables
- Called by AIME MLC on container start

**container-entrypoint.sh** - Container entrypoint script
- Legacy container initialization (deprecated, use container-init.sh)
- Configures user shell, aliases, environment variables

**gpu-availability-checker.py** - GPU availability validation
- Checks if GPUs are accessible via nvidia-smi
- Validates MIG instance availability
- Used during container start to validate GPU still exists

**emergency-container-stop.sh** - Force stop containers
- Emergency shutdown script
- Bypasses normal cleanup hooks
- Use only in emergencies

## Design Decisions

### `set -e` Not Used in mlc-create-wrapper.sh

**Problem:** Container creation was failing with "exit code: 2" and no diagnostic output.

**Root Cause:** The wrapper script used `set -e` (exit on error), which caused the script to exit immediately when capturing command output in a `$()` substitution. Error handling code never ran.

**Solution:** Temporarily disable `set -e` around the mlc-patched.py call:
```bash
set +e  # Disable exit-on-error to allow error handling
MLC_OUTPUT=$(python3 "$MLC_PATCHED" $MLC_ARGS 2>&1)
MLC_EXIT_CODE=$?
set -e  # Re-enable
```

**Rationale:** Allows the script to capture exit codes and provide user-friendly error messages instead of silent failures.

**Prevention:** When writing wrapper scripts, always use `set +e` / `set -e` pairs around command substitutions that may fail, OR use `|| true` pattern.

See: [testing/cleanup-automation/FINDINGS.md](../../testing/cleanup-automation/FINDINGS.md) for detailed analysis.

---

### GPU Allocation File Locking

**Problem:** Race conditions when multiple container-create commands ran simultaneously, causing duplicate GPU allocations.

**Solution:** Use Python `fcntl.flock()` for file-based locking in `gpu_allocator.py`:
```python
import fcntl
with open(STATE_FILE, 'r+') as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)  # Exclusive lock
    # ... read, modify, write state ...
    # Lock released automatically on file close
```

**Rationale:** File locking ensures atomic read-modify-write operations on GPU state, preventing race conditions without requiring a database.

**Alternative Considered:** Advisory locks via `flock` command were rejected due to inconsistent behavior across shells.

---

### CUDA_VISIBLE_DEVICES for MIG Isolation

**Problem:** When allocating a single MIG instance (e.g., `0:1`), need to ensure container only sees that instance, not all MIG instances on the physical GPU.

**Solution:** Set `CUDA_VISIBLE_DEVICES` environment variable to the specific MIG UUID:
```bash
# For single MIG: export CUDA_VISIBLE_DEVICES=<MIG-UUID>
# For multiple MIG: export CUDA_VISIBLE_DEVICES=<UUID1>,<UUID2>
# For full GPU: use --gpus device=0 (no CUDA_VISIBLE_DEVICES needed)
```

**Rationale:** Docker's `--gpus device=X:Y` syntax does not isolate MIG instances at the CUDA runtime level. Setting `CUDA_VISIBLE_DEVICES` ensures CUDA applications only see their allocated MIG instance.

**Reference:** NVIDIA MIG documentation on CUDA visibility.

---

### IPC Mode vs shm-size Mutual Exclusivity

**Problem:** Docker does not allow `--ipc=host` and `--shm-size` to be specified together (returns error).

**Solution:** In resource limits, use either `ipc_mode: host` OR `shm_size: 16g`, never both:
```yaml
# Option 1: IPC host mode (shared memory unlimited via host)
ipc_mode: host

# Option 2: Custom shared memory size (isolated IPC namespace)
shm_size: 16g
```

**Rationale:** This is a Docker constraint. Host IPC mode gives unlimited shared memory but reduces isolation. Custom shm-size provides isolation but requires explicit limit.

**Current Default:** `shm_size: 16g` for better isolation. Groups requiring unlimited shared memory can use `ipc_mode: host` override.

---

### GID Mapping Fix ("I have no name!" error)

**Problem:** Containers showed "I have no name!" error when LDAP GID didn't exist in container's `/etc/group`.

**Root Cause:** AIME MLC's `mlc-create` only created the user, not the group. When host LDAP GID (e.g., 5025) doesn't exist in container, user has no group name.

**Solution:** 6-step robust user/group creation in `mlc-patched.py`:
```python
# 1. Check if GID exists
# 2. If not, create group with matching GID
# 3. Check if UID exists
# 4. If not, create user with matching UID/GID
# 5. Verify user creation
# 6. Set ownership of home directory
```

**Rationale:** Ensures both user AND group exist in container with matching host UID/GID, fixing name resolution issues.

**Testing:** Verified with LDAP users having non-standard GIDs (5000-6000 range).

---

### Python Heredoc Variable Substitution

**Problem:** Variables in Python heredocs were not being substituted, causing scripts to use literal `$VAR` strings instead of values.

**Root Cause:** Bash heredoc delimiters must be unquoted for variable substitution to occur. Using `<<'PYEOF'` prevents substitution.

**Solution:** Pass variables via environment instead of heredoc substitution:
```bash
# Bad: Variables in heredoc (doesn't work with quoted delimiter)
python3 <<'PYEOF'
user = "$USERNAME"  # Literal string "$USERNAME"
PYEOF

# Good: Pass via environment
export DS01_USERNAME="$USERNAME"
python3 <<'PYEOF'
import os
user = os.environ['DS01_USERNAME']  # Correctly receives value
PYEOF
```

**Rationale:** Using quoted delimiters (`<<'EOF'`) is safer (prevents unintended variable expansion), and environment variables are the standard way to pass data to subprocesses.

**Convention:** All Python heredocs use quoted delimiters and environment variables for inputs.

---

### LDAP Username Sanitization

**Problem:** LDAP usernames with dots and `@` symbols (e.g., `h.baker@hertie-school.lan`) cannot be used in systemd slice names (hyphens are the only valid separators).

**Solution:** Sanitize usernames for systemd using underscores:
```bash
# Original: h.baker@hertie-school.lan
# Sanitized: h_baker_hertie-school_lan
sanitize_username_for_slice() {
    echo "$1" | sed 's/@/_/g; s/\./_/g'
}
```

**Rationale:** Systemd slice names have strict character requirements. Underscores are valid and preserve readability. This is applied consistently in:
- `docker-wrapper.sh` (cgroup injection)
- `username-utils.sh` (library function)
- `username_utils.py` (Python equivalent)

**Important:** Container names and Docker labels still use original username for user identification. Sanitization is ONLY for systemd slice names.

---

## Container Creation Flow

Complete flow from user command to running container:

```
1. User runs: container-create my-project

2. container-create script calls:
   scripts/docker/mlc-create-wrapper.sh my-project ds01-alice/my-project:latest alice

3. mlc-create-wrapper.sh:
   a. Calls get_resource_limits.py alice
   b. Gets: max_gpus=2, cpus=16, memory=64g, priority=50

   c. Calls gpu_allocator.py allocate --user alice --container my-project --max-gpus 2 --priority 50
   d. Gets: gpu_id="0" (or "0:1" for MIG)

   e. Creates systemd cgroup: /sys/fs/cgroup/ds01-researchers-alice.slice

   f. Calls mlc-patched.py with flags:
      --image ds01-alice/my-project:latest
      --gpus device=0
      --cpus 16
      --memory 64g
      --cgroup-parent ds01-researchers-alice.slice

   g. Saves metadata: /var/lib/ds01/container-metadata/my-project._.alice.json

4. mlc-patched.py:
   a. Validates image exists locally
   b. Adds DS01 labels
   c. Creates container via Docker API
   d. Names it: my-project._.alice

5. Container starts with:
   - GPU 0 allocated exclusively
   - 16 CPU cores max
   - 64GB RAM max
   - Systemd cgroup limits enforced
   - User workspace mounted
```

## Container Lifecycle

### Creation
```bash
container-create my-project
# → mlc-create-wrapper.sh → get_resource_limits.py + gpu_allocator.py → mlc-patched.py
```

### Start/Run
```bash
container-run my-project
# → Validates GPU still exists → mlc-open → clears stopped timestamp
```

### Stop
```bash
container-stop my-project
# → mlc-stop → gpu_allocator.py mark-stopped → GPU held for hold_after_stop duration
```

### Restart
```bash
container-start my-project
# → Validates GPU → mlc-open → gpu_allocator.py clear-stopped
```

### Removal
```bash
container-remove my-project
# → mlc-remove → gpu_allocator.py release → metadata deleted
```

## Testing

### Test Resource Limits

```bash
# Test for specific user
python3 scripts/docker/get_resource_limits.py alice

# Test multiple users
for user in student1 researcher1 admin1; do
    echo "=== $user ==="
    python3 scripts/docker/get_resource_limits.py $user
done

# Get Docker args format
python3 scripts/docker/get_resource_limits.py alice --docker-args
```

### Test GPU Allocator

```bash
# Check current status
python3 scripts/docker/gpu_allocator.py status

# Test allocation (dry run)
python3 scripts/docker/gpu_allocator.py allocate \
    --user testuser \
    --container test-container \
    --max-gpus 1 \
    --priority 10

# View state
cat /var/lib/ds01/gpu-state.json | python3 -m json.tool

# Test release
python3 scripts/docker/gpu_allocator.py release --container test-container
```

### Test MIG Configuration

```bash
# View MIG instances
nvidia-smi mig -lgi

# Test MIG parsing
python3 scripts/docker/mig-config-parser.py

# Test MIG allocation
python3 scripts/docker/gpu_allocator.py allocate \
    --user alice \
    --container mig-test \
    --max-gpus 1 \
    --priority 50
# Should allocate MIG instance like "0:1"
```

### Test mlc-patched.py

```bash
# Build test image
docker build -t test-image:latest -f ~/dockerfiles/test.Dockerfile ~/dockerfiles/

# Test custom image creation
python3 scripts/docker/mlc-patched.py \
    --image test-image:latest \
    --gpus device=0 \
    --cpus 4 \
    --memory 16g \
    testcontainer

# Verify labels
docker inspect testcontainer._.$(whoami) | grep -A5 Labels
```

## State Management

### GPU State

**Location:** `/var/lib/ds01/gpu-state.json`

**Structure:**
```json
{
  "allocations": {
    "container-name._.username": {
      "user": "username",
      "gpu_id": "0",
      "allocated_at": "2025-11-21T10:00:00",
      "priority": 50,
      "stopped_at": "2025-11-21T12:00:00"
    }
  },
  "last_updated": "2025-11-21T12:00:00"
}
```

**Fields:**
- `user` - Username
- `gpu_id` - GPU ID (e.g., "0" or "0:1" for MIG)
- `allocated_at` - Allocation timestamp
- `priority` - User priority level
- `stopped_at` - Stop timestamp (null if running)

### Container Metadata

**Location:** `/var/lib/ds01/container-metadata/<container>.json`

**Structure:**
```json
{
  "container_name": "my-project._.alice",
  "user": "alice",
  "image": "ds01-alice/my-project:latest",
  "gpu_id": "0",
  "created_at": "2025-11-21T10:00:00",
  "resource_limits": {
    "max_cpus": 16,
    "memory": "64g",
    "shm_size": "16g"
  }
}
```

## Troubleshooting

### GPU Allocation Issues

**Symptom:** "No GPUs available"

**Check:**
```bash
# View current allocations
python3 scripts/docker/gpu_allocator.py status

# Check nvidia-smi
nvidia-smi

# Check for stale allocations
# Look for stopped containers holding GPUs
python3 scripts/docker/gpu_allocator.py status | grep stopped_at
```

**Fix:**
```bash
# Release GPU from stopped container
python3 scripts/docker/gpu_allocator.py release --container <container-name>
```

### Container Creation Fails

**Symptom:** mlc-create-wrapper.sh errors

**Check:**
```bash
# Verify image exists
docker images | grep <image-name>

# Check resource limits
python3 scripts/docker/get_resource_limits.py <username>

# Check GPU availability
python3 scripts/docker/gpu_allocator.py status

# View detailed error
bash -x scripts/docker/mlc-create-wrapper.sh <container> <image> <user>
```

### Exit Code 2 with No Output

**Symptom:** Container creation fails with "exit code: 2" and no diagnostic output

**Cause:** This was caused by `set -e` in wrapper scripts preventing error handling code from running. When a command in a `$()` substitution fails with `set -e` enabled, the script exits immediately without capturing the exit code or running error handlers.

**Fix applied (Dec 2024):** The `mlc-create-wrapper.sh` now temporarily disables `set -e` around the Python call:
```bash
set +e  # Disable exit-on-error to allow error handling
MLC_OUTPUT=$(python3 "$MLC_PATCHED" $MLC_ARGS 2>&1)
MLC_EXIT_CODE=$?
set -e  # Re-enable
```

**Prevention:** When writing new wrapper scripts that need to capture exit codes:
- Use `set +e` / `set -e` around command substitutions that may fail
- Or use `|| true` pattern: `result=$(cmd 2>&1) || true; exit_code=$?`
- Never rely on `$?` after a `$()` substitution with `set -e` enabled

### MIG Not Detected

**Symptom:** MIG instances not showing in allocation

**Check:**
```bash
# Verify MIG enabled
nvidia-smi mig -lgi

# Check config
grep -A5 gpu_allocation config/resource-limits.yaml

# Test MIG parser
python3 scripts/docker/mig-config-parser.py
```

### State File Corruption

**Symptom:** GPU allocator errors reading state

**Fix:**
```bash
# Backup current state
sudo cp /var/lib/ds01/gpu-state.json /var/lib/ds01/gpu-state.json.bak

# Rebuild state from running containers
# (Manual process - contact admin)

# Or reset state (WARNING: loses all allocations)
sudo python3 scripts/docker/gpu_allocator.py status
```

## Container Permissions System

DS01 implements per-user container isolation using a Docker socket proxy.

### Architecture

```
Users/VS Code → /var/run/docker.sock (proxy) → /var/run/docker-real.sock (daemon)
                       ↑
              Filter Proxy detects user
              via SO_PEERCRED credentials
```

### Components

**docker-filter-proxy.py** - Transparent Docker socket proxy
- Filters `docker ps` to only show user's own containers
- Blocks operations (exec, logs, start, stop, rm) on containers owned by others
- Detects connecting user via Unix socket credentials (SO_PEERCRED)
- Admins (ds01-admin group) have full access
- Returns: `"Permission denied: container owned by <owner>"`

**sync-container-owners.py** - Container ownership synchronization
- Maintains `/var/lib/ds01/opa/container-owners.json`
- Maps container IDs to owners by reading Docker labels
- Updates every 5 seconds (configurable)
- Identifies owners from:
  - `ds01.user` label (DS01 containers)
  - `aime.mlc.USER` label (AIME containers)
  - `devcontainer.local_folder` path (Dev Containers)

**docker-wrapper.sh** - Universal container labeling
- Intercepts `docker run` and `docker create` commands
- Injects `--label ds01.user=<username>` on all containers
- Ensures all containers have ownership tracking

### Admin Access

Users with full container access:
- Members of `ds01-admin` Linux group
- Members listed in `resource-limits.yaml` `groups.admin.members`
- The `ds01-dashboard` service user

### Setup

```bash
# Deploy permissions system
sudo scripts/system/setup-docker-permissions.sh

# Uninstall if needed
sudo scripts/system/setup-docker-permissions.sh --uninstall

# Preview changes without applying
sudo scripts/system/setup-docker-permissions.sh --dry-run
```

### Testing

```bash
# Run test suite
scripts/testing/docker-permissions/test-permissions.sh

# As admin - should see all containers
docker ps -a

# As regular user - should only see own containers
docker ps -a

# Try accessing another user's container (should be denied for non-admins)
docker exec <other-user-container> ls
```

### Ownership Data

**Location:** `/var/lib/ds01/opa/container-owners.json`

**Structure:**
```json
{
  "containers": {
    "abc123def456": {
      "owner": "alice@example.com",
      "name": "my-project._.alice",
      "ds01_managed": true
    }
  },
  "admins": ["datasciencelab", "ds01-dashboard"],
  "service_users": ["ds01-dashboard"],
  "updated_at": "2025-12-04T18:30:00Z"
}
```

### Fail-Open Behavior

Containers without ownership labels (legacy or external) are accessible by all users. To lock down a container, add an owner label:

```bash
docker run --label ds01.user=$(whoami) ...
```

## Related Documentation

- [Root README](../../README.md) - System architecture and overview
- [config/README.md](../../config/README.md) - Resource limits configuration
- [scripts/user/README.md](../user/README.md) - User command workflows
- [scripts/maintenance/README.md](../maintenance/README.md) - Cleanup automation
- [scripts/monitoring/README.md](../monitoring/README.md) - GPU monitoring tools
- [scripts/system/README.md](../system/README.md) - System administration including permissions setup
