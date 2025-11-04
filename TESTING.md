# Testing Guide for DS01 CLI Commands

## Quick Test Commands

### 1. Test Dispatcher Scripts Directly (No sudo needed)

```bash
# Test main dispatchers
/opt/ds01-infra/scripts/user/container-dispatcher.sh help
/opt/ds01-infra/scripts/user/image-dispatcher.sh help
/opt/ds01-infra/scripts/user/project-dispatcher.sh help

# Test individual user commands
/opt/ds01-infra/scripts/user/container-list
/opt/ds01-infra/scripts/user/image-list
/opt/ds01-infra/scripts/user/ssh-config --help
```

### 2. Test Admin Commands

```bash
# Admin dashboard and tools
/opt/ds01-infra/scripts/admin/ds01-dashboard
/opt/ds01-infra/scripts/admin/ds01-logs --help
/opt/ds01-infra/scripts/admin/ds01-users --help
/opt/ds01-infra/scripts/admin/alias-list
/opt/ds01-infra/scripts/admin/help
/opt/ds01-infra/scripts/admin/version
```

### 3. Install Symlinks (Requires sudo)

```bash
# Create all symlinks in /usr/local/bin
sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh

# Then test with clean command names
container help
image help
project help
ds01-dashboard
alias-list
help
version
```

### 4. Check Color Formatting

All help screens should show:
- ✅ Cyan separator lines (━━━) at top and bottom
- ✅ Bold titles
- ✅ Green subcommands
- ✅ Cyan example commands
- ✅ Yellow tips

```bash
# Test a few to verify colors work
container help
ds01-logs --help
alias-create --help
```

### 5. Test Both Command Forms

After installing symlinks:

```bash
# Noun-verb form (space)
container list
image list
project init --help

# Hyphenated form
container-list
image-list
project-init --help
```

Both should work identically!

## Comprehensive Test Script

```bash
#!/bin/bash
# Run all tests

echo "=== Testing Dispatcher Scripts ==="
for cmd in container image project; do
    echo "Testing ${cmd}-dispatcher.sh..."
    /opt/ds01-infra/scripts/user/${cmd}-dispatcher.sh help | head -5
    echo ""
done

echo "=== Testing Admin Commands ==="
for cmd in ds01-dashboard ds01-logs ds01-users alias-list help version; do
    echo "Testing ${cmd}..."
    /opt/ds01-infra/scripts/admin/${cmd} --help 2>&1 | head -5
    echo ""
done

echo "=== Testing User Subcommands ==="
/opt/ds01-infra/scripts/user/container-list --help 2>&1 | head -3
/opt/ds01-infra/scripts/user/image-list --help 2>&1 | head -3
/opt/ds01-infra/scripts/user/ssh-config --help 2>&1 | head -3

echo ""
echo "✓ All tests complete!"
```

## File Permissions Check

```bash
# Verify all scripts are executable and readable by all users
ls -la /opt/ds01-infra/scripts/user/ | grep "rwxr-xr-x"
ls -la /opt/ds01-infra/scripts/admin/ | grep "rwxr-xr-x"
```

Should show `755` permissions (rwxr-xr-x).

## Symlink Verification

```bash
# Check if symlinks exist
ls -la /usr/local/bin/ | grep ds01-infra

# Test a symlinked command
which container
which ds01-dashboard

# Follow the symlink
readlink -f /usr/local/bin/container
# Should show: /opt/ds01-infra/scripts/user/container-dispatcher.sh
```

## Test as Different User

```bash
# Switch to another user (if available)
sudo -u testuser /opt/ds01-infra/scripts/user/container-dispatcher.sh help

# Or test permissions
ls -l /opt/ds01-infra/scripts/user/container-dispatcher.sh
# Should show: -rwxr-xr-x (755)
```

## Expected Results

### ✅ Working Correctly:
- Help screens show colored output (not escape codes like `\033[1m`)
- Separator lines display as cyan bars (━━━)
- Commands work from any directory
- Both `container list` and `container-list` work
- All users can execute scripts (not just owner)

### ❌ Issues to Watch For:
- Permission denied errors → Files need 755 permissions
- Command not found → Symlinks not created or PATH issue
- Literal escape codes shown → Using heredocs instead of echo -e
- Docker permission errors → User needs to be in docker group

## Troubleshooting

### If colors don't work:
```bash
# Check if echo -e is being used
grep -n "echo -e" /opt/ds01-infra/scripts/user/container-dispatcher.sh
# Should see multiple lines with echo -e
```

### If commands aren't accessible:
```bash
# Check permissions
stat -c "%a %n" /opt/ds01-infra/scripts/user/container-dispatcher.sh
# Should show: 755

# Check if you can execute
/opt/ds01-infra/scripts/user/container-dispatcher.sh help
```

### If symlinks don't work:
```bash
# Recreate symlinks
sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh

# Verify symlink creation
ls -la /usr/local/bin/container
```

## Quick One-Liner Tests

```bash
# Test all dispatchers at once
for cmd in container image project; do /opt/ds01-infra/scripts/user/${cmd}-dispatcher.sh help 2>&1 | head -8; echo "---"; done

# Test all admin commands at once
for cmd in ds01-dashboard ds01-logs ds01-users alias-list help version alias-create; do echo "=== $cmd ==="; /opt/ds01-infra/scripts/admin/$cmd --help 2>&1 | head -5; echo ""; done

# Count total user-accessible commands
ls -1 /opt/ds01-infra/scripts/user/ | wc -l
ls -1 /opt/ds01-infra/scripts/admin/ | wc -l
```

## Full Integration Test

```bash
# Run through a typical user workflow
echo "1. View available commands"
/opt/ds01-infra/scripts/admin/alias-list | head -20

echo "2. Get help"
/opt/ds01-infra/scripts/admin/help # Press 0 to exit

echo "3. Check version"
/opt/ds01-infra/scripts/admin/version

echo "4. List containers"
/opt/ds01-infra/scripts/user/container-list

echo "5. List images"
/opt/ds01-infra/scripts/user/image-list

echo "6. Admin dashboard"
/opt/ds01-infra/scripts/admin/ds01-dashboard

echo "✓ Integration test complete!"
```
