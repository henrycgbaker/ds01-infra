#!/bin/bash
# /opt/ds01-infra/scripts/system/setup-docker-cgroups.sh
# Phase 1: Universal Enforcement Foundation - Docker Daemon Configuration
#
# This script configures Docker to use systemd cgroups with DS01 as the default
# cgroup parent. ALL containers (from any interface) will be placed under ds01.slice.
#
# Usage: sudo ./setup-docker-cgroups.sh [--dry-run] [--enable-opa]
#
# What it does:
# 1. Backs up current daemon.json
# 2. Adds systemd cgroup driver
# 3. Sets ds01.slice as default cgroup-parent
# 4. Optionally enables OPA authorization plugin
# 5. Restarts Docker daemon

set -euo pipefail

# Configuration
DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_DIR="/var/lib/ds01/backups"
WRAPPER_SRC="/opt/ds01-infra/scripts/docker/docker-wrapper.sh"
WRAPPER_DST="/usr/local/bin/docker"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
DRY_RUN=false
ENABLE_OPA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            ;;
        --enable-opa)
            ENABLE_OPA=true
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--enable-opa]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --enable-opa Enable OPA authorization plugin in daemon.json"
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

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

log_info "DS01 Docker Cgroup Setup"
log_info "========================"
echo ""

# Step 1: Read current daemon.json
log_info "Reading current Docker daemon configuration..."

if [ -f "$DAEMON_JSON" ]; then
    CURRENT_CONFIG=$(cat "$DAEMON_JSON")
    log_info "Current config:"
    echo "$CURRENT_CONFIG" | sed 's/^/  /'
else
    CURRENT_CONFIG="{}"
    log_warning "No daemon.json found, will create new one"
fi

# Step 2: Build new configuration using Python (reliable JSON manipulation)
log_info "Building new configuration..."

NEW_CONFIG=$(python3 << 'PYEOF'
import json
import sys
import os

# Read current config
current = os.environ.get('CURRENT_CONFIG', '{}')
enable_opa = os.environ.get('ENABLE_OPA', 'false') == 'true'

try:
    config = json.loads(current)
except json.JSONDecodeError:
    config = {}

# Ensure config is a dict
if not isinstance(config, dict):
    config = {}

# Add systemd cgroup driver
if 'exec-opts' not in config:
    config['exec-opts'] = []
if 'native.cgroupdriver=systemd' not in config['exec-opts']:
    config['exec-opts'].append('native.cgroupdriver=systemd')

# Set default cgroup-parent to ds01.slice
config['cgroup-parent'] = 'ds01.slice'

# Ensure nvidia runtime is configured
if 'default-runtime' not in config:
    config['default-runtime'] = 'nvidia'

if 'runtimes' not in config:
    config['runtimes'] = {}

if 'nvidia' not in config['runtimes']:
    config['runtimes']['nvidia'] = {
        'args': [],
        'path': 'nvidia-container-runtime'
    }

# Optionally add OPA authorization plugin
if enable_opa:
    if 'authorization-plugins' not in config:
        config['authorization-plugins'] = []
    if 'opa-docker-authz' not in config['authorization-plugins']:
        config['authorization-plugins'].append('opa-docker-authz')

# Output formatted JSON
print(json.dumps(config, indent=4))
PYEOF
)

export CURRENT_CONFIG
export ENABLE_OPA

# Re-run with environment variables
NEW_CONFIG=$(CURRENT_CONFIG="$CURRENT_CONFIG" ENABLE_OPA="$ENABLE_OPA" python3 << 'PYEOF'
import json
import sys
import os

# Read current config
current = os.environ.get('CURRENT_CONFIG', '{}')
enable_opa = os.environ.get('ENABLE_OPA', 'false') == 'true'

try:
    config = json.loads(current)
except json.JSONDecodeError:
    config = {}

# Ensure config is a dict
if not isinstance(config, dict):
    config = {}

# Add systemd cgroup driver
if 'exec-opts' not in config:
    config['exec-opts'] = []
if 'native.cgroupdriver=systemd' not in config['exec-opts']:
    config['exec-opts'].append('native.cgroupdriver=systemd')

# Set default cgroup-parent to ds01.slice
config['cgroup-parent'] = 'ds01.slice'

# Ensure nvidia runtime is configured
if 'default-runtime' not in config:
    config['default-runtime'] = 'nvidia'

if 'runtimes' not in config:
    config['runtimes'] = {}

if 'nvidia' not in config['runtimes']:
    config['runtimes']['nvidia'] = {
        'args': [],
        'path': 'nvidia-container-runtime'
    }

# Optionally add OPA authorization plugin
if enable_opa:
    if 'authorization-plugins' not in config:
        config['authorization-plugins'] = []
    if 'opa-docker-authz' not in config['authorization-plugins']:
        config['authorization-plugins'].append('opa-docker-authz')

# Output formatted JSON
print(json.dumps(config, indent=4))
PYEOF
)

