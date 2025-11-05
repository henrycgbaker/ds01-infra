# Deprecated Scripts Archive - November 2025

This directory contains scripts that were deprecated during the major refactoring effort (Phases 1-7) in November 2025.

## Why These Scripts Were Archived

The DS01 infrastructure underwent a comprehensive refactoring to:
1. Eliminate >1,100 lines of duplicated code
2. Establish a four-tier hierarchical architecture
3. Create modular, reusable components
4. Add consistent `--guided` mode across all commands
5. Fix exit behavior documentation

## Archived Scripts

### Deprecated Scripts (Superseded)

| Script | Replaced By | Reason |
|--------|-------------|--------|
| `new-project` | `project-init` | Renamed to match primary command naming convention. Legacy symlink remains for backwards compatibility. |
| `project-init-beginner` | `project-init --guided` | Merged into modular architecture with `--guided` flag. Educational mode now available as a flag, not a separate script. |

### Backup Files (Refactoring Snapshots)

| Backup | Date | Phase | Description |
|--------|------|-------|-------------|
| `container-create.backup-20251105` | 2025-11-05 | Pre-Phase 3 | Before adding --guided flag |
| `container-run.backup-20251105` | 2025-11-05 | Pre-Phase 3 | Before adding --guided flag |
| `image-create.backup-20251105-phase3` | 2025-11-05 | Phase 3 | After adding --guided flag |
| `user-setup.backup-20251105-phase5` | 2025-11-05 | Pre-Phase 5 | Before refactoring to Tier 4 wizard (932 lines) |

## What Replaced These Scripts

### Current Architecture (Four-Tier)

**Tier 4 - Wizards:**
- `user-setup`: Complete onboarding (ssh-setup → project-init → vscode-setup)
  - 932 lines → 285 lines (69.4% reduction from backup)

**Tier 3 - Orchestrators:**
- `project-init`: Project setup workflow (dir-create → git-init → readme-create → image-create → container-create)
  - 958 lines → 397 lines (58.5% reduction)
  - Supports both `project-init` and `project-init --guided` modes

**Tier 2 - Modular Commands:**
- `dir-create`, `git-init`, `readme-create`, `ssh-setup`, `vscode-setup`
- `container-create`, `container-run` (with --guided flags)
- `image-create` (with --guided flag)
- All work standalone or as part of orchestrators

## Legacy Support

For backwards compatibility, the following symlinks remain:
- `new-project` → `project-init`
- `new-user` → `user-setup`

Users are encouraged to use the new primary commands.

## Restoration

If needed, these scripts can be restored from this archive. However, the new modular architecture provides:
- Better maintainability (single source of truth)
- Enhanced user experience (consistent --guided mode)
- Flexibility (modules can be used standalone or orchestrated)
- Reduced codebase size (>1,100 lines eliminated)

## Refactoring Documentation

For complete details, see:
- `/opt/ds01-infra/docs/REFACTORING_PLAN.md` - Complete refactoring plan with phase details
- `/opt/ds01-infra/CLAUDE.md` - Architecture documentation
- `/opt/ds01-infra/README.md` - User-facing documentation

---

**Archive Date**: November 5, 2025
**Refactoring Phases**: 1-7
**Total Code Reduction**: >1,100 lines eliminated
