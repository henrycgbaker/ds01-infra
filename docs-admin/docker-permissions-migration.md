# Docker Permissions Migration: Socket Proxy → OPA + Wrapper

**Date**: 2025-12-04
**Status**: Partially Complete (Parked)
**Plan file**: `~/.claude/plans/tidy-rolling-twilight.md`

## Summary

Migrated from an unstable custom Python socket proxy to a simpler approach using:
- **Wrapper script** for visibility filtering (working)
- **OPA authorization plugin** for operation blocking (disabled - needs more work)

## What Was Done

### 1. Removed Socket Proxy ✅

**Problem**: Custom Python socket proxy (`docker-filter-proxy.py`) was:
- 500+ lines of complex HTTP/gRPC handling
- Unstable (crashes, connection resets)
- Hard to debug (threading issues)

**Actions taken**:
```bash
# Stopped and disabled the service
sudo systemctl stop ds01-docker-filter
sudo systemctl disable ds01-docker-filter

# Deleted proxy files
rm /opt/ds01-infra/scripts/docker/docker-filter-proxy.py
rm /opt/ds01-infra/scripts/docker/docker-socket-proxy.py

# Removed the socket redirect
sudo rm /etc/systemd/system/docker.service.d/ds01-socket.conf
```

### 2. Fixed Docker Configuration ✅

**Problem**: Docker was configured to use `docker-real.sock` for the proxy.

**Actions taken**:
- Updated `/etc/docker/daemon.json` to use standard `docker.sock`
- Created systemd drop-in to prevent `hosts` conflict with socket activation

**Current daemon.json**:
```json
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    },
    "exec-opts": ["native.cgroupdriver=systemd"],
    "cgroup-parent": "ds01.slice",
    "hosts": ["unix:///var/run/docker.sock"]
}
```

**Systemd drop-in** (`/etc/systemd/system/docker.service.d/ds01-override.conf`):
```ini
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
```

### 3. Enhanced Docker Wrapper ✅

**File**: `/opt/ds01-infra/scripts/docker/docker-wrapper.sh`
**Deployed to**: `/usr/local/bin/docker`

**Added visibility filtering**:
- `docker ps` and `docker container ls` now filter by `ds01.user` label
- Admins (`ds01-admin` group) see all containers
- Non-admins only see their own containers

**Key code added**:
```bash
# Check if user is an admin (ds01-admin group)
is_admin() {
    groups "$CURRENT_USER" 2>/dev/null | grep -qE '\bds01-admin\b'
}

# Filter docker ps/container ls to show only user's containers (non-admins)
filter_container_list() {
    if is_admin; then
        exec "$REAL_DOCKER" "$@"
    fi
    exec "$REAL_DOCKER" "$@" --filter "label=ds01.user=$CURRENT_USER"
}
```

### 4. Installed OPA Authorization (Partially) ⚠️

**Installed**:
- Go 1.21.5 at `/usr/local/go/bin`
- OPA Docker authz plugin at `/usr/local/bin/opa-docker-authz`
- Policy file at `/opt/ds01-infra/config/opa/docker-authz.rego`
- Systemd service at `/etc/systemd/system/opa-docker-authz.service`

**Current state**: Disabled (service stopped, not in daemon.json)

## What We Found

### 1. Docker Socket + daemon.json Conflict

When `hosts` is specified in `daemon.json`, Docker's default systemd socket activation (`-H fd://`) conflicts with it. Solution: Use a systemd drop-in to override `ExecStart` and remove the `-H fd://` flag.

### 2. OPA Plugin Circular Dependency

The initial OPA service had:
```ini
After=docker.service
Requires=docker.service
```

But Docker requires OPA to start first (authorization plugin). Fixed by changing to:
```ini
Before=docker.service
```

### 3. OPA Plugin Doesn't Support External Data Files

**Critical finding**: The `opa-docker-authz` plugin does NOT support the `-data-file` flag.

The policy at `/opt/ds01-infra/config/opa/docker-authz.rego` expects external data:
```rego
# Loaded from /var/lib/ds01/opa/container-owners.json
container_owner := owner if {
    owner := data.containers[container_id].owner
}
```

But the plugin only supports:
- `-policy-file` - Load policy
- `-quiet` - Disable logging
- `-skip-ping` - Skip ping endpoint
- `-version` - Print version

**No way to load container ownership data** without:
1. OPA bundle server
2. Embedding data in policy
3. Using full OPA server instead of the authz plugin

### 4. Docker Socket User Authentication

The OPA policy uses `input.User` to identify the requesting user. This comes from Docker socket authentication, which may not reliably pass the Unix username for all connection methods.

## Current State

