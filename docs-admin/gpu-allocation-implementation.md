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

**Problem:** 4 GPUs, 10-20 students, episodic workloads

**Solution:**

UPDATE I CHANGED TO 4 INSTANCES PER GPU!!!

MIG (Multi-Instance GPU) on A100s
```
Each A100 → 3 MIG instances (2g.20gb profile)
4 GPUs × 3 instances = 12 MIG instances total

Result:
- 12 students can work simultaneously
- Hard memory isolation (can't crash each other)
- Each student gets 20GB GPU memory
```

**See:** `docs-admin/mig-setup-guide.md` for full setup instructions

### 2. **Dynamic Allocation with Priority**

**Priority Order:**
1. **Specific overrides** (100) - Reserved resources
2. **Admins** (90) - Full GPU or multiple MIG instances
3. **Researchers** (50) - Up to 4 MIG instances
4. **Students** (10) - Up to 2 MIG instances

**Allocation happens when container starts:**
- User launches → system finds least-loaded MIG instance
- Respects priority (high priority gets low-priority GPUs first)
- Container stops → MIG instance released immediately

### 3. **Corrected Resource Limits**

- **Students**: max 4 MIG (i.e. 1 whole GPU) instances simultaneously
- **Researchers**: max 8  MIG instances (i.e. 2 whole GPUs) simultaneously
- **Admins**: unlimited

**Important:** Limits are PER USER, not per container #TODO - UPDATE THIS BASED ON NEW RESOURCE LIMITS
- Student can have 2 containers, each with 1 GPU = ✅ OK (total 2 GPUs)
- Student tries 3rd container with GPU = ❌ REJECTED (already has 2 GPUs)

### 4. **Directory Structure**

```
/var/lib/ds01/                  State data
├── gpu-state.json              Current allocations (MIG-aware)
└── container-metadata/         Per-container info

/var/logs/ds01/                 All logs
├── gpu-allocations.log         GPU/MIG allocation events
├── metrics/                    Daily metrics
├── reports/                    Compiled reports
└── audits/                     System audits

/opt/ds01-infra/logs/          Symlink → /var/logs/ds01/
```

---

## Corrected Example Scenarios

### Scenario 1: Student at Limit (NEED TO UPDATE BASED ON NEW RESOURCE LIMITS)

**Alice (student, max 2 GPUs, 16 CPUs per container):**

```bash
# 1. Launch first container with GPU
mlc-create training1 pytorch
# → Gets MIG instance 0:1
# → Alice GPU count: 1/2 ✅

# 2. Launch second container with GPU
mlc-create training2 pytorch
# → Gets MIG instance 2:0
# → Alice GPU count: 2/2 ✅

# 3. Try third container with GPU
mlc-create training3 pytorch
# ❌ REJECTED: "USER_AT_LIMIT (2/2)"
# → Error message shown in wizard

# 4. Try third container WITHOUT GPU (CPU-only)
mlc-create preprocessing pytorch --cpu-only
# ✅ SUCCESS (doesn't count against GPU limit)

# 5. Container tries to use 20 CPU cores
# ⚠️ cgroups throttles to 16 cores (CPUQuota=1600%)
```

**What changed from old doc:**
- ✅ Alice CAN have 2 containers each with 1 GPU (total 2)
- ❌ Alice CANNOT have 3 containers with GPUs (exceeds limit)

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
    max_gpus_per_user: 1
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

**See full guide:** `docs-admin/mig-setup-guide.md`

### **Step 2: Setup /var directories**

```bash
cd /opt/ds01-infra
git pull

sudo chmod +x scripts/system/setup-var-directories.sh
sudo ./scripts/system/setup-var-directories.sh
```

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
│ USER: Student requests GPU                                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Check user's current GPU count (0/2) ✅                   │
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
| **Students per GPU** | 1 | 3 |
| **Total capacity** | 4 students | 12 students |
| **Isolation** | None | Hard memory isolation |
| **Crash risk** | High (OOM affects all) | None (isolated) |
| **Memory per user** | 40GB (full) | 20GB (partitioned) |
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
      
      You requested {requested} GPUs, but your limit is {max}.
      You currently have {current} GPUs allocated.
      
      Options:
      1. Reduce GPU request to {available} or fewer
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
tail /var/logs/ds01/gpu-allocations.log | grep priority
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

## Next Steps

1. ✅ **Setup MIG first** (see mig-setup-guide.md)
2. ✅ Setup /var directories
3. ✅ Create systemd slices
4. ✅ Initialize GPU allocator (MIG-aware)
5. ✅ Test thoroughly
6. ⚠️ Update mlc-create-wrapper.sh (integrate allocator)
7. ⚠️ Setup storage quotas
8. ⚠️ Implement idle detection

---

**Questions? Contact datasciencelab@university.edu**
