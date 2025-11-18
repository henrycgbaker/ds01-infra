# DS01 Cron Job Testing Guide

This guide explains how to test the DS01 automated cleanup cron jobs with reduced time scales.

## Overview

DS01 has 4 automated cleanup cron jobs:

1. **Idle Container Check** (`:30/hour`) - `check-idle-containers.sh`
   - Stops containers idle beyond user's `idle_timeout`
   - Warns at 80% of timeout, stops at 100%
   - Log: `/var/log/ds01/idle-cleanup.log`

2. **Max Runtime Enforcement** (`:45/hour`) - `enforce-max-runtime.sh`
   - Stops containers exceeding user's `max_runtime`
   - Warns at 90% of limit, stops at 100%
   - Log: `/var/log/ds01/runtime-enforcement.log`

3. **GPU Stale Cleanup** (`:15/hour`) - `cleanup-stale-gpu-allocations.sh`
   - Releases GPUs from stopped containers after `gpu_hold_after_stop`
   - Log: `/var/log/ds01/gpu-stale-cleanup.log`

4. **Container Stale Cleanup** (`:30/hour`) - `cleanup-stale-containers.sh`
   - Removes stopped containers after `container_hold_after_stop`
   - Log: `/var/log/ds01/container-stale-cleanup.log`

## Quick Test (Recommended)

### 1. Check Current Status

```bash
# View current cron jobs
cat /etc/cron.d/ds01-infra

# Check when logs were last updated
ls -lh /var/log/ds01/*.log

# View recent log entries
sudo tail -50 /var/log/ds01/idle-cleanup.log
sudo tail -50 /var/log/ds01/runtime-enforcement.log
```

### 2. Manual Test Run

Run the comprehensive test script:

```bash
cd /opt/ds01-infra/testing/cleanup-automation
./test-cron-comprehensive.sh
```

This script will:
- Show current configuration
- List all containers and GPU allocations
- Let you run each cleanup script manually
- Show results and logs

### 3. Verify Logs Are Being Written

If you see "Permission denied" errors, the log files may have wrong permissions:

```bash
# Fix log permissions (run as root)
sudo chown root:root /var/log/ds01/*.log
sudo chmod 600 /var/log/ds01/*.log
```

## Intensive Test with Reduced Time Scales

To test with very short timeouts (minutes instead of hours):

### 1. Enable Test Timeouts

```bash
cd /opt/ds01-infra/testing/cleanup-automation
./enable-test-timeouts.sh
```

This sets:
- `max_runtime: 0.05h` (3 minutes)
- `idle_timeout: 0.02h` (~1 minute)
- `gpu_hold_after_stop: 0.01h` (36 seconds)
- `container_hold_after_stop: 0.02h` (~1 minute)

### 2. Create Test Container

```bash
# Create a simple test container
container-create test-cron-validation --guided
# Or manually:
# docker run -d --name test._.$(id -u) ubuntu:22.04 sleep 3600
```

### 3. Test Each Script

#### Test 1: Max Runtime (3 minute limit)

```bash
# Wait 3+ minutes, then run:
sudo bash /opt/ds01-infra/scripts/maintenance/enforce-max-runtime.sh

# Check log:
sudo tail -30 /var/log/ds01/runtime-enforcement.log

# Container should be stopped after exceeding 3 minutes runtime
```

#### Test 2: Idle Timeout (~1 minute)

```bash
# Ensure container is running but idle (no activity)
# Wait ~1 minute, then run:
sudo bash /opt/ds01-infra/scripts/monitoring/check-idle-containers.sh

# Check log:
sudo tail -30 /var/log/ds01/idle-cleanup.log

# Container should be stopped after ~1 minute of idleness
```

#### Test 3: GPU Hold Release (36 seconds)

```bash
# After a container with GPU is stopped, wait 36+ seconds, then run:
sudo bash /opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh

# Check log:
sudo tail -30 /var/log/ds01/gpu-stale-cleanup.log

# GPU allocation should be released
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status
```

#### Test 4: Container Removal (~1 minute)

```bash
# After container is stopped, wait ~1 minute, then run:
sudo bash /opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh

# Check log:
sudo tail -30 /var/log/ds01/container-stale-cleanup.log

# Container should be removed
docker ps -a | grep test
```

