# DS01 Custom Image Infrastructure: Changes and Risk Assessment

## Session Summary (2025-12-01)

This session addressed several critical issues with custom Docker image creation and container deployment, particularly for LDAP users with high UIDs.

---

## Changes Made This Session

### 1. `scripts/docker/mlc-patched.py` (+216 lines)

#### A. High UID Sparse File Fix (CRITICAL)
**Problem:** LDAP users have high UIDs (e.g., 1722830498). When creating users, Linux creates `/var/log/lastlog` and `/var/log/faillog` as sparse files indexed by UID. Docker's overlay2 storage materializes these as real data (300GB+), causing builds to hang.

**Fix:** Added truncation of sparse files after user creation:
```python
# In build_docker_run_command() - after user creation
bash_lines.extend([
    ": > /var/log/lastlog;",
    ": > /var/log/faillog;",
])
```

**Risk Level:** LOW - Only affects logging files, no functional impact.

#### B. Skip User Setup Optimization (NEW)
**Problem:** Custom images built with `image-create` already have user/group baked in. Running user setup again via docker commit is redundant and slow.

**Fix:** Check for `DS01_HAS_USER_SETUP` label in custom images and skip user creation + docker commit:
```python
skip_user_setup = False
# Check labels...
if has_setup == 'true' and img_uid == str(user_id) and img_gid == str(group_id):
    skip_user_setup = True
```

**Risk Level:** MEDIUM - This changes the container creation flow significantly:
- Original AIME: Always runs user setup + docker commit
- DS01 Patched: Skips if image already has matching user

**Mitigation:**
- Only skips if ALL conditions match (label exists, UID matches, GID matches)
- Falls back to original flow if any check fails
- Clearly marked with `DS01 OPTIMIZATION` comments

#### C. Image Tag Handling Fix
**Problem:** When `skip_user_setup=True`, code was still trying to use committed image tag (`base:container_tag`) instead of original image.

**Fix:** Added `skip_user_setup` parameter to `build_docker_create_command()`:
```python
if skip_user_setup:
    image_with_tag = selected_docker_image  # Use original
else:
    image_with_tag = f'{base_image_name}:{container_tag}'  # Use committed
```

**Risk Level:** MEDIUM - Changes which image is used for container creation.

#### D. HOME Export and .local Directory Fixes
**Problem:** LDAP usernames with `@` caused HOME path issues and pip --user failed.

**Fix:** Added HOME export and .local directory creation in `build_docker_run_command()`.

**Risk Level:** LOW - Additive change, doesn't modify existing functionality.

#### E. Username Sanitization with Domain Stripping
**Problem:** LDAP usernames like `c.fusarbassini@hertie-school.lan` are too long (36+ chars) and contain invalid characters.

**Fix:** Strip domain part and replace invalid characters:
```python
# Strip domain part (everything after @)
sanitized = username.split('@')[0] if '@' in username else username
sanitized = sanitized.replace('.', '-')
# Truncate to 32 chars with hash suffix if needed
```

**Result:** `c.fusarbassini@hertie-school.lan` → `c-fusarbassini` (14 chars)

**Risk Level:** LOW - Makes usernames cleaner and compatible with Linux limits.

---

### 2. `scripts/user/image-create` (+93 lines)

#### A. User/Group Baking into Image (NEW)
**Change:** Added Dockerfile template to create user/group at image build time:
- ARG for DS01_USER_ID, DS01_GROUP_ID, DS01_USERNAME
- RUN command to create user with matching UID:GID
- LABEL commands for DS01_HAS_USER_SETUP, DS01_USER_ID, DS01_GROUP_ID

**Why:** Avoids the slow docker commit at container creation time.

**Risk Level:** LOW - Image contains the correct user from the start.

#### B. Sparse File Truncation in Dockerfile
**Change:** Added `: > /var/log/lastlog && : > /var/log/faillog` after user creation.

**Risk Level:** LOW - Same fix as above, but at build time.

#### C. PATH and Environment Configuration (AIME PARITY)
**Change:** Added to user's `.bashrc` at image build time:
- `export PATH="$HOME/.local/bin:$PATH"` - for pip install --user packages
- `export HOME=/home/$DS01_USERNAME` - fixes LDAP username issues
- `export PS1='[\h] \u@ds01:\w\$ '` - container-aware prompt

**Why:** Matches functionality from original AIME `docker run` user setup phase.

**Risk Level:** LOW - Additive, matches AIME behavior.

---

### 3. `scripts/user/image-update` (+13 lines)

#### A. Build Args for Rebuild
**Problem:** When rebuilding images, user setup wasn't being performed because --build-arg wasn't passed.

**Fix:** Added GROUP_ID, SANITIZED_USERNAME variables and build args to rebuild command. Now uses shared `username-utils.sh` library.

**Risk Level:** LOW - Required for user setup to work on rebuild.

---

### 4. `scripts/user/install-to-image.sh` (+3 lines)

**Change:** Truncate sparse files before docker commit.

**Risk Level:** LOW.

