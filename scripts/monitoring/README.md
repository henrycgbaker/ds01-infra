# Monitoring Scripts - System Status & Metrics

Monitoring tools, dashboards, and metrics collection.

## Overview

Real-time monitoring and historical metrics for:
- GPU allocation and usage
- Container resource consumption
- System health checks
- User resource utilization

## Key Tools

### DS01 Dashboard

Unified admin dashboard for system monitoring.

**Command:** `dashboard`

**Features:**
- GPU/MIG allocation with hierarchical container display
- Color-coded utilization bars (green <50%, yellow 50-80%, red >90%)
- System resources (CPU, RAM, Disk, Swap)
- Recent GPU allocations with timestamps
- Active alerts and warnings
- Per-user resource breakdown

**Usage:**
```bash
dashboard                    # Default compact view
dashboard --full             # All sections expanded
dashboard --watch / -w       # Watch mode (2s refresh)
dashboard --json             # JSON output for scripting

# Subcommands (modular sections)
dashboard gpu                # GPU/MIG utilization with containers
dashboard mig-config         # MIG partition configuration
dashboard system             # CPU, Memory, Disk utilization
dashboard containers         # All containers with stats
dashboard users              # Per-user resource breakdown
dashboard allocations [N]    # Recent N GPU allocations (default: 10)
dashboard temp               # GPU temperatures
dashboard alerts             # Active alerts and warnings
```

**Visual Features:**
- Full GPUs shown in cyan, MIG-enabled GPUs in green
- Allocated containers shown in yellow
- FREE slots shown in green
- Progress bars for all utilization metrics

### GPU Utilization Monitoring

**gpu-utilization-monitor.py** - Real-time GPU utilization tracking

Tracks actual GPU usage (not just allocation) and identifies underutilized GPUs. Monitors GPU utilization percentage, memory usage, and power consumption.

**Purpose:** Distinguish between "allocated" (reserved by DS01) and "utilized" (actively used by workloads). Helps identify wasted allocations.

**Features:**
- Real-time utilization snapshot
- Historical utilization recording (for trending)
- Waste detection (allocated but idle GPUs)
- Per-GPU and per-container breakdown
- JSON output for automation

**Usage:**
```bash
# Current snapshot
gpu-utilization-monitor

# JSON output
gpu-utilization-monitor --json

# Record to history (admin/cron)
sudo gpu-utilization-monitor --record

# Check for wasted allocations (>80% idle over 30min)
sudo gpu-utilization-monitor --check-waste

# Watch mode (continuous monitoring)
watch -n 2 gpu-utilization-monitor
```

**Output:**
```
GPU Utilization Status (2025-12-09 14:30:00)

GPU 0: 85% utilized | 45GB/80GB memory | 250W
  Container: my-project._.alice (running)

GPU 1: 12% utilized | 5GB/80GB memory | 75W
  Container: experiment._.bob (running) [UNDERUTILIZED]
```

**Cron Integration:** Run every 5 minutes to record utilization history:
```bash
*/5 * * * * root /usr/local/bin/gpu-utilization-monitor --record >> /var/log/ds01/gpu-utilization.log
```

---

**mig-utilization-monitor.py** - MIG instance-specific monitoring

Track utilization per MIG instance with container mapping. Essential for MIG-enabled systems where multiple containers share a physical GPU.

**Purpose:** Monitor individual MIG instances separately, showing which containers are actively using their allocated MIG slices.

**Features:**
- Per-MIG instance utilization tracking
- Container-to-MIG mapping
- Waste detection for MIG instances
- Historical recording
- JSON output

**Usage:**
```bash
# Current MIG snapshot
mig-utilization-monitor

# JSON output
mig-utilization-monitor --json

# Record to history (admin/cron)
sudo mig-utilization-monitor --record

# Check for wasted MIG allocations
sudo mig-utilization-monitor --check-waste

# Watch mode
watch -n 2 mig-utilization-monitor
```

**Output:**
```
MIG Utilization Status (2025-12-09 14:30:00)

GPU 0 (MIG-enabled):
  Instance 0:0 (2g.20gb): 78% utilized | Container: thesis._.alice
  Instance 0:1 (2g.20gb): 15% utilized | Container: test._.bob [UNDERUTILIZED]
  Instance 0:2 (2g.20gb): FREE
```

**Cron Integration:** Run every 5 minutes alongside gpu-utilization-monitor:
```bash
*/5 * * * * root /usr/local/bin/mig-utilization-monitor --record >> /var/log/ds01/mig-utilization.log
```

**Notes:**
- Requires MIG to be enabled and configured (`gpu_allocation.enable_mig: true`)
- Uses `nvidia-smi mig -lgi` to discover MIG instances
- Cross-references with DS01 GPU state to map containers

---

### Container Monitoring

**container-dashboard.sh** - Container resource dashboard

Displays resource usage for all running containers with color-coded status indicators.

**Purpose:** Quick overview of container CPU, memory, and GPU usage across the system.

**Features:**
- Color-coded resource usage (green <50%, yellow 50-80%, red >80%)
- Per-container CPU and memory breakdown
- GPU allocation display
- Idle container detection
- User grouping

**Usage:**
```bash
# Default view
container-dashboard

# Group by user
container-dashboard --by-user

# Show only high-usage containers (>80%)
container-dashboard --high-usage

# JSON output
container-dashboard --json

# Watch mode
watch -n 2 container-dashboard
```

**Output:**
```
Container Resource Dashboard (2025-12-09 14:30:00)

USER: alice
  my-project._.alice    CPU: 45% | MEM: 32GB | GPU: 0 (85% util)
  thesis._.alice        CPU: 2%  | MEM: 4GB  | GPU: 0:0 (78% util)

USER: bob
  experiment._.bob      CPU: 5%  | MEM: 8GB  | GPU: 1 (12% util) [IDLE]
```

---

### State Validation

**validate-state.py** - State validation and consistency checker

Validates consistency between DS01 state files, Docker runtime, and GPU hardware.

**Purpose:** Detect and report inconsistencies in system state (orphaned allocations, missing containers, GPU mismatches).

**Features:**
- GPU allocation vs. running containers validation
- Container metadata vs. Docker state validation
- MIG configuration consistency checks
- Orphaned allocation detection
- Automatic repair suggestions

**Usage:**
```bash
# Run validation
validate-state

# Show detailed report
validate-state --verbose

# Check specific subsystem
validate-state --gpu          # GPU allocations only
validate-state --containers   # Container metadata only
validate-state --mig          # MIG configuration only

# Auto-repair (with confirmation)
sudo validate-state --repair

# JSON output
validate-state --json
```

**Output:**
```
DS01 State Validation Report (2025-12-09 14:30:00)

[OK] GPU State File: /var/lib/ds01/gpu-state.json
[OK] Container Metadata: 12 containers, all valid
[WARN] Orphaned GPU Allocation: GPU 2 allocated to deleted container test._.charlie
[OK] MIG Configuration: 9 instances match expected configuration

Suggestions:
  - Run: sudo python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py release --container test._.charlie
```

**Cron Integration:** Run daily to detect state drift:
```bash
0 2 * * * root /usr/local/bin/validate-state --repair >> /var/log/ds01/state-validation.log
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
