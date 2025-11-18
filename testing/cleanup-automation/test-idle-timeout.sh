#!/bin/bash
# Test script for idle_timeout detection
# This tests that containers idle beyond idle_timeout are automatically stopped

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="/opt/ds01-infra"
TEST_LOG="$SCRIPT_DIR/test-idle-timeout.log"

echo "=====================================" | tee "$TEST_LOG"
echo "Testing idle_timeout Detection" | tee -a "$TEST_LOG"
echo "=====================================" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Get running containers
echo "[1] Checking running containers..." | tee -a "$TEST_LOG"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep '\._\.' | tee -a "$TEST_LOG" || echo "No DS01 containers running" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Check user's idle_timeout limit
echo "[2] Checking datasciencelab's idle_timeout limit..." | tee -a "$TEST_LOG"
python3 "$INFRA_ROOT/scripts/docker/get_resource_limits.py" datasciencelab | grep -i "idle" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Check container activity
echo "[3] Checking test._.1001 activity..." | tee -a "$TEST_LOG"
if docker ps --format "{{.Names}}" | grep -q "^test\._\.1001$"; then
    CPU=$(docker stats test._.1001 --no-stream --format "{{.CPUPerc}}" 2>/dev/null || echo "0%")
    MEM=$(docker stats test._.1001 --no-stream --format "{{.MemPerc}}" 2>/dev/null || echo "0%")
    echo "  CPU: $CPU" | tee -a "$TEST_LOG"
    echo "  Memory: $MEM" | tee -a "$TEST_LOG"

    # Check for state file
    if [ -f "/var/lib/ds01/container-states/test._.1001.state" ]; then
        echo "  State file exists:" | tee -a "$TEST_LOG"
        cat "/var/lib/ds01/container-states/test._.1001.state" | tee -a "$TEST_LOG"
    else
        echo "  No state file yet" | tee -a "$TEST_LOG"
    fi
else
    echo "  Container not running" | tee -a "$TEST_LOG"
fi
echo "" | tee -a "$TEST_LOG"

# Run idle check script manually
echo "[4] Running check-idle-containers.sh manually..." | tee -a "$TEST_LOG"
echo "  (Output will show if containers are idle)" | tee -a "$TEST_LOG"
bash "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh" 2>&1 | grep -v "Permission denied" | head -50 | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Check if container still running
echo "[5] Checking container status after idle check..." | tee -a "$TEST_LOG"
if docker ps --format "{{.Names}}" | grep -q "^test\._\.1001$"; then
    echo "  ✓ Container still running" | tee -a "$TEST_LOG"
else
    echo "  ✗ Container stopped (idle timeout reached)" | tee -a "$TEST_LOG"
fi
echo "" | tee -a "$TEST_LOG"

echo "=====================================" | tee -a "$TEST_LOG"
echo "Test completed. Log saved to: $TEST_LOG" | tee -a "$TEST_LOG"
echo "=====================================" | tee -a "$TEST_LOG"
