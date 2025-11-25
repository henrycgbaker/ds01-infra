#!/bin/bash
# /opt/ds01-infra/scripts/system/setup-opa-authz.sh
# Phase 1: OPA Docker Authorization Plugin Deployment
#
# This script installs and configures the OPA Docker authorization plugin
# with DS01's fail-open policy.
#
# Usage: sudo ./setup-opa-authz.sh [--dry-run] [--uninstall]
#
# Prerequisites:
#   - Docker daemon running
#   - Go 1.21+ (for building OPA plugin)
#   - setup-docker-cgroups.sh already run (daemon.json configured)

set -euo pipefail

# Configuration
INFRA_ROOT="/opt/ds01-infra"
OPA_POLICY="$INFRA_ROOT/config/opa/docker-authz.rego"
OPA_PLUGIN_DIR="/opt/opa-docker-authz"
OPA_SOCKET="/run/docker/plugins/opa-docker-authz.sock"
SYSTEMD_SERVICE="/etc/systemd/system/opa-docker-authz.service"

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
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --uninstall  Remove OPA plugin and disable in daemon.json"
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

# Uninstall mode
if [ "$UNINSTALL" = true ]; then
    log_info "Uninstalling OPA Docker authz plugin..."

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN - No changes made"
        echo "Would:"
        echo "  - Stop opa-docker-authz service"
        echo "  - Remove $SYSTEMD_SERVICE"
        echo "  - Remove authorization-plugins from daemon.json"
        echo "  - Restart Docker"
        exit 0
    fi

    # Stop and disable service
    systemctl stop opa-docker-authz 2>/dev/null || true
    systemctl disable opa-docker-authz 2>/dev/null || true

    # Remove systemd service
    rm -f "$SYSTEMD_SERVICE"
    systemctl daemon-reload

    # Remove from daemon.json
    if [ -f /etc/docker/daemon.json ]; then
        python3 << 'PYEOF'
import json
import sys

try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)

    if 'authorization-plugins' in config:
        config['authorization-plugins'] = [
            p for p in config['authorization-plugins']
            if p != 'opa-docker-authz'
        ]
        if not config['authorization-plugins']:
            del config['authorization-plugins']

    with open('/etc/docker/daemon.json', 'w') as f:
        json.dump(config, f, indent=4)

    print("Removed OPA from daemon.json")
except Exception as e:
    print(f"Warning: Could not update daemon.json: {e}", file=sys.stderr)
PYEOF
    fi

    # Restart Docker
    systemctl restart docker
    log_success "OPA plugin uninstalled"
    exit 0
fi

# Installation
log_info "DS01 OPA Docker Authorization Setup"
log_info "===================================="
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

# Check policy file exists
if [ ! -f "$OPA_POLICY" ]; then
    log_error "OPA policy not found: $OPA_POLICY"
    exit 1
fi
log_success "OPA policy found"

# Check if Go is available (needed to build plugin)
if ! command -v go &>/dev/null; then
    log_warning "Go not installed. OPA plugin requires manual installation."
    echo ""
    echo "To install OPA Docker authz plugin:"
    echo ""
    echo "1. Install Go 1.21+:"
    echo "   sudo apt install golang-go"
    echo ""
    echo "2. Build and install plugin:"
    echo "   git clone https://github.com/open-policy-agent/opa-docker-authz.git"
    echo "   cd opa-docker-authz"
    echo "   go build -o opa-docker-authz"
    echo "   sudo cp opa-docker-authz /usr/local/bin/"
    echo ""
    echo "3. Re-run this script to complete setup"
    exit 1
fi
log_success "Go installed: $(go version | cut -d' ' -f3)"

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN - No changes made"
    echo ""
    echo "Would:"
    echo "  - Clone/build opa-docker-authz plugin"
    echo "  - Create systemd service"
    echo "  - Enable authorization-plugins in daemon.json"
    echo "  - Start OPA plugin service"
    echo "  - Restart Docker"
    exit 0
fi

# Step 1: Build OPA plugin if needed
if [ ! -f "/usr/local/bin/opa-docker-authz" ]; then
    log_info "Building OPA Docker authz plugin..."

    # Create temp directory for build
    BUILD_DIR=$(mktemp -d)
    trap "rm -rf $BUILD_DIR" EXIT

    cd "$BUILD_DIR"
    git clone --depth 1 https://github.com/open-policy-agent/opa-docker-authz.git
    cd opa-docker-authz

    # Build
    go build -o opa-docker-authz

    # Install
    cp opa-docker-authz /usr/local/bin/
    chmod +x /usr/local/bin/opa-docker-authz

    log_success "OPA plugin built and installed"
else
    log_info "OPA plugin already installed"
fi

# Step 2: Create systemd service
log_info "Creating systemd service..."

cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=OPA Docker Authorization Plugin (DS01)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/opa-docker-authz -policy-file $OPA_POLICY
Restart=on-failure
RestartSec=5

# Socket configuration
Environment=DOCKER_PLUGINS_DIR=/run/docker/plugins

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
log_success "Systemd service created"

# Step 3: Start OPA service
log_info "Starting OPA plugin..."
systemctl enable opa-docker-authz
systemctl start opa-docker-authz

# Wait for socket
sleep 2
if [ -S "$OPA_SOCKET" ]; then
    log_success "OPA plugin running (socket: $OPA_SOCKET)"
else
    log_warning "OPA socket not found. Check: journalctl -u opa-docker-authz"
fi

# Step 4: Enable in daemon.json (if not already)
log_info "Enabling in daemon.json..."

python3 << 'PYEOF'
import json
import sys

try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

if 'authorization-plugins' not in config:
    config['authorization-plugins'] = []

if 'opa-docker-authz' not in config['authorization-plugins']:
    config['authorization-plugins'].append('opa-docker-authz')
    with open('/etc/docker/daemon.json', 'w') as f:
        json.dump(config, f, indent=4)
    print("Added OPA to daemon.json")
else:
    print("OPA already in daemon.json")
PYEOF

# Step 5: Restart Docker
log_info "Restarting Docker..."
systemctl restart docker

# Wait for Docker
sleep 3
if docker info &>/dev/null; then
    log_success "Docker restarted successfully"
else
    log_error "Docker failed to start. Check: journalctl -u docker"
    log_warning "You may need to disable OPA: $0 --uninstall"
    exit 1
fi

# Step 6: Verify
log_info "Verifying setup..."

# Check if authorization plugins are configured
AUTH_PLUGINS=$(docker info --format '{{.Plugins.Authorization}}' 2>/dev/null || echo "")
if echo "$AUTH_PLUGINS" | grep -q "opa-docker-authz"; then
    log_success "OPA plugin active"
else
    log_warning "OPA plugin not showing in docker info"
fi

echo ""
log_success "OPA setup complete!"
echo ""
log_info "Policy: $OPA_POLICY"
log_info "Service: systemctl status opa-docker-authz"
echo ""
log_info "Test enforcement:"
echo "  # Should work (uses default ds01.slice):"
echo "  docker run --rm alpine echo 'Hello'"
echo ""
echo "  # Should be denied (attempts to escape):"
echo "  docker run --rm --cgroup-parent=system.slice alpine echo 'Bypass'"
