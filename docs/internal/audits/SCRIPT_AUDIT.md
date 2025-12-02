# DS01 Scripts Audit and Classification

## Overview

This document audits all scripts in `/opt/ds01-infra/scripts/user/` and classifies them for the tiered architecture refactoring.

**Classification Categories:**
- **KEEP & REFACTOR**: Core commands that fit the tiered structure (add --guided, integrate with base system)
- **KEEP AS-IS**: Utility scripts that don't need refactoring (dispatchers, info commands)
- **DEPRECATE**: Older versions superseded by newer commands (keep for backwards compatibility)
- **DELETE**: Backup files and obsolete code

---

## Complete Script Inventory (27 scripts)

### TIER 4: Workflow Wizards

| Script | Status | Action | Notes |
|--------|--------|--------|-------|
| `user-setup` | ✅ KEEP & REFACTOR | Refactor as `user-init` wizard | 29KB - Complete onboarding (SSH + VS Code + project) |
| `project-init` | ✅ KEEP & REFACTOR | Refactor as orchestrator | 28KB - Main project workflow, calls Tier 2 modules |
| `new-project` | ⚠️ DEPRECATE | Keep as legacy alias | 28KB - Near-duplicate of project-init, maintain symlink |
| `project-init-beginner` | ⚠️ DEPRECATE | Merge into project-init --guided | 31KB - Now handled by --guided flag |
| `student-setup.sh` | ❌ DEPRECATE | Superseded by user-setup | Old onboarding script, keep for legacy |

**Refactoring Plan:**
1. **user-setup** → **user-init**: Extract ssh-setup + vscode-setup, then orchestrate
2. **project-init**: Keep as Tier 3 orchestrator, add --guided propagation
3. **new-project**: Symlink to project-init (backwards compatibility)
4. **project-init-beginner**: Delete, functionality in project-init --guided

---

### TIER 3: Dispatchers (Command Routing)

| Script | Status | Action | Notes |
|--------|--------|--------|-------|
| `container-dispatcher.sh` | ✅ KEEP AS-IS | Add --guided passthrough | Routes `container <subcommand>` to `container-*` scripts |
| `image-dispatcher.sh` | ✅ KEEP AS-IS | Add --guided passthrough | Routes `image <subcommand>` to `image-*` scripts |
| `project-dispatcher.sh` | ✅ KEEP AS-IS | Add --guided passthrough | Routes `project <subcommand>` to project scripts |
| `user-dispatcher.sh` | ✅ KEEP AS-IS | Add --guided passthrough | Routes `user <subcommand>` to user scripts |

**How Dispatchers Work:**
```bash
# User runs:
container create my-project

# Dispatcher parses:
SUBCOMMAND="create"  # First arg
SCRIPT="$SCRIPT_DIR/container-$SUBCOMMAND"

# Executes:
/opt/ds01-infra/scripts/user/container-create my-project

# Also works with hyphenated form:
container-create my-project  # Direct symlink to script
```

**Refactoring Need:**
- Add --guided flag passthrough in dispatchers
- Ensure flags propagate correctly to sub-commands

---

### TIER 2: Container Management Commands

| Script | Size | Status | Action | Notes |
|--------|------|--------|--------|-------|
| `container-create` | 15KB | ✅ KEEP & REFACTOR | Add --guided, call mlc-create-wrapper | Currently uses direct docker create |
| `container-run` | 9.5KB | ✅ KEEP & REFACTOR | Add --guided, call mlc-open | Currently uses direct docker exec |
| `container-stop` | 7.5KB | ✅ KEEP & REFACTOR | Add --guided explanations | Good standalone command |
| `container-list` | 9.4KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `container-stats` | 7.9KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `container-cleanup` | 11KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `container-exit` | 4.4KB | ✅ KEEP AS-IS | Fix Ctrl+P/Ctrl+Q docs | Info command (not executable action) |

**Key Refactoring:**
1. **container-create**:
   - Replace direct `docker create` with call to `mlc-create-wrapper.sh`
   - Add --guided explanations (what is container, resource allocation)
   - Keep recovery flows for existing containers

2. **container-run**:
   - Replace direct `docker exec` with call to `mlc-open` (if available)
   - Add comprehensive --guided mode:
     - BEFORE entering: What you can do, how to exit
     - AFTER exiting: What happened, what's next

3. **container-exit**:
   - Fix misleading documentation about Ctrl+P, Ctrl+Q
   - Reality: `docker exec` doesn't support detach keys
   - Update to reflect actual behavior

---

### TIER 2: Image Management Commands

