#!/bin/bash
# /opt/ds01-infra/testing/docker-permissions/test-permissions.sh
# Test script for Docker container permissions
#
# This script tests:
# 1. Container listing (docker ps)
# 2. Container access controls (exec, logs, etc.)
# 3. Admin bypass
#
# Usage: ./test-permissions.sh [--as-user <username>]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "========================================"
echo "DS01 Docker Permissions Test Suite"
echo "========================================"
echo ""

# Get current user info
CURRENT_USER=$(whoami)
CURRENT_UID=$(id -u)
log_info "Running as: $CURRENT_USER (uid=$CURRENT_UID)"

# Check if user is admin
IS_ADMIN=false
if getent group ds01-admin | grep -q "$CURRENT_USER"; then
    IS_ADMIN=true
    log_info "User is ADMIN (member of ds01-admin)"
else
    log_info "User is NOT admin"
fi

echo ""
echo "Test 1: Docker connectivity"
echo "----------------------------"
if docker info &>/dev/null; then
    log_pass "Docker is accessible"
else
    log_fail "Docker is NOT accessible"
    exit 1
fi

echo ""
echo "Test 2: Socket proxy is active"
echo "------------------------------"
if [ -S /var/run/docker.sock ] && [ -S /var/run/docker-real.sock ]; then
    log_pass "Both proxy and real sockets exist"
else
    log_fail "Socket configuration incorrect"
    ls -la /var/run/docker*.sock 2>/dev/null || true
fi

echo ""
echo "Test 3: Container listing"
echo "-------------------------"
CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' | wc -l)
log_info "Visible containers: $CONTAINER_COUNT"

# Show containers with owners
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Label "ds01.user"}}' | head -10

echo ""
echo "Test 4: Ownership data"
echo "----------------------"
if [ -f /var/lib/ds01/opa/container-owners.json ]; then
    TRACKED=$(python3 -c "import json; d=json.load(open('/var/lib/ds01/opa/container-owners.json')); print(len([k for k in d.get('containers',{}) if len(k)==12]))")
    log_pass "Ownership data exists: $TRACKED containers tracked"
else
    log_fail "Ownership data file not found"
fi

echo ""
echo "Test 5: Container access tests"
echo "------------------------------"

# Get a container we don't own (if any)
OTHER_CONTAINERS=$(docker ps -a --format '{{.Names}}\t{{.Label "ds01.user"}}' | grep -v "^$CURRENT_USER" | grep -v "^$" | head -1 || true)

if [ -n "$OTHER_CONTAINERS" ]; then
    OTHER_NAME=$(echo "$OTHER_CONTAINERS" | cut -f1)
    OTHER_OWNER=$(echo "$OTHER_CONTAINERS" | cut -f2)

    log_info "Testing access to container: $OTHER_NAME (owner: $OTHER_OWNER)"

    # Try to exec into the container
    if docker exec "$OTHER_NAME" echo "test" 2>&1 | grep -q "Permission denied"; then
        if [ "$IS_ADMIN" = true ]; then
            log_fail "Admin was blocked (should have access)"
        else
            log_pass "Non-admin correctly blocked from other's container"
        fi
    else
        if [ "$IS_ADMIN" = true ]; then
            log_pass "Admin has access to all containers"
        else
            log_warn "Non-admin was NOT blocked (may be expected for containers with no owner)"
        fi
    fi
else
    log_info "No containers owned by other users to test"
fi

# Test access to our own container (if any)
OWN_CONTAINERS=$(docker ps -a --format '{{.Names}}\t{{.Label "ds01.user"}}' | grep "$CURRENT_USER" | head -1 || true)

if [ -n "$OWN_CONTAINERS" ]; then
    OWN_NAME=$(echo "$OWN_CONTAINERS" | cut -f1)
    log_info "Testing access to own container: $OWN_NAME"

    if docker inspect "$OWN_NAME" &>/dev/null; then
        log_pass "Can access own container"
    else
        log_fail "Cannot access own container"
    fi
else
    log_info "No containers owned by current user to test"
fi

echo ""
echo "Test 6: Service status"
echo "----------------------"
for svc in docker ds01-container-sync ds01-docker-filter; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log_pass "$svc: running"
    else
        log_fail "$svc: not running"
    fi
done

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
log_info "Current user: $CURRENT_USER"
log_info "Is admin: $IS_ADMIN"
log_info "Visible containers: $CONTAINER_COUNT"
echo ""

if [ "$IS_ADMIN" = true ]; then
    log_info "As an admin, you should see ALL containers and have full access."
    log_info "To test non-admin behavior, run this script as a regular user."
else
    log_info "As a non-admin, you should only see YOUR containers."
    log_info "Access to other users' containers should be denied."
fi
