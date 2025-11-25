#!/bin/bash
# Comprehensive test for GID mapping fix
# Tests container creation, user setup, and opening

set -e

BLUE='\033[94m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TEST_CONTAINER="gid-test-$(date +%s)"
PASSED=0
FAILED=0

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}GID Mapping Fix - Comprehensive Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Test container: $TEST_CONTAINER"
echo "User: $(whoami)"
echo "UID: $(id -u)"
echo "GID: $(id -g)"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test container...${NC}"
    docker stop "${TEST_CONTAINER}._.$(id -u)" 2>/dev/null || true
    docker rm -f "${TEST_CONTAINER}._.$(id -u)" 2>/dev/null || true
    rm -rf ~/workspace/${TEST_CONTAINER} 2>/dev/null || true
}

trap cleanup EXIT

# Test helper functions
test_start() {
    echo -e "${CYAN}━━━ Test: $1 ━━━${NC}"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
    echo ""
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
    echo ""
}

# Test 1: Create container
test_start "Container Creation"
echo "Creating test container with DS01 container-create..."
# Use DS01 container-create command (not raw mlc-create)
if container-create "$TEST_CONTAINER" pytorch > /tmp/mlc-create-output.log 2>&1; then
    test_pass "Container created successfully"
    echo "Container tag: ${TEST_CONTAINER}._.$(id -u)"
else
    test_fail "Container creation failed"
    echo "Output:"
    cat /tmp/mlc-create-output.log
    exit 1
fi

CONTAINER_TAG="${TEST_CONTAINER}._.$(id -u)"

# Test 2: Check container exists
test_start "Container Existence Check"
if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_TAG}$"; then
    test_pass "Container exists in Docker"
else
    test_fail "Container not found in Docker"
    exit 1
fi

# Test 3: Start container
test_start "Container Start"
if docker start "$CONTAINER_TAG" > /dev/null 2>&1; then
    test_pass "Container started successfully"
    sleep 2
else
    test_fail "Failed to start container"
    exit 1
fi

# Test 4: Check /etc/passwd has user entry
test_start "User Entry in /etc/passwd"
USER_ENTRY=$(docker exec "$CONTAINER_TAG" cat /etc/passwd 2>/dev/null | grep "^.*:x:$(id -u):$(id -g):" || true)
if [ -n "$USER_ENTRY" ]; then
    test_pass "User entry found in /etc/passwd"
    echo "Entry: $USER_ENTRY"
else
    test_fail "No user entry for UID $(id -u) in /etc/passwd"
    echo "Full /etc/passwd:"
    docker exec "$CONTAINER_TAG" cat /etc/passwd
fi

# Test 5: Check /etc/group has group entry
test_start "Group Entry in /etc/group"
GROUP_ENTRY=$(docker exec "$CONTAINER_TAG" cat /etc/group 2>/dev/null | grep ":$(id -g):" || true)
if [ -n "$GROUP_ENTRY" ]; then
    test_pass "Group entry found in /etc/group"
    echo "Entry: $GROUP_ENTRY"
else
    test_fail "No group entry for GID $(id -g) in /etc/group"
    echo "Full /etc/group:"
    docker exec "$CONTAINER_TAG" cat /etc/group
fi

# Test 6: Check 'id' command works
test_start "'id' Command Execution"
ID_OUTPUT=$(docker exec "$CONTAINER_TAG" id 2>&1)
if echo "$ID_OUTPUT" | grep -q "uid=$(id -u)"; then
    test_pass "'id' command works correctly"
    echo "Output: $ID_OUTPUT"
else
    test_fail "'id' command failed or returned wrong UID"
    echo "Output: $ID_OUTPUT"
fi

# Test 7: Check 'whoami' command works
test_start "'whoami' Command Execution"
WHOAMI_OUTPUT=$(docker exec "$CONTAINER_TAG" whoami 2>&1)
if [ "$WHOAMI_OUTPUT" = "$(whoami)" ]; then
    test_pass "'whoami' returns correct username: $WHOAMI_OUTPUT"
else
    test_fail "'whoami' returned unexpected value: $WHOAMI_OUTPUT (expected: $(whoami))"
fi

# Test 8: Check 'groups' command works without error
test_start "'groups' Command Execution"
GROUPS_OUTPUT=$(docker exec "$CONTAINER_TAG" groups 2>&1)
if ! echo "$GROUPS_OUTPUT" | grep -qi "cannot find name"; then
    test_pass "'groups' command works without 'cannot find name' error"
    echo "Output: $GROUPS_OUTPUT"