| Script | Size | Status | Action | Notes |
|--------|------|--------|--------|-------|
| `image-create` | 12KB | ✅ KEEP & REFACTOR | Add --guided flag | Main image creation command |
| `image-list` | 5.1KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `image-update` | 6.8KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `image-delete` | 6.9KB | ✅ KEEP AS-IS | Minor polish | Already good |
| `create-custom-image.sh` | ? | ⚠️ DEPRECATE | Superseded by image-create | Old version, different UX |
| `manage-images.sh` | ? | ⚠️ DEPRECATE | Superseded by image-* commands | Old version |
| `install-to-image.sh` | ? | ⚠️ DEPRECATE | Functionality in image-update | Old helper script |

**Key Refactoring:**
1. **image-create**:
   - Add --guided flag with Docker/Dockerfile explanations
   - Remove duplication (project-init should call this, not reimplement)
   - Already has good standalone functionality

2. **Deprecate old scripts**:
   - `create-custom-image.sh` → Keep for legacy, point to image-create
   - `manage-images.sh` → Delete or archive
   - `install-to-image.sh` → Delete or archive

---

### TIER 2: New Modular Commands (To Be Created)

| Script | Purpose | Extract From | Lines | Priority |
|--------|---------|--------------|-------|----------|
| `dir-create` | Create project directory structure | project-init | 152-198 | High |
| `git-init` | Initialize Git repository | project-init | 200-351 | High |
| `readme-create` | Generate README and requirements.txt | project-init | 353-610 | High |
| `ssh-setup` | Configure SSH for remote access | user-setup | TBD | Medium |
| `vscode-setup` | VS Code Dev Containers setup | user-setup | TBD | Medium |
| `docker-setup` | Add user to docker group | N/A | New | Low |

**These will be NEW scripts** extracted from orchestrators to enable:
- Standalone usage (users can call them directly)
- Orchestration (project-init calls them)
- --guided mode support
- No code duplication

---

### TIER 2: Utility & Helper Commands

| Script | Size | Status | Action | Notes |
|--------|------|--------|--------|-------|
| `ds01-status` | ? | ✅ KEEP AS-IS | Polish | System status dashboard |
| `ds01-run` | ? | ✅ KEEP AS-IS | Review integration | Standalone container launcher |
| `ssh-config` | ? | ✅ KEEP AS-IS | Fold into ssh-setup? | SSH configuration helper |
| `git-ml-repo-setup.sh` | ? | ⚠️ DEPRECATE | Fold into git-init? | Git + LFS setup |

---

### DELETE: Backup and Obsolete Files

| Script | Status | Action | Reason |
|--------|--------|--------|--------|
| `project-init.bak` | ❌ DELETE | Remove after refactoring complete | Backup file |

---

## Command Mapping: User Commands → Scripts

This maps the commands users type to the actual scripts and shows the dispatcher flow.

### Container Management

```
User Command                          → Dispatcher → Script
──────────────────────────────────────────────────────────────────────
container create NAME IMAGE           → container-dispatcher.sh → container-create
container-create NAME IMAGE            → [direct symlink] → container-create

container run NAME                     → container-dispatcher.sh → container-run
container-run NAME                     → [direct symlink] → container-run

container stop NAME                    → container-dispatcher.sh → container-stop
container-stop NAME                    → [direct symlink] → container-stop

container exit                         → container-dispatcher.sh → container-exit
container-exit                         → [direct symlink] → container-exit

container list                         → container-dispatcher.sh → container-list
container-list                         → [direct symlink] → container-list

container stats                        → container-dispatcher.sh → container-stats
container-stats                        → [direct symlink] → container-stats

container cleanup                      → container-dispatcher.sh → container-cleanup
container-cleanup                      → [direct symlink] → container-cleanup
```

### Image Management

```
User Command                          → Dispatcher → Script
──────────────────────────────────────────────────────────────────────
image create NAME                      → image-dispatcher.sh → image-create
image-create NAME                      → [direct symlink] → image-create

image list                             → image-dispatcher.sh → image-list
image-list                             → [direct symlink] → image-list

image update NAME                      → image-dispatcher.sh → image-update
image-update NAME                      → [direct symlink] → image-update

image delete NAME                      → image-dispatcher.sh → image-delete
image-delete NAME                      → [direct symlink] → image-delete
```

### Project Management

```
User Command                          → Dispatcher → Script
──────────────────────────────────────────────────────────────────────
project init                           → project-dispatcher.sh → project-init
project-init                           → [direct symlink] → project-init

project init --guided                  → project-dispatcher.sh → project-init --guided
project-init --guided                  → [direct symlink] → project-init --guided

new-project                            → [legacy symlink] → project-init
new-user                               → [legacy symlink] → project-init --guided
```

