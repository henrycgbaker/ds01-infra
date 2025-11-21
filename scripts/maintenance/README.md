# Maintenance Scripts - Cleanup Automation

Automated container lifecycle management and resource cleanup.

## Overview

DS01 automates container lifecycle management through cron jobs that enforce:
- Idle timeout policies
- Max runtime limits
- GPU release after stop
- Container removal after stop

**Key principle:** Each user's containers are checked against **their own** resource limits from `config/resource-limits.yaml`.

## Cleanup Scripts

### check-idle-containers.sh

Detects and stops idle containers exceeding user's `idle_timeout`.

**Schedule:** `:30/hour` (via cron)

**What it does:**
1. Checks ALL running containers
2. For each container, reads owner's `idle_timeout` from YAML
3. If CPU < 1% for longer than timeout: stops container
4. Warns at 80% of idle time

**Idle detection:**
- Samples CPU usage over 1 minute
- Considers container idle if CPU < 1%
- Tracks cumulative idle time

**User override:**
```bash
# Inside container, prevent auto-stop
touch ~/.keep-alive

# Re-enable auto-stop
rm ~/.keep-alive
```

**Manual run:**
```bash
sudo bash scripts/maintenance/check-idle-containers.sh
```

**Log:** `/var/log/ds01/idle-cleanup.log`

**Example log:**
```
2025-11-21T10:30:00|WARNING|alice|my-project|idle:38h/48h|warn_threshold_80%
2025-11-21T12:00:00|STOPPED|alice|my-project|idle:48h/48h|timeout_exceeded
```

### enforce-max-runtime.sh

Enforces max runtime limits per user.

**Schedule:** `:45/hour` (via cron)

**What it does:**
1. Checks ALL running containers
2. For each container, reads owner's `max_runtime` from YAML
3. If running longer than max_runtime: stops container
4. Warns at 90% of max_runtime

**Runtime calculation:**
- Based on container start time
- Cumulative across restarts (tracked in metadata)

**Manual run:**
```bash
sudo bash scripts/maintenance/enforce-max-runtime.sh
```

**Log:** `/var/log/ds01/runtime-enforcement.log`

**Example log:**
```
2025-11-21T10:00:00|WARNING|bob|experiment|runtime:90h/100h|warn_threshold_90%
2025-11-21T12:00:00|STOPPED|bob|experiment|runtime:100h/100h|limit_exceeded
```

### cleanup-stale-gpu-allocations.sh

Releases GPUs from stopped containers after `gpu_hold_after_stop` timeout.

**Schedule:** `:15/hour` (via cron)

**What it does:**
1. Reads GPU allocation state from `/var/lib/ds01/gpu-state.json`
2. For each allocation with `stopped_at` timestamp:
   - Reads owner's `gpu_hold_after_stop` from YAML
   - If timeout exceeded: releases GPU
3. Handles restarted containers (clears `stopped_at`)

**Manual run:**
```bash
sudo bash scripts/maintenance/cleanup-stale-gpu-allocations.sh
```

**Log:** `/var/log/ds01/gpu-stale-cleanup.log`

**Example log:**
```
2025-11-21T10:00:00|RELEASED|alice|my-project|gpu:0|stopped:24h/24h|timeout_exceeded
2025-11-21T10:15:00|CLEARED|bob|experiment|gpu:1|container_restarted
```

### cleanup-stale-containers.sh

Removes stopped containers after `container_hold_after_stop` timeout.

**Schedule:** `:30/hour` (via cron)

**What it does:**
1. Finds ALL stopped containers
2. For each stopped container:
   - Reads owner's `container_hold_after_stop` from YAML
   - If timeout exceeded: removes container
3. Skips containers without metadata (conservative)

**Manual run:**
```bash
sudo bash scripts/maintenance/cleanup-stale-containers.sh
```

**Log:** `/var/log/ds01/container-stale-cleanup.log`

**Example log:**
```
2025-11-21T10:00:00|REMOVED|alice|old-project|stopped:12h/12h|timeout_exceeded
```

## Lifecycle Automation Flow

