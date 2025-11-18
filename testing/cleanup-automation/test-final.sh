#!/bin/bash
# Final test of fixed functions

set -e

INFRA_ROOT="/opt/ds01-infra"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
username="datasciencelab"

echo "Final Test - Fixed Functions"
echo "============================="
echo ""

echo "[Test 1] Testing get_idle_timeout function from actual script..."
timeout=$(bash -c "source $INFRA_ROOT/scripts/monitoring/check-idle-containers.sh && get_idle_timeout datasciencelab")
echo "  Result: '$timeout'"
echo "  Expected: '0.5h' (from defaults, since admin group doesn't define it)"
if [ "$timeout" = "0.5h" ]; then
    echo "  ✅ PASS"
else
    echo "  ❌ FAIL"
fi
echo ""

echo "[Test 2] Testing get_max_runtime function from actual script..."
runtime=$(bash -c "source $INFRA_ROOT/scripts/maintenance/enforce-max-runtime.sh && get_max_runtime datasciencelab")
echo "  Result: '$runtime'"
echo "  Expected: '12h' (from defaults, since admin group doesn't define it)"
if [ "$runtime" = "12h" ]; then
    echo "  ✅ PASS"
else
    echo "  ❌ FAIL"
fi
echo ""

echo "============================="
echo "Tests complete!"
echo "============================="
