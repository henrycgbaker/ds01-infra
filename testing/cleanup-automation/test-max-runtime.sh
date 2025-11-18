#!/bin/bash
# Test script for max_runtime enforcement
# This tests that containers exceeding max_runtime are automatically stopped

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="/opt/ds01-infra"
TEST_LOG="$SCRIPT_DIR/test-max-runtime.log"

echo "=====================================" | tee "$TEST_LOG"
echo "Testing max_runtime Enforcement" | tee -a "$TEST_LOG"
echo "=====================================" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Get running containers
echo "[1] Checking running containers..." | tee -a "$TEST_LOG"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep '\._\.' | tee -a "$TEST_LOG" || echo "No DS01 containers running" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Check container runtime for test._.1001
echo "[2] Checking runtime for test._.1001..." | tee -a "$TEST_LOG"
if docker ps --format "{{.Names}}" | grep -q "^test\._\.1001$"; then
    START_TIME=$(docker inspect test._.1001 --format='{{.State.StartedAt}}')
    START_EPOCH=$(date -d "$START_TIME" +%s)
    NOW_EPOCH=$(date +%s)
    RUNTIME_SECONDS=$((NOW_EPOCH - START_EPOCH))
    RUNTIME_HOURS=$((RUNTIME_SECONDS / 3600))
    echo "  Container: test._.1001" | tee -a "$TEST_LOG"
    echo "  Started: $START_TIME" | tee -a "$TEST_LOG"
    echo "  Runtime: ${RUNTIME_HOURS}h (${RUNTIME_SECONDS}s)" | tee -a "$TEST_LOG"
else
    echo "  Container test._.1001 not running" | tee -a "$TEST_LOG"
fi
echo "" | tee -a "$TEST_LOG"

# Check user's max_runtime limit
echo "[3] Checking datasciencelab's max_runtime limit..." | tee -a "$TEST_LOG"
MAX_RUNTIME=$(python3 "$INFRA_ROOT/scripts/docker/get_resource_limits.py" datasciencelab 2>/dev/null | grep -i "max_runtime" | awk '{print $NF}')
echo "  max_runtime: $MAX_RUNTIME" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Run enforcement script manually
echo "[4] Running enforce-max-runtime.sh manually..." | tee -a "$TEST_LOG"
echo "  (Check /var/log/ds01/runtime-enforcement.log for detailed output)" | tee -a "$TEST_LOG"
sudo "$INFRA_ROOT/scripts/maintenance/enforce-max-runtime.sh" 2>&1 | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Check if container still running
echo "[5] Checking container status after enforcement..." | tee -a "$TEST_LOG"
if docker ps --format "{{.Names}}" | grep -q "^test\._\.1001$"; then
    echo "  ✓ Container still running (not exceeded limit)" | tee -a "$TEST_LOG"
else
    echo "  ✗ Container stopped (limit exceeded)" | tee -a "$TEST_LOG"
fi
echo "" | tee -a "$TEST_LOG"

echo "=====================================" | tee -a "$TEST_LOG"
echo "Test completed. Log saved to: $TEST_LOG" | tee -a "$TEST_LOG"
echo "=====================================" | tee -a "$TEST_LOG"
