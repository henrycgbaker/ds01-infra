# Docker Permissions Testing

Test suite for DS01 container permission system.

## Overview

The Docker permission system ensures users can only see and interact with their own containers. This directory contains tests to validate the system works correctly.

## Test Script

### test-permissions.sh

Comprehensive test suite for container permissions.

**Usage:**
```bash
./test-permissions.sh
```

**Tests performed:**
1. Docker connectivity through proxy
2. Socket proxy is active (both sockets exist)
3. Container listing visibility
4. Ownership data file exists
5. Container access controls (for non-admins)
6. Service status checks

**Expected results by user type:**

| User Type | `docker ps -a` | Access other's container |
|-----------|----------------|--------------------------|
| Admin (ds01-admin) | All containers | Allowed |
| Regular user | Own containers only | "Permission denied: container owned by \<owner\>" |

## Manual Testing

### As Admin

```bash
# Should see all containers
docker ps -a

# Should have full access to any container
docker exec <any-container> echo "test"
docker logs <any-container>
```

### As Regular User

```bash
# Should only see own containers (may be empty)
docker ps -a

# Should be denied access to others' containers
docker exec <other-user-container> echo "test"
# Expected: "Permission denied: container owned by <owner>"

# Should work on own container
docker exec <own-container> echo "test"
```

## Checking Current State

```bash
# View ownership data
cat /var/lib/ds01/opa/container-owners.json | python3 -m json.tool

# Check who are admins
getent group ds01-admin

# Check service status
systemctl status ds01-docker-filter
systemctl status ds01-container-sync
```

## Troubleshooting

### Permissions not working

1. Check services are running:
   ```bash
   systemctl status ds01-docker-filter
   systemctl status ds01-container-sync
   ```

2. Check ownership data is being synced:
   ```bash
   cat /var/lib/ds01/opa/container-owners.json
   ```

3. Check sockets exist:
   ```bash
   ls -la /var/run/docker*.sock
   ```

### Performance issues

If `docker ps` is slow, restart the filter proxy:
```bash
sudo systemctl restart ds01-docker-filter
```

### User should be admin but isn't

Add user to ds01-admin group:
```bash
sudo usermod -aG ds01-admin <username>
# User needs to log out and back in
```

Or add to `config/resource-limits.yaml`:
```yaml
groups:
  admin:
    members: [username1, username2]
```

## Related Documentation

- [scripts/docker/README.md](../../scripts/docker/README.md) - Container permissions system
- [scripts/system/README.md](../../scripts/system/README.md) - Setup script documentation
