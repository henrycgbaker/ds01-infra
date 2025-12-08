# Rollback Documentation - December 5, 2025

## What Happened
Docker permission changes caused workload failures with error:
```
libgomp: Thread creation failed: Resource temporarily unavailable
```

## Rollback Details
- **Rolled back to:** `f6da415` (Add DS01 UI/UX design guide for CLI consistency)
- **Backup branch:** `backup/docker-permissions-and-other-changes`
- **Backup commit:** `3855e5b`

## How to Access Backed Up Changes
```bash
# View all backed up commits
git log --oneline main..backup/docker-permissions-and-other-changes

# Cherry-pick a specific commit
git cherry-pick <commit-hash>

# View changes in a specific commit
git show <commit-hash>
```

---

## Commits in Backup Branch

### DOCKER-RELATED (Do NOT reapply without investigation)

| Commit | Description | Risk |
|--------|-------------|------|
| `8a8dc37` | Add per-user Docker container isolation system | HIGH - caused the issue |
| `82f83bd` | Fix Docker proxy HTTP/2 support and container deployment workflow | HIGH - part of permission system |
| `c3d34bf` | Replace socket proxy with wrapper-based visibility filtering | HIGH - part of permission system |
| `3855e5b` | Add open issues: container labeling gap and OPA blocking | LOW - just docs |

### NON-DOCKER (Safe to reapply)

| Commit | Description | Files Changed | Recommendation |
|--------|-------------|---------------|----------------|
| `384fd48` | Apply UI/UX guide standards to image-create | `image-create`, `ds01-UI_UX_GUIDE.md`, `scripts/user/README.md` | REAPPLY - good improvements |
| `f4947eb` | Add container shell integration and debugging tools | `mlc-patched.py`, `ds01-profile.sh`, test files | PARTIAL - shell integration useful, skip docker-socket-proxy.py |
| `06e22f2` | Streamline VS Code remote development docs | `docs/advanced/vscode-remote.md` | REAPPLY - docs only |
| `22b29d3` | Fix image-create non-interactive mode defaults | `scripts/user/image-create` | REAPPLY - bug fix |

---

## Recommended Reapply Order

1. **`06e22f2`** - VS Code docs (safe, docs only)
   ```bash
   git cherry-pick 06e22f2
   ```

2. **`384fd48`** - UI/UX standards for image-create (safe, good improvements)
   ```bash
   git cherry-pick 384fd48
   ```

3. **`22b29d3`** - image-create defaults fix (safe, bug fix)
   ```bash
   git cherry-pick 22b29d3
   ```

4. **`f4947eb`** - Container shell integration (PARTIAL - needs review)
   - Useful: `ds01-profile.sh`, shell aliases, test files
   - Skip: `docker-socket-proxy.py` (part of failed permission system)
   - May need manual cherry-pick or patch

---

## Mixed Commit: 82f83bd
This commit mixed Docker proxy fixes with useful non-Docker fixes:

**KEEP (manually extract):**
- `image-create`: Name sanitization (strip trailing dots/hyphens)
- `container-deploy`: Custom image passing fix

**SKIP:**
- `docker-filter-proxy.py` changes

To extract just the good parts:
```bash
git show 82f83bd -- scripts/user/image-create
git show 82f83bd -- scripts/user/container-deploy
```

---

## Files Added by Docker Permission System (now removed)

These files existed only in the backup branch:
- `scripts/docker/docker-filter-proxy.py`
- `scripts/docker/docker-socket-proxy.py`
- `scripts/docker/sync-container-owners.py`
- `scripts/system/setup-docker-permissions.sh`
- `scripts/system/migrate-to-opa.sh`
- `config/docker/daemon.json`
- `config/systemd/opa-docker-authz.service`
- `docs/docker-permissions-migration.md`
- `TODO/planning_doc.md`
- `testing/docker-permissions/`

---

## ADDITIONAL FIX: TasksMax Cgroup Limit (Dec 5, 2025)

### Root Cause
The `libgomp: Thread creation failed` error was NOT caused by the Docker permission changes.
It was caused by **`TasksMax=512`** in `/etc/systemd/system/ds01-student.slice`.

This limit caps the total number of threads+processes for ALL student containers combined.
A single PyTorch/NumPy process with OpenMP can spawn 32+ threads, so 512 is far too low.

### Fix Applied
```bash
# Runtime fix (immediate)
sudo systemctl set-property ds01-student.slice TasksMax=65536

# Permanent fix (survives reboot)
sudo sed -i 's/TasksMax=512/TasksMax=65536/' /etc/systemd/system/ds01-student.slice
sudo systemctl daemon-reload
```

