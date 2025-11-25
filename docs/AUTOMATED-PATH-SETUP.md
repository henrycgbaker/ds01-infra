# Automated PATH Configuration

**Problem:** Domain users and some local users don't have `/usr/local/bin` in PATH, preventing access to DS01 commands.

**Solution:** Multi-layer automated approach that ensures ALL users get correct PATH without manual intervention.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: /etc/bash.bashrc (System-wide)                     │
│ ✓ Sourced by ALL interactive bash shells                    │
│ ✓ Works immediately (no logout required)                    │
│ ✓ Covers: SSH non-login, docker exec, su, bash              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Layer 2: PAM Session Hook (Auto-create .bashrc)             │
│ ✓ Runs on every user login (SSH, console, etc.)             │
│ ✓ Creates ~/.bashrc from /etc/skel/ if missing              │
│ ✓ Completely automatic, zero user action                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Layer 3: /etc/profile.d/ (Login shells)                     │
│ ✓ Sourced by login shells (ssh with -l, su -, bash -l)      │
│ ✓ Backup for systems that use login shells                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Layer 4: /etc/skel/.bashrc (New users)                      │
│ ✓ Template for new user accounts                            │
│ ✓ Used by useradd -m and pam_mkhomedir                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Layer 5: shell-setup command (Manual fallback)              │
│ ✓ User-run command: /opt/ds01-infra/scripts/user/shell-setup│
│ ✓ Creates/fixes ~/.bashrc if needed                         │
└─────────────────────────────────────────────────────────────┘
```

## Deployment

### One-Command Deployment

```bash
sudo /opt/ds01-infra/scripts/system/deploy-automated-path.sh
```

This runs:
1. `deploy-bash-bashrc.sh` - Updates `/etc/bash.bashrc`
2. `deploy-pam-bashrc.sh` - Installs PAM hook

### Manual Step-by-Step

```bash
# Layer 1: System-wide bash.bashrc
sudo /opt/ds01-infra/scripts/system/deploy-bash-bashrc.sh

# Layer 2: PAM automation
sudo /opt/ds01-infra/scripts/system/deploy-pam-bashrc.sh

# Verify
grep "DS01:" /etc/bash.bashrc
grep "pam-ensure-bashrc" /etc/pam.d/common-session
```

## Files

### Source Files (Git-tracked)

```
config/etc-mirrors/
├── bash.bashrc              → /etc/bash.bashrc
├── profile.d/ds01-path.sh   → /etc/profile.d/ds01-path.sh
└── skel/.bashrc             → /etc/skel/.bashrc

scripts/system/
├── pam-ensure-bashrc.sh           (PAM session script)
├── deploy-bash-bashrc.sh          (Deploy /etc/bash.bashrc)
├── deploy-pam-bashrc.sh           (Deploy PAM automation)
└── deploy-automated-path.sh       (Master deployment script)

scripts/user/
└── shell-setup                    (Manual fallback command)
```

### Deployed Files

```
/etc/bash.bashrc                            (Layer 1: System-wide)
/etc/profile.d/ds01-path.sh                 (Layer 3: Login shells)
/etc/skel/.bashrc                           (Layer 4: New users)
/usr/local/bin/pam-ensure-bashrc.sh         (Layer 2: PAM script)
/etc/pam.d/common-session                   (Layer 2: PAM config)
/usr/local/bin/shell-setup                  (Layer 5: Manual fallback)
```

## How It Works

### Scenario 1: h.baker logs in via SSH (first time)

1. **SSH creates interactive shell** (non-login)
2. **Bash sources `/etc/bash.bashrc`** → PATH includes `/usr/local/bin` ✓
3. **PAM hook runs** → creates `~/.bashrc` from `/etc/skel/` ✓
4. **Next shell** → Sources `~/.bashrc` with DS01 PATH ✓

**Result:** Commands work immediately in current session, and persist in future sessions.

### Scenario 2: New user account created

1. **`useradd -m newuser`** or **`pam_mkhomedir` creates home**
2. **Copies `/etc/skel/.bashrc`** → includes DS01 PATH config ✓
3. **User logs in** → interactive shell sources `/etc/bash.bashrc` ✓
4. **User's shell** → sources `~/.bashrc` with DS01 PATH ✓

**Result:** Works from first login, no manual steps needed.

### Scenario 3: Existing user (already logged in)

1. **Current shell** → doesn't have PATH (old session)
2. **User types `bash`** → new shell sources `/etc/bash.bashrc` ✓
3. **Commands work** → immediately in new shell ✓

**Result:** One command (`bash`) gives immediate access.

## Coverage Matrix

| Login Type | /etc/bash.bashrc | /etc/profile.d/ | ~/.bashrc | Result |
|------------|------------------|-----------------|-----------|--------|
| SSH (non-login) | ✓ | ✗ | ✓ (PAM) | ✓ Works |
| SSH (login) | ✓ | ✓ | ✓ (PAM) | ✓ Works |
| Console login | ✓ | ✓ | ✓ (PAM) | ✓ Works |
| docker exec | ✓ | ✗ | ✓ (existing) | ✓ Works |
| su (no -) | ✓ | ✗ | ✓ (existing) | ✓ Works |
| su - | ✓ | ✓ | ✓ (existing) | ✓ Works |
| bash (new) | ✓ | ✗ | ✓ (existing) | ✓ Works |

**Conclusion:** 100% coverage across all shell types.

## Testing

### Test 1: Verify /etc/bash.bashrc

```bash
# Check deployed
grep "DS01: Ensure /usr/local/bin" /etc/bash.bashrc

