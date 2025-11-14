# GPU Allocation & Cgroups Implementation Guide

## Overview

Hybrid resource management system with MIG support:
- **cgroups (systemd slices)**: CPU/RAM/task limits (kernel enforcement)
- **Dynamic GPU/MIG allocation**: Per-container, priority-aware, on-demand
- **Storage quotas**: Per-user workspace/data limits  
- **Single YAML config**: Source of truth for all limits
- **MIG partitioning**: Multiple students per physical GPU (A100s)

---

## Key Design Decisions

### 1. **MIG Partitioning for Fair GPU Sharing** ⭐

**Problem:** 4 GPUs, many users, episodic workloads

**Solution:**


MIG (Multi-Instance GPU) on A100s
```
GPU=0: a full unpartitioned device
GPUs=1-3:
- Each A100 → 4 MIG instances
= 3 GPUs × 4 instances = 12 MIG instances total
+ 1 full GPU

Result:
- users can work simultaneously
- Hard memory isolation (can't crash each other)
```
TODO: 
- need to also handle robust GPU memory isolation 
  - -> this would allow students to work on same MIG isntance if really full?
- make system robust to whole GPUs vs MIG patitions. 
  - MIG partitions are the priority unit, we expect each GPU to be partitioned, but if not, allow graceful failover to working with unparitioned GPUs (in which case students get 1 GPU access, researchers up to 2 GPUs). 
  - 1GPU should in general count for 4 MIG instances
  - in overrides we may want to be able to allocate specifically workign with full unparitioned GPU (device=0), rather than across 4 MIG instances.

**See:** `docs-admin/mig-setup-guide.md` for full setup instructions
- EDIT: this got deleted, TODO: rewrite it.

### 2. **Dynamic Allocation with Priority**

**Priority Order:**
1. **Specific overrides** (100) - Reserved resources
2. **Admins** (90) - No limits
3. **Researchers** (50) - Full GPU (on device=0) (which counts as 4 MIG instanes)/ up to 8 MIG instances
4. **Students** (10) - Up to 2 MIG instances

**IMPORTANT: Allocation happens when container starts:**
- User launches → system finds least-loaded MIG instance
- Respects priority (high priority gets low-priority GPUs first)
- Container stops → MIG instance released immediately
- Done on a per-container basis (not per-user, although users are restricted to number of simultaneous containers they can run).
- Responsive, as system is designed for containers to be spun up and down frequently.

### 3. **Directory Structure**

```
/var/lib/ds01/                  State data
├── gpu-state.json              Current allocations (MIG-aware)
└── container-metadata/         Per-container info

/var/log/ds01/                  All logs
├── gpu-allocations.log         GPU/MIG allocation events
├── metrics/                    Daily metrics
├── reports/                    Compiled reports
└── audits/                     System audits

/opt/ds01-infra/logs/          Symlink → /var/log/ds01/
```

---

## Corrected Example Scenarios

### Scenario 1: Student at Limit

**Alice (student, max 2 MIGs, 16 CPUs per container):**

```bash
# 1. Launch first container with GPU
container run training1 pytorch
# → Gets MIG instance 0:1
# → Alice MIG count: 1/2 ✅

# 2. Launch second container with GPU
container run training2 pytorch
# → Gets MIG instance 2:0
# → Alice MIG count: 2/2 ✅

# 3. Try third container with GPU
container run training3 pytorch
# ❌ REJECTED: "USER_AT_LIMIT (2/2)"
# → Error message shown in wizard

# 4. Try third container WITHOUT GPU (CPU-only)
container run preprocessing pytorch --cpu-only
# ✅ SUCCESS (doesn't count against GPU limit)

# 5. Container tries to use 20 CPU cores
# ⚠️ cgroups throttles to 16 cores (CPUQuota=1600%)
```

**What changed from old doc:**
- ✅ Alice CAN have 2 containers each with 1 MIG instance (total 2)
- ❌ Alice CANNOT have 3 containers with MIG instances (exceeds limit)

### Scenario 2: Priority Allocation

**3 users try to allocate at same time:**

```
MIG instances available:
- 0:0 (empty)
- 0:1 (has bob/student container, priority 10)
- 0:2 (has carol/researcher container, priority 50)

New allocation requests:
1. Dave (admin, priority 90)
2. Eve (researcher, priority 50)
3. Frank (student, priority 10)

Allocation order:
1. Dave → gets MIG 0:0 (empty, always first choice)
2. Eve → gets MIG 0:1 (lowest priority container, bob displaced? No, shared)
3. Frank → gets MIG 0:1 (shared with bob, both students)

Result: Multiple students share same MIG instance (safe due to memory isolation)
```

### Scenario 3: Time-Based Reservation

**Researcher John needs dedicated GPU for thesis week:**

```yaml
# /opt/ds01-infra/config/resource-limits.yaml
user_overrides:
  john_doe:
    max_mig_instances: 1
    priority: 100               # Highest
    reservation_start: "2025-11-01T00:00:00"
    reservation_end: "2025-11-08T00:00:00"
    reserved_gpus: [0]          # Reserve full GPU 0
    reason: "Thesis deadline - needs dedicated GPU"
```

