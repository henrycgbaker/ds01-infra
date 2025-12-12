# User Privacy Hardening

DS01 implements industry-standard user privacy controls to prevent unauthorized access to other users' data while maintaining system usability.

## Current Implementation

### Active Controls

| Control | Implementation | Effect |
|---------|---------------|--------|
| `/home` permissions | `chmod 711 /home` | Blocks `ls /home`, allows `cd ~` |
| Home directories | `chmod 700 /home/*` | Each user's home is private |
| Login enforcement | `/etc/profile.d/ds01-home-enforce.sh` | Ensures 700 on every login |
| Drift correction | `fix-home-permissions.sh` | Fixes permission drift (manual/cron) |

### How It Works

**1. Base directory (`/home`):**
- Permissions: `711` (rwx--x--x)
- Users cannot list directory contents (`ls /home` fails)
- Users can traverse the directory (`cd /home/username` works if they know the path)

**2. Individual home directories (`/home/*`):**
- Permissions: `700` (rwx------)
- Only the owner can read, write, or traverse
- Other users cannot access any content

**3. Login-time enforcement:**
```bash
# /etc/profile.d/ds01-home-enforce.sh
[ -d "$HOME" ] && chmod 700 "$HOME" 2>/dev/null || true
```
This runs on every login, automatically fixing any permission drift.

**4. Periodic maintenance:**
```bash
# Check for issues without fixing
sudo fix-home-permissions.sh --check

# Fix all permission issues
sudo fix-home-permissions.sh

# Optional weekly cron (already in place)
0 2 * * 0 root /opt/ds01-infra/scripts/maintenance/fix-home-permissions.sh
```

### Verification

Run these tests as a regular user to verify privacy controls:

```bash
# These should FAIL (Permission denied):
ls /home
ls /home/otheruser
cat /home/otheruser/.bashrc

# These should SUCCEED:
cd ~
ls ~
echo "test" > ~/test.txt
```

---

## Deferred Hardening Options

The following additional controls are documented for future implementation if stricter privacy is required. Each has trade-offs that require evaluation.

### 1. Process Hiding (hidepid=2)

**What it does:** Hides other users' processes in `/proc`

**Current state:** All users can see all processes via `ps aux`, `top`, etc.

**Implementation:**
```bash
# Add to /etc/fstab:
proc /proc proc defaults,hidepid=2,gid=ds01-admin 0 0

# Remount immediately:
mount -o remount,hidepid=2,gid=ds01-admin /proc
```

**Pros:**
- Users cannot see other users' processes
- Hides command-line arguments (may contain sensitive paths/params)
- Hides process resource usage of other users

**Cons:**
- May break monitoring tools expecting full process visibility
- Some systemd services may require adjustment
- Admin group (ds01-admin) needed for full visibility
- cgroupfs monitoring may be affected

**Status:** DEFERRED - Evaluate after monitoring stack is mature

---

### 2. User Enumeration Prevention (SSSD)

**What it does:** Prevents listing all system users

**Current state:** Users can run `getent passwd` and see all accounts

**Implementation:**
```ini
# /etc/sssd/sssd.conf
[domain/your_domain]
enumerate = false
```

```bash
# Restart SSSD
systemctl restart sssd
```

**Pros:**
- `getent passwd` returns nothing (or only queried user)
- Prevents user discovery attacks
- Reduces information exposure

**Cons:**
- May break tools that enumerate users (some backup scripts, etc.)
- Tab completion for usernames stops working
- Some administrative workflows may need adjustment
- Only effective if using SSSD (not local accounts)

**Status:** DEFERRED - Needs testing with existing tooling

---

### 3. Login Record Restrictions (wtmp/utmp)

**What it does:** Restricts access to `w`, `who`, `last` commands

**Current state:** Any user can see who else is logged in

**Implementation:**
```bash
# Restrict read access to root and adm group
chmod 640 /var/log/wtmp
chmod 640 /var/run/utmp
chgrp adm /var/log/wtmp /var/run/utmp
```

**Pros:**
- Users cannot see who else is logged in
- `w`, `who`, `last` commands return empty or error
- Hides login patterns of other users