# Test in new shell
bash -c 'echo $PATH | grep /usr/local/bin'
# Expected: /usr/local/bin found
```

### Test 2: Verify PAM Hook

```bash
# Check PAM config
grep "pam-ensure-bashrc" /etc/pam.d/common-session

# Check script exists
ls -l /usr/local/bin/pam-ensure-bashrc.sh

# Test (simulate login for test user)
sudo -u testuser /usr/local/bin/pam-ensure-bashrc.sh
ls -l /home/testuser/.bashrc
# Expected: .bashrc created if didn't exist
```

### Test 3: End-to-End (as h.baker)

```bash
# h.baker logs in via SSH
ssh h.baker@ds01

# Check PATH
echo $PATH | grep /usr/local/bin
# Expected: found

# Test command
container-list
# Expected: works

# Check .bashrc created
ls -l ~/.bashrc
# Expected: exists
```

## Rollback

```bash
# Restore bash.bashrc
sudo cp /etc/bash.bashrc.backup-ds01 /etc/bash.bashrc

# Remove PAM hook
sudo cp /etc/pam.d/common-session.backup-ds01 /etc/pam.d/common-session
sudo rm /usr/local/bin/pam-ensure-bashrc.sh
```

## Maintenance

### When Ubuntu Updates /etc/bash.bashrc

1. Copy new system version: `cp /etc/bash.bashrc /opt/ds01-infra/config/etc-mirrors/bash.bashrc`
2. Add DS01 PATH section (see mirror file for example)
3. Redeploy: `sudo /opt/ds01-infra/scripts/system/deploy-bash-bashrc.sh`

### When Ubuntu Updates /etc/skel/.bashrc

1. Copy new system version: `cp /etc/skel/.bashrc /opt/ds01-infra/config/etc-mirrors/skel/.bashrc`
2. Add DS01 PATH section (see mirror file for example)
3. Redeploy: `sudo cp /opt/ds01-infra/config/etc-mirrors/skel/.bashrc /etc/skel/.bashrc`

## Troubleshooting

**Symptom:** User still can't find commands

**Diagnosis:**
```bash
# Check which layer failed
echo $PATH | grep /usr/local/bin  # Check current shell
grep "DS01" /etc/bash.bashrc      # Check Layer 1
grep "DS01" ~/.bashrc             # Check Layer 4
cat /etc/pam.d/common-session     # Check Layer 2
```

**Fix:**
```bash
# Immediate: Start new shell
bash

# Persistent: Run shell-setup
/opt/ds01-infra/scripts/user/shell-setup
source ~/.bashrc
```

## Security Notes

- PAM script runs as root but only creates files owned by the user
- No secrets or credentials involved
- Only modifies user's .bashrc if missing
- Idempotent: safe to run multiple times
- Uses `pam_exec.so` with `seteuid` to run as user for file creation

## References

- `/etc/bash.bashrc` - System-wide bashrc for interactive shells
- `/etc/pam.d/common-session` - PAM session configuration
- `man pam_exec` - PAM exec module documentation
- `man bash` - Bash startup files
