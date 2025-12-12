# DS01 Group Membership Configuration

This directory contains the **single source of truth** for user group membership in DS01.

## Data Flow Architecture

```
UPSTREAM (auto-population):
  /home/ directory scan
       ↓
  + ../group-overrides.txt (deterministic assignments)
       ↓
  MERGE into *.members (ADD only, never remove)
       ↓
DOWNSTREAM (reads):
  resource-limits.yaml parser reads *.members
       ↓
  + user-overrides.yaml (custom resource limits)
       ↓
  Final resource allocation per container
```

## Key Principles

1. **MERGE, not replace**: Auto-sync adds new users but **never removes** existing entries
2. **Admin changes preserved**: Manual edits to `.members` files are always kept
3. **Archived users skipped**: Users in `archived.members` are not added to any active group
4. **Override precedence**: `group-overrides.txt` takes priority over pattern matching

## Files in This Directory

| File | Purpose | Auto-synced? |
|------|---------|--------------|
| `student.members` | Student group (MIG only, limited resources) | Yes |
| `researcher.members` | PhD students, research staff (full GPU) | Yes |
| `faculty.members` | Professors (highest resources) | Yes |
| `admin.members` | System admins (unlimited) | **No** - manual only |
| `archived.members` | Inactive users (skipped by sync) | No |

## Two Override Systems

DS01 uses **two different override files** for different purposes:

### 1. Group Assignment Override (`../group-overrides.txt`)

**Purpose**: Force a user into a specific GROUP regardless of username pattern.

```
# Example: PhD student with student-style ID forced to researcher
204214@hertie-school.lan:researcher

# Example: Professor forced to faculty
w.lowe@hertie-school.lan:faculty
```

**When to use**:
- PhD students with numeric IDs (would auto-classify as student)
- Faculty members who need elevated access
- IT staff who need admin access

### 2. Resource Limit Override (`../user-overrides.yaml`)

**Purpose**: Give a specific USER custom RESOURCE limits, regardless of their group.

```yaml
# Example: Researcher with no idle timeout
204214@hertie-school.lan:
  idle_timeout: null
  max_runtime: null
```

**When to use**:
- User needs longer runtime than their group allows
- User needs exception from idle timeout
- User needs custom GPU limits

## Auto-Classification Rules

When a user is **not** in `group-overrides.txt`, the sync script classifies by username pattern:

| Pattern | Example | Assigned Group |
|---------|---------|----------------|
| `[0-9]+@hertie-school.lan` | `228755@hertie-school.lan` | student |
| `[a-z].[a-z]+@hertie-school.lan` | `h.baker@hertie-school.lan` | researcher |
| Other | `localuser` | student |

## Manual Editing Rules

### Safe to Edit:
- Add users to any `.members` file (they won't be removed by sync)
- Add users to `archived.members` to prevent them from being added elsewhere
- Add comments (lines starting with `#`)

### Never Do:
- Don't edit `admin.members` unless adding/removing actual admins
- Don't add the same user to multiple `.members` files
- Don't remove users from `.members` files to revoke access (use `archived.members` instead)

## Archiving Users

To remove access for a user:

1. Add their username to `archived.members`:
   ```
   228755@hertie-school.lan  # Graduated 2024-05
   ```

2. Optionally remove from their current `.members` file (or leave it - won't cause issues)

3. The sync script will skip archived users, so they won't be re-added

## Sync Script

The sync script runs automatically via cron:

```bash
# Manual run:
sudo /opt/ds01-infra/scripts/system/sync-group-membership.sh

# Dry run (show what would change):
sudo /opt/ds01-infra/scripts/system/sync-group-membership.sh --dry-run

# Verbose output:
sudo /opt/ds01-infra/scripts/system/sync-group-membership.sh --verbose
```

**Cron schedule**: Daily at 4am

## Group Resource Limits

| Group | GPU Access | Max MIG | Memory | Idle Timeout | Max Runtime |
|-------|------------|---------|--------|--------------|-------------|
| student | MIG only | 3 | 32GB | 30min | 24h |
| researcher | Full GPU | 6 | 64GB | 1h | 48h |
| faculty | Full GPU | 8 | 128GB | 2h | 72h |
| admin | Unlimited | ∞ | 128GB | 1h | 24h |

See `../resource-limits.yaml` for complete resource definitions.

## Troubleshooting

### User not getting expected resources

1. Check which group they're in:
   ```bash
   grep -l "username@" /opt/ds01-infra/config/groups/*.members
   ```

2. Check if they have an override in `group-overrides.txt`:
   ```bash
   grep "username@" /opt/ds01-infra/config/group-overrides.txt
   ```

3. Check if they have custom limits in `user-overrides.yaml`:
   ```bash
   grep -A5 "username@" /opt/ds01-infra/config/user-overrides.yaml
   ```

### User appearing in wrong group

1. Add them to `../group-overrides.txt` with correct group:
   ```
   username@hertie-school.lan:researcher
   ```

2. Run sync to update:
   ```bash
   sudo /opt/ds01-infra/scripts/system/sync-group-membership.sh
   ```

### User keeps getting re-added after removal

1. Add them to `archived.members` instead of just removing from `.members`
2. Users in `archived.members` are skipped by the sync script

## Related Files

- `../resource-limits.yaml` - Group resource limit definitions
- `../group-overrides.txt` - Deterministic group assignment overrides
- `../user-overrides.yaml` - Per-user resource limit exceptions
- `../../scripts/system/sync-group-membership.sh` - Auto-sync script
- `../../scripts/admin/user-activity-report` - Activity/inactivity report
