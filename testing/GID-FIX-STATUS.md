# GID Mapping Fix - Status Update

**Date:** 2025-11-24
**Status:** ✅ **FIXED AND VERIFIED**

## Summary

The GID mapping issue ("I have no name!" and "cannot find name for group ID") **has been fixed** and is working correctly in the current codebase.

## What Was Fixed

- **Commit:** `a92a6e6` - "Fix GID mapping issue - robust user/group creation"
- **Date:** 2025-11-24
- **Location:** `scripts/docker/mlc-patched.py` lines 1417-1446

The fix implements a robust 6-step user/group creation process that:
1. Removes conflicting groups
2. Creates the group with the correct GID
3. Removes conflicting users
4. Creates the user with the correct UID/GID
5. Verifies creation succeeded
6. Configures user permissions

## Verification

All tests pass successfully:

```bash
cd /opt/ds01-infra/testing
./quick-test-gid-fix.sh
```

**Results:**
```
✓ Test 1 - No 'I have no name!' error
✓ Test 2 - No 'cannot find name for group ID' error
✓ Test 3 - whoami returns correct username
✓ Test 4 - /etc/passwd has user entry
✓ Test 5 - /etc/group has group entry

✓ ALL TESTS PASSED!
```

## What You Need To Do

### If You're Seeing the Issue

The error you saw was from a container created **before** the fix was applied (before commit `a92a6e6`). To resolve:

**Option 1: Recreate the container (Recommended)**

```bash
# Your workspace files are safe - they persist in ~/workspace/
container-stop <container-name>
container-remove <container-name>
container-create <container-name> <framework>
```

**Option 2: Use the runtime fix script (Temporary)**

```bash
cd /opt/ds01-infra/testing
./fix-gid-issue.sh <container-name>
```

⚠️ **Note:** The runtime fix only affects the running container. If you recreate it, you'll need to apply it again. With the current fix in `mlc-patched.py`, new containers won't have this issue.

### For New Containers

All **new** containers created with the current codebase will work correctly without any issues. The fix is automatically applied during container creation.

## Test Scripts Updated

The test scripts have been updated to use DS01 commands instead of raw AIME commands:

- `testing/quick-test-gid-fix.sh` - Uses `container-create` instead of `mlc-create -s`
- `testing/test-gid-fix.sh` - Uses `container-create` instead of `mlc-create -s`

Both scripts now work correctly with the DS01 infrastructure.

## Technical Details

### How the Fix Works

During container creation (`mlc-patched.py`):

1. **Conflict Resolution:** Checks for existing users/groups with the same UID/GID and removes them if they have different names
2. **Dual Command Support:** Uses both Debian (`adduser`/`addgroup`) and RHEL (`useradd`/`groupadd`) commands for compatibility
3. **Verification:** Confirms that both `/etc/passwd` and `/etc/group` entries were created successfully
4. **Error Visibility:** Errors are no longer silently swallowed - you'll see "User setup: FAILED" if something goes wrong

### Why This Issue Occurred

Docker containers run with `--user UID:GID` to match the host user, but the container's `/etc/passwd` and `/etc/group` files need entries for those IDs for proper username/group name resolution.

Before the fix:
- User/group creation commands silently failed
- Conflicts with base image users/groups were not handled
- No verification that entries were created

After the fix:
- Conflicts are detected and resolved
- Fallback commands ensure compatibility
- Creation is verified before proceeding

## Related Documentation

- Full technical details: `/opt/ds01-infra/testing/GID-MAPPING-FIX.md`
- Quick test: `/opt/ds01-infra/testing/quick-test-gid-fix.sh`
- Comprehensive test: `/opt/ds01-infra/testing/test-gid-fix.sh`
- Diagnostic tool: `/opt/ds01-infra/testing/diagnose-gid-issue.sh`
- Runtime fix: `/opt/ds01-infra/testing/fix-gid-issue.sh`

## Conclusion

✅ The GID mapping fix is **working correctly**
✅ All test scripts have been **updated and verified**
✅ New containers will **not experience this issue**
⚠️ Old containers created before the fix should be **recreated**
