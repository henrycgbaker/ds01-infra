#!/bin/bash
# /opt/ds01-infra/scripts/system/migrate-to-opa.sh
# Migrate from socket proxy to OPA authorization
#
# Run with: sudo ./migrate-to-opa.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Run with sudo: sudo $0"
    exit 1
fi

echo ""
log_info "=== DS01: Socket Proxy → OPA Migration ==="
echo ""

# Step 1: Stop and disable socket proxy
log_info "Step 1/4: Disabling socket proxy..."
if systemctl is-active ds01-docker-filter &>/dev/null; then
    systemctl stop ds01-docker-filter
    log_success "Socket proxy stopped"
else
    log_info "Socket proxy already stopped"
fi
systemctl disable ds01-docker-filter 2>/dev/null || true
log_success "Socket proxy disabled"

# Step 2: Restore normal Docker socket
log_info "Step 2/4: Restoring Docker socket..."
if [ -S /var/run/docker-real.sock ]; then
    # Remove the proxy socket
    rm -f /var/run/docker.sock
    # Restart Docker to recreate normal socket
    systemctl restart docker
    sleep 2
    if [ -S /var/run/docker.sock ]; then
        log_success "Docker socket restored"
    else
        log_error "Failed to restore Docker socket"
        exit 1
    fi
else
    log_info "No proxy socket migration needed"
fi

# Remove the docker-real.sock symlink dance
rm -f /var/run/docker-real.sock 2>/dev/null || true

# Step 3: Install Go if needed
log_info "Step 3/4: Checking Go installation..."
if ! command -v go &>/dev/null; then
    log_info "Installing Go..."
    apt update && apt install -y golang-go
    log_success "Go installed"
else
    log_success "Go already installed: $(go version | cut -d' ' -f3)"
fi

# Step 4: Run OPA setup
log_info "Step 4/4: Setting up OPA authorization..."
/opt/ds01-infra/scripts/system/setup-opa-authz.sh

echo ""
log_success "Migration complete!"
echo ""
log_info "To verify:"
echo "  docker info | grep -A2 Authorization"
echo ""
log_info "To test (as regular user):"
echo "  docker ps                    # Should work"
echo "  docker exec <other-user-container> bash  # Should be denied by OPA"
