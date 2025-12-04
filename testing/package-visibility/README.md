# Package Visibility Tests

Tests to verify that packages installed in Docker images are visible in containers,
and that users can install packages with `pip install --user`.

## Background

SSSD/LDAP users reported:
1. Packages installed in images not appearing in containers
2. Permission errors: `OSError: [Errno 13] Permission denied: '/.local'`
3. "I have no name!" GID mapping issues

## Root Cause

The root cause was in `mlc-patched.py` where the home directory path used the
**original** username (e.g., `h.baker@hertie-school.lan`) instead of the
**sanitized** username (e.g., `h-baker-at-hertie-school-lan`).

This caused:
- PATH pointing to non-existent directory
- HOME not properly set
- `.local` directory not created with correct ownership

## Fix Location

File: `/opt/ds01-infra/scripts/docker/mlc-patched.py`

Changes:
1. Line ~2094: Use sanitized username for `dir_to_be_added`
2. Line ~1440: Add `HOME` export to bashrc
3. Line ~1493: Create `.local` directory with correct ownership

## Test Scripts

### test-package-fix.sh

Tests the basic package visibility fix for local users.

```bash
./test-package-fix.sh [--no-cleanup] [--verbose]
```

**Tests:**
1. Container creation with correct user setup
2. User identity (no "I have no name!")
3. HOME environment variable set correctly
4. `.local` directory exists and is writable
5. `pip install --user` works
6. PATH in bashrc includes `.local/bin`

### test-ldap-username-fix.sh

Tests that the fix works correctly with LDAP/SSSD-style usernames containing `@` and `.`.

```bash
./test-ldap-username-fix.sh [--no-cleanup]
```

**Tests:**
1. Username sanitization for various LDAP patterns
2. Container creation with sanitized username
3. No "I have no name!" error
4. HOME points to correct sanitized path
5. `pip install --user` works
6. `.local` path is valid

## Manual Validation (for SSSD Users)

After the fix is deployed, SSSD users can validate with:

```bash
# 1. Create a test image with a specific package
image-create test-fix-validation -f pytorch -t ml -p "pytorch-lightning"

# 2. Deploy container
container-deploy test-fix-validation

# 3. Inside container, verify GID mapping (no "I have no name!")
whoami                    # Should show sanitized username
id                        # Should show UID and GID with names
groups                    # Should NOT show "cannot find name"

# 4. Verify packages work
python -c "import pytorch_lightning; print('SUCCESS:', pytorch_lightning.__version__)"

# 5. Verify pip install --user works
pip install --user colorama
python -c "import colorama; print('SUCCESS: colorama installed')"

# 6. Verify HOME and PATH
echo "HOME=$HOME"
ls -la ~/.local/bin/

# 7. Cleanup
exit
container-retire test-fix-validation --force
image-delete test-fix-validation
```

## For Existing Broken Containers

Containers created before the fix must be **recreated**:

```bash
container-retire broken-container --force
container-deploy broken-container
```

The ephemeral container model means recreation is the intended workflow.

## Related Documentation

- GID Fix: `/opt/ds01-infra/testing/GID-MAPPING-FIX.md`
- LDAP Username Support: `/opt/ds01-infra/testing/ldap-support/`
