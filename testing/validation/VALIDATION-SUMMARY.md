# Validation Scripts Summary

## Created Scripts

### 1. Master Health Check
**Path**: `/opt/ds01-infra/testing/validation/health-check`

Single command to check entire system:
```bash
/opt/ds01-infra/testing/validation/health-check
```

**Output**: Concise pass/fail for each subsystem
**Exit Code**: 0 = all good, 1 = issues found

---

### 2. Individual Validation Scripts

| Script | Checks | Exit Code |
|--------|--------|-----------|
| `check-gpu-consistency.sh` | GPU allocator ↔ Docker containers | 0/1 |
| `check-gpu-docker-match.sh` | GPU allocator state ↔ Docker HostConfig | 0/1 |
| `check-container-list-sync.sh` | container-list ↔ Docker containers | 0/1 |
| `check-metadata-files.sh` | Metadata files ↔ Docker containers | 0/1 |

**Usage**: Run individually to focus on specific subsystem
```bash
/opt/ds01-infra/testing/validation/check-gpu-consistency.sh
```

---

### 3. Detailed Discrepancy Viewer
**Path**: `/opt/ds01-infra/testing/validation/show-discrepancies.sh`

More verbose output for debugging:
```bash
/opt/ds01-infra/testing/validation/show-discrepancies.sh
```

Shows side-by-side comparison of:
- GPU allocator view
- Docker containers with GPUs
- container-list output
- Metadata files

---

## Quick Reference

### Fast Status Check
```bash
# Quickest way to check system health
health-check && echo "All good" || echo "Problems found"
```

### Debugging Workflow
```bash
# 1. Identify problem area
health-check

# 2. Get details
show-discrepancies.sh

# 3. Fix
/opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh

# 4. Verify
health-check
```

### Current System Status (Example Output)

```bash
$ /opt/ds01-infra/testing/validation/health-check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DS01 System Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GPU Consistency     ... ✓ GPU allocations consistent
GPU-Docker Match    ... ⚠ Found 1 mismatch(es)
Container List Sync ... ✓ container-list in sync with Docker
Metadata Files      ... ✓ No orphaned metadata files
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✗ 1 check(s) failed (3/4 passed)

To fix issues, run:
  /opt/ds01-infra/scripts/maintenance/reconcile-gpu-state.sh
```

---

## Integration Examples

### Automated Monitoring (Cron)
```bash
# Daily health check with email alert
0 8 * * * /opt/ds01-infra/testing/validation/health-check || \
          echo "DS01 health check failed - run show-discrepancies.sh" | \
          mail -s "DS01 Alert" admin@example.com
```

### CI/CD Pipeline
```bash
#!/bin/bash
# In deployment script
echo "Running DS01 validation..."
if ! /opt/ds01-infra/testing/validation/health-check; then
    echo "FAILED: System inconsistent"
    /opt/ds01-infra/testing/validation/show-discrepancies.sh
    exit 1
fi
echo "PASSED: System consistent"
```

### Git Pre-commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit
if ! /opt/ds01-infra/testing/validation/health-check > /dev/null 2>&1; then
    echo "Warning: DS01 system has inconsistencies"
    echo "Run: /opt/ds01-infra/testing/validation/show-discrepancies.sh"
fi
```

---

## All Scripts Location

```
/opt/ds01-infra/testing/validation/
├── health-check                      # Master health check
├── check-gpu-consistency.sh          # GPU allocator vs Docker
├── check-gpu-docker-match.sh         # Allocator state vs HostConfig
├── check-container-list-sync.sh      # container-list vs Docker
├── check-metadata-files.sh           # Metadata files vs Docker
├── show-discrepancies.sh             # Detailed comparison view
└── README.md                         # Full documentation
```

---

## Design Philosophy

**Minimal Output**: Only show problems, not verbose details
**Fast Execution**: Sub-second for most checks
**Exit Codes**: Scriptable (0 = pass, 1 = fail)
**Color Coded**: Green ✓ / Yellow ⚠ / Red ✗
**Actionable**: Tells you what to run to fix issues

These validation scripts are designed for:
- Quick manual checks during development
- Automated monitoring in production
- CI/CD pipeline validation
- Pre/post deployment verification
