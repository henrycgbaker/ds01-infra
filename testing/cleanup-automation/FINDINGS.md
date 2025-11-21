# Cleanup Automation Testing - Findings

**Date**: 2025-11-18
**Tester**: Automated Testing
**Issue**: Automated cleanup scripts (cron jobs) not working

## Summary

The cron jobs ARE running (verified by log file timestamps), but the scripts have a critical bug that prevents them from working correctly.

## Root Cause

**Python heredoc variable substitution bug** in ALL cleanup/monitoring scripts:

The scripts use bash heredocs to embed Python code, but place bash variables inside Python single quotes:

```python
# BROKEN (current code):
if 'user_overrides' in config and '$username' in config['user_overrides']:
#                                  ^^^^^^^^^ - bash substitutes this but it's in Python quotes!
```

When bash processes the heredoc:
1. `$username` gets replaced with actual value (e.g., "datasciencelab")
2. But it's INSIDE Python single quotes
3. Python then looks for literal string `"$username"` in the dict
4. Never finds it because the key is `"datasciencelab"`, not `"$username"`

## Affected Scripts

1. **`scripts/maintenance/enforce-max-runtime.sh`** (lines 42-73)
   - Function: `get_max_runtime()`
   - Impact: Never enforces max_runtime limits

2. **`scripts/monitoring/check-idle-containers.sh`** (lines 33-67)
   - Function: `get_idle_timeout()`
   - Impact: Never stops idle containers

3. **`scripts/maintenance/cleanup-stale-gpu-allocations.sh`**
   - Uses `gpu_allocator.py` which works correctly
   - Status: ✅ LIKELY WORKING

4. **`scripts/maintenance/cleanup-stale-containers.sh`** (line 89)
   - Uses `get_resource_limits.py` which should work
   - Status: ⚠️  NEEDS TESTING (may have metadata issues)

## Test Evidence

### Test 1: Max Runtime Enforcement
```bash
Container: test._.1001
Runtime: 10h
User: datasciencelab (admin group)
Expected limit: 12h
Result: ✅ Container NOT stopped (correct - hasn't exceeded limit yet)
```

### Test 2: Idle Timeout Detection
```bash
Container: test._.1001
Runtime: 11h
CPU: 0.00% (IDLE)
User: datasciencelab
Expected limit: 0.5h (30 minutes)
Result: ❌ Container STILL RUNNING (should have been stopped 10.5h ago!)
```

Debug output shows:
- Python code executed
- Returned "48h" (default, not the user's actual 0.5h limit)
- `timeout_str` variable remained EMPTY (bug!)

## Configuration Values (from resource-limits.yaml)

For `datasciencelab` (admin group):
- `max_runtime`: 12h (commented out in admin group, uses default)
- `idle_timeout`: 0.5h
- `gpu_hold_after_stop`: 0.25h
- `container_hold_after_stop`: 0.5h

## Secondary Issues Found

1. **Missing state directories**: `/var/lib/ds01/container-states/` doesn't always exist
   - Scripts try to create it with `mkdir -p` but may fail silently
   - Created manually during testing

2. **Old containers without metadata**: Many stopped containers have no metadata files
   - Example: `test-2._.1001` (Exited 11h ago, no metadata)
   - cleanup-stale-containers.sh skips these (conservative approach)

3. **Non-DS01 containers**: Many containers don't follow AIME naming (`name._.uid`)
   - Examples: `epic_ramanujan`, `ollama`, `open-webui`, etc.
   - Scripts correctly ignore these

## Recommended Fixes

### Fix 1: Python Heredoc Variable Substitution (CRITICAL)

Replace single quotes with escaped double quotes in Python code:

```python
# BEFORE (broken):
if 'user_overrides' in config and '$username' in config['user_overrides']:
    timeout = config['user_overrides']['$username'].get('idle_timeout')

# AFTER (fixed):
if 'user_overrides' in config and \"$username\" in config['user_overrides']:
    timeout = config['user_overrides'][\"$username\"].get('idle_timeout')
```

Apply to:
- `enforce-max-runtime.sh` (get_max_runtime function)
- `check-idle-containers.sh` (get_idle_timeout function)

### Fix 2: State Directory Creation

Ensure state directories are created with proper permissions during system setup:
```bash
sudo mkdir -p /var/lib/ds01/container-states
sudo mkdir -p /var/lib/ds01/container-runtime
sudo chown root:root /var/lib/ds01/container-states
sudo chown root:root /var/lib/ds01/container-runtime
```

### Fix 3: Metadata Cleanup for Old Containers

For containers without metadata, use Docker's FinishedAt timestamp as fallback:
- Already implemented in `cleanup-stale-containers.sh` (lines 111-118)
- ✅ Should work correctly

## Next Steps

1. ✅ Apply Fix 1 to affected scripts
2. ✅ Test each script manually with debug output
3. ✅ Verify containers are stopped/removed as expected
4. ✅ Test with short timeout values (e.g., 0.01h = 36 seconds)
5. ✅ Monitor cron logs after fixes deployed