### User Management

```
User Command                          → Dispatcher → Script
──────────────────────────────────────────────────────────────────────
user init                              → user-dispatcher.sh → user-init (NEW)
user-init                              → [direct symlink] → user-init

user setup                             → user-dispatcher.sh → user-setup
user-setup                             → [direct symlink] → user-setup

user-setup --guided                    → [direct symlink] → user-setup --guided
```

---

## Dispatcher Pattern Integration with Tiers

### How Dispatchers Enable Both Command Forms

**Users can type commands two ways:**

1. **Space-separated**: `container create my-project`
   - Goes through dispatcher
   - Dispatcher routes to `container-create` script

2. **Hyphenated**: `container-create my-project`
   - Direct symlink to script
   - Bypasses dispatcher

**Both forms work identically** because:
- Symlinks point to same scripts
- Dispatchers just route to scripts
- Scripts implement actual functionality

### Example Flow with --guided Flag

```bash
# User runs:
container create my-project pytorch --guided

# Flow:
1. User shell looks up 'container' command
   → Symlink: /usr/local/bin/container → /opt/ds01-infra/scripts/user/container-dispatcher.sh

2. Dispatcher executes:
   SUBCOMMAND="create"
   ARGS="my-project pytorch --guided"
   exec /opt/ds01-infra/scripts/user/container-create my-project pytorch --guided

3. container-create parses:
   PROJECT_NAME="my-project"
   IMAGE="pytorch"
   GUIDED=true

4. Script executes with guided mode active
```

### Dispatcher Refactoring Needed

**Current Issue**: Dispatchers don't understand flags, just pass them through

**Solution**: No change needed! Dispatchers should be transparent. They just route:
```bash
# In dispatcher (current - already correct):
shift  # Remove subcommand
exec "$SUBCOMMAND_SCRIPT" "$@"  # Pass ALL remaining args
```

**Flags automatically propagate** to the actual command scripts.

---

## Inside Container Aliases

**Location**: `/opt/ds01-infra/config/container-aliases.sh`

**Status**: ✅ KEEP, but FIX documentation

**Issues to Fix:**

1. **Misleading `detach` alias**: Says Ctrl+P, Ctrl+Q works, but doesn't with `docker exec`
2. **Confusing exit-stop**: Implies `exit` stops container, but it doesn't (with exec)
3. **Wrong container-list alias**: Shows warning it's host-only, but misleading

**Corrections Needed:**

```bash
# REMOVE (misleading):
alias detach='echo -e "💡 To detach without stopping: Press Ctrl+P, then Ctrl+Q"'

# FIX:
alias exit-help='echo -e "━━━ Exit Options ━━━
  • exit or Ctrl+D - Exit session (container keeps running)
  • Stop container: Exit first, then run container-stop <name> on host
  • Re-enter: container-run <name> on host"'

# ADD:
alias stop-this='echo -e "💡 To stop this container:
  1. Exit this session (type: exit)
  2. Run on host: container-stop <name>"'
```

---

## Admin Commands

**These are separate from user workflow**, located in `/opt/ds01-infra/scripts/admin/`

| Command | Script Location | Status | Notes |
|---------|----------------|--------|-------|
| `ds01-dashboard` | scripts/admin/ds01-dashboard | ✅ Keep | System overview |
| `ds01-logs` | scripts/admin/ds01-logs | ✅ Keep | Infrastructure logs |
| `ds01-users` | scripts/admin/ds01-users | ✅ Keep | Active users |
| `alias-list` | scripts/admin/alias-list | ✅ Keep | Command reference |
| `alias-create` | scripts/admin/alias-create | ✅ Keep | Custom aliases |

**No refactoring needed** - these are admin-only utilities.

---

## Symlink Strategy

**All commands available in `/usr/local/bin/` via symlinks:**

### Current Symlinks (from deploy-commands.sh)

```bash
# Project commands
/usr/local/bin/project-init → /opt/ds01-infra/scripts/user/project-init
/usr/local/bin/project → /opt/ds01-infra/scripts/user/project-dispatcher.sh

# Legacy aliases
/usr/local/bin/new-project → /opt/ds01-infra/scripts/user/project-init
/usr/local/bin/new-user → /opt/ds01-infra/scripts/user/project-init
/usr/local/bin/user-setup → /opt/ds01-infra/scripts/user/project-init

# User commands
/usr/local/bin/user → /opt/ds01-infra/scripts/user/user-dispatcher.sh
```

### NEW Symlinks to Add

