# DS01 Hybrid Resource Management - Quick Reference

## Summary

TODO: UPDATE BASED ON NEW RESOURCE LIMITS

**MIG-enabled GPU sharing + cgroups + priority allocation**

- GPU allocation is **dynamic** with **priority** awareness
- **MIG partitioning** allows 12 students to work simultaneously (4 GPUs → 12 MIG instances)
- CPU/RAM limits enforced via **cgroups**
- Students: max 2 GPUs, Researchers: max 4 GPUs, Admins: unlimited

---

## Limits (NEEDS UPDATING)

| Group | Max GPUs | Priority | CPUs | Memory | Storage |
|-------|----------|----------|------|---------|---------|
| **Student** | 2 | 10 (low) | 16 | 32G | 100G workspace |
| **Researcher** | 4 | 50 (med) | 32 | 64G | 500G workspace |
| **Admin** | unlimited | 90 (high) | 64 | 128G | 2T workspace |

**Important:** Limits are PER USER across all containers
- Student can have 2 containers each with 1 GPU = ✅ OK
- Student cannot have 3 containers with GPUs = ❌ REJECTED

---

## MIG Configuration

```
Each A100 → 3 MIG instances (2g.20gb)
4 GPUs × 3 instances = 12 MIG instances total

Result:
- 12 students can work simultaneously
- Each gets 20GB GPU memory
- Hard memory isolation (can't crash each other)
```

**Device notation:**
THIS IS WRONG - THEY HAVE UUIDs
- `0:0` = GPU 0, MIG instance 0
- `1:2` = GPU 1, MIG instance 2

---

## Directory Structure

```
/var/lib/ds01/           → State (current allocations)
/var/log/ds01/          → All logs
/opt/ds01-infra/logs/    → Symlink to /var/log/ds01/
```

---

## Priority Allocation

**Order:** Overrides (100) > Admins (90) > Researchers (50) > Students (10)

**Strategy:**
1. Check reservations (highest priority)
2. Find empty MIG instances first
3. Share MIG with same-priority users
4. Avoid displacing higher-priority users

---

## Commands

### Check GPU/MIG status:
```bash
ds01-gpu-status                # Terminal (MIG-aware)
ds01-gpu-status --markdown     # Generate markdown
nvidia-smi mig -lgi            # Raw MIG list
```

### Check your limits:
```bash
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py $USER
```

### Check your allocation:
```bash
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py user-status $USER
```

### Manual GPU operations (admin):
```bash
# Allocate
python3 scripts/docker/gpu_allocator.py allocate <user> <container> <max_gpus> <priority>

# Release
python3 scripts/docker/gpu_allocator.py release <container>

# Status
python3 scripts/docker/gpu_allocator.py status
```

---

## Log Files

```bash
# GPU allocations (includes priority info)
tail /var/log/ds01/gpu-allocations.log

# Format: timestamp|event|user|container|gpu_id|priority=X|reason
```

---

## Example Scenarios

### Scenario 1: Student Creates 2 Containers (CORRECTED)

```bash
# Alice (student, max 2 GPUs)

# Container 1
mlc-create training1 pytorch
# ✅ SUCCESS: MIG 0:1 allocated (1/2 GPUs)

# Container 2
mlc-create training2 pytorch
# ✅ SUCCESS: MIG 2:0 allocated (2/2 GPUs)

# Container 3
mlc-create training3 pytorch
# ❌ REJECTED: "USER_AT_LIMIT (2/2)"
# Graceful error message shown in wizard

# CPU-only container (doesn't count against GPU limit)
mlc-create preprocess pytorch --cpu-only
# ✅ SUCCESS (no GPU)
```

### Scenario 2: Priority Allocation

```bash
# 3 users request MIG instances simultaneously

# MIG 0:0: empty
# MIG 0:1: student (priority 10)
# MIG 0:2: researcher (priority 50)

# Requests:
# - Admin (priority 90)
# - Researcher (priority 50)
# - Student (priority 10)

# Allocation:
# Admin → MIG 0:0 (empty, always first)
# Researcher → MIG 0:1 (shares with student, lower priority than admin)
# Student → MIG 0:1 (shares with another student)
```

### Scenario 3: Reservation

```yaml
# In resource-limits.yaml
user_overrides:
  john_doe:
    priority: 100
    reserved_gpus: [0]  # Reserve full GPU 0
    reservation_start: "2025-11-01T00:00:00"
    reservation_end: "2025-11-08T00:00:00"
```

