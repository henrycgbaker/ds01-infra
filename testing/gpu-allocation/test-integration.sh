#!/bin/bash
# Integration tests for GPU allocation system
# Tests end-to-end workflows

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

PASSED=0
FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

echo "GPU Allocation Integration Tests"
echo "=================================="
echo ""

# Test 1: Query tools exist
echo "Test 1: Checking query tools exist..."
if [ -f "$INFRA_ROOT/scripts/docker/gpu-state-reader.py" ] && \
   [ -f "$INFRA_ROOT/scripts/docker/gpu-availability-checker.py" ] && \
   [ -f "$INFRA_ROOT/scripts/docker/gpu-allocator-smart.py" ] && \
   [ -f "$INFRA_ROOT/scripts/docker/ds01-resource-query.py" ]; then
    test_pass "All query tools exist"
else
    test_fail "Missing query tools"
fi

# Test 2: GPU state reader works
echo "Test 2: GPU state reader functionality..."
if python3 "$INFRA_ROOT/scripts/docker/gpu-state-reader.py" status &>/dev/null; then
    test_pass "GPU state reader executes successfully"
else
    test_fail "GPU state reader failed"
fi

# Test 3: GPU availability checker works
echo "Test 3: GPU availability checker functionality..."
if python3 "$INFRA_ROOT/scripts/docker/gpu-availability-checker.py" summary &>/dev/null; then
    test_pass "GPU availability checker executes successfully"
else
    test_fail "GPU availability checker failed"
fi

# Test 4: GPU allocator smart works
echo "Test 4: GPU allocator smart status..."
if python3 "$INFRA_ROOT/scripts/docker/gpu-allocator-smart.py" status &>/dev/null; then
    test_pass "GPU allocator smart executes successfully"
else
    test_fail "GPU allocator smart failed"
fi

# Test 5: Resource query tool works
echo "Test 5: Resource query tool functionality..."
USERNAME=$(whoami)
if python3 "$INFRA_ROOT/scripts/docker/ds01-resource-query.py" gpus --json &>/dev/null; then
    test_pass "ds01-resource-query.py executes successfully"
else
    test_fail "ds01-resource-query.py failed"
fi

# Test 6: Query containers
echo "Test 6: Query user containers..."
if python3 "$INFRA_ROOT/scripts/docker/ds01-resource-query.py" containers --user "$USERNAME" --json &>/dev/null; then
    test_pass "Container query successful"
else
    test_fail "Container query failed"
fi

# Test 7: Check user summary
echo "Test 7: User summary query..."
if python3 "$INFRA_ROOT/scripts/docker/ds01-resource-query.py" user-summary "$USERNAME" --json &>/dev/null; then
    test_pass "User summary query successful"
else
    test_fail "User summary query failed"
fi

# Test 8: Verify Docker labels on existing containers
echo "Test 8: Checking Docker labels on containers..."
CONTAINERS=$(docker ps -a --filter "label=ds01.managed=true" --format "{{.Names}}" 2>/dev/null | head -1)

if [ -n "$CONTAINERS" ]; then
    CONTAINER_NAME=$(echo "$CONTAINERS" | head -1)

    # Check if ds01.managed label exists
    MANAGED_LABEL=$(docker inspect --format '{{index .Config.Labels "ds01.managed"}}' "$CONTAINER_NAME" 2>/dev/null)

    if [ "$MANAGED_LABEL" = "true" ]; then
        test_pass "DS01 labels present on containers"
    else
        test_fail "DS01 labels missing on containers"
    fi
else
    echo -e "${YELLOW}⊘${NC} No DS01-managed containers found (skipping label test)"
fi

# Test 9: Verify no state files are being created
echo "Test 9: Checking state file creation..."
STATE_FILE="/var/lib/ds01/gpu-state.json"
MTIME_BEFORE=""

if [ -f "$STATE_FILE" ]; then
    MTIME_BEFORE=$(stat -c %Y "$STATE_FILE" 2>/dev/null)
fi

# Run allocation status check
python3 "$INFRA_ROOT/scripts/docker/gpu-allocator-smart.py" status &>/dev/null

if [ -f "$STATE_FILE" ]; then
    MTIME_AFTER=$(stat -c %Y "$STATE_FILE" 2>/dev/null)

    if [ "$MTIME_BEFORE" = "$MTIME_AFTER" ]; then
        test_pass "State file not modified (stateless operation confirmed)"
    else
        test_fail "State file was modified (not stateless)"
    fi
else
    test_pass "No state file exists (stateless operation)"
fi

# Test 10: Verify old allocator shows deprecation warning
echo "Test 10: Old allocator deprecation warning..."
if python3 "$INFRA_ROOT/scripts/docker/gpu_allocator.py" status 2>&1 | grep -q "DEPRECATED"; then
    test_pass "Old allocator shows deprecation warning"
else
    test_fail "Old allocator missing deprecation warning"
fi

# Summary
echo ""
echo "=================================="
echo "Test Results:"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
