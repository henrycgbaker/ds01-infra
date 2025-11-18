# GPU Allocator Migration Guide

## Overview

The DS01 GPU allocation system has been refactored to use **Docker labels as the single source of truth**, replacing the previous state-file-based approach.

## What Changed

### Old System (DEPRECATED)
- `gpu_allocator.py` - maintained `/var/lib/ds01/gpu-state.json`
- Separate metadata files in `/var/lib/ds01/container-metadata/`
- State could become stale after system restarts or direct docker commands
- Required periodic reconciliation

### New System (CURRENT)
- `gpu-allocator-smart.py` - stateless, reads from Docker
- `gpu-state-reader.py` - reads GPU allocations from Docker HostConfig
- `gpu-availability-checker.py` - calculates available GPUs
- `ds01-resource-query.py` - unified query interface
- All state stored in Docker labels (`ds01.*`) and HostConfig
- Always accurate, survives restarts, no reconciliation needed

## Migration Status

### ✅ Completed
- All scripts updated to use `gpu-allocator-smart.py`
- Container creation uses Docker labels
- Dashboard reads from Docker
- Container-list reads from Docker
- Auto-reallocation on GPU mismatch

### 🗑️ Deprecated Files
- `/opt/ds01-infra/scripts/docker/gpu_allocator.py` - kept for reference only
- `/var/lib/ds01/gpu-state.json` - no longer written or read
- `/var/lib/ds01/container-metadata/*.json` - still written by old allocator (to remove)

## For Administrators

### Updated Scripts
All these now use `gpu-allocator-smart.py`:
- `scripts/docker/mlc-create-wrapper.sh`
- `scripts/user/container-{start,list}`
- `scripts/admin/ds01-dashboard`
- `scripts/monitoring/check-idle-containers.sh`
- `scripts/maintenance/enforce-max-runtime.sh`
- `scripts/maintenance/cleanup-stale-*.sh`

### New Query Commands
```bash
# Get GPU allocation status
python3 scripts/docker/ds01-resource-query.py gpus

# List user's containers with GPU info
python3 scripts/docker/ds01-resource-query.py containers --user alice

# Check available GPUs
python3 scripts/docker/ds01-resource-query.py available

# Get user summary
python3 scripts/docker/ds01-resource-query.py user-summary alice
```

### Backward Compatibility
The old `gpu_allocator.py` will print a deprecation warning but still work for now. All DS01 infrastructure has been updated to use the new allocator.

## Benefits

✅ **No stale state** - Docker is always correct
✅ **Survives restarts** - State persists with containers
✅ **Works with direct docker commands** - Labels survive docker stop/start
✅ **Better debugging** - `docker inspect` shows everything
✅ **Auto-recovery** - Can detect and fix GPU mismatches

## Technical Details

### Docker Labels Used
```
ds01.managed=true                    # DS01-managed container
ds01.user=<username>                 # Owner
ds01.created_at=<timestamp>          # Creation time
ds01.gpu.allocated=<slot_id>         # GPU/MIG ID (e.g., "1.2")
ds01.gpu.uuid=<MIG_UUID>            # Device UUID
ds01.gpu.allocated_at=<timestamp>    # When allocated
ds01.gpu.priority=<priority>         # User priority
```

### Reading GPU State
```python
from gpu_state_reader import GPUStateReader

reader = GPUStateReader()
allocations = reader.get_all_allocations()
user_gpus = reader.get_user_allocations("alice")
```

### Checking Availability
```python
from gpu_availability_checker import GPUAvailabilityChecker

checker = GPUAvailabilityChecker()
available = checker.get_available_gpus()
summary = checker.get_allocation_summary()
```

## Cleanup Schedule

Old state files will be removed in a future update once confirmed all systems are migrated. For now:
- Old files ignored by new system
- New system writes only to Docker labels
- No reconciliation scripts needed

## Questions?

Contact DS01 admin team or see:
- `/opt/ds01-infra/TODO/gpu_allocation_architecture.md`
- `/opt/ds01-infra/TODO/gpu_allocation_refactor_todo.md`