### Container Creation
```
1. User runs: container-create my-project
2. Container created with GPU allocation
3. Metadata saved: /var/lib/ds01/container-metadata/my-project._.alice.json
   - created_at: 2025-11-21T10:00:00
   - gpu_id: 0
   - user: alice
```

### Running Container
```
4. Container runs, monitored by cron jobs:

   a. check-idle-containers.sh (:30/hour)
      - Checks CPU usage
      - If idle > alice's idle_timeout (48h): stops container

   b. enforce-max-runtime.sh (:45/hour)
      - Checks runtime
      - If runtime > alice's max_runtime (168h): stops container
```

### Container Stop
```
5. User runs: container-stop my-project
   (or auto-stopped by idle/runtime enforcement)

6. GPU marked as stopped:
   - stopped_at: 2025-11-21T12:00:00 in gpu-state.json
   - GPU held for alice's gpu_hold_after_stop (24h)

7. User prompted: "Remove container now? [y/N]"
   - If yes: container removed immediately
   - If no: container held for alice's container_hold_after_stop (12h)
```

### Automated Cleanup
```
8. cleanup-stale-gpu-allocations.sh (:15/hour)
   - Checks: stopped_at + alice's gpu_hold_after_stop
   - If exceeded: releases GPU

9. cleanup-stale-containers.sh (:30/hour)
   - Checks: stop time + alice's container_hold_after_stop
   - If exceeded: removes container
```

## Configuration

All timeouts configured per-user in `config/resource-limits.yaml`:

```yaml
defaults:
  idle_timeout: "48h"              # Stop if idle
  max_runtime: "168h"              # Stop after max runtime
  gpu_hold_after_stop: "24h"       # Hold GPU after stop
  container_hold_after_stop: "12h" # Remove container after stop

groups:
  researchers:
    idle_timeout: "72h"            # Longer idle timeout
    gpu_hold_after_stop: "48h"     # Hold GPU longer

user_overrides:
  long_job_user:
    idle_timeout: null             # Never stop for idle
    max_runtime: null              # No runtime limit
    gpu_hold_after_stop: null      # Hold GPU indefinitely
    container_hold_after_stop: null # Never auto-remove
```

**Special values:**
- `null` = disabled (no timeout)
- `"0h"` = immediate (no hold time)

## Cron Schedule

Cron configuration deployed separately to `/etc/cron.d/`:

```bash
# /etc/cron.d/ds01-maintenance

# Max runtime enforcement (45 minutes past every hour)
45 * * * * root /opt/ds01-infra/scripts/maintenance/enforce-max-runtime.sh >> /var/log/ds01/runtime-enforcement.log 2>&1

# Idle container check (30 minutes past every hour)
30 * * * * root /opt/ds01-infra/scripts/maintenance/check-idle-containers.sh >> /var/log/ds01/idle-cleanup.log 2>&1

# GPU stale allocation cleanup (15 minutes past every hour)
15 * * * * root /opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh >> /var/log/ds01/gpu-stale-cleanup.log 2>&1

# Container stale cleanup (30 minutes past every hour, offset from idle check)
30 */2 * * * root /opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh >> /var/log/ds01/container-stale-cleanup.log 2>&1
```

## Testing

### Test Idle Detection

**Setup short timeout:**
```yaml
# config/resource-limits.yaml
user_overrides:
  testuser:
    idle_timeout: "0.01h"  # 36 seconds
```

**Test:**
```bash
# Create container
container-create test-project

# Start container (will be idle)
container-run test-project
# Press Ctrl+D to exit without running anything

# Wait 36+ seconds, then run manually:
sudo bash scripts/maintenance/check-idle-containers.sh

# Check log
tail /var/log/ds01/idle-cleanup.log
```

### Test Max Runtime

**Setup short runtime:**
```yaml
user_overrides:
  testuser:
    max_runtime: "0.02h"  # 72 seconds
```

**Test:**
```bash
# Create and start container
container-run test-project

# Wait 72+ seconds, then run:
sudo bash scripts/maintenance/enforce-max-runtime.sh

# Check log
tail /var/log/ds01/runtime-enforcement.log
```