### Verification
```bash
systemctl show ds01-student.slice -p TasksCurrent,TasksMax
# Should show: TasksMax=65536
```

### TODO: Make TasksMax Robust
The current system has these issues that need addressing:

1. **Hardcoded TasksMax=512 in slice files** - Too low for ML workloads
2. **No TasksMax in resource-limits.yaml** - Should be configurable per group
3. **create-user-slice.sh may recreate with old defaults** - Need to update script

**Future fix needed in:**
- `/opt/ds01-infra/config/resource-limits.yaml` - Add `tasks_max` field
- `/opt/ds01-infra/scripts/system/create-user-slice.sh` - Read from config
- `/opt/ds01-infra/scripts/system/setup-resource-slices.sh` - Update defaults

**Recommended values:**
| Group | TasksMax |
|-------|----------|
| student | 65536 |
| researcher | 131072 |
| admin | infinity |

---

## ONGOING: Performance Issue (Dec 5, 2025)

After fixing the thread limit, user reported container is "super slow".

**Possible causes to investigate:**
1. GPU not properly attached to container
2. CPU throttling from CPUQuota=1600% in student slice
3. Memory pressure from MemoryMax=32g limit
4. I/O contention
5. Container using CPU instead of GPU for computation

**Diagnostic commands:**
```bash
# Check GPU visibility in container
docker exec <container> nvidia-smi

# Check CPU throttling
systemctl show ds01-student-<user>.slice -p CPUQuotaPerSecUSec

# Check memory pressure
cat /sys/fs/cgroup/ds01.slice/ds01-student.slice/memory.pressure
```

---

## RESOLVED: Performance Issue - CPU Quota (Dec 5, 2025)

### Root Cause
User (Silke Kaiser / 204214) was running sklearn (CPU-only workload) and hitting the student CPU quota limit of 1600% (16 cores). She was maxing out at ~26% per core in htop.

### Fix Applied

**1. Added user to researcher group in resource-limits.yaml:**
```yaml
researcher:
  members: [s.kaiser@hertie-school.lan, 204214@hertie-school.lan, 204214]
  max_cpus: 64
  memory: 128g
  max_tasks: 65536
```

**2. Created researcher slice with higher limits:**
```bash
sudo bash -c 'echo -e "[Unit]\nDescription=DS01 Researcher Group\nBefore=slices.target\n\n[Slice]\nSlice=ds01.slice\nCPUAccounting=true\nMemoryAccounting=true\nTasksAccounting=true\nIOAccounting=true\nCPUQuota=6400%\nMemoryMax=128g\nTasksMax=65536" > /etc/systemd/system/ds01-researcher.slice'
```

**3. Created user-specific slice under researcher:**
```bash
sudo bash -c 'echo -e "[Unit]\nDescription=DS01 Researcher - 204214 (Silke Kaiser)\nBefore=slices.target\n\n[Slice]\nSlice=ds01-researcher.slice\nCPUAccounting=true\nMemoryAccounting=true\nTasksAccounting=true\nIOAccounting=true" > /etc/systemd/system/ds01-researcher-204214.slice'
```

**4. Increased CPU quota to full system (128 cores):**
```bash
sudo systemctl daemon-reload
sudo systemctl set-property ds01-researcher.slice CPUQuota=12800%
```

**5. User recreated container** (closed VS Code, reopened in container)

### Result
- Before: CPU throttled at 1600% (16 cores), ~26% per core in htop
- After: CPU usage at 12376% (~124 cores), full speed

### LDAP Username Note
Silke has two LDAP accounts:
- `s.kaiser@hertie-school.lan` (UID 1722829049)
- `204214@hertie-school.lan` (UID 1722827400) - this is in docker group

Both were added to researcher members list to ensure matching.

---

## TODO: Permanent Fixes Needed

1. **Make slice file changes permanent** - currently runtime changes via `set-property`
   ```bash
   # Edit the slice file directly to persist across reboots
   sudo sed -i 's/CPUQuota=6400%/CPUQuota=12800%/' /etc/systemd/system/ds01-researcher.slice
   ```

2. **Update create-user-slice.sh** to read group from resource-limits.yaml and create slice under correct parent (student vs researcher)

3. **Update setup-resource-slices.sh** to set appropriate TasksMax and CPUQuota defaults:
   - student: CPUQuota=1600%, TasksMax=65536
   - researcher: CPUQuota=12800%, TasksMax=65536
   - admin: no limits

4. **Add TasksMax to resource-limits.yaml schema** and have slice creation read from it
