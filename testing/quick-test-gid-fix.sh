#!/bin/bash
# Quick validation test for GID mapping fix
# Creates a test container and checks for the "I have no name!" issue

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Quick GID Mapping Fix Validation${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Generate unique test container name
TEST_NAME="gid-quick-test-$(date +%s)"
CONTAINER_TAG="${TEST_NAME}._.$(id -u)"

# Cleanup function
cleanup() {
    if [ -n "$CONTAINER_TAG" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up...${NC}"
        docker rm -f "$CONTAINER_TAG" 2>/dev/null || true
        rm -rf ~/workspace/${TEST_NAME} 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo "Creating test container: $TEST_NAME"
echo "User: $(whoami), UID: $(id -u), GID: $(id -g)"
echo ""

# Create container
echo -e "${BLUE}Step 1: Creating container...${NC}"
# Use DS01 container-create command (not raw mlc-create)
if container-create "$TEST_NAME" pytorch > /tmp/quick-test-output.log 2>&1; then
    echo -e "${GREEN}✓ Container created${NC}"
else
    echo -e "${RED}✗ Container creation failed${NC}"
    cat /tmp/quick-test-output.log
    exit 1
fi

# Start container
echo ""
echo -e "${BLUE}Step 2: Starting container...${NC}"
if docker start "$CONTAINER_TAG" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Container started${NC}"
    sleep 2
else
    echo -e "${RED}✗ Failed to start${NC}"
    exit 1
fi

# Critical tests
echo ""
echo -e "${BLUE}Step 3: Running critical tests...${NC}"
echo ""

# Test 1: Check for "I have no name!"
echo -n "  Test 1 - Checking for 'I have no name!' error... "
SHELL_OUTPUT=$(docker exec "$CONTAINER_TAG" bash -c 'whoami; id; groups' 2>&1)
if echo "$SHELL_OUTPUT" | grep -qi "I have no name"; then
    echo -e "${RED}FAILED${NC}"
    echo "    Found 'I have no name!' in output:"
    echo "$SHELL_OUTPUT" | grep -i "I have no name"
    TEST1_PASS=false
else
    echo -e "${GREEN}PASSED${NC}"
    TEST1_PASS=true
fi

# Test 2: Check for "cannot find name for group ID"
echo -n "  Test 2 - Checking for 'cannot find name for group ID' error... "
if echo "$SHELL_OUTPUT" | grep -qi "cannot find name"; then
    echo -e "${RED}FAILED${NC}"
    echo "    Found 'cannot find name' in output:"
    echo "$SHELL_OUTPUT" | grep -i "cannot find name"
    TEST2_PASS=false
else
    echo -e "${GREEN}PASSED${NC}"
    TEST2_PASS=true
fi

# Test 3: Verify whoami returns correct username
echo -n "  Test 3 - Checking whoami returns correct username... "
WHOAMI_OUTPUT=$(docker exec "$CONTAINER_TAG" whoami 2>&1)
if [ "$WHOAMI_OUTPUT" = "$(whoami)" ]; then
    echo -e "${GREEN}PASSED${NC} (${WHOAMI_OUTPUT})"
    TEST3_PASS=true
else
    echo -e "${RED}FAILED${NC}"
    echo "    Expected: $(whoami)"
    echo "    Got: $WHOAMI_OUTPUT"
    TEST3_PASS=false
fi

# Test 4: Verify /etc/passwd has entry
echo -n "  Test 4 - Checking /etc/passwd has user entry... "
if docker exec "$CONTAINER_TAG" getent passwd $(id -u) > /dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
    TEST4_PASS=true
else
    echo -e "${RED}FAILED${NC}"
    TEST4_PASS=false
fi

# Test 5: Verify /etc/group has entry
echo -n "  Test 5 - Checking /etc/group has group entry... "
if docker exec "$CONTAINER_TAG" getent group $(id -g) > /dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
    TEST5_PASS=true
else
    echo -e "${RED}FAILED${NC}"
    TEST5_PASS=false
fi

# Results
echo ""
echo -e "${BLUE}=================================${NC}"

if [ "$TEST1_PASS" = true ] && [ "$TEST2_PASS" = true ] && [ "$TEST3_PASS" = true ] && [ "$TEST4_PASS" = true ] && [ "$TEST5_PASS" = true ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo ""
    echo "The GID mapping fix is working correctly."
    echo "No 'I have no name!' or 'cannot find name' errors detected."
    echo ""
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo ""
    echo "The issue may not be fully resolved."
    echo "See test results above for details."
    echo ""
    echo "Full command output:"
    echo "$SHELL_OUTPUT"
    echo ""
    exit 1
fi