else
    test_fail "'groups' command shows 'cannot find name' error"
    echo "Output: $GROUPS_OUTPUT"
fi

# Test 9: Interactive shell test (check for "I have no name!")
test_start "Interactive Shell Test"
SHELL_OUTPUT=$(docker exec "$CONTAINER_TAG" bash -c 'whoami && echo "Shell test passed"' 2>&1)
if echo "$SHELL_OUTPUT" | grep -q "Shell test passed" && ! echo "$SHELL_OUTPUT" | grep -qi "I have no name"; then
    test_pass "Interactive shell works without 'I have no name!' error"
    echo "Output: $SHELL_OUTPUT"
else
    test_fail "Interactive shell shows 'I have no name!' or other issues"
    echo "Output: $SHELL_OUTPUT"
fi

# Test 10: Check user can write to workspace
test_start "Workspace Write Permission"
if docker exec "$CONTAINER_TAG" bash -c 'touch /workspace/test-file && rm /workspace/test-file' 2>/dev/null; then
    test_pass "User can write to /workspace"
else
    test_fail "User cannot write to /workspace"
fi

# Test 11: Check user home directory
test_start "User Home Directory"
HOME_DIR=$(docker exec "$CONTAINER_TAG" bash -c 'echo $HOME' 2>&1)
if [ -n "$HOME_DIR" ] && [ "$HOME_DIR" != "/" ]; then
    test_pass "User has valid home directory: $HOME_DIR"
else
    test_fail "User home directory is invalid: $HOME_DIR"
fi

# Test 12: Check PS1 prompt (should show container name, not "I have no name!")
test_start "Shell Prompt (PS1)"
PS1_TEST=$(docker exec "$CONTAINER_TAG" bash -c 'echo $PS1' 2>&1)
if ! echo "$PS1_TEST" | grep -qi "I have no name"; then
    test_pass "Shell prompt does not contain 'I have no name!'"
    echo "PS1: $PS1_TEST"
else
    test_fail "Shell prompt contains 'I have no name!'"
    echo "PS1: $PS1_TEST"
fi

# Test 13: Full interactive session simulation
test_start "Full Interactive Session Simulation"
SESSION_OUTPUT=$(docker exec -it "$CONTAINER_TAG" bash -c '
    echo "Testing interactive session..."
    whoami
    id
    groups
    pwd
    ls -la /workspace 2>/dev/null | head -5
    echo "Session test complete"
' 2>&1)

if echo "$SESSION_OUTPUT" | grep -q "Session test complete" && \
   ! echo "$SESSION_OUTPUT" | grep -qi "I have no name" && \
   ! echo "$SESSION_OUTPUT" | grep -qi "cannot find name"; then
    test_pass "Full interactive session works correctly"
else
    test_fail "Interactive session has issues"
    echo "Full output:"
    echo "$SESSION_OUTPUT"
fi

# Test 14: Verify container can be stopped and restarted
test_start "Container Stop and Restart"
if docker stop "$CONTAINER_TAG" > /dev/null 2>&1 && \
   docker start "$CONTAINER_TAG" > /dev/null 2>&1 && \
   sleep 2 && \
   docker exec "$CONTAINER_TAG" whoami > /dev/null 2>&1; then
    test_pass "Container can be stopped and restarted successfully"
else
    test_fail "Container stop/restart failed"
fi

# Test 15: Verify committed image has correct user setup
test_start "Committed Image User Setup"
IMAGE=$(docker inspect "$CONTAINER_TAG" --format '{{.Config.Image}}' 2>/dev/null)
if [ -n "$IMAGE" ] && docker images -q "$IMAGE" > /dev/null 2>&1; then
    # Check if the committed image has user entry
    IMAGE_USER_CHECK=$(docker run --rm "$IMAGE" cat /etc/passwd 2>/dev/null | grep "$(id -u)" || echo "")
    if [ -n "$IMAGE_USER_CHECK" ]; then
        test_pass "Committed image contains user entry"
        echo "Entry: $IMAGE_USER_CHECK"
    else
        test_fail "Committed image missing user entry"
    fi
else
    test_fail "Could not find committed image: $IMAGE"
fi

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED!${NC}"
    echo ""
    echo "The GID mapping fix is working correctly."
    echo "Containers created with the patched mlc-patched.py will not show"
    echo "the 'I have no name!' or 'cannot find name for group ID' errors."
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo "Please review the failed tests above."
    echo "The GID mapping fix may need additional work."
    echo ""
    exit 1
fi