**Effect:**
- During reservation: GPU 0 only available to john_doe
- Others see: "❌ GPU Reserved for john_doe until 2025-11-08"
- After reservation ends: GPU 0 returns to normal pool

---

## Implementation Steps

### **Step 1: Setup MIG (CRITICAL)** ⭐

```bash
# Enable MIG on all A100s
sudo nvidia-smi -i 0,1,2,3 -mig 1
sudo reboot

# Create MIG instances (2g.20gb profile)
for gpu in 0 1 2 3; do
  sudo nvidia-smi mig -i $gpu -cgi 14,14,14 -C
done

# Verify
nvidia-smi mig -lgi
# Should show 12 instances (3 per GPU)
```

**See full guide:** `docs-admin/mig-setup-guide.md` EDIT: NEED TO REWRITE

### **Step 2: Setup /var directories**

```bash
cd /opt/ds01-infra
git pull

# EDIT: BELOW DELETED, BUT ALREADY. IMPLEMENTED: 
sudo chmod +x scripts/system/setup-var-directories.sh
sudo ./scripts/system/setup-var-directories.sh
```
TODO: 
- Make sure all these var logging directories configs are documented
- add easy access link(s) in /opt/ds01-infra/logs (same format as links already there)

### **Step 3: Setup systemd slices**

```bash
sudo chmod +x scripts/system/setup-resource-slices.sh
sudo ./scripts/system/setup-resource-slices.sh

# Verify
systemctl status ds01.slice
```

### **Step 4: Initialize GPU allocator (MIG-aware)**

```bash
# Make scripts executable
sudo chmod +x scripts/docker/*.py

# Initialize (will detect MIG instances)
python3 scripts/docker/gpu_allocator.py status

# Should show 12 MIG instances
```

### **Step 5: Test allocation**

```bash
# Test as student
python3 scripts/docker/gpu_allocator.py allocate alice test1 2 10
# → Should allocate MIG instance

python3 scripts/docker/gpu_allocator.py allocate alice test2 2 10
# → Should allocate another MIG instance

python3 scripts/docker/gpu_allocator.py allocate alice test3 2 10
# → Should reject: USER_AT_LIMIT (2/2)

# Clean up
python3 scripts/docker/gpu_allocator.py release test1
python3 scripts/docker/gpu_allocator.py release test2
```

### **Step 6: Create user commands**

```bash
sudo ln -sf /opt/ds01-infra/scripts/monitoring/gpu-status-dashboard.py \
    /usr/local/bin/ds01-gpu-status

# Test
ds01-gpu-status
```

---

## How Priority-Aware MIG Allocation Works

```
┌─────────────────────────────────────────────────────────────┐
│ USER: Student requests MIG/GPU                                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Check user's current MIG/GPU count (0/2) ✅                   │
│ 2. Get user's priority (student = 10)                       │
│ 3. Check for reservations (none active)                     │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Find least-allocated MIG instance:                       │
│                                                              │
│    MIG 0:0 → 0 containers, max_priority=0                  │
│    MIG 0:1 → 1 container (admin, priority=90)              │
│    MIG 0:2 → 2 containers (both students, priority=10)     │
│    MIG 1:0 → 1 container (researcher, priority=50)         │
│                                                              │
│    Score = (priority_diff, container_count, memory_used)    │
│                                                              │
│    MIG 0:0 → (-10, 0, 0%) = BEST                          │
│    MIG 0:2 → (0, 2, 30%)  = OK (same priority level)       │
│    MIG 1:0 → (-40, 1, 50%) = AVOID (higher priority user)  │
│    MIG 0:1 → (-80, 1, 80%) = AVOID (admin)                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Allocate MIG 0:0 (empty, lowest score)                  │
│    Launch: docker run --gpus "device=0:0" ...              │
└─────────────────────────────────────────────────────────────┘
```

**Key insight:** Students fill empty MIG instances first, then share with other students before displacing higher-priority users.

---

## Resource Enforcement

| Resource | Enforcement | Tool | Scope |
|----------|-------------|------|-------|
| **CPU** | ✅ Hard limit | cgroups | Per container |
| **Memory** | ✅ Hard limit | cgroups | Per container |
| **GPU device** | ✅ MIG instance | Docker --gpus | Per container |
| **GPU count** | ✅ Max per user | gpu_allocator.py | Per user |
| **GPU memory** | ✅ MIG partition | Hardware | Per MIG instance |
| **Containers** | ✅ Max per user | wrapper check | Per user |
| **Priority** | ✅ Allocation order | gpu_allocator.py | Per user |
| **Reservations** | ✅ Time-based lock | gpu_allocator.py | Per GPU/MIG |

---

## MIG vs Non-MIG Comparison

| Aspect | Without MIG | With MIG |
|--------|-------------|----------|
| **Users per GPU** | 1 | 4 |
| **Total capacity** | 4 users | 12+1 users |
| **Isolation** | None | Hard memory isolation |
| **Crash risk** | High (OOM affects all) | None (isolated) |
| **Memory per user** | 40GB (full) | ??GB (partitioned) |
| **Fair sharing** | Manual | Automatic |

