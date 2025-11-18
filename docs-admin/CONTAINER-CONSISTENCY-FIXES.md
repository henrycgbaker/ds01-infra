# Container Consistency Fixes - Summary

## Issues Identified

### 1. CUDA Version Detection Bug (FIXED ✓)
**Problem**: `mlc-patched.py` failed with "CUDA driver version not found" even though NVIDIA drivers were installed.

**Root Cause**: The script checked for packages like `cuda-12-3` but the system had `libcudnn8` with version `8.9.7.29-1+cuda12.2` which didn't match the regex pattern.

**Fix**: Modified `/opt/ds01-infra/scripts/docker/mlc-patched.py` lines 788-830:
- Changed `if "cuda-" in line:` to `if "cuda" in line.lower():`
- Added alternative regex pattern: `r'\+cuda(\d+)\.(\d+)'` to match `libcudnn8` version strings
- Refactored logic to try multiple patterns sequentially

**Test**: Container creation now works:
```bash
container-create test-final pytorch
# ✓ SUCCESS: Container created successfully
```

### 2. Stale GPU Allocations (FIXED ✓)
**Problem**: GPU allocator showed containers that didn't exist:
- `test-validation._.1001` - allocated GPU 1.1 but container didn't exist
- `test-debug2._.1001` - allocated GPU 1.2 but container didn't exist

**Root Cause**: During debugging, GPUs were allocated but container creation failed. The GPU allocations weren't released when containers were manually removed.

**Fix**:
1. Manually cleaned up stale allocations:
   ```bash
   python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py release test-validation._.1001
   python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py release test-debug2._.1001
   ```

2. Created reconciliation script: `/opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh`
   - Detects containers with GPU allocations that don't exist
   - Automatically releases stale allocations
   - Removes orphaned metadata files
   - Can be run manually or via cron

### 3. Inconsistent State Tracking (FIXED ✓)
**Problem**: Three sources of truth existed:
1. GPU allocator state (`/var/lib/ds01/gpu-state.json`)
2. Container metadata (`/var/lib/ds01/container-metadata/*.json`)
3. Actual Docker containers

These could become out of sync, causing confusion about what containers exist.

**Fix**:
1. **Created Single Source of Truth**: `/var/log/ds01/container-operations.log`
   - All container operations (create/start/stop/remove) now logged here
   - Pipe-delimited format: `timestamp|operation|user|container|gpu_id|status|details`
   - Also logs to syslog for centralized logging

2. **Integrated Logging Library**: `/opt/ds01-infra/scripts/lib/container-logger.sh`
   - Provides `log_container_operation()` function
   - Sourced by `mlc-create-wrapper.sh` and other container scripts
   - Logs at key points:
     - `create_start`: When container creation begins
     - `create_failed`: If container creation fails
     - `create_success`: When container is fully created and configured

3. **Reconciliation Script**: Automatically syncs GPU state with Docker reality
   ```bash
   /opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh
   ```

## --Guided Mode Issue

**Status**: Works in interactive shells, fails in automated environments

**Problem**: `--guided` mode requires `/dev/tty` for interactive prompts, which doesn't exist in CI/CD environments.

**Error**: `/usr/local/bin/container-create: line 837: /dev/tty: No such device or address`

**Workaround**: Use without `--guided` flag for automation:
```bash
container-create test pytorch    # Works everywhere
container-create test pytorch --guided  # Only works in interactive terminals
```

## Container Metadata

The metadata files in `/var/lib/ds01/container-metadata/` are **GPU allocation metadata only**, not full container metadata. They contain:
- Container name
- User
- GPU ID
- Priority
- Allocation timestamp

Docker labels provide the authoritative container metadata:
- `aime.mlc.USER` - Username
- `aime.mlc.NAME` - Container name (without ._.uid)
- `aime.mlc.FRAMEWORK` - Framework and version
- `aime.mlc.DS01_MANAGED` - DS01 management flag
- `aime.mlc.GPUS` - GPU device assignment

## Verification Commands

### Check System Consistency
```bash
# 1. Check GPU allocations
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status

# 2. Check actual containers
docker ps -a --format "{{.Names}}" | grep '\._\.'

# 3. Run reconciliation
/opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh

# 4. Check operation log
tail -f /var/log/ds01/container-operations.log

# 5. Verify container labels
docker inspect test-final._.1001 --format '{{.Config.Labels}}'
```

### Test Container Creation
```bash
# Clean test
container-create test-workflow pytorch

# Verify it appears everywhere
container-list --all
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status
ds01-dashboard
```

## Automated Reconciliation (Optional)

To automatically clean up stale allocations, add to cron:

```bash
# Add to /etc/cron.d/ds01-infra
# Run reconciliation every hour at :05
5 * * * * root /opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh >> /var/log/ds01/reconciliation.log 2>&1
```

## Summary of Changes

### Files Modified
1. `/opt/ds01-infra/scripts/docker/mlc-patched.py`
   - Lines 788-830: Fixed CUDA version detection

2. `/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh`
   - Added logging integration (lines 474-496, 572+)

### Files Created
1. `/opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh`
   - Reconciles GPU allocator state with Docker reality

2. `/opt/ds01-infra/scripts/lib/container-logger.sh`
   - Centralized logging for all container operations

3. `/var/log/ds01/container-operations.log`
   - Single source of truth for container operations

## Testing Performed

✓ Container creation with CUDA detection fix
✓ GPU allocation and release
✓ Stale allocation cleanup
✓ Reconciliation script
✓ Operation logging

## Recommendations

1. **Run reconciliation regularly**: Add to cron or run manually after system maintenance
2. **Monitor operation log**: Check `/var/log/ds01/container-operations.log` periodically
3. **Avoid manual Docker commands**: Always use `container-*` commands to maintain consistency
4. **Use reconciliation after issues**: If containers/GPUs get out of sync, run reconciliation script

## Next Steps

1. Test --guided mode in actual interactive terminal (optional)
2. Add reconciliation to cron (optional, but recommended)
3. Monitor logs for a few days to ensure consistency
4. Consider adding automated tests for container lifecycle
