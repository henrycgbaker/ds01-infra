# DS01 Validation Scripts - Quick Reference

Fast, minimal-output consistency checkers for debugging and monitoring.

## Master Health Check

```bash
/opt/ds01-infra/testing/validation/health-check
```

Runs all checks and shows summary. Exit code 0 = all good, 1 = issues found.

**Output**:
```
DS01 System Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GPU Consistency     ... ✓ GPU allocations consistent
GPU-Docker Match    ... ⚠ Found 1 mismatch(es)
Container List Sync ... ✓ container-list in sync with Docker
Metadata Files      ... ✓ No orphaned metadata files
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✗ 1 check(s) failed (3/4 passed)
```

## Individual Checks

### 1. GPU Consistency
**Script**: `check-gpu-consistency.sh`
**Checks**: Containers in GPU allocator actually exist in Docker

**Detects**:
- ✗ STALE: GPU allocated to deleted container
- ⚠ UNTRACKED: Running container with GPU not in allocator

```bash
/opt/ds01-infra/testing/validation/check-gpu-consistency.sh
```

### 2. GPU-Docker Match
**Script**: `check-gpu-docker-match.sh`
**Checks**: GPU allocator state matches Docker HostConfig

**Detects**:
- ✗ MISMATCH: Allocator says GPU X, Docker has GPU Y
- ⚠ ALLOCATOR-ONLY: GPU in allocator but not in Docker
- ⚠ DOCKER-ONLY: GPU in Docker but not in allocator

```bash
/opt/ds01-infra/testing/validation/check-gpu-docker-match.sh
```

### 3. Container List Sync
**Script**: `check-container-list-sync.sh`
**Checks**: `container-list` shows same containers as Docker

**Detects**:
- ✗ MISSING: Container exists but not shown in container-list
- ⚠ PHANTOM: Shown in container-list but doesn't exist

```bash
/opt/ds01-infra/testing/validation/check-container-list-sync.sh
```

### 4. Metadata Files
**Script**: `check-metadata-files.sh`
**Checks**: Metadata files correspond to existing containers

**Detects**:
- ⚠ ORPHANED: Metadata file exists but container deleted

```bash
/opt/ds01-infra/testing/validation/check-metadata-files.sh
```

## Usage Patterns

### Quick Status Check
```bash
# Just see if there are problems (fast)
/opt/ds01-infra/testing/validation/health-check
echo $?  # 0 = good, 1 = problems
```

### Before/After Testing
```bash
# Before making changes
/opt/ds01-infra/testing/validation/health-check > before.txt

# Make changes...
container-create test pytorch

# After changes
/opt/ds01-infra/testing/validation/health-check > after.txt

# Compare
diff before.txt after.txt
```

### Automated Monitoring
```bash
# Add to cron for daily checks
0 8 * * * /opt/ds01-infra/testing/validation/health-check || \
          echo "DS01 health check failed" | mail -s "DS01 Alert" admin@example.com
```

### Fix Issues Found
```bash
# If validation finds problems, run reconciliation
/opt/ds01-infra/testing/validation/health-check
if [ $? -ne 0 ]; then
    /opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh
fi
```

## Exit Codes

All scripts return:
- **0**: Check passed, no issues
- **1**: Check failed, issues found

## Color Coding

- 🟢 **Green** `✓`: Check passed
- 🟡 **Yellow** `⚠`: Warning (non-critical issue)
- 🔴 **Red** `✗`: Error (critical issue)

## Integration with CI/CD

```bash
# In CI pipeline
/opt/ds01-infra/testing/validation/health-check || exit 1
```

## Debugging Workflow

1. Run health check to identify which subsystem has issues
2. Run specific check for more details
3. Manually inspect using Docker/GPU allocator commands
4. Run reconciliation if needed
5. Verify with health check again

```bash
# Example debugging session
$ /opt/ds01-infra/testing/validation/health-check
GPU-Docker Match    ... ✗ Found 1 mismatch(es)

$ /opt/ds01-infra/testing/validation/check-gpu-docker-match.sh
⚠ DOCKER-ONLY: test-2._.1001 has GPU in Docker but not in allocator

$ docker inspect test-2._.1001 --format '{{.HostConfig.DeviceRequests}}'
# Investigate why it's not tracked...

$ /opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh
# Fix the issue

$ /opt/ds01-infra/testing/validation/health-check
✓ All checks passed (4/4)
```
