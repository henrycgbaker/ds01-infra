# GPU Allocation Architecture - Before & After

## BEFORE (Current - Multiple Sources of Truth)

```
┌─────────────────────────────────────────────────────────────┐
│  User Commands                                              │
│  container-create, container-list, ds01-dashboard          │
└────────┬──────────────────────────┬─────────────────────────┘
         │                          │
         ▼                          ▼
┌─────────────────┐        ┌──────────────────┐
│ gpu-state.json  │        │  Docker Labels   │
│  (allocator)    │        │  (aime.mlc.*)    │
└─────────────────┘        └──────────────────┘
         │                          │
         │                          │
         ▼                          ▼
┌─────────────────┐        ┌──────────────────┐
│ container-      │        │ Docker HostConfig│
│ metadata/*.json │        │ DeviceRequests   │
└─────────────────┘        └──────────────────┘

Problem: 4 different sources can diverge!
```

## AFTER (Proposed - Single Source of Truth)

```
┌─────────────────────────────────────────────────────────────┐
│  User Commands                                              │
│  container-create, container-list, ds01-dashboard          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                ┌────────────────┐
                │  ds01-query.py │  ◄── Central Query Service
                │  (stateless)   │
                └────────┬───────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
┌─────────────┐  ┌──────────────┐  ┌─────────────┐
│Docker Labels│  │Docker        │  │nvidia-smi   │
│ds01.gpu.*   │  │HostConfig    │  │mig -lgi     │
│ds01.user    │  │DeviceRequests│  │(MIG UUIDs)  │
│ds01.managed │  │              │  │             │
└─────────────┘  └──────────────┘  └─────────────┘
       │                 │                 │
       └─────────────────┴─────────────────┘
                         │
                         ▼
              ┌──────────────────┐
              │ DOCKER (Runtime) │  ◄── SINGLE SOURCE OF TRUTH
              │ Containers with  │
              │ GPU assignments  │
              └──────────────────┘

All state derived from Docker at query time!
```

## Key Architectural Changes

TODO: ADD INTO THIS DESIGN DOC: MAKE IT POSSIBLE FOR USERS TO CREATE CONTAINERS WHICH HAVE MULTIPLE PHYSICAL GPUs / MIG INSTANCES EXPOSED TO THE CONTAINER. 
   - e.g. maybe a user wants to use an larger open source LLM that requires memory / compute for more than one MIG instance.
   - IF their user cgroup limits allow (`max_mig_instances`), they should be able to request additional mig instances / GPUs be exposed to their container. 
   - `max_mig_instances` applies to each container; of which they can only have `max_containers_per_user` (e.g. if they have `max_mig_instances`:2 and `max_containers_per_user`:2 they should be able to run 2 containers, each with 2 mig-insrtances)
   - it should be possible to have multiple MIG instances across different physical GPUs (? maybe at a future insgtance we will use an allocation algo that prioritises intra-GPU MIGs, but for now it's fine to distribute them)
   - we will need to expose this in `container create` (both when run as a script, and by inserting a new decision point into the interactive GUI after choice of GPU mode). 
   - the decision point in the interactive GUI should default to 1 MIG instance (recommended), but also offer users choice of more if needed (with more explanation in --guided)
   - docker resource allocation system should be robust to multiple MIGs/GPUs being allocated to a single container (so the container labels need to be able to hold records of multiple MIGs/GPUs)


### 1. Docker Labels Replace State Files
**OLD**: `/var/lib/ds01/gpu-state.json` + `/var/lib/ds01/container-metadata/*.json`
**NEW**: Docker labels on containers
```yaml
ds01.gpu.allocated: "1.2"              # MIG slot ID
ds01.gpu.uuid: "MIG-abc123..."         # MIG UUID
ds01.gpu.allocated_at: "2025-11-18T15:00:00Z"
ds01.gpu.priority: "90"
ds01.user: "datasciencelab"
ds01.managed: "true"
```

### 2. Query Layer Over Docker
**OLD**: Each tool maintains own state/cache
**NEW**: Central `ds01-query.py` reads from Docker

```python
# All tools use this:
ds01-query.py containers --user datasciencelab
ds01-query.py gpus --status
ds01-query.py available --user datasciencelab
```

### 3. Stateless Allocation
**OLD**: `gpu_allocator.py` maintains persistent state
**NEW**: `gpu-allocator-smart.py` is stateless

```python
# Allocation process:
1. Read current state from Docker (via gpu-state-reader.py)
2. Check availability (via gpu-availability-checker.py)
3. Apply user limits and priority
4. Return GPU ID to assign (don't store anywhere)
5. Docker gets updated with GPU device
6. Docker labels get updated with allocation info
```

### 4. Auto-Recovery on Start
**OLD**: Container start fails if GPU missing
**NEW**: Auto-reallocate if GPU unavailable

```bash
container-start test
  → Check labels: had GPU 1.2
  → Verify: nvidia-smi shows MIG 1.2 exists?
  → If yes: start with same GPU
  → If no: reallocate new GPU, update labels, start
```

### 5. Event-Driven Cleanup
**OLD**: Periodic cron checks for stale state
**NEW**: Docker event listener + periodic validation

```python
# Listen to Docker events:
on container.stop:
    label.set("ds01.gpu.released_at", now())
    start timer for gpu_hold_after_stop

on container.remove:
    cleanup any reservations (already handled via labels)
```

## Data Flow Examples

### Creating a Container
```
1. User: container-create myproject pytorch
2. gpu-allocator-smart.py:
   - Queries Docker for user's current allocations
   - Checks resource limits
   - Returns: "Allocate MIG 2.1"
3. mlc-create-wrapper.sh:
   - Calls mlc-patched.py with --gpus device=MIG-uuid
   - Adds Docker labels: ds01.gpu.allocated=2.1, ds01.user=username, etc.
4. Container created with GPU in HostConfig AND labels
```

### Querying Status
```
1. User: ds01-dashboard
2. ds01-query.py gpus --status:
   - docker ps -a --filter label=ds01.managed
   - For each container:
     * Read HostConfig.DeviceRequests → actual GPU
     * Read label ds01.gpu.allocated → intended allocation
     * Read label ds01.user → owner
   - Group by MIG instance
   - Return formatted status
3. Dashboard displays real-time state
```

### Starting Stopped Container
```
1. User: container-start myproject
2. container-start script:
   - Reads labels: ds01.gpu.allocated=2.1, ds01.gpu.uuid=MIG-xyz
   - Validates: nvidia-smi | grep MIG-xyz
   - If valid: docker start (GPU already in HostConfig)
   - If invalid:
     * Call gpu-allocator-smart.py for new GPU
     * Update HostConfig.DeviceRequests
     * Update labels with new allocation
     * docker start
3. Container starts with correct GPU
```

## Migration Path

```
1. Deploy new tools (ds01-query.py, gpu-state-reader.py, etc.)
2. Run migration script:
   - For each container in Docker:
     * Read old metadata from /var/lib/ds01/container-metadata/
     * Add ds01.* labels to container
     * Verify against HostConfig.DeviceRequests
3. Update all scripts to use ds01-query.py
4. Test everything still works
5. Archive old state files
6. Remove old code paths after 1 week
```

## Benefits

✅ **Single Source of Truth**: Docker is always correct
✅ **No Stale State**: Can't diverge because there's only one source
✅ **Works with Direct Docker**: Labels survive docker stop/start
✅ **Auto-Recovery**: Smart reallocation on start if GPU missing
✅ **Simpler Code**: No state file management
✅ **Better Debugging**: `docker inspect` shows everything
✅ **Atomic Updates**: Docker ensures consistency