```bash
# Container commands (hyphenated forms)
/usr/local/bin/container → scripts/user/container-dispatcher.sh
/usr/local/bin/container-create → scripts/user/container-create
/usr/local/bin/container-run → scripts/user/container-run
/usr/local/bin/container-stop → scripts/user/container-stop
/usr/local/bin/container-exit → scripts/user/container-exit
/usr/local/bin/container-list → scripts/user/container-list
/usr/local/bin/container-stats → scripts/user/container-stats
/usr/local/bin/container-cleanup → scripts/user/container-cleanup

# Image commands (hyphenated forms)
/usr/local/bin/image → scripts/user/image-dispatcher.sh
/usr/local/bin/image-create → scripts/user/image-create
/usr/local/bin/image-list → scripts/user/image-list
/usr/local/bin/image-update → scripts/user/image-update
/usr/local/bin/image-delete → scripts/user/image-delete

# New modular commands (Tier 2)
/usr/local/bin/dir-create → scripts/user/dir-create
/usr/local/bin/git-init → scripts/user/git-init
/usr/local/bin/readme-create → scripts/user/readme-create
/usr/local/bin/ssh-setup → scripts/user/ssh-setup
/usr/local/bin/vscode-setup → scripts/user/vscode-setup

# New wizard
/usr/local/bin/user-init → scripts/user/user-init
```

---

## Refactoring Priority Matrix

### Phase 1: Critical Base Integration (Week 1)
**Risk**: High | **Impact**: High | **Effort**: Medium

- [ ] Verify /opt/aime-ml-containers/mlc-create works
- [ ] Refactor container-create to call mlc-create-wrapper.sh
- [ ] Refactor container-run to call mlc-open
- [ ] Test thoroughly

### Phase 2: Extract Tier 2 Modules (Week 2)
**Risk**: Low | **Impact**: High | **Effort**: Medium

- [ ] Extract dir-create from project-init
- [ ] Extract git-init from project-init
- [ ] Extract readme-create from project-init
- [ ] Test each independently
- [ ] Create symlinks

### Phase 3: Add --guided Flags (Week 2-3)
**Risk**: Low | **Impact**: High | **Effort**: Low

- [ ] Add --guided to image-create
- [ ] Add --guided to container-create
- [ ] Add --guided to container-run (with exit explanations)
- [ ] Test guided mode for each

### Phase 4: Refactor Orchestrators (Week 3)
**Risk**: Medium | **Impact**: High | **Effort**: High

- [ ] Refactor project-init to call Tier 2 modules
- [ ] Remove ~220 lines of duplicated code
- [ ] Ensure --guided propagates
- [ ] Preserve all explanations
- [ ] Test complete workflow

### Phase 5: Create Wizards (Week 4)
**Risk**: Low | **Impact**: Medium | **Effort**: Medium

- [ ] Extract ssh-setup from user-setup
- [ ] Extract vscode-setup from user-setup
- [ ] Create user-init wizard
- [ ] Test full onboarding

### Phase 6: Fix Exit & Cleanup (Week 4)
**Risk**: Low | **Impact**: Medium | **Effort**: Low

- [ ] Fix container-exit documentation
- [ ] Update container-aliases.sh
- [ ] Remove misleading Ctrl+P, Ctrl+Q references
- [ ] Test exit behavior

### Phase 7: Deprecate & Document (Week 5)
**Risk**: Low | **Impact**: Low | **Effort**: Low

- [ ] Move old scripts to deprecated/ folder
- [ ] Update all documentation
- [ ] Create migration guide
- [ ] Announce changes

---

## Backwards Compatibility Strategy

**Principle**: All old commands continue to work via symlinks.

### Legacy Command → New Implementation

```bash
# Old command still works:
new-project my-thesis
  → Symlink: new-project → project-init
  → Runs: project-init my-thesis

# Old command with intended meaning:
new-user
  → Symlink: new-user → user-init --guided
  → Runs: user-init --guided

# Old explicit user-setup:
user-setup
  → Symlink: user-setup → user-init --guided
  → Runs: user-init --guided
```

**No users need to change their habits!**

---

## Testing Strategy by Script Category

### Tier 2 Commands (Unit Tests)

For each command, test:
1. **Standalone execution** (no orchestrator)
2. **With all flags** (--guided, --help)
3. **Error cases** (invalid args, missing files)
4. **Idempotency** (run twice, same result)

Example for `container-create`:
```bash
# Basic
container-create test1 pytorch

# With guided
container-create test2 pytorch --guided

# Error cases
container-create  # Missing args
container-create existing-name  # Already exists (test recovery)

# Cleanup
container-stop test1 && container-remove test1
```

