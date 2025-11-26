# Monitoring Scripts - System Status & Metrics

Monitoring tools, dashboards, and metrics collection.

## Overview

Real-time monitoring and historical metrics for:
- GPU allocation and usage
- Container resource consumption
- System health checks
- User resource utilization

## Key Tools

### gpu-status-dashboard.py

Interactive admin dashboard for system monitoring.

**Command:** `ds01-dashboard`

**Features:**
- GPU allocation status (who's using which GPU)
- Container resource usage (CPU, memory, GPU utilization)
- User resource quotas and consumption
- Systemd cgroup statistics
- Real-time updates

**Usage:**
```bash
ds01-dashboard

# Or directly:
python3 scripts/monitoring/gpu-status-dashboard.py
```

**Display sections:**
1. **GPU Allocations** - Current GPU assignments
2. **Container Stats** - CPU, memory, GPU usage per container
3. **User Quotas** - Resource limits and current usage
4. **System Resources** - Overall system CPU, memory, GPU

### GPU Utilization Monitoring

**gpu-utilization-monitor.py** - Real-time GPU utilization tracking

Track actual GPU usage (not just allocation) and identify underutilized GPUs.

```bash
# Current snapshot
gpu-utilization-monitor

# JSON output
gpu-utilization-monitor --json

# Record to history (admin/cron)
sudo gpu-utilization-monitor --record

# Check for wasted allocations (>80% idle over 30min)
sudo gpu-utilization-monitor --check-waste
```

**mig-utilization-monitor.py** - MIG instance-specific monitoring

Track utilization per MIG instance with container mapping.

```bash
# Current MIG snapshot
mig-utilization-monitor

# JSON output
mig-utilization-monitor --json

# Record to history (admin/cron)
sudo mig-utilization-monitor --record

# Check for wasted MIG allocations
sudo mig-utilization-monitor --check-waste
```

### Resource Alerts

**resource-alert-checker.sh** - User resource usage alerts

Generates alerts when users approach their resource limits (80% soft limit).

```bash
# Check all users
sudo resource-alert-checker

# Check specific user
sudo resource-alert-checker username

# Clean old alerts (>24h)
sudo resource-alert-checker --clean
```

Alerts are stored in `/var/lib/ds01/alerts/<username>.json` and displayed on user login.

### Event Logging

**ds01-events** - Centralized event log viewer

Query the append-only event log for all DS01 system events.

```bash
# Recent events
ds01-events

# Events for specific user
ds01-events user alice

# GPU events only
ds01-events gpu

# Failed/rejected events
ds01-events errors

# JSON output
ds01-events --json
```

Events are logged to `/var/log/ds01/events.jsonl` in append-only format.

### GPU Monitoring

**gpu_allocator.py status** - Current GPU allocations
```bash
python3 scripts/docker/gpu_allocator.py status

# Output:
GPU Allocation Status:
  GPU 0: my-project._.alice (priority 50, allocated 2h ago)
  GPU 1: Available
  GPU 0:1 (MIG): experiment._.bob (priority 10, allocated 30m ago, stopped 5m ago)
```

**nvidia-smi** - NVIDIA GPU monitoring
```bash
# Basic status
nvidia-smi

# Continuous monitoring (2s refresh)
watch -n 2 nvidia-smi

# Advanced monitoring with process tree
nvitop
```

### Container Monitoring

**container-stats** - Per-container resource usage
```bash
# Single container
container-stats my-project

# All containers
docker stats

# Specific user's containers
docker stats $(docker ps --filter "name=*._.<username>" -q)
```

**container-list** - Container inventory
```bash
# Your containers
container-list

# All containers (admin)
container-list --all
```

### System Monitoring

**systemd-cgtop** - Cgroup resource usage
```bash
# All DS01 slices
systemd-cgtop | grep ds01

# Specific group
systemctl status ds01-researchers.slice

# Per-user slice
systemctl status ds01-researchers-alice.slice
```

**get-limits** - User resource limits
```bash
# As user
get-limits

# As admin for any user
python3 scripts/docker/get_resource_limits.py <username>
```

## Metrics Collection

### collect-gpu-metrics.sh

Periodic GPU utilization logging.

**What it collects:**
- GPU utilization percentage
- Memory usage
- Temperature
- Power consumption
- Process information

**Usage:**
```bash
scripts/monitoring/collect-gpu-metrics.sh
```

**Output:** `/var/log/ds01/gpu-metrics.log`

**Format:**
```
2025-11-21T10:30:00|GPU:0|Util:85%|Mem:32GB/80GB|Temp:75C|Power:250W|Process:python3(alice)
```

### collect-container-metrics.sh

Container resource usage logging.

**What it collects:**
- CPU usage percentage
- Memory consumption
- Network I/O
- Block I/O
- PIDs count

**Usage:**
```bash
scripts/monitoring/collect-container-metrics.sh
```

**Output:** `/var/log/ds01/container-metrics.log`

### collect-system-metrics.sh

System-wide resource logging.

**What it collects:**
- Overall CPU usage
- Memory usage
- Disk space
- Network throughput
- Active containers

**Usage:**
```bash
scripts/monitoring/collect-system-metrics.sh
```

**Output:** `/var/log/ds01/system-metrics.log`

## Log Files

### GPU Logs

**GPU allocations:**
```bash
tail -f /var/log/ds01/gpu-allocations.log
```

Format: `timestamp|event|user|container|gpu_id|reason`

Example:
```
2025-11-21T10:30:00|allocated|alice|my-project|0|priority:50
2025-11-21T12:00:00|marked_stopped|alice|my-project|0|hold:24h
2025-11-21T14:00:00|released|alice|my-project|0|timeout
```

**GPU metrics:**
```bash
tail -f /var/log/ds01/gpu-metrics.log
```

### Container Logs

**Container lifecycle:**
```bash
# Docker container logs
docker logs <container-name>

# DS01 container creation
tail -f /var/log/ds01/container-creation.log
```

**Container metrics:**
```bash
tail -f /var/log/ds01/container-metrics.log
```

### Cleanup Logs

```bash
# Idle container detection
tail -f /var/log/ds01/idle-cleanup.log

# Max runtime enforcement
tail -f /var/log/ds01/runtime-enforcement.log

# GPU release automation
tail -f /var/log/ds01/gpu-stale-cleanup.log

# Container removal automation
tail -f /var/log/ds01/container-stale-cleanup.log
```

## State Files

### GPU State

**Location:** `/var/lib/ds01/gpu-state.json`

**View:**
```bash
cat /var/lib/ds01/gpu-state.json | python3 -m json.tool
```

**Structure:**
```json
{
  "allocations": {
    "container._.user": {
      "user": "alice",
      "gpu_id": "0",
      "allocated_at": "2025-11-21T10:00:00",
      "priority": 50,
      "stopped_at": null
    }
  },
  "last_updated": "2025-11-21T10:00:00"
}
```

### Container Metadata

**Location:** `/var/lib/ds01/container-metadata/`

**List:**
```bash
ls -lh /var/lib/ds01/container-metadata/
```

**View specific:**
```bash
cat /var/lib/ds01/container-metadata/my-project._.alice.json | python3 -m json.tool
```

## Monitoring Workflows

### Daily System Check

```bash
# 1. GPU status
python3 scripts/docker/gpu_allocator.py status
nvidia-smi

# 2. Container inventory
container-list --all

# 3. Resource usage
ds01-dashboard

# 4. Check for issues
docker ps --filter "status=exited"
systemctl status ds01.slice

# 5. Review logs
tail -50 /var/log/ds01/gpu-allocations.log
tail -50 /var/log/ds01/idle-cleanup.log
```

### Investigating High Usage

```bash
# 1. Identify heavy users
systemd-cgtop | grep ds01

# 2. Check specific user
container-list --all | grep <username>
container-stats <container-name>

# 3. GPU utilization
nvidia-smi
nvitop

# 4. Container processes
docker exec <container> ps aux
docker top <container>
```

### Tracking User Activity

```bash
# 1. User's resource limits
python3 scripts/docker/get_resource_limits.py <username>

# 2. User's containers
docker ps --filter "name=*._.<username>"

# 3. GPU allocations
python3 scripts/docker/gpu_allocator.py status | grep <username>

# 4. Historical logs
grep <username> /var/log/ds01/gpu-allocations.log
grep <username> /var/log/ds01/container-metrics.log
```

## Alerts and Notifications

### Manual Checks

**GPU over-allocation:**
```bash
python3 scripts/docker/gpu_allocator.py status | grep -c "allocated"
# Compare to actual GPU count
```

**Resource exhaustion:**
```bash
df -h | grep -E "9[0-9]%|100%"  # Disk space
free -h  # Memory
```

**Container issues:**
```bash
docker ps --filter "status=exited" --filter "status=dead"
```

### Automated Monitoring

Set up cron job for critical checks:

```bash
# /etc/cron.d/ds01-monitoring
*/15 * * * * root /opt/ds01-infra/scripts/monitoring/check-critical.sh
```

**Example check-critical.sh:**
```bash
#!/bin/bash
# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    echo "ALERT: Disk usage at ${DISK_USAGE}%"
fi

# Check for stuck containers
STUCK=$(docker ps --filter "status=dead" -q | wc -l)
if [ $STUCK -gt 0 ]; then
    echo "ALERT: ${STUCK} stuck containers"
fi
```

## Troubleshooting

### Dashboard Not Showing Data

**Check dependencies:**
```bash
python3 -c "import yaml, json"  # Should not error
```

**Check state files:**
```bash
ls -lh /var/lib/ds01/
cat /var/lib/ds01/gpu-state.json
```

### Missing Logs

**Check log directory:**
```bash
ls -lh /var/log/ds01/
```

**Create if missing:**
```bash
sudo mkdir -p /var/log/ds01
sudo chown root:ds-admin /var/log/ds01
sudo chmod 775 /var/log/ds01
```

### Incorrect GPU Status

**Verify with nvidia-smi:**
```bash
nvidia-smi
```

**Compare with allocator state:**
```bash
python3 scripts/docker/gpu_allocator.py status
```

**Check for stale allocations:**
```bash
# GPUs allocated to stopped/deleted containers
python3 scripts/docker/gpu_allocator.py status
docker ps -a | grep <container-name>
```

## Related Documentation

- [Root README](../../README.md) - System overview
- [scripts/docker/README.md](../docker/README.md) - GPU allocation details
- [scripts/maintenance/README.md](../maintenance/README.md) - Automated cleanup
- [config/README.md](../../config/README.md) - Resource configuration