---

### 5. `scripts/user/container-create` (+27 lines)

#### A. Double :latest Tag Fix
**Problem:** If image already has `:latest` tag, script was adding it again.

**Fix:** Check if image name contains `:` before appending `:latest`.

**Risk Level:** LOW.

#### B. Auto-detect Matching Image
**Change:** If no image specified, check if `ds01-{userid}/{container-name}` exists.

**Risk Level:** LOW - Convenience feature, falls back to original behavior.

---

### 6. `scripts/lib/username-utils.sh` (+18 lines)

#### A. Domain Stripping
**Change:** Strip everything after `@` from usernames for cleaner container names.
- Before: `c.fusarbassini@hertie-school.lan` → `c-fusarbassini-at-hertie-school-lan` (36 chars, FAILS)
- After: `c.fusarbassini@hertie-school.lan` → `c-fusarbassini` (14 chars)

#### B. 32-Character Limit with Hash
**Change:** Truncate long usernames to 32 characters (Linux limit) with 4-char hash suffix to prevent collisions.
- Example: `a.very.long.username.with.many.dots@domain.edu` → `a-very-long-username-with-m-ab6d` (32 chars)

**Risk Level:** LOW - Required for Linux compatibility.

---

### 7. `scripts/lib/username_utils.py` (+21 lines)

Same changes as bash version for Python consistency:
- Domain stripping
- 32-character limit with hash suffix
- Identical output for same input (verified)

---

## Deviation Analysis: mlc-patched.py vs Original mlc.py

| Aspect | Original AIME mlc.py | DS01 mlc-patched.py | Risk |
|--------|---------------------|---------------------|------|
| **File Size** | 2368 lines | 2584 lines (+216) | - |
| **Custom Image Support** | None | --image flag bypasses AIME catalog | LOW |
| **User Setup** | Always via docker run + commit | Baked in image OR docker commit | MEDIUM |
| **Resource Limits** | None | --shm-size, --cgroup-parent | LOW |
| **GPU Labels** | None | --ds01-labels for tracking | LOW |
| **Username Handling** | Direct passthrough | Domain stripped, 32-char limit | LOW |
| **Sparse File Fix** | None | Truncates lastlog/faillog | LOW |

### Key Functional Changes from Original AIME Flow

1. **Original Flow (AIME):**
   ```
   docker pull → docker run (user setup) → docker commit → docker create → docker start
   ```

2. **DS01 Patched Flow (with skip_user_setup=True):**
   ```
   verify local image → docker create → docker start
   ```

3. **DS01 Patched Flow (with skip_user_setup=False):**
   ```
   verify/pull image → docker run (user setup + sparse fix) → docker commit → docker create → docker start
   ```

---

## Username Sanitization Examples

| Original Username | Sanitized | Length |
|-------------------|-----------|--------|
| `c.fusarbassini@hertie-school.lan` | `c-fusarbassini` | 14 |
| `h.baker@hertie-school.lan` | `h-baker` | 7 |
| `alice` | `alice` | 5 |
| `john.doe` | `john-doe` | 8 |
| `christopher.vandenbergenstein@hertie-school.lan` | `christopher-vandenbergenstein` | 29 |
| `a.very.long.username.with.many.dots@domain.edu` | `a-very-long-username-with-m-ab6d` | 32 |

---

## Risk Assessment Summary

### HIGH RISK: None

### MEDIUM RISK:
1. **skip_user_setup optimization** - Changes container creation flow significantly
   - Mitigation: Strict UID/GID matching, fallback to original flow
   - Testing: Verified working for LDAP users

2. **Image tag selection logic** - Uses original vs committed image
   - Mitigation: Clear conditional logic based on skip_user_setup flag

### LOW RISK:
- Sparse file truncation (no functional impact)
- HOME export fix (additive)
- Resource limits support (additive)
- Username sanitization (required for Linux compatibility)
- Domain stripping (cleaner usernames)

---

## Recommendations for Future

1. **Add Integration Tests:** Test the three main flows:
   - AIME catalog image → container (original flow)
   - Custom image without user labels → container (commit flow)
   - Custom image with user labels → container (skip flow)

2. **Consider Upstream Sync:** Monitor AIME mlc.py for updates and merge carefully

3. **Documentation:** Keep this deviation log updated with each change

---

## Files Changed This Session

```
scripts/docker/mlc-patched.py        | 216 insertions(+), changes
scripts/user/image-create            |  93 insertions(+), changes
scripts/user/container-create        |  27 insertions(+), changes
scripts/user/image-update            |  13 insertions(+), changes
scripts/user/install-to-image.sh     |   3 insertions(+)
scripts/lib/username-utils.sh        |  18 insertions(+), changes
scripts/lib/username_utils.py        |  21 insertions(+), changes
```

---

## Version History

| Date | Author | Description |
|------|--------|-------------|
| 2025-12-01 | DS01 Admin | High UID sparse file fix, skip_user_setup optimization, username sanitization with domain stripping and 32-char limit |
