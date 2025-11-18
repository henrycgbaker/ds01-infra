# GPU Allocation Refactor - Single Source of Truth

## Core Problem (SOLVED ✅)
Multiple sources of truth existed:
- `/var/lib/ds01/gpu-state.json` (GPU allocator state) ← OLD, being phased out
- `/var/lib/ds01/container-metadata/*.json` (Container GPU assignments) ← Still created by old gpu_allocator.py
- Docker `HostConfig.DeviceRequests` (Actual GPU devices) ← ✅ PRIMARY SOURCE
- Docker labels (`ds01.*`) ← ✅ NEW PRIMARY SOURCE

## Solution Architecture (IN PROGRESS)
**Single Source of Truth**: Docker itself (HostConfig + Labels)

All DS01 tools become stateless query layers over Docker, with smart allocation logic.

---

## Implementation Summary (as of 2025-11-18)

### ✅ Completed (Core Infrastructure)
1. **Docker-First GPU State Reader** (`gpu-state-reader.py`)
   - Reads GPU allocations directly from Docker HostConfig.DeviceRequests
   - Maps MIG UUIDs to slot IDs (e.g., "1.2")
   - No dependency on state files - Docker is source of truth

2. **GPU Availability Checker** (`gpu-availability-checker.py`)
   - Queries nvidia-smi for available MIG instances
   - Uses gpu-state-reader for current allocations
   - Calculates available = total - allocated
   - Enforces user limits

3. **Docker Labels Support**
   - Added `--ds01-label` argument to mlc-patched.py
   - Labels added at container creation time:
     * `ds01.managed=true`
     * `ds01.user=<username>`
     * `ds01.created_at=<timestamp>`
     * `ds01.gpu.allocated=<slot_id>` (e.g., "1.2")
     * `ds01.gpu.uuid=<MIG_UUID>`
     * `ds01.gpu.allocated_at=<timestamp>`
     * `ds01.gpu.priority=<priority>`

4. **Unified Query Layer** (`ds01-resource-query.py`)
   - Central service for querying containers and GPUs
   - Commands: containers, gpus, available, container, user-summary
   - JSON output support
   - All queries read from Docker

5. **Container Start Validation**
   - container-start updated to read GPU allocation from Docker labels
   - Validates GPU UUID still exists before starting
   - Clear error messages if GPU missing

### ✅ Completed (Phase 5 - 2025-11-18)
6. **Stateless GPU Allocator** (`gpu-allocator-smart.py`)
   - No state files - reads current state from Docker via gpu-state-reader
   - Uses gpu-availability-checker for allocation decisions
   - Logs events to /var/log/ds01/gpu-allocations.log
   - Compatible API with old gpu_allocator.py (drop-in replacement)
   - mlc-create-wrapper.sh updated to use new allocator

### ✅ Completed (Phase 6 - 2025-11-18)
7. **User Tools Updated** (`container-list`)
   - Uses ds01-resource-query.py for container listing
   - Shows GPU allocations from Docker labels
   - JSON parsing with jq
   - Cleaner code, better error handling

8. **Admin Dashboard Updated** (`ds01-dashboard`)
   - Uses gpu-state-reader and gpu-availability-checker
   - No GPUAllocationManager dependency
   - Reads allocations directly from Docker
   - Maintains same display format