| Component | Status | Notes |
|-----------|--------|-------|
| Docker | ✅ Running | Standard socket at `/var/run/docker.sock` |
| Socket Proxy | ❌ Removed | Files deleted, service disabled |
| Wrapper | ✅ Active | Visibility filtering works |
| OPA Plugin | ⚠️ Installed but disabled | Needs data loading solution |
| Go 1.21.5 | ✅ Installed | At `/usr/local/go/bin` |

### What Works

1. **Visibility filtering**: Non-admin users only see their own containers in `docker ps`
2. **Admin bypass**: Admins see all containers
3. **Cgroup enforcement**: Wrapper injects `--cgroup-parent` for resource limits
4. **Owner labeling**: Wrapper injects `ds01.user` label on container creation

### What Doesn't Work

1. **Exec blocking**: Users CAN exec into other users' containers if they know the name
2. **Stop/kill blocking**: Users CAN stop other users' containers
3. **Logs blocking**: Users CAN view other users' container logs

## Limitations

### Security Gap

Without OPA blocking, the system relies on "security through obscurity":
- Users can't easily **discover** other containers (visibility filtering)
- But if they **know** a container name, they can interact with it

### Wrapper Limitations

- Only affects CLI users
- VS Code Dev Containers extension sees all containers in sidebar
- Docker Compose sees all containers
- Any tool using Docker socket directly bypasses wrapper

## Files Created/Modified

### Created
- `/opt/ds01-infra/config/systemd/opa-docker-authz.service`
- `/opt/ds01-infra/config/docker/daemon.json`
- `/opt/ds01-infra/docs-user/docker-permissions-migration.md` (this file)

### Modified
- `/opt/ds01-infra/scripts/docker/docker-wrapper.sh` - Added visibility filtering
- `/etc/docker/daemon.json` - Removed proxy socket, removed OPA plugin
- `/etc/systemd/system/docker.service.d/ds01-override.conf` - Drop-in for ExecStart

### Deleted
- `/opt/ds01-infra/scripts/docker/docker-filter-proxy.py`
- `/opt/ds01-infra/scripts/docker/docker-socket-proxy.py`

## To Resume: OPA Blocking

To complete OPA-based operation blocking, investigate these options:

### Option 1: OPA Bundle Server
Run a separate OPA server that serves bundles containing both policy and data.

```bash
# Start OPA as a server
opa run --server --addr :8181 \
    /opt/ds01-infra/config/opa/docker-authz.rego \
    /var/lib/ds01/opa/container-owners.json

# Configure authz plugin to query OPA server
opa-docker-authz -opa-url http://localhost:8181
```

### Option 2: Embed Data in Policy
Modify policy to query Docker directly for container labels instead of external data file.

### Option 3: Use Docker's Built-in User Namespace
Docker's user namespace remapping provides stronger isolation than authorization plugins.

### Option 4: Different Authorization Plugin
Investigate other Docker authorization plugins that support external data.

## Rollback Instructions

If issues occur, restore the simple state:

```bash
# Ensure wrapper is deployed
sudo cp /opt/ds01-infra/scripts/docker/docker-wrapper.sh /usr/local/bin/docker
sudo chmod +x /usr/local/bin/docker

# Ensure clean daemon.json (no authorization plugins)
sudo cp /opt/ds01-infra/config/docker/daemon.json /etc/docker/daemon.json

# Ensure OPA is stopped
sudo systemctl stop opa-docker-authz
sudo systemctl disable opa-docker-authz

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Technical Learnings

### 1. Docker Daemon Configuration Conflicts

**Learning**: Docker's `hosts` directive in `daemon.json` conflicts with systemd socket activation.

**Details**:
- Default Docker systemd unit uses `-H fd://` for socket activation
- If `daemon.json` also specifies `hosts`, Docker fails with:
  ```
  the following directives are specified both as a flag and in the configuration file: hosts
  ```

**Solution**: Create a systemd drop-in that clears and redefines `ExecStart`:
```ini
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
```

The empty `ExecStart=` clears the default, then the second line sets the new command without `-H fd://`.

### 2. Systemd Service Dependencies for Docker Plugins

**Learning**: Authorization plugins must start BEFORE Docker, not after.

**Wrong**:
```ini
[Unit]
After=docker.service
Requires=docker.service
```

**Correct**:
```ini
[Unit]
Before=docker.service

[Install]
RequiredBy=docker.service
```

### 3. OPA Docker Authz Plugin Limitations

**Learning**: The `opa-docker-authz` plugin is minimal and doesn't support external data files.

**What the plugin supports**:
```
-policy-file string    # Load Rego policy
-quiet                 # Disable request logging
-skip-ping             # Skip /_ping evaluation
-version               # Print version
```

**What it doesn't support**:
- `-data-file` for external JSON data
- Bundle loading
- Remote OPA server queries (in simple mode)

