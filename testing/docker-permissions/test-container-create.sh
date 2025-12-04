#!/bin/bash
# /opt/ds01-infra/testing/docker-permissions/test-container-create.sh
# Debug script for container creation issues
#
# This script tests container creation step by step to identify
# where the failure occurs.
#
# Usage: ./test-container-create.sh [username]
#        Run as the user experiencing the issue

set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "============================================="
echo "DS01 Container Creation Debug Test"
echo "============================================="
echo ""

# Get current user info
USER=$(whoami)
USER_ID=$(id -u)
GROUP_ID=$(id -g)
log_info "Testing as user: $USER (UID: $USER_ID, GID: $GROUP_ID)"
log_info "Groups: $(id -Gn)"
echo ""

# Test 1: Check docker group membership
echo "Test 1: Docker Group Membership"
echo "--------------------------------"
if id -nG | grep -qw docker; then
    log_success "User is in docker group"
else
    log_error "User is NOT in docker group"
    log_info "Fix: sudo usermod -aG docker $USER (then re-login)"
fi
echo ""

# Test 2: Check socket access
echo "Test 2: Socket Access"
echo "---------------------"
if [ -S /var/run/docker.sock ]; then
    log_success "Proxy socket exists: /var/run/docker.sock"
    ls -la /var/run/docker.sock
else
    log_error "Proxy socket does not exist"
fi
echo ""

if [ -S /var/run/docker-real.sock ]; then
    log_success "Real socket exists: /var/run/docker-real.sock"
    ls -la /var/run/docker-real.sock
else
    log_error "Real socket does not exist"
fi
echo ""

# Test 3: Basic docker commands
echo "Test 3: Basic Docker Commands"
echo "-----------------------------"

# docker info
log_info "Testing 'docker info'..."
if docker info >/dev/null 2>&1; then
    log_success "docker info: OK"
else
    log_error "docker info: FAILED"
fi

# docker ps
log_info "Testing 'docker ps'..."
if docker ps >/dev/null 2>&1; then
    log_success "docker ps: OK"
    CONTAINERS=$(docker ps -q | wc -l)
    log_info "  Visible containers: $CONTAINERS"
else
    log_error "docker ps: FAILED"
fi
echo ""

# Test 4: Simple container creation
echo "Test 4: Simple Container Creation"
echo "----------------------------------"
TEST_NAME="ds01-test-create-$$"

log_info "Creating simple test container: $TEST_NAME"
CREATE_OUTPUT=$(docker create --name "$TEST_NAME" alpine:latest echo test 2>&1)
CREATE_EXIT=$?

if [ $CREATE_EXIT -eq 0 ]; then
    log_success "Simple container created (exit code: 0)"
    log_info "  Container ID: ${CREATE_OUTPUT:0:12}"
    docker rm -f "$TEST_NAME" >/dev/null 2>&1
else
    log_error "Simple container creation FAILED (exit code: $CREATE_EXIT)"
    log_info "  Output: $CREATE_OUTPUT"
fi
echo ""

# Test 5: Container with cgroup-parent
echo "Test 5: Container with Cgroup Parent"
echo "-------------------------------------"
TEST_NAME="ds01-test-cgroup-$$"

# Get user's group
if [ -f /opt/ds01-infra/scripts/docker/get_resource_limits.py ]; then
    USER_GROUP=$(python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py "$USER" --group 2>/dev/null || echo "student")
else
    USER_GROUP="student"
fi

# Sanitize username
SANITIZED_USER=$(echo "$USER" | sed 's/@.*//; s/\./-/g')
SLICE_NAME="ds01-${USER_GROUP}-${SANITIZED_USER}.slice"

log_info "User group: $USER_GROUP"
log_info "Slice name: $SLICE_NAME"

CREATE_OUTPUT=$(docker create \
    --name "$TEST_NAME" \
    --cgroup-parent="$SLICE_NAME" \
    alpine:latest echo test 2>&1)
CREATE_EXIT=$?

if [ $CREATE_EXIT -eq 0 ]; then
    log_success "Cgroup container created (exit code: 0)"
    docker rm -f "$TEST_NAME" >/dev/null 2>&1
else
    log_error "Cgroup container creation FAILED (exit code: $CREATE_EXIT)"
    log_info "  Output: $CREATE_OUTPUT"