---

## Monitoring

### Real-time MIG status:

```bash
# DS01 dashboard (MIG-aware)
ds01-gpu-status

# Sample output:
# ======================================================================
#              DS01 GPU SERVER STATUS (MIG ENABLED)
# ======================================================================
# 
# MIG 0:0: 1 container
#   Util: 85% | Mem: 18000/20480 MB
#     - alice-training (alice, priority=10, 2h 15m)
# 
# MIG 0:1: 2 containers
#   Util: 92% | Mem: 19500/20480 MB
#     - bob-inference (bob, priority=10, 45m)
#     - carol-test (carol, priority=10, 12m)
# 
# MIG 0:2: 0 containers
#   Util: 0% | Mem: 0/20480 MB
#   🟢 AVAILABLE
# ...

# NVIDIA MIG list
nvidia-smi mig -lgi

# Cgroups
systemd-cgtop --depth=3
```

---

## Graceful Error Handling

**Configured in YAML:**

```yaml
wizard:
  error_messages:
    gpu_limit_exceeded: |
      ❌ GPU Limit Exceeded
      
      You requested {requested} MIG instances, but your limit is {max}.
      You currently have {current} MIG instances allocated.
      
      Options:
      1. Reduce MIG/GPU request to {available} or fewer
      2. Stop an existing container
      3. Launch as CPU-only
```

**Usage in wrapper:**
```bash
# When user exceeds limit, show helpful error
echo "$(get_error_message gpu_limit_exceeded \
  requested=2 max=2 current=2 available=0)"
```

---

## Troubleshooting

### MIG not working:

See `docs-admin/mig-setup-guide.md` for comprehensive troubleshooting.

### Priority not respected:

```bash
# Check user's priority
python3 scripts/docker/get_resource_limits.py alice --priority

# Check allocation logs
tail /var/log/ds01/gpu-allocations.log | grep priority
```

### Reservation conflicts:

```bash
# Check active reservations
cat /opt/ds01-infra/config/resource-limits.yaml | grep -A10 user_overrides
```

---

## Migration Plan

### Phase 1: MIG Setup (Day 1)
1. Enable MIG on all GPUs (requires reboot, schedule maintenance)
2. Create MIG instances
3. Test with admin account

### Phase 2: Deploy Code (Day 2)
1. Deploy updated scripts
2. Initialize GPU allocator (MIG-aware)
3. Test with student accounts

### Phase 3: Announce (Week 1)
- Email users about new system
- Explain MIG benefits (more capacity!)
- New containers use MIG automatically

### Phase 4: Monitor (Week 2-4)
- Track utilization of 12 MIG instances
- Adjust profile if needed (more/fewer instances)
- Gather user feedback

---

## Recent Updates (November 2025)

### Bug Fixes & MIG Compatibility

**Issue #1: False MIG Instance Detection**
- **Problem**: Allocator assumed 3 MIG instances per GPU when MIG mode enabled, even if no partitions configured
- **Fix**: Check `nvidia-smi mig -lgi` return code and output before adding instances
- **Result**: Gracefully falls back to whole-GPU mode when no MIG partitions exist

**Issue #2: NoneType Config Handling**
- **Problem**: YAML with `user_overrides:` (no entries) caused TypeError when checking reservations
- **Fix**: Changed `config.get('user_overrides', {})` to `config.get('user_overrides') or {}`
- **Result**: Handles empty/null config sections correctly

### Test Results

**Hardware Configuration:**
- GPU 0: MIG Disabled (whole GPU mode)
- GPUs 1-3: MIG Enabled (no partitions configured)

**Functional Test Results:**
```
✓ MIG detection: Correctly identified 4 physical GPUs (not 9 fake MIG instances)
✓ GPU allocation: Successfully allocated GPU to student (priority=10)
✓ Priority handling: Admin (priority=90) received different GPU
✓ User limits: Tracked GPU counts per user correctly
✓ Release: GPU successfully released and count decremented
```

**Compatibility:** System works in both modes:
- **With MIG partitions**: Tracks individual MIG instances (e.g., "1:0", "1:1")
- **Without MIG partitions**: Falls back to whole GPU mode (e.g., "0", "1", "2", "3")

### Test Scripts

Run automated tests:
```bash
# Unit test: MIG detection logic
python3 /opt/ds01-infra/testing/unit/test_gpu_allocator_mig_detection.py

# Functional test: Full allocation workflow
python3 /opt/ds01-infra/testing/functional/test_gpu_allocator_functional.py
```

---

## Next Steps

1. ✅ **Setup MIG first** (see mig-setup-guide.md)
2. ✅ Setup /var directories
3. ✅ Create systemd slices
4. ✅ Initialize GPU allocator (MIG-aware)
5. ✅ Test thoroughly - **COMPLETE (Nov 2025)**
6. ✅ Fix MIG compatibility bugs - **COMPLETE (Nov 2025)**
7. ⚠️ Update mlc-create-wrapper.sh (integrate allocator)
8. ⚠️ Setup storage quotas
9. ⚠️ Implement idle detection

---
