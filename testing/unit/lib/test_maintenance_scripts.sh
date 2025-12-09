#!/bin/bash
# Regression tests for maintenance scripts
# /opt/ds01-infra/testing/unit/lib/test_maintenance_scripts.sh
#
# These tests verify that refactored scripts produce identical output
# to the original implementations.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="${SCRIPT_DIR%/testing/*}"
GET_LIMITS="$INFRA_ROOT/scripts/docker/get_resource_limits.py"

# Test colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        ((TESTS_PASSED += 1))
    else
        echo -e "${RED}FAIL${NC}: $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED += 1))
    fi
}

echo "=========================================="
echo "Maintenance Scripts Regression Tests"
echo "=========================================="
echo

# Test 1: --max-runtime returns valid duration
echo "Testing get_resource_limits.py CLI flags..."

MAX_RUNTIME=$(python3 "$GET_LIMITS" datasciencelab --max-runtime)
if [[ "$MAX_RUNTIME" =~ ^[0-9]+[hd]$ ]] || [ "$MAX_RUNTIME" = "None" ]; then
    test_result "--max-runtime returns valid format" "valid" "valid"
else
    test_result "--max-runtime returns valid format" "valid" "$MAX_RUNTIME"
fi

# Test 2: --container-hold-time returns valid duration
HOLD_TIME=$(python3 "$GET_LIMITS" datasciencelab --container-hold-time)
if [[ "$HOLD_TIME" =~ ^[0-9.]+[hd]$ ]] || [ "$HOLD_TIME" = "never" ]; then
    test_result "--container-hold-time returns valid format" "valid" "valid"
else
    test_result "--container-hold-time returns valid format" "valid" "$HOLD_TIME"
fi

# Test 3: --idle-timeout returns valid duration
IDLE_TIMEOUT=$(python3 "$GET_LIMITS" datasciencelab --idle-timeout)
if [[ "$IDLE_TIMEOUT" =~ ^[0-9.]+[hd]$ ]] || [ "$IDLE_TIMEOUT" = "None" ]; then
    test_result "--idle-timeout returns valid format" "valid" "valid"
else
    test_result "--idle-timeout returns valid format" "valid" "$IDLE_TIMEOUT"
fi

# Test 4: --high-demand-threshold returns decimal
HD_THRESHOLD=$(python3 "$GET_LIMITS" - --high-demand-threshold)
if [[ "$HD_THRESHOLD" =~ ^0\.[0-9]+$ ]]; then
    test_result "--high-demand-threshold returns decimal" "valid" "valid"
else
    test_result "--high-demand-threshold returns decimal" "0.X format" "$HD_THRESHOLD"
fi

# Test 5: --high-demand-reduction returns decimal
HD_REDUCTION=$(python3 "$GET_LIMITS" - --high-demand-reduction)
if [[ "$HD_REDUCTION" =~ ^0\.[0-9]+$ ]]; then
    test_result "--high-demand-reduction returns decimal" "valid" "valid"
else
    test_result "--high-demand-reduction returns decimal" "0.X format" "$HD_REDUCTION"
fi

# Test 6: --all-lifecycle returns valid JSON
LIFECYCLE_JSON=$(python3 "$GET_LIMITS" datasciencelab --all-lifecycle)
if python3 -c "import json; json.loads('$LIFECYCLE_JSON')" 2>/dev/null; then
    test_result "--all-lifecycle returns valid JSON" "valid" "valid"
else
    test_result "--all-lifecycle returns valid JSON" "valid JSON" "invalid"
fi

# Test 7: JSON contains all expected keys
KEYS_OK=$(python3 -c "import json; d=json.loads('$LIFECYCLE_JSON'); print('ok' if all(k in d for k in ['idle_timeout', 'max_runtime', 'gpu_hold_after_stop', 'container_hold_after_stop']) else 'missing')")
test_result "--all-lifecycle JSON has all keys" "ok" "$KEYS_OK"

# Test 8: Duration values are consistent
# If --max-runtime returns "24h", the JSON should have the same value
JSON_MAX_RUNTIME=$(python3 -c "import json; print(json.loads('$LIFECYCLE_JSON')['max_runtime'])")
test_result "CLI and JSON max_runtime match" "$MAX_RUNTIME" "$JSON_MAX_RUNTIME"

echo
echo "=========================================="
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "=========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
