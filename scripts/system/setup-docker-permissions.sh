#!/bin/bash
# /opt/ds01-infra/scripts/system/setup-docker-permissions.sh
# DS01 Docker Permissions Setup
#
# This script sets up the Docker permission system:
# 1. Creates ds01-admin group for admin users
# 2. Creates ds01-dashboard service user for dashboard access
# 3. Sets up container ownership sync service
# 4. Configures Docker to use a separate socket
# 5. Deploys the filter proxy for container visibility/authorization
#
# Usage: sudo ./setup-docker-permissions.sh [--dry-run] [--uninstall]
#
# Architecture:
#   Users/VS Code → /var/run/docker.sock (proxy) → /var/run/docker-real.sock (daemon)
#
# The proxy:
#   - Filters 'docker ps' to only show user's own containers
#   - Blocks operations (exec, logs, start, stop, etc.) on others' containers
#   - Allows admins full access

set -euo pipefail

# Configuration
INFRA_ROOT="/opt/ds01-infra"
OPA_DATA_DIR="/var/lib/ds01/opa"
OPA_DATA_FILE="$OPA_DATA_DIR/container-owners.json"
SYNC_SCRIPT="$INFRA_ROOT/scripts/docker/sync-container-owners.py"
FILTER_PROXY="$INFRA_ROOT/scripts/docker/docker-filter-proxy.py"
RESOURCE_LIMITS="$INFRA_ROOT/config/resource-limits.yaml"
REAL_DOCKER_SOCKET="/var/run/docker-real.sock"
PROXY_DOCKER_SOCKET="/var/run/docker.sock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $1"; }

# Parse arguments
DRY_RUN=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            ;;
        --uninstall)
            UNINSTALL=true
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--uninstall]"
            echo ""
            echo "Sets up DS01 Docker container permission system."
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --uninstall  Remove permission system components"
            echo ""
            echo "Components installed:"
            echo "  - ds01-admin Linux group"
            echo "  - ds01-dashboard service user"
            echo "  - Container ownership sync service"
            echo "  - Docker filter proxy"
            echo ""
            echo "Architecture:"
            echo "  Users → /var/run/docker.sock (proxy) → /var/run/docker-real.sock (daemon)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Must be root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# =============================================================================
# UNINSTALL
# =============================================================================

if [ "$UNINSTALL" = true ]; then
    log_info "Uninstalling DS01 Docker permissions..."

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN - No changes made"
        echo "Would:"
        echo "  - Stop and disable ds01-container-sync service"
        echo "  - Stop and disable ds01-docker-filter service"
        echo "  - Restore Docker socket configuration"
        echo "  - Restart Docker"
        exit 0
    fi

    # Stop services
    systemctl stop ds01-container-sync 2>/dev/null || true
    systemctl disable ds01-container-sync 2>/dev/null || true
    rm -f /etc/systemd/system/ds01-container-sync.service

    systemctl stop ds01-docker-filter 2>/dev/null || true
    systemctl disable ds01-docker-filter 2>/dev/null || true
    rm -f /etc/systemd/system/ds01-docker-filter.service

    systemctl daemon-reload

    # Restore Docker socket configuration
    if [ -f /etc/docker/daemon.json ]; then
        python3 << 'PYEOF'
import json
try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)

    # Remove the hosts configuration that uses the real socket
    if 'hosts' in config:
        config['hosts'] = [h for h in config['hosts'] if 'docker-real.sock' not in h]
        if not config['hosts']:
            del config['hosts']

    with open('/etc/docker/daemon.json', 'w') as f:
        json.dump(config, f, indent=4)

    print("Restored daemon.json")
except Exception as e:
    print(f"Warning: {e}")
PYEOF
    fi

    # Remove the real socket symlink/move if exists
    if [ -S "$REAL_DOCKER_SOCKET" ]; then
        rm -f "$REAL_DOCKER_SOCKET"
    fi

    # Restart Docker to restore normal operation
    systemctl restart docker || true

    log_success "Uninstall complete"
    log_info "Docker restored to default configuration"
    log_info "Note: ds01-dashboard user and ds01-admin group were preserved"
    exit 0
fi

# =============================================================================
# INSTALLATION
# =============================================================================

log_info "DS01 Docker Permissions Setup"
log_info "=============================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN - No changes will be made"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 1: Create ds01-admin group
# -----------------------------------------------------------------------------
log_step "1/5: Creating ds01-admin Linux group..."

if getent group ds01-admin &>/dev/null; then
    log_info "Group ds01-admin already exists"
else
    if [ "$DRY_RUN" = false ]; then
        groupadd ds01-admin
        log_success "Created group: ds01-admin"
    else
        echo "  Would create group: ds01-admin"
    fi