### Test GPU Release

**Setup short hold time:**
```yaml
user_overrides:
  testuser:
    gpu_hold_after_stop: "0.01h"  # 36 seconds
```

**Test:**
```bash
# Stop container
container-stop test-project

# Check GPU still allocated
python3 scripts/docker/gpu_allocator.py status

# Wait 36+ seconds, then run:
sudo bash scripts/maintenance/cleanup-stale-gpu-allocations.sh

# Check GPU released
python3 scripts/docker/gpu_allocator.py status

# Check log
tail /var/log/ds01/gpu-stale-cleanup.log
```

### Test Container Removal

**Setup short hold time:**
```yaml
user_overrides:
  testuser:
    container_hold_after_stop: "0.01h"  # 36 seconds
```

**Test:**
```bash
# Stop container
container-stop test-project

# Check still exists
docker ps -a | grep test-project

# Wait 36+ seconds, then run:
sudo bash scripts/maintenance/cleanup-stale-containers.sh

# Check removed
docker ps -a | grep test-project  # Should be empty

# Check log
tail /var/log/ds01/container-stale-cleanup.log
```

**See:** [testing/cleanup-automation/README.md](../../testing/cleanup-automation/README.md) for comprehensive test suite

## Monitoring Cleanup Operations

### View Logs

```bash
# Real-time monitoring
tail -f /var/log/ds01/idle-cleanup.log
tail -f /var/log/ds01/runtime-enforcement.log
tail -f /var/log/ds01/gpu-stale-cleanup.log
tail -f /var/log/ds01/container-stale-cleanup.log

# Recent activity
tail -50 /var/log/ds01/idle-cleanup.log

# Search for specific user
grep alice /var/log/ds01/*.log
```

### Check Cron Execution

```bash
# View cron config
cat /etc/cron.d/ds01-maintenance

# Check cron service
sudo systemctl status cron

# View cron logs
grep ds01 /var/log/syslog
```

### Verify Scripts Running

```bash
# Check if scripts are running
ps aux | grep -E "check-idle|enforce-max|cleanup-stale"

# View last execution times
ls -lt /var/log/ds01/
```

## Troubleshooting

### Script Not Running

**Check cron:**
```bash
sudo systemctl status cron
grep CRON /var/log/syslog
```

**Check permissions:**
```bash
ls -l scripts/maintenance/*.sh
# Should be executable: -rwxr-xr-x
```

**Run manually to see errors:**
```bash
sudo bash -x scripts/maintenance/check-idle-containers.sh
```

### Incorrect Timeouts Applied

**Check user's limits:**
```bash
python3 scripts/docker/get_resource_limits.py <username>
```

**Check YAML syntax:**
```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

**Common issues:**
- Typo in username
- User not in any group
- Wrong units (use "h" for hours: "48h", not "48")

### Container Not Stopped Despite Idle

**Check .keep-alive file:**
```bash
docker exec <container> test -f ~/.keep-alive && echo "Keep-alive enabled"
```

**Check idle detection:**
```bash
# View container CPU usage
docker stats <container> --no-stream
```

**Check logs for warnings:**
```bash
grep <container> /var/log/ds01/idle-cleanup.log
```

### GPU Not Released

**Check allocation state:**
```bash
python3 scripts/docker/gpu_allocator.py status
cat /var/lib/ds01/gpu-state.json
```

**Check stopped timestamp:**
```bash
cat /var/lib/ds01/gpu-state.json | grep stopped_at
```

**Manual release:**
```bash
python3 scripts/docker/gpu_allocator.py release --container <container>
```

## Related Documentation

- [Root README](../../README.md) - System overview
- [config/README.md](../../config/README.md) - Timeout configuration
- [scripts/docker/README.md](../docker/README.md) - GPU allocation details
- [scripts/monitoring/README.md](../monitoring/README.md) - Monitoring tools
- [testing/cleanup-automation/README.md](../../testing/cleanup-automation/README.md) - Comprehensive test suite