### 4. Restore Original Timeouts

**IMPORTANT**: After testing, restore the original configuration:

```bash
cd /opt/ds01-infra/testing/cleanup-automation
./restore-timeouts.sh
```

## Debugging Cron Issues

### Check Cron Service

```bash
# Check cron is running
systemctl status cron

# View recent cron activity
journalctl -u cron --since "1 hour ago" | grep ds01
```

### Check Script Permissions

```bash
# Scripts should be executable
ls -la /opt/ds01-infra/scripts/monitoring/check-idle-containers.sh
ls -la /opt/ds01-infra/scripts/maintenance/enforce-max-runtime.sh
ls -la /opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh
ls -la /opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh
```

### Check Log Directory Permissions

```bash
# Log directory should exist and be writable by root
ls -ld /var/log/ds01/
sudo ls -la /var/log/ds01/
```

### Verify Cron Files Are Deployed

```bash
# Check cron.d files exist
ls -la /etc/cron.d/ds01-*

# Verify no syntax errors (no output = good)
sudo cron -T /etc/cron.d/ds01-infra
```

### Manual Script Execution

If scripts fail when run via cron but work manually, check:

1. **PATH issues**: Cron has limited PATH
   - Scripts should use absolute paths
   - Check PATH in cron file: `PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin`

2. **Environment variables**: Cron has minimal environment
   - Scripts use environment variables passed to Python heredocs
   - Check heredoc delimiters are quoted: `<<'PYEOF'`

3. **Permissions**: Cron runs as root
   - Scripts should handle root execution
   - Check state directories exist: `/var/lib/ds01/`

## Common Issues

### Issue 1: Logs Show "Permission Denied"

**Cause**: Log files have wrong ownership/permissions

**Fix**:
```bash
sudo chown root:root /var/log/ds01/*.log
sudo chmod 600 /var/log/ds01/*.log
```

### Issue 2: Scripts Don't Run at Scheduled Time

**Cause**: Cron files not deployed or have syntax errors

**Fix**:
```bash
# Redeploy cron files
sudo cp /opt/ds01-infra/config/etc-mirrors/cron.d/ds01-infra /etc/cron.d/
sudo systemctl restart cron

# Check for errors
sudo cron -T /etc/cron.d/ds01-infra
```

### Issue 3: Python Heredoc Failures

**Cause**: Bash variable substitution in Python code

**Fix**: Scripts should use quoted heredoc delimiters and environment variables:
```bash
# WRONG:
python3 - <<PYEOF
if '$var' in config:  # Bash substitutes this!
PYEOF

# CORRECT:
VAR="$var" python3 - <<'PYEOF'  # Quoted delimiter
import os
var = os.environ['VAR']
if var in config:
PYEOF
```

### Issue 4: Containers Not Being Cleaned Up

**Possible causes**:
1. Timeouts set to `null` (disabled)
2. Containers have `.keep-alive` file
3. Container naming doesn't match AIME convention (`name._.uid`)
4. State files in `/var/lib/ds01/` have stale data

**Debug**:
```bash
# Check user's timeout settings
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py <username>

# Check container naming
docker ps --format "{{.Names}}" | grep '\._\.'

# Check state files
sudo ls -la /var/lib/ds01/container-states/
sudo ls -la /var/lib/ds01/container-runtime/

# Check for keep-alive files
docker exec <container> test -f /workspace/.keep-alive && echo "Keep-alive enabled"
```

## Automated Testing

For comprehensive automated testing, see:
- `testing/cleanup-automation/test-final.sh` - Full automation test suite
- `testing/cleanup-automation/README.md` - Complete testing documentation
- `testing/cleanup-automation/FINDINGS.md` - Known issues and fixes

## Next Steps

After verifying cron jobs work:

1. **Monitor in production**: Watch logs for a few days
   ```bash
   sudo tail -f /var/log/ds01/*.log
   ```

2. **Adjust timeouts**: Based on user needs, modify `resource-limits.yaml`

3. **Set up alerting**: Configure notifications for cleanup events

4. **Review cleanup logs**: Check weekly/monthly to ensure policies work as expected