fi

# Add admin users from resource-limits.yaml to the group
if [ -f "$RESOURCE_LIMITS" ]; then
    ADMIN_MEMBERS=$(python3 << PYEOF
import yaml
try:
    with open('$RESOURCE_LIMITS') as f:
        config = yaml.safe_load(f)
    members = config.get('groups', {}).get('admin', {}).get('members', [])
    print(' '.join(members))
except:
    pass
PYEOF
)
    if [ -n "$ADMIN_MEMBERS" ]; then
        for user in $ADMIN_MEMBERS; do
            if id "$user" &>/dev/null; then
                if [ "$DRY_RUN" = false ]; then
                    usermod -aG ds01-admin "$user" 2>/dev/null || true
                    log_info "Added $user to ds01-admin group"
                else
                    echo "  Would add $user to ds01-admin group"
                fi
            fi
        done
    fi
fi

# -----------------------------------------------------------------------------
# Step 2: Create ds01-dashboard service user
# -----------------------------------------------------------------------------
log_step "2/5: Creating ds01-dashboard service user..."

if id ds01-dashboard &>/dev/null; then
    log_info "User ds01-dashboard already exists"
else
    if [ "$DRY_RUN" = false ]; then
        useradd --system --no-create-home --shell /usr/sbin/nologin ds01-dashboard
        log_success "Created user: ds01-dashboard"
    else
        echo "  Would create system user: ds01-dashboard"
    fi
fi

# Add to docker group (needed for socket access)
if [ "$DRY_RUN" = false ]; then
    usermod -aG docker ds01-dashboard 2>/dev/null || true
    # Also add to ds01-admin for full access
    usermod -aG ds01-admin ds01-dashboard 2>/dev/null || true
    log_info "Added ds01-dashboard to docker and ds01-admin groups"
else
    echo "  Would add ds01-dashboard to docker and ds01-admin groups"
fi

# -----------------------------------------------------------------------------
# Step 3: Set up container ownership sync
# -----------------------------------------------------------------------------
log_step "3/5: Setting up container ownership sync..."

if [ "$DRY_RUN" = false ]; then
    mkdir -p "$OPA_DATA_DIR"
    chmod 755 "$OPA_DATA_DIR"

    # Initial sync (uses current docker socket)
    python3 "$SYNC_SCRIPT" --once 2>/dev/null || log_warning "Initial sync skipped (will run after Docker configured)"
    log_success "Container ownership data directory ready"
else
    echo "  Would create $OPA_DATA_DIR"
fi

# Create sync service
SYNC_SERVICE="/etc/systemd/system/ds01-container-sync.service"

if [ "$DRY_RUN" = false ]; then
    cat > "$SYNC_SERVICE" << EOF
[Unit]
Description=DS01 Container Ownership Sync
After=docker.service
Requires=docker.service

[Service]
Type=simple
# Use the real Docker socket for queries
Environment=DOCKER_HOST=unix://$REAL_DOCKER_SOCKET
ExecStart=/usr/bin/python3 $SYNC_SCRIPT --watch --interval 5
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Container sync service configured"
else
    echo "  Would create systemd service: ds01-container-sync"
fi

# -----------------------------------------------------------------------------
# Step 4: Configure Docker daemon to use alternate socket
# -----------------------------------------------------------------------------
log_step "4/5: Configuring Docker daemon..."

if [ "$DRY_RUN" = false ]; then
    # Update daemon.json to listen on the real socket
    python3 << 'PYEOF'
import json
import sys

try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

# Configure Docker to listen on the real socket
# The proxy will listen on the standard socket path
real_socket = "unix:///var/run/docker-real.sock"

if 'hosts' not in config:
    config['hosts'] = []

if real_socket not in config['hosts']:
    # Remove any existing unix socket entries
    config['hosts'] = [h for h in config['hosts'] if not h.startswith('unix://')]
    config['hosts'].append(real_socket)

with open('/etc/docker/daemon.json', 'w') as f:
    json.dump(config, f, indent=4)

print("Configured Docker daemon for real socket")
PYEOF

    # Create systemd override to disable default socket
    mkdir -p /etc/systemd/system/docker.service.d/
    cat > /etc/systemd/system/docker.service.d/ds01-socket.conf << 'EOF'
[Service]
# Clear default socket and use our configured socket
ExecStart=
ExecStart=/usr/bin/dockerd
EOF

    systemctl daemon-reload
    log_success "Docker daemon configured"
else
    echo "  Would configure Docker to listen on $REAL_DOCKER_SOCKET"
fi

# -----------------------------------------------------------------------------
# Step 5: Create and start filter proxy
# -----------------------------------------------------------------------------
log_step "5/5: Setting up Docker filter proxy..."