**Effect:** GPU 0 only available to john_doe during that week

---

## MIG Setup (One-Time)

```bash
# Enable MIG
sudo nvidia-smi -i 0,1,2,3 -mig 1
sudo reboot

# Create instances (2g.20gb profile)
for gpu in 0 1 2 3; do
  sudo nvidia-smi mig -i $gpu -cgi 14,14,14 -C
done

# Verify
nvidia-smi mig -lgi

# Update config
# Set enable_mig: true in resource-limits.yaml

# Reinitialize
sudo rm /var/lib/ds01/gpu-state.json
python3 scripts/docker/gpu_allocator.py status
```

**Full guide:** `/opt/ds01-infra/docs-admin/mig-setup-guide.md`

---

## What Happens at Limits

### GPU limit (via allocator):
```
Alice has 2 GPUs allocated
Tries 3rd container with GPU
→ Allocator rejects: "USER_AT_LIMIT (2/2)"
→ Graceful error shown in wizard
```

### CPU limit (via cgroups):
```
Container tries 20 cores
Student limit: 16 cores
→ Kernel throttles to 16 cores
```

### Memory limit (via cgroups):
```
Container tries 40GB
Student limit: 32GB
→ OOM (allocation fails)
```

### MIG memory limit (hardware):
```
Process tries 25GB
MIG instance: 20GB
→ CUDA OOM (hardware limit)
→ Other MIG instances unaffected
```

---

## Error Messages (User-Facing)

Configured in `/opt/ds01-infra/config/resource-limits.yaml`:

**GPU limit exceeded:**
```
❌ GPU Limit Exceeded

You requested 1 GPU, but your limit is 2 GPUs.
You currently have 2 GPUs allocated.

Options:
1. Stop an existing container to free up a GPU
2. Launch this container without GPU (CPU-only)

Check your allocations: ds01-gpu-status
```

**No GPU available:**
```
⚠️ No GPUs Available

All 12 MIG instances are currently allocated.

Options:
1. Wait for a MIG instance to become available
2. Launch as CPU-only container
3. Check status: ds01-gpu-status
```

**Reservation conflict:**
```
❌ MIG Instance Reserved

MIG 0:0 is reserved for john_doe until 2025-11-08.
Reason: Thesis deadline

Please try a different MIG instance or wait.
```

---

## Monitoring

### Check MIG utilization:
```bash
ds01-gpu-status

# Output shows:
# - 12 MIG instances
# - Containers per MIG instance
# - Per-user summary
# - Priority levels
# - Reservations
```

### Check cgroups:
```bash
systemctl status ds01.slice
systemd-cgtop --depth=3
```

---

## Troubleshooting

```bash
# MIG not working?
nvidia-smi mig -lgi  # Should show 12 instances
# If not, see docs-admin/mig-setup-guide.md

# GPU allocator broken?
sudo rm /var/lib/ds01/gpu-state.json
python3 scripts/docker/gpu_allocator.py status

# User stuck at limit?
python3 scripts/docker/gpu_allocator.py user-status <user>
python3 scripts/docker/gpu_allocator.py release <container>  # If needed

# Priority not working?
python3 scripts/docker/get_resource_limits.py <user> --priority
tail /var/log/ds01/gpu-allocations.log | grep priority
```

---

## Key Differences from Old System

| Aspect | Old | New |
|--------|-----|-----|
| Students per GPU | 1 | 3 (via MIG) |
| Total capacity | 4 students | 12 students |
| GPU isolation | None | Hard (MIG) |
| Allocation | Manual | Dynamic + priority |
| Limits | 1 GPU per student | 2 GPUs per student |
| Crash risk | High | None (isolated) |

---

## Files Modified

**New:**
- `scripts/docker/gpu_allocator.py` (MIG + priority aware)
- `scripts/monitoring/gpu-status-dashboard.py` (MIG aware)
- `scripts/system/setup-var-directories.sh`
- `docs-admin/mig-setup-guide.md` ⭐

**Updated:**
- `config/resource-limits.yaml` (priority, reservations, MIG, corrected limits)
- `scripts/docker/get_resource_limits.py` (priority support)
- `docs-admin/gpu-allocation-implementation.md` (corrected scenarios)

**TODO:**
- `scripts/docker/mlc-create-wrapper.sh` (integrate allocator + priority)

---

**Full docs:** `/opt/ds01-infra/docs-admin/`
**MIG setup:** `/opt/ds01-infra/docs-admin/mig-setup-guide.md`