### Tier 3 Orchestrators (Integration Tests)

Test complete workflows:
```bash
# Full project setup
project-init my-thesis --guided

# Verify:
- Directory created with correct structure
- Git initialized
- README, requirements.txt exist
- Image built
- Container created
```

### Tier 4 Wizards (End-to-End Tests)

Test complete onboarding:
```bash
# Fresh user
user-init --guided

# Follow all prompts, verify:
- SSH configured
- VS Code instructions shown
- Project created
- Container running
- Can work inside
```

---

## Migration Timeline

**Week 1**: Base system integration (container-create, container-run)
**Week 2**: Extract modules (dir-create, git-init, readme-create)
**Week 3**: Add --guided flags, refactor project-init
**Week 4**: Create user-init wizard, fix exit documentation
**Week 5**: Deprecate old scripts, update docs, test with users

**Total estimated time**: 5 weeks of development + 2 weeks testing/rollout

---

## Success Metrics

- [ ] **Code reduction**: 30% fewer lines (eliminate duplication)
- [ ] **Command consistency**: All commands support --guided
- [ ] **Base integration**: 100% of containers via mlc-create
- [ ] **Test coverage**: All Tier 2 commands have tests
- [ ] **User feedback**: Positive reviews from 5+ users
- [ ] **Zero breakage**: All legacy commands still work

---

## Questions & Decisions Needed

1. **Deprecation timeline**: When to remove old scripts completely?
   - Recommend: Keep for 6 months, then archive

2. **Command naming**: Keep hyphenated forms (container-create) or migrate to space-separated (container create)?
   - Recommend: Support both indefinitely (symlinks are cheap)

3. **Guided mode verbosity**: How detailed should explanations be?
   - Recommend: Detailed for beginners, add --quiet flag for experts

4. **Base system dependency**: What if mlc-create unavailable?
   - Recommend: Hybrid approach (try wrapper, fallback to direct)

---

## Appendix: Complete File Tree (After Refactoring)

```
/opt/ds01-infra/scripts/user/
├── Tier 4: Wizards
│   ├── user-init                    ✅ NEW (refactored from user-setup)
│   └── project-init                 ♻️ REFACTORED (orchestrator)
│
├── Tier 3: Dispatchers
│   ├── container-dispatcher.sh      ✅ KEEP
│   ├── image-dispatcher.sh          ✅ KEEP
│   ├── project-dispatcher.sh        ✅ KEEP
│   └── user-dispatcher.sh           ✅ KEEP
│
├── Tier 2: Container Commands
│   ├── container-create             ♻️ REFACTORED (call mlc-create-wrapper)
│   ├── container-run                ♻️ REFACTORED (call mlc-open)
│   ├── container-stop               ✅ KEEP
│   ├── container-list               ✅ KEEP
│   ├── container-stats              ✅ KEEP
│   ├── container-cleanup            ✅ KEEP
│   └── container-exit               ♻️ FIX (documentation)
│
├── Tier 2: Image Commands
│   ├── image-create                 ♻️ REFACTORED (add --guided)
│   ├── image-list                   ✅ KEEP
│   ├── image-update                 ✅ KEEP
│   └── image-delete                 ✅ KEEP
│
├── Tier 2: New Modular Commands
│   ├── dir-create                   ✅ NEW (extracted from project-init)
│   ├── git-init                     ✅ NEW (extracted from project-init)
│   ├── readme-create                ✅ NEW (extracted from project-init)
│   ├── ssh-setup                    ✅ NEW (extracted from user-setup)
│   └── vscode-setup                 ✅ NEW (extracted from user-setup)
│
├── Utilities
│   ├── ds01-status                  ✅ KEEP
│   └── ds01-run                     ✅ KEEP
│
└── Deprecated (moved to archive/)
    ├── new-project                  ⚠️ DEPRECATED (symlink to project-init)
    ├── project-init-beginner        ⚠️ DEPRECATED (use project-init --guided)
    ├── user-setup                   ⚠️ DEPRECATED (renamed to user-init)
    ├── student-setup.sh             ❌ DEPRECATED (superseded)
    ├── create-custom-image.sh       ❌ DEPRECATED (superseded)
    ├── manage-images.sh             ❌ DEPRECATED (superseded)
    ├── install-to-image.sh          ❌ DEPRECATED (superseded)
    ├── git-ml-repo-setup.sh         ❌ DEPRECATED (folded into git-init)
    └── project-init.bak             ❌ DELETE
```

---

**This document is the source of truth for script classification and refactoring decisions.**
