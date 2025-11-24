# GID Mapping Fix Documentation

## Issue Description

When opening containers, users encountered the following errors:
```
groups: cannot find name for group ID 1019
I have no name!@ds01:/workspace$
```

This occurred because the user and group entries were not properly created in `/etc/passwd` and `/etc/group` during container creation.

## Root Cause

The issue was in `scripts/docker/mlc-patched.py` in the `build_docker_run_command()` function (around line 1417). The bash commands that create users and groups during container setup were:

1. **Silently failing** - Errors were redirected to `/dev/null`
2. **Not handling conflicts** - If a user/group with the same UID/GID already existed in the base image, `adduser`/`addgroup` would fail
3. **Not verifying** - No check to confirm the user/group were actually created

## The Fix

### Location
`scripts/docker/mlc-patched.py` lines 1417-1446

### Changes Made

The fix implements a **6-step robust user/group creation process**:

**Step 1**: Remove conflicting groups
- Check if a group with the target GID already exists
- If it exists and has a different name, delete it
- Prevents "GID already in use" errors

**Step 2**: Create the group
- Try `addgroup` (Debian/Ubuntu)
- Fallback to `groupadd` (RHEL/CentOS)
- Only create if it doesn't already exist

**Step 3**: Remove conflicting users
- Check if a user with the target UID already exists
- If it exists and has a different name, delete it
- Prevents "UID already in use" errors

**Step 4**: Create the user
- Try `adduser` (Debian/Ubuntu) with proper flags
- Fallback to `useradd` (RHEL/CentOS)
- Only create if it doesn't already exist

**Step 5**: Verify creation
- Check that both user and group entries exist
- Print "User setup: OK" or "User setup: FAILED"
- Provides visibility into setup process

**Step 6**: Configure user
- Remove password (passwordless user)
- Add to sudo group
- Create sudoers entry for NOPASSWD access

### Key Improvements

1. **Idempotent** - Safe to run multiple times
2. **Defensive** - Handles existing users/groups gracefully
3. **Visible** - Errors are no longer silently swallowed
4. **Verified** - Confirms user/group were actually created
5. **Compatible** - Works with both Debian and RHEL-based images

## Testing

### Quick Test (2 minutes)

Run the quick validation script on the DS01 server:

```bash
cd /opt/ds01-infra/testing
./quick-test-gid-fix.sh
```

This will:
1. Create a test container
2. Check for "I have no name!" errors
3. Check for "cannot find name for group ID" errors
4. Verify whoami, /etc/passwd, and /etc/group entries
5. Clean up automatically

**Expected output:**
```
✓ ALL TESTS PASSED!

The GID mapping fix is working correctly.
No 'I have no name!' or 'cannot find name' errors detected.
```

### Comprehensive Test (5 minutes)

For thorough validation, run the full test suite:

```bash
cd /opt/ds01-infra/testing
./test-gid-fix.sh
```

This runs 15 tests including:
- Container creation and startup
- User/group entry verification
- Command execution (id, whoami, groups)
- Interactive shell simulation
- Write permissions
- Container stop/restart
- Committed image verification

**Expected output:**
```
Passed: 15
Failed: 0

✓ ALL TESTS PASSED!
```

### Manual Testing

Test with a real container:

```bash
# Create a new container
container-create my-test-project

# Start and enter the container
container-run my-test-project

# Inside container - these should all work without errors:
whoami        # Should show your username, not "I have no name!"
id            # Should show your UID and GID with names
groups        # Should NOT show "cannot find name for group ID"
echo $USER    # Should show your username

# Exit
exit
```

## Diagnosing Issues

If you encounter problems, use the diagnostic script:

```bash
cd /opt/ds01-infra/testing
./diagnose-gid-issue.sh <container-name>
```

This will show:
- Host user information
- Container /etc/passwd entries
- Container /etc/group entries
- What the container sees when running commands
- Docker configuration
- Committed image status

## Fixing Existing Containers

For containers created **before** this fix, you have two options:

### Option 1: Recreate the container (recommended)

```bash
# Your workspace files are safe - they persist in ~/workspace/
container-remove old-container
container-create old-container <framework>
```

### Option 2: Apply runtime fix (temporary)

```bash
cd /opt/ds01-infra/testing
./fix-gid-issue.sh <container-name>
```

**Note:** This option is temporary and only affects the running container instance. If you recreate the container, you'll need to apply it again (or use the new mlc-patched.py which has the permanent fix).

## Verification Checklist

After deploying the fix, verify:

- [ ] `mlc-patched.py` has the updated `build_docker_run_command()` function
- [ ] Quick test passes: `./quick-test-gid-fix.sh`
- [ ] Create a new container and verify no "I have no name!" error
- [ ] Existing containers can be fixed with `./fix-gid-issue.sh` if needed
- [ ] Users can run `whoami`, `id`, and `groups` without errors

## Technical Details

### Why This Issue Occurred

Docker containers run with `--user UID:GID` to match the host user. However, the container's `/etc/passwd` and `/etc/group` files need entries for those IDs for proper username/group name resolution.

The container creation process:
1. `docker run` - Runs as root, executes user creation bash commands
2. `docker commit` - Saves container state (including /etc/passwd and /etc/group)
3. `docker create` - Creates final container from committed image
4. Container runs with `--user UID:GID` and uses the /etc/passwd from step 2

If step 1 fails to create the user/group, steps 3-4 will show "I have no name!"

### Base Image Considerations

Some base images (Ubuntu, PyTorch official images) have pre-existing system users/groups that might conflict with host UIDs/GIDs. The fix handles this by detecting and removing conflicts before creating the new user/group.

## Related Files

- `scripts/docker/mlc-patched.py` - Main fix location
- `scripts/docker/container-init.sh` - Runtime initialization (not currently used)
- `scripts/docker/container-entrypoint.sh` - Runtime entrypoint (not currently used)
- `testing/diagnose-gid-issue.sh` - Diagnostic tool
- `testing/fix-gid-issue.sh` - Runtime fix for existing containers
- `testing/quick-test-gid-fix.sh` - Quick validation test
- `testing/test-gid-fix.sh` - Comprehensive test suite

## Support

If issues persist after applying the fix:

1. Run the diagnostic script and save the output
2. Check the mlc-create output for "User setup: FAILED" messages
3. Verify the base image being used (some images may have special restrictions)
4. Check if the user's UID/GID conflicts with system reserved ranges (typically < 1000)

## Changelog

**2025-11-24** - Initial fix implemented
- Robust user/group creation with conflict resolution
- Verification and error reporting
- Fallback to both Debian and RHEL commands
- Comprehensive test suite created