FILTER_SERVICE="/etc/systemd/system/ds01-docker-filter.service"

if [ "$DRY_RUN" = false ]; then
    cat > "$FILTER_SERVICE" << EOF
[Unit]
Description=DS01 Docker Filter Proxy
After=docker.service ds01-container-sync.service
Requires=docker.service
Wants=ds01-container-sync.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $FILTER_PROXY \\
    --socket $PROXY_DOCKER_SOCKET \\
    --backend $REAL_DOCKER_SOCKET
Restart=on-failure
RestartSec=2
User=root

# Ensure proxy starts after Docker is ready
ExecStartPre=/bin/sleep 2

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Filter proxy service configured"
else
    echo "  Would create systemd service: ds01-docker-filter"
fi

# =============================================================================
# START SERVICES
# =============================================================================

if [ "$DRY_RUN" = false ]; then
    echo ""
    log_info "Starting services..."

    # Stop Docker and remove old socket
    systemctl stop docker || true
    rm -f /var/run/docker.sock

    # Start Docker (will create real socket)
    systemctl start docker
    sleep 2

    if [ -S "$REAL_DOCKER_SOCKET" ]; then
        log_success "Docker daemon listening on $REAL_DOCKER_SOCKET"
    else
        log_error "Docker real socket not found!"
        log_warning "Check: journalctl -u docker"
        exit 1
    fi

    # Start container sync
    systemctl enable ds01-container-sync
    systemctl start ds01-container-sync

    # Run initial sync now that Docker is ready
    python3 "$SYNC_SCRIPT" --once

    # Start filter proxy
    systemctl enable ds01-docker-filter
    systemctl start ds01-docker-filter
    sleep 1

    if [ -S "$PROXY_DOCKER_SOCKET" ]; then
        log_success "Filter proxy listening on $PROXY_DOCKER_SOCKET"
    else
        log_error "Filter proxy socket not found!"
        log_warning "Check: journalctl -u ds01-docker-filter"
        exit 1
    fi
fi

# =============================================================================
# VERIFICATION
# =============================================================================

echo ""
log_info "Verifying installation..."

if [ "$DRY_RUN" = false ]; then
    # Check services
    for svc in docker ds01-container-sync ds01-docker-filter; do
        if systemctl is-active --quiet "$svc"; then
            log_success "$svc service: running"
        else
            log_warning "$svc service: not running"
        fi
    done

    # Check sockets
    if [ -S "$REAL_DOCKER_SOCKET" ]; then
        log_success "Docker socket (real): $REAL_DOCKER_SOCKET"
    else
        log_warning "Docker socket (real): not found"
    fi

    if [ -S "$PROXY_DOCKER_SOCKET" ]; then
        log_success "Docker socket (proxy): $PROXY_DOCKER_SOCKET"
    else
        log_warning "Docker socket (proxy): not found"
    fi

    # Check data file
    if [ -f "$OPA_DATA_FILE" ]; then
        CONTAINER_COUNT=$(python3 -c "import json; d=json.load(open('$OPA_DATA_FILE')); print(len([k for k in d.get('containers',{}) if len(k)==12]))" 2>/dev/null || echo "0")
        log_success "Container ownership data: $CONTAINER_COUNT containers tracked"
    else
        log_warning "Container ownership data: not found"
    fi

    # Test Docker access
    if docker info &>/dev/null; then
        log_success "Docker client test: working"
    else
        log_warning "Docker client test: failed"
    fi
fi

# =============================================================================
# COMPLETION
# =============================================================================

echo ""
log_success "DS01 Docker Permissions Setup Complete!"
echo ""
log_info "What was configured:"
echo "  - ds01-admin group: Members have full access to all containers"
echo "  - ds01-dashboard user: Service account for dashboard"
echo "  - Container ownership sync: Updates every 5 seconds"
echo "  - Docker filter proxy: Controls container visibility and access"
echo ""
log_info "Architecture:"
echo "  Users → /var/run/docker.sock (proxy) → /var/run/docker-real.sock (daemon)"
echo ""
log_info "What users will experience:"
echo "  - 'docker ps' only shows their own containers"
echo "  - VS Code Dev Containers only shows their own containers"
echo "  - Attempting to exec/logs/stop others' containers shows:"
echo "    'Permission denied: container owned by <owner>'"
echo ""
log_info "To add a user to admin group:"
echo "  sudo usermod -aG ds01-admin <username>"
echo ""
log_info "To check service status:"
echo "  systemctl status ds01-container-sync"
echo "  systemctl status ds01-docker-filter"
echo ""
log_info "To test permissions (as regular user):"
echo "  docker ps                        # Should only show your containers"
echo "  docker exec <other-container> ls # Should show 'Permission denied'"