fi
echo ""

# Test 6: Container with labels (including special chars)
echo "Test 6: Container with Labels"
echo "------------------------------"
TEST_NAME="ds01-test-labels-$$"

log_info "Testing with label ds01.user=$USER"
CREATE_OUTPUT=$(docker create \
    --name "$TEST_NAME" \
    --label "ds01.user=$USER" \
    --label "ds01.managed=true" \
    alpine:latest echo test 2>&1)
CREATE_EXIT=$?

if [ $CREATE_EXIT -eq 0 ]; then
    log_success "Labeled container created (exit code: 0)"
    docker rm -f "$TEST_NAME" >/dev/null 2>&1
else
    log_error "Labeled container creation FAILED (exit code: $CREATE_EXIT)"
    log_info "  Output: $CREATE_OUTPUT"
fi
echo ""

# Test 7: Full command similar to mlc-patched
echo "Test 7: Full MLC-style Container Creation"
echo "------------------------------------------"
TEST_NAME="ds01-test-full-$$"

log_info "Testing full container creation similar to mlc-patched.py"

CREATE_OUTPUT=$(docker create \
    -it \
    -w "/home/$USER/workspace/test" \
    --name "$TEST_NAME" \
    --label "aime.mlc=$USER" \
    --label "aime.mlc.NAME=test" \
    --label "aime.mlc.USER=$USER" \
    --label "aime.mlc.DS01_MANAGED=true" \
    --label "ds01.user=$USER" \
    --label "ds01.managed=true" \
    --user "$USER_ID:$GROUP_ID" \
    --tty \
    --privileged \
    --interactive \
    --network host \
    --shm-size 16g \
    --cgroup-parent="$SLICE_NAME" \
    alpine:latest \
    bash 2>&1)
CREATE_EXIT=$?

if [ $CREATE_EXIT -eq 0 ]; then
    log_success "Full container created (exit code: 0)"
    docker rm -f "$TEST_NAME" >/dev/null 2>&1
else
    log_error "Full container creation FAILED (exit code: $CREATE_EXIT)"
    log_info "  Output: $CREATE_OUTPUT"
    log_warning "This matches the issue!"
fi
echo ""

# Test 8: Direct socket test
echo "Test 8: Direct Socket Test (bypassing wrapper)"
echo "-----------------------------------------------"
log_info "Testing direct Docker API call via proxy socket"

RESPONSE=$(python3 << 'EOF' 2>&1
import socket
import json

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('/var/run/docker.sock')

body = json.dumps({
    "Image": "alpine",
    "Cmd": ["echo", "test"],
    "Labels": {"ds01.test": "direct-api"}
})

request = f"POST /containers/create?name=ds01-test-direct HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}"
s.send(request.encode())
s.settimeout(10.0)

response = b""
while True:
    try:
        chunk = s.recv(4096)
        if not chunk:
            break
        response += chunk
        if b"}\n" in response or b"}" in response[-10:]:
            break
    except socket.timeout:
        break

s.close()
print(response.decode('utf-8', errors='replace'))
EOF
)

if echo "$RESPONSE" | grep -q "201 Created"; then
    log_success "Direct API call succeeded"
    # Clean up
    docker rm -f ds01-test-direct >/dev/null 2>&1
elif echo "$RESPONSE" | grep -q "409 Conflict"; then
    log_warning "Container already exists (clean it up: docker rm ds01-test-direct)"
else
    log_error "Direct API call returned unexpected response"
fi
log_info "Response: ${RESPONSE:0:200}"
echo ""

# Summary
echo "============================================="
echo "Summary"
echo "============================================="
echo ""
echo "If tests 1-6 pass but test 7 fails, the issue is"
echo "likely related to the combination of options used"
echo "by mlc-patched.py."
echo ""
echo "If all tests pass but 'container deploy' fails,"
echo "check the mlc-create-wrapper.sh debug output:"
echo "  DS01_DEBUG=1 container-deploy <name> --background"
echo ""
echo "To enable proxy debug mode (requires sudo):"
echo "  sudo systemctl stop ds01-docker-filter"
echo "  sudo python3 /opt/ds01-infra/scripts/docker/docker-filter-proxy.py --debug"
echo ""