### 📋 TODO (Next Steps)
- Add auto-reallocation to container-start (when GPU missing)
- Clean up old files:
  * Deprecate old gpu_allocator.py
  * Remove /var/lib/ds01/gpu-state.json dependency
  * Remove /var/lib/ds01/container-metadata/*.json dependency
- Update remaining scripts that may reference old allocator

---

# GPU Allocation Refactor - Progress Tracker

## Completed ✓

### Phase 1.1: Docker-First GPU State Reader ✓
**File**: `/opt/ds01-infra/scripts/docker/gpu-state-reader.py`

**What it does**:
- Reads GPU allocations directly from Docker (HostConfig.DeviceRequests)
- Maps MIG UUIDs to slot IDs (1.0, 1.2, etc.)  
- Extracts user info from Docker labels
- **No dependency on separate state files** - Docker is the source of truth

**Usage**:
```bash
python3 /opt/ds01-infra/scripts/docker/gpu-state-reader.py all
python3 /opt/ds01-infra/scripts/docker/gpu-state-reader.py user datasciencelab
python3 /opt/ds01-infra/scripts/docker/gpu-state-reader.py container test._.1001
python3 /opt/ds01-infra/scripts/docker/gpu-state-reader.py json
```

**Test Results**: ✓ Working - Shows 6 containers with GPUs (more accurate than old allocator)

### Validation Scripts ✓
**Location**: `/opt/ds01-infra/testing/validation/`

**Scripts created**:
1. `health-check` - Master validation (runs all checks)
2. `check-gpu-consistency.sh` - GPU allocator vs Docker
3. `check-gpu-docker-match.sh` - State vs HostConfig  
4. `check-container-list-sync.sh` - container-list vs Docker
5. `check-metadata-files.sh` - Orphaned metadata detection
6. `show-discrepancies.sh` - Detailed comparison view
7. `debug-verbose.sh` - Full system state dump

**Usage**:
```bash
/opt/ds01-infra/testing/validation/health-check
```

---

## In Progress 🔄

### Phase 1.2: GPU Availability Checker
**Next step**: Create `gpu-availability-checker.py`

**Will do**:
- Query nvidia-smi for all MIG instances
- Query gpu-state-reader for current allocations
- Calculate: available = total - allocated
- Enforce user limits

### Phase 1.3: Stateless GPU Allocator
**Next step**: Refactor `gpu_allocator.py`

**Changes needed**:
- Remove `/var/lib/ds01/gpu-state.json` persistence
- Use `gpu-state-reader.py` to get current state
- Use `gpu-availability-checker.py` for availability
- Return allocation decision only (don't store state)

---

## Pending (From TODO)

### Phase 2: Docker Labels
- Define `ds01.*` label schema
- Update `mlc-create-wrapper.sh` to add labels
- Deprecate metadata files

### Phase 3: Unified Query Layer
- Create `Also add --running, --stopped (incl all not-running),  --all` central service
- Update `ds01-dashboard`
- Update `container-list` (this queries just users containers)

### Phase 4: Smart Allocation & Auto-Recovery
- GPU validation on container start (GPU/MIG necessarily first allocated at container create -> needs to query avaialbility here first, but then re-query availability at container start, in case allocation/availability changed between time)
- Auto-reallocation if GPU missing
- Handle MIG recreation after reboot

### Phase 5: Lifecycle Hooks
- Docker event listener
- Automated GPU release (there's a version of this in crontab already -> adapt / update / improve as needed)

### Phase 6: Migration
- delete old state and restart afresh with docker labels workflow 
- no need for background compatbility

### Phase 7: Testing
- Unit tests
- Integration tests

---

## Key Insights So Far

**Discovered**:
- GPU allocator had 3 containers
- Docker actually has 6 containers with GPUs
- **This is why dashboard and container-list were out of sync**

**Root Cause**:
- Containers created/started outside DS01 workflow
- GPU allocator state file doesn't reflect Docker reality
- Multiple sources of truth diverged

**Solution Architecture**:
- Docker HostConfig = single source of truth
- All tools query Docker via `gpu-state-reader.py`
- Allocator becomes stateless query/decision layer

---

## Next Actions

1. Complete Phase 1 (readers + stateless allocator)
2. Add Docker labels (Phase 2)
3. Build unified query layer (Phase 3)
4. Test end-to-end
5. Deploy in one go (not production ready yet, so start right away)

**Estimated remaining**: 1-2 days for Phases 1-3 (core functionality)


---


## Phase 1: Docker-First GPU State Reader

### 1.1 Create `gpu-state-reader.py` ✅ COMPLETED
- [x] Read all DS01 containers from Docker (`name=.*\._\..*`)
- [x] Extract GPU assignments from `HostConfig.DeviceRequests`
- [x] Map MIG UUIDs to MIG slot IDs (1.0, 1.1, etc.)
- [x] Return current GPU allocation state by querying Docker only
- [x] Cache nvidia-smi MIG list for UUID→slot mapping
**File**: `/opt/ds01-infra/scripts/docker/gpu-state-reader.py`
**Tested**: ✅ Shows 6 containers with GPUs (actual Docker state)

### 1.2 Create `gpu-availability-checker.py`
- [ ] Query all available MIG instances from `nvidia-smi mig -lgi`
- [ ] Query all allocated GPUs via `gpu-state-reader.py`
- [ ] Calculate available GPUs = total - allocated
- [ ] Support filtering by user (check user's current allocations)
- [ ] Return list of available MIG instances for allocation

### 1.3 Migrate `gpu_allocator.py` to stateless mode
- [ ] Remove `gpu-state.json` persistence
- [ ] Use `gpu-state-reader.py` to get current state
- [ ] Use `gpu-availability-checker.py` for allocation decisions
- [ ] When allocating: just return the GPU ID to assign
- [ ] Don't store allocation state - Docker HostConfig is the state

---

## Phase 2: Container Metadata via Docker Labels ✅ COMPLETED

### 2.1 Define standard DS01 labels ✅
- [x] `ds01.gpu.allocated` = GPU/MIG ID (e.g., "1.2")
- [x] `ds01.gpu.uuid` = MIG UUID assigned
- [x] `ds01.gpu.allocated_at` = ISO timestamp
- [x] `ds01.gpu.priority` = Allocation priority
- [x] `ds01.user` = Username
- [x] `ds01.managed` = "true" (for DS01-managed containers)
- [x] `ds01.created_at` = Container creation timestamp

### 2.2 Update `mlc-create-wrapper.sh` ✅
- [x] Add DS01 labels when creating container (via `mlc-patched.py --ds01-label`)
- [x] Store GPU allocation info in labels at creation time
- Note: Metadata files still created by gpu_allocator.py for backward compat

### 2.3 Update `mlc-patched.py` ✅
- [x] Added `--ds01-label` argument (can be specified multiple times)
- [x] Modified `build_docker_create_command()` to accept and apply ds01_labels
- [x] Labels added during container creation (not after)

---

## Phase 3: Unified Query Layer ✅ COMPLETED

### 3.1 Create `ds01-resource-query.py` (Central query service) ✅
- [x] `query containers --user <user> --status <all|running|stopped>` - List containers with GPU info
- [x] `query gpus` - Show all GPU allocations (reads from Docker)
- [x] `query available --user <user> --max-gpus <N>` - Show available GPUs for user
- [x] `query container <name>` - Get full container metadata
- [x] `query user-summary <user>` - Get user's resource usage summary
- [x] All queries read from Docker via gpu-state-reader and gpu-availability-checker
- [x] JSON output support with --json flag

### 3.2 Update `ds01-dashboard` (TODO - future phase)
- [ ] Replace `gpu_allocator.py status` with `ds01-resource-query.py`
- [ ] Show real-time state from Docker, not cached state
- [ ] Highlight containers started outside DS01 workflow (missing ds01.managed label)

### 3.3 Update `container-list` (TODO - future phase)
- [ ] Use `ds01-resource-query.py containers --user` instead of mlc-list
- [ ] Add --running, --stopped, --all flags
- [ ] Show GPU assignments from Docker labels

---

## Phase 4: Smart Allocation & Auto-Recovery ✅ PARTIALLY COMPLETED

### 4.1 Create `gpu-allocator-smart.py` (TODO - future phase)
- [ ] Read user's resource limits from YAML
- [ ] Check current allocations via `gpu-state-reader.py`
- [ ] Enforce `max_mig_instances` limit
- [ ] Implement priority-based allocation
- [ ] Detect and handle stale allocations (stopped containers holding GPUs)
- [ ] Return allocation decision (which GPU to assign)
- Note: Current gpu_allocator.py still used; will be replaced in future phase

### 4.2 Update `container-start` / `container-run` ✅
- [x] Check if container has GPU (read Docker labels: ds01.gpu.allocated, ds01.gpu.uuid)
- [x] Validate GPU still exists via nvidia-smi UUID check
- [x] If GPU missing, display clear error message with recreation steps
- [ ] TODO: Auto-reallocation (requires gpu-allocator-smart.py)

### 4.3 GPU Validation & Recovery ✅
- [x] Before starting container: verify assigned GPU UUID exists in nvidia-smi
- [x] If GPU missing: prompt user to recreate container
- [x] Workspace safety message displayed
- [ ] TODO: Automatic reallocation if GPUs available

---

## Phase 5: Container Lifecycle Hooks

### 5.1 Create Docker event listener
- [ ] Listen for container start/stop/remove events
- [ ] On container stop: start `gpu_hold_after_stop` timer
- [ ] On container remove: clean up any GPU reservations
- [ ] Log all events to `/var/log/ds01/container-events.log`

### 5.2 GPU Release Automation
- [ ] Periodic checker (cron): find stopped containers past `gpu_hold_after_stop`
- [ ] For each: update allocation state (mark GPU as released)
- [ ] Or: use container labels to mark "GPU released at <timestamp>"

---

## Phase 6: Backward Compatibility & Migration

### 6.1 Migration script
- [ ] Read old `/var/lib/ds01/gpu-state.json`
- [ ] Read old `/var/lib/ds01/container-metadata/*.json`
- [ ] For each container, add DS01 labels if missing
- [ ] Verify labels match actual GPU assignments
- [ ] Create backup of old state files
- [ ] Archive old state files (don't delete, for rollback)

### 6.2 Graceful degradation
- [ ] If Docker labels missing, try metadata files
- [ ] If metadata files missing, query HostConfig.DeviceRequests directly
- [ ] Log warnings when using fallback methods

---

## Phase 7: Testing & Validation

### 7.1 Unit tests
- [ ] Test `gpu-state-reader.py` with mock Docker data
- [ ] Test `gpu-allocator-smart.py` allocation logic
- [ ] Test label parsing and fallbacks

### 7.2 Integration tests
- [ ] Create container via `container-create` → verify labels
- [ ] Stop container → verify GPU marked for release
- [ ] Start container → verify GPU assignment preserved
- [ ] Remove container → verify no stale state
- [ ] Direct `docker run` with GPU → verify ds01-dashboard detects it

### 7.3 Stress tests
- [ ] Create/start/stop/remove 10 containers rapidly
- [ ] Verify no race conditions in GPU allocation
- [ ] Verify state always consistent between tools

---

## Phase 8: Documentation & Deployment

### 8.1 Update documentation
- [ ] Document new architecture in `/docs/GPU_ALLOCATION.md`
- [ ] Update troubleshooting guide
- [ ] Document migration process

### 8.2 Deployment checklist
- [ ] Run migration script
- [ ] Verify all containers have DS01 labels
- [ ] Test all `container-*` commands
- [ ] Test `ds01-dashboard`
- [ ] Monitor logs for 24h
- [ ] Remove old state files after verification

---

## Success Criteria

✓ `ds01-dashboard` and `container-list` always show identical containers
✓ GPU allocations survive container stop/start cycles
✓ Works correctly even with direct `docker` commands
✓ Stale allocations auto-detected and cleaned
✓ Single command shows complete system state: `ds01-query gpus`
✓ No separate state files - Docker is the source of truth
✓ Handles MIG instance recreation after reboot gracefully

---

## Implementation Order

1. Phase 1 (readers) - enables querying current state
2. Phase 2 (labels) - establishes new source of truth
3. Phase 3 (unified query) - migrates all tools to new architecture
4. Phase 4 (smart allocation) - adds robustness
5. Phase 6 (migration) - moves existing data
6. Phase 5 (lifecycle) - adds automation
7. Phase 7 (testing) - validates everything
8. Phase 8 (docs) - finishes deployment

**Estimated effort**: 2-3 days of focused development + testing