**Cons:**
- Breaks legitimate use of these commands
- Users cannot check their own login history (without workarounds)
- May confuse users expecting these commands to work

**Status:** DEFERRED - Low priority, moderate usability impact

---

### 4. Filtered Wrapper Scripts

**What it does:** Custom `w`/`who`/`last` that show only the caller's sessions

**Current state:** Not implemented

**Implementation concept:**
```bash
#!/bin/bash
# /usr/local/bin/w (wrapper)
/usr/bin/w | head -2  # Header lines
/usr/bin/w | grep "^$(whoami)"
```

**Pros:**
- Preserves command functionality for legitimate self-inspection
- More user-friendly than complete restriction
- Gradual privacy without breaking workflows

**Cons:**
- Users can bypass via `/usr/bin/w` directly
- Requires maintaining wrapper scripts
- Complex to implement correctly for all output formats
- False sense of security if bypassable

**Status:** DEFERRED - High complexity, moderate benefit

---

## Information Leakage Analysis

### Current Exposure Matrix

| Vector | Risk Level | Current State | Mitigation | Notes |
|--------|------------|---------------|------------|-------|
| `ls /home` | HIGH | **Blocked** | chmod 711 | Users cannot enumerate home directories |
| Home directory access | HIGH | **Blocked** | chmod 700 | Users cannot access others' files |
| `/etc/passwd` | MEDIUM | Readable | None (system requirement) | Usernames visible, no passwords |
| `getent passwd` | MEDIUM | Returns all | SSSD enumerate=false (deferred) | Same as /etc/passwd |
| `/proc` (processes) | MEDIUM | All visible | hidepid=2 (deferred) | Process names, args visible |
| `w`, `who`, `last` | LOW | All visible | wtmp restrictions (deferred) | Login times, terminals visible |
| Docker containers | LOW | Names visible | Accepted trade-off | User IDs in container names |
| File ownership | LOW | UIDs visible | Cannot mitigate | In shared directories |

### Unavoidable Information Exposure

Some information leakage cannot be prevented without breaking Linux fundamentals:

1. **`/etc/passwd` must remain world-readable**
   - Required for username resolution (`ls -l`, `ps`, etc.)
   - Contains no sensitive data (passwords in `/etc/shadow`)
   - Shows: username, UID, home directory, shell

2. **File ownership in shared directories**
   - Files created in `/tmp`, shared mounts show owner UID
   - `ls -l` resolves UID to username via `/etc/passwd`
   - Mitigation: Avoid shared directories, use private tmp

3. **Docker container names (AIME convention)**
   - Format: `{project-name}._.{user-id}`
   - Visible via `docker ps` (to docker group members)
   - Accepted as operational requirement

---

## Implementation Files

| File | Location | Purpose |
|------|----------|---------|
| Login enforcement | `/etc/profile.d/ds01-home-enforce.sh` | Ensures 700 on login |
| Deploy source | `config/deploy/profile.d/ds01-home-enforce.sh` | Source for deployment |
| Permission fixer | `scripts/maintenance/fix-home-permissions.sh` | Manual/cron drift correction |

---

## Audit Checklist

For periodic security reviews:

```bash
# 1. Verify /home permissions
stat -c "%a %n" /home
# Expected: 711 /home

# 2. Check all home directories
stat -c "%a %n" /home/*
# Expected: 700 for each

# 3. Verify enforcement script is deployed
ls -la /etc/profile.d/ds01-home-enforce.sh
# Expected: File exists, readable

# 4. Run permission fixer in check mode
sudo /opt/ds01-infra/scripts/maintenance/fix-home-permissions.sh --check
# Expected: No issues found

# 5. Test as regular user (log in as test user)
su - testuser -c "ls /home"
# Expected: Permission denied
```

---

## Future Considerations

If stricter privacy is required (e.g., for compliance or after security audit):

1. **Phase 1:** Implement hidepid=2 with admin group exception
2. **Phase 2:** Enable SSSD enumerate=false after testing
3. **Phase 3:** Consider wtmp/utmp restrictions based on user feedback

Document any changes in this file and update the exposure matrix accordingly.
