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

**container-entrypoint.sh** - Container initialization
- Sets up container environment on first run
- Configures user shell, aliases, environment variables
- Called by AIME MLC on container start

**container-init.sh** - Container setup hooks
- Additional DS01-specific initialization
- Sets up workspace mounts, permissions

**gpu-availability-checker.py** - GPU availability validation
- Checks if GPUs are accessible via nvidia-smi
- Validates MIG instance availability
- Used during container start

**emergency-container-stop.sh** - Force stop containers
- Emergency shutdown script
- Bypasses normal cleanup hooks

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

## Related Documentation

- [Root README](../../README.md) - System architecture and overview
- [config/README.md](../../config/README.md) - Resource limits configuration
- [scripts/user/README.md](../user/README.md) - User command workflows
- [scripts/maintenance/README.md](../maintenance/README.md) - Cleanup automation
- [scripts/monitoring/README.md](../monitoring/README.md) - GPU monitoring tools
