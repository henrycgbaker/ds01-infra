# Cleanup Automation Testing Suite

**Purpose**: Test and verify automated container/GPU cleanup functionality

## Bug Fixed

### Critical Bug: Python Heredoc Variable Substitution

**Problem**: Bash variables inside Python heredocs were placed in single quotes, preventing proper substitution.

**Files Affected**:
- `scripts/maintenance/enforce-max-runtime.sh`
- `scripts/monitoring/check-idle-containers.sh`

**Solution**: Use environment variables with quoted heredoc delimiters:

```bash
# BEFORE (broken):
python3 - <<PYEOF
if '$username' in config['user_overrides']:  # Bash substitutes, but it's in Python quotes!
PYEOF

# AFTER (fixed):
USERNAME="$username" python3 - <<'PYEOF'  # Note the QUOTED delimiter '
if username in config['user_overrides']:   # Use os.environ['USERNAME'] instead
PYEOF
```

**Secondary Bug**: Empty YAML keys become `null`/`None`, causing `NoneType` errors.

**Solution**: Add `is not None` checks before accessing dict methods.

## Test Scripts

### 1. `test-functions-only.sh` - Unit Tests
Tests the get_idle_timeout() and get_max_runtime() functions in isolation.

**Usage**:
```bash
./test-functions-only.sh
```

**Expected Output**:
```
[Test 1] get_idle_timeout for datasciencelab... ✅ PASS
[Test 2] get_max_runtime for datasciencelab... ✅ PASS
[Test 3] get_idle_timeout for non-existent user... ✅ PASS
```

### 2. `test-idle-timeout.sh` - Integration Test
Tests the full idle timeout detection workflow.

**Usage**:
```bash
./test-idle-timeout.sh
```

### 3. `test-max-runtime.sh` - Integration Test
Tests the full max runtime enforcement workflow.

**Usage**:
```bash
./test-max-runtime.sh
```

## Manual Testing with Short Timeouts

To test the cleanup automation without waiting hours, temporarily modify `resource-limits.yaml`:

```yaml
defaults:
  idle_timeout: 0.01h          # 36 seconds (was 0.5h)
  max_runtime: 0.02h           # 72 seconds (was 12h)
  gpu_hold_after_stop: 0.005h  # 18 seconds (was 0.25h)
  container_hold_after_stop: 0.01h  # 36 seconds (was 0.5h)
```

Then:
1. Create/start a container
2. Wait for the timeout period
3. Run the cleanup script manually to verify it works
4. **Don't forget to restore original values!**

## Testing Each Cleanup Function

### Test 1: Max Runtime Enforcement

**Script**: `scripts/maintenance/enforce-max-runtime.sh`

**What it does**: Stops containers that have been running longer than `max_runtime`

**Test procedure**:
```bash
# 1. Set short timeout (e.g., 0.02h = 72 seconds)
# 2. Start a container
container-run test

# 3. Wait 72+ seconds
sleep 80

# 4. Run enforcement script
bash scripts/maintenance/enforce-max-runtime.sh

# 5. Check if container was stopped
docker ps -a | grep test._.1001
```

**Expected**: Container status changes from "Up" to "Exited"

### Test 2: Idle Timeout Detection

**Script**: `scripts/monitoring/check-idle-containers.sh`

**What it does**: Stops containers with no activity (CPU < 1%) for longer than `idle_timeout`

**Test procedure**:
```bash
# 1. Set short timeout (e.g., 0.01h = 36 seconds)
# 2. Start a container (don't run any processes in it)
container-run test

# 3. Wait 36+ seconds
sleep 40

# 4. Run idle check script
bash scripts/monitoring/check-idle-containers.sh

# 5. Check if container was stopped
docker ps -a | grep test._.1001
```

**Expected**: Container stopped with idle timeout message

### Test 3: GPU Hold Cleanup

**Script**: `scripts/maintenance/cleanup-stale-gpu-allocations.sh`

**What it does**: Releases GPU allocations from stopped containers after `gpu_hold_after_stop` timeout

**Test procedure**:
```bash
# 1. Set short timeout (e.g., 0.005h = 18 seconds)
# 2. Create container with GPU
container-create test

# 3. Stop the container
container-stop test

# 4. Verify GPU is still allocated
python3 scripts/docker/gpu_allocator.py status

# 5. Wait 18+ seconds
sleep 20

# 6. Run GPU cleanup
bash scripts/maintenance/cleanup-stale-gpu-allocations.sh

# 7. Check if GPU was released
python3 scripts/docker/gpu_allocator.py status
```

**Expected**: GPU allocation removed from state

### Test 4: Container Removal Cleanup

**Script**: `scripts/maintenance/cleanup-stale-containers.sh`

**What it does**: Removes stopped containers after `container_hold_after_stop` timeout

**Test procedure**:
```bash
# 1. Set short timeout (e.g., 0.01h = 36 seconds)
# 2. Create and stop container
container-create test
container-stop test

# 3. Wait 36+ seconds
sleep 40

# 4. Run container cleanup
bash scripts/maintenance/cleanup-stale-containers.sh

# 5. Check if container was removed
docker ps -a | grep test._.1001
```

**Expected**: Container completely removed from Docker

## Cron Job Testing

After verifying scripts work manually, test as cron jobs:

```bash
# 1. Temporarily modify cron timings to run every minute
#    Edit /etc/cron.d/ds01-infra:
#      */1 * * * * root /opt/ds01-infra/scripts/monitoring/check-idle-containers.sh

# 2. Monitor logs in real-time
tail -f /var/log/ds01/idle-cleanup.log

# 3. Verify cron execution
grep "check-idle-containers" /var/log/syslog

# 4. Restore original cron timings
```

## Current Status

✅ **FIXED**: Python heredoc variable substitution bugs
✅ **TESTED**: get_idle_timeout() and get_max_runtime() functions work correctly
⚠️ **PENDING**: Full end-to-end testing with real containers and short timeouts
⚠️ **PENDING**: Cron job execution verification

## Notes

- All scripts require root permissions to write to `/var/log/ds01/` and `/var/lib/ds01/`
- Container cleanup skips containers without metadata files (conservative approach)
- Idle detection requires CPU/memory stats from Docker (may fail for very short-lived containers)
- Test scripts should be run from `/opt/ds01-infra/` directory