**The policy expects**:
```rego
data.containers[container_id].owner  # From external JSON
data.admins[_]                        # Admin user list
```

But without data loading, `data.containers` is always empty, so `unknown_owner` is always true, and the policy allows everything.

### 4. Go Version Requirements

**Learning**: OPA requires Go 1.18+ to build. Ubuntu 20.04's apt package provides Go 1.13.

**Solution**: Install Go manually:
```bash
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH
```

**Important**: `sudo` uses a different PATH. When building with sudo:
```bash
sudo PATH=/usr/local/go/bin:$PATH /opt/ds01-infra/scripts/system/setup-opa-authz.sh
```

### 5. Docker Labels for Ownership Tracking

**Learning**: Container labels are the most reliable way to track ownership.

The wrapper injects:
```bash
--label ds01.user=$CURRENT_USER
--label ds01.managed=true
```

This works because:
- Labels persist with the container
- Labels are queryable via Docker API and CLI
- Labels work with `--filter` for visibility

### 6. Wrapper vs Authorization Plugin Trade-offs

| Aspect | Wrapper | Authorization Plugin |
|--------|---------|---------------------|
| Visibility filtering | ✅ Works | Not applicable |
| Operation blocking | ❌ No | ✅ Yes (if working) |
| CLI users | ✅ Affected | ✅ Affected |
| VS Code/other tools | ❌ Bypassed | ✅ Affected |
| Complexity | Low | High |
| Failure mode | Graceful | Docker won't start |

## What Needs Doing to Fix It

### Immediate (To Get OPA Blocking Working)

#### Option A: Use OPA Server Mode (Recommended)

1. **Run OPA as a standalone server** instead of using the authz plugin directly:

```bash
# Create OPA server service
cat > /etc/systemd/system/opa-server.service << 'EOF'
[Unit]
Description=OPA Policy Server
Before=docker.service

[Service]
ExecStart=/usr/local/bin/opa run --server --addr localhost:8181 \
    /opt/ds01-infra/config/opa/docker-authz.rego \
    /var/lib/ds01/opa/container-owners.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

2. **Configure authz plugin to query OPA server**:
```bash
# Update authz plugin to use OPA server
ExecStart=/usr/local/bin/opa-docker-authz -opa-url http://localhost:8181/v1/data/docker/authz/allow
```

3. **Set up data sync** to keep `container-owners.json` updated:
```bash
# Run sync on container events
docker events --filter type=container | while read event; do
    python3 /opt/ds01-infra/scripts/docker/sync-container-owners.py
done
```

#### Option B: Modify Policy to Query Docker Directly

Rewrite the policy to not depend on external data. Instead, make OPA query Docker for container labels at decision time.

**Challenges**:
- OPA can't make HTTP calls in Rego (without plugins)
- Would need custom OPA built-in function

#### Option C: Use Docker Socket Directly in Policy

The OPA authz plugin receives the full Docker API request. For some operations, container info is in the request body.

**Limitation**: For `exec`, the request is to `/containers/{id}/exec` but doesn't include container labels. Would need to look up container info.

### Medium-Term Improvements

1. **Systemd timer for container sync**:
```bash
# /etc/systemd/system/ds01-container-sync.timer
[Unit]
Description=Sync container owners every minute

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
```

2. **Docker event listener service** for real-time sync:
```bash
docker events --filter type=container --format '{{.Action}} {{.Actor.ID}}' | \
    while read action id; do
        /opt/ds01-infra/scripts/docker/sync-container-owners.py
    done
```

3. **Health check** for OPA + Docker integration:
```bash
# Add to ds01-health-check
check_opa_authz() {
    if docker info 2>/dev/null | grep -q "Authorization.*opa"; then
        curl -s http://localhost:8181/health && echo "OPA healthy"
    fi
}
```

### Testing Checklist (When Resuming)

```bash
# 1. Start OPA server
sudo systemctl start opa-server

# 2. Verify OPA is responding
curl http://localhost:8181/v1/data/docker/authz

# 3. Start authz plugin
sudo systemctl start opa-docker-authz

# 4. Restart Docker
sudo systemctl restart docker

# 5. Verify authorization is active
docker info | grep -i auth

# 6. Test as non-admin user
sudo -u testuser docker exec admin-test-container echo "should fail"

# 7. Check OPA logs for decisions
sudo journalctl -u opa-docker-authz -f
```

## References

- OPA Docker authz plugin: https://github.com/open-policy-agent/opa-docker-authz
- Docker authorization plugins: https://docs.docker.com/engine/extend/plugins_authorization/
- OPA documentation: https://www.openpolicyagent.org/docs/
- OPA server mode: https://www.openpolicyagent.org/docs/latest/deployments/
- Plan file: `~/.claude/plans/tidy-rolling-twilight.md`