echo ""
log_info "New configuration:"
echo "$NEW_CONFIG" | sed 's/^/  /'
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN - No changes made"
    echo ""
    log_info "Would write to: $DAEMON_JSON"
    log_info "Would restart Docker daemon"
    if [ -f "$WRAPPER_SRC" ]; then
        log_info "Would deploy docker-wrapper.sh to: $WRAPPER_DST"
    fi
    exit 0
fi

# Step 3: Backup current config
BACKUP_FILE="$BACKUP_DIR/daemon.json.$(date +%Y%m%d_%H%M%S).bak"
if [ -f "$DAEMON_JSON" ]; then
    cp "$DAEMON_JSON" "$BACKUP_FILE"
    log_success "Backed up current config to: $BACKUP_FILE"
fi

# Step 4: Write new config
echo "$NEW_CONFIG" > "$DAEMON_JSON"
log_success "Wrote new configuration to $DAEMON_JSON"

# Step 5: Ensure ds01.slice exists
if [ ! -f "/etc/systemd/system/ds01.slice" ]; then
    log_info "Creating ds01.slice..."
    cat > /etc/systemd/system/ds01.slice << 'EOF'
[Unit]
Description=DS01 Container Slice
Before=slices.target

[Slice]
CPUAccounting=true
MemoryAccounting=true
TasksAccounting=true
IOAccounting=true
EOF
    systemctl daemon-reload
    log_success "Created ds01.slice"
else
    log_info "ds01.slice already exists"
fi

# Step 6: Deploy docker wrapper if it exists
if [ -f "$WRAPPER_SRC" ]; then
    log_info "Deploying docker-wrapper.sh..."

    # Check if /usr/local/bin/docker already exists and is not our wrapper
    if [ -f "$WRAPPER_DST" ]; then
        if ! grep -q "DS01 Docker Wrapper" "$WRAPPER_DST" 2>/dev/null; then
            # Backup existing file
            cp "$WRAPPER_DST" "$BACKUP_DIR/docker.$(date +%Y%m%d_%H%M%S).bak"
            log_warning "Backed up existing $WRAPPER_DST"
        fi
    fi

    cp "$WRAPPER_SRC" "$WRAPPER_DST"
    chmod +x "$WRAPPER_DST"
    log_success "Deployed docker-wrapper.sh to $WRAPPER_DST"
else
    log_warning "docker-wrapper.sh not found at $WRAPPER_SRC (skipping wrapper deployment)"
fi

# Step 7: Restart Docker
log_info "Restarting Docker daemon..."

# Check for running containers
RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    log_warning "$RUNNING_CONTAINERS container(s) currently running"
    log_warning "They will be stopped during restart"
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Aborted. Run 'sudo systemctl restart docker' manually when ready."
        exit 0
    fi
fi

systemctl restart docker

# Wait for Docker to be ready
log_info "Waiting for Docker to be ready..."
for i in {1..30}; do
    if docker info &>/dev/null; then
        break
    fi
    sleep 1
done

if docker info &>/dev/null; then
    log_success "Docker daemon restarted successfully"
else
    log_error "Docker daemon failed to start. Check: journalctl -u docker"
    exit 1
fi

# Step 8: Verify configuration
log_info "Verifying configuration..."
echo ""

# Check cgroup driver
CGROUP_DRIVER=$(docker info --format '{{.CgroupDriver}}' 2>/dev/null || echo "unknown")
if [ "$CGROUP_DRIVER" = "systemd" ]; then
    log_success "Cgroup driver: systemd"
else
    log_warning "Cgroup driver: $CGROUP_DRIVER (expected: systemd)"
fi

# Check default cgroup parent
DEFAULT_CGROUP=$(docker info --format '{{.CgroupParent}}' 2>/dev/null || echo "unknown")
if [ "$DEFAULT_CGROUP" = "ds01.slice" ]; then
    log_success "Default cgroup-parent: ds01.slice"
else
    log_warning "Default cgroup-parent: $DEFAULT_CGROUP (expected: ds01.slice)"
fi

# Check wrapper
if [ -f "$WRAPPER_DST" ] && grep -q "DS01 Docker Wrapper" "$WRAPPER_DST" 2>/dev/null; then
    log_success "Docker wrapper installed at $WRAPPER_DST"
else
    log_warning "Docker wrapper not installed"
fi

echo ""
log_success "Setup complete!"
echo ""
log_info "What this means:"
echo "  - ALL containers will be placed in ds01.slice by default"
echo "  - Resource limits enforced via systemd cgroups"
echo "  - Docker wrapper injects per-user slices automatically"
echo ""
log_info "Test with:"
echo "  docker run --rm alpine echo 'Hello from DS01'"
echo "  cat /sys/fs/cgroup/ds01.slice/*/tasks  # Should show container PIDs"
