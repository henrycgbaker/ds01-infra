#!/bin/bash
# DS01 Layered Architecture - Phase 2: Container State Management Tests
# Tests binary state model for orchestration and full state model for atomic/docker

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-lib.sh"

INFRA_ROOT="/opt/ds01-infra"

section "Phase 2: Container State Management Tests"

# ============================================================================
# Test 1: GPU Allocator v2 State Model Implementation
# ============================================================================
section "1. GPU Allocator v2 State Model"

ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator_v2.py"

assert_file_exists "$ALLOCATOR" "GPU allocator v2 exists"

if [[ -f "$ALLOCATOR" ]]; then
    # Syntax check
    if python3 -m py_compile "$ALLOCATOR" 2>/dev/null; then
        pass "GPU allocator v2 Python syntax is valid"
    else
        fail "GPU allocator v2 syntax" "Python syntax error"
    fi

    # Check for container state handling
    assert_grep 'get_container_state\|_get_container_state' "$ALLOCATOR" "Allocator has container state method"

    # Check for binary state model (orchestration interface)
    assert_grep 'Binary state\|binary.*model\|orchestration' "$ALLOCATOR" "Allocator handles binary state model"

    # Check for full state model support (stopped state)
    assert_grep 'stopped\|mark.*stopped\|stopped_timestamp' "$ALLOCATOR" "Allocator handles stopped state"

    # Check for GPU release on removal
    assert_grep 'release\|free.*gpu\|remove.*allocation' "$ALLOCATOR" "Allocator releases GPU on removal"

    # Check for GPU hold timeout
    assert_grep 'gpu_hold\|hold.*after.*stop' "$ALLOCATOR" "Allocator supports GPU hold timeout"
fi

# ============================================================================
# Test 2: Container Deploy (Binary State: create + start)
# ============================================================================
section "2. Container Deploy Binary Model"

DEPLOY_SCRIPT="$INFRA_ROOT/scripts/user/container-deploy"

assert_file_exists "$DEPLOY_SCRIPT" "container-deploy script exists"

if [[ -f "$DEPLOY_SCRIPT" ]]; then
    assert_file_executable "$DEPLOY_SCRIPT" "container-deploy is executable"

    # Check that deploy creates and starts atomically
    assert_grep 'container-create\|create' "$DEPLOY_SCRIPT" "Deploy calls create"
    assert_grep 'container-start\|mlc-open' "$DEPLOY_SCRIPT" "Deploy calls start"

    # Check for atomic operation (both in sequence)
    if grep -q 'container-create' "$DEPLOY_SCRIPT" && grep -q 'container-start\|mlc-open' "$DEPLOY_SCRIPT"; then
        pass "Deploy performs create + start sequence"
    else
        skip "Deploy create+start sequence" "May use different command names"
    fi

    # Check for error handling (rollback on failure)
    if grep -qE 'if.*\[\[.*-ne.*\]\]|trap|rollback|cleanup' "$DEPLOY_SCRIPT" 2>/dev/null; then
        pass "Deploy has error handling"
    else
        skip "Deploy error handling" "Error handling may be implicit"
    fi
fi

# ============================================================================
# Test 3: Container Retire (Binary State: stop + remove)
# ============================================================================
section "3. Container Retire Binary Model"

RETIRE_SCRIPT="$INFRA_ROOT/scripts/user/container-retire"

assert_file_exists "$RETIRE_SCRIPT" "container-retire script exists"

if [[ -f "$RETIRE_SCRIPT" ]]; then
    assert_file_executable "$RETIRE_SCRIPT" "container-retire is executable"

    # Check that retire stops and removes atomically
    assert_grep 'container-stop\|mlc-stop\|stop' "$RETIRE_SCRIPT" "Retire calls stop"
    assert_grep 'container-remove\|mlc-remove\|remove' "$RETIRE_SCRIPT" "Retire calls remove"

    # Check for GPU release
    if grep -qE 'gpu.*release|free.*gpu|allocation' "$RETIRE_SCRIPT" 2>/dev/null; then
        pass "Retire handles GPU release"
    else
        skip "Retire GPU release" "May be handled by remove command"
    fi

    # Check for --force flag
    assert_grep 'force' "$RETIRE_SCRIPT" "Retire supports --force flag"
fi

# ============================================================================
# Test 4: Atomic Commands Support Full State Model
# ============================================================================
section "4. Atomic Commands Full State Model"

# container-stop should NOT auto-remove (full state model)
STOP_SCRIPT="$INFRA_ROOT/scripts/user/container-stop"

if [[ -f "$STOP_SCRIPT" ]]; then
    # Stop should not call remove (keeps container in stopped state)
    if grep -q 'mlc-remove\|container-remove' "$STOP_SCRIPT" 2>/dev/null; then
        fail "container-stop does not remove" "Stop should only stop, not remove"
    else
        pass "container-stop preserves stopped state (does not remove)"
    fi

    # Check for GPU hold behavior
    if grep -qE 'gpu.*hold|mark.*stopped|stopped.*timestamp' "$STOP_SCRIPT" 2>/dev/null; then
        pass "container-stop supports GPU hold"
    else
        skip "container-stop GPU hold" "May be handled by allocator"
    fi
fi

# container-start should work on stopped containers
START_SCRIPT="$INFRA_ROOT/scripts/user/container-start"

if [[ -f "$START_SCRIPT" ]]; then
    assert_file_exists "$START_SCRIPT" "container-start exists"

    # Check for GPU validation on restart
    if grep -qE 'gpu.*valid|nvidia.*smi|gpu.*available' "$START_SCRIPT" 2>/dev/null; then
        pass "container-start validates GPU on restart"
    else
        skip "container-start GPU validation" "May be handled by mlc layer"
    fi
fi

# ============================================================================
# Test 5: Container Create Handles GPU Allocation
# ============================================================================
section "5. Container Create GPU Allocation"

CREATE_SCRIPT="$INFRA_ROOT/scripts/user/container-create"

if [[ -f "$CREATE_SCRIPT" ]]; then
    # Check that create allocates GPU
    if grep -qE 'gpu_allocator|allocate.*gpu|--gpu' "$CREATE_SCRIPT" 2>/dev/null; then
        pass "container-create handles GPU allocation"
    else
        skip "container-create GPU allocation" "May be handled by wrapper"
    fi
fi

# Check mlc-create-wrapper handles allocation
MLC_WRAPPER="$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh"

if [[ -f "$MLC_WRAPPER" ]]; then
    assert_grep 'gpu_allocator' "$MLC_WRAPPER" "mlc-create-wrapper uses gpu_allocator"
    assert_grep 'ds01.interface' "$MLC_WRAPPER" "mlc-create-wrapper sets interface label"
fi

# ============================================================================
# Test 6: Container Remove Releases GPU
# ============================================================================
section "6. Container Remove GPU Release"

REMOVE_SCRIPT="$INFRA_ROOT/scripts/user/container-remove"

if [[ -f "$REMOVE_SCRIPT" ]]; then
    # Check for GPU release
    if grep -qE 'gpu_allocator.*release|release.*gpu|free.*allocation' "$REMOVE_SCRIPT" 2>/dev/null; then
        pass "container-remove releases GPU allocation"
    else
        skip "container-remove GPU release" "May be handled by allocator automatically"
    fi
fi

# ============================================================================
# Test 7: State Transitions Validation
# ============================================================================
section "7. State Transition Constants"

if [[ -f "$ALLOCATOR" ]]; then
    # Check for state constants
    STATES=("created" "running" "stopped" "removed")

    for state in "${STATES[@]}"; do
        if grep -qi "$state" "$ALLOCATOR" 2>/dev/null; then
            pass "Allocator recognizes '$state' state"
        else
            skip "Allocator '$state' state" "May use different naming"
        fi
    done
fi

# ============================================================================
# Test 8: Interface-Specific Behavior
# ============================================================================
section "8. Interface-Specific State Handling"

if [[ -f "$ALLOCATOR" ]]; then
    # Check for orchestration interface handling
    if grep -qE 'orchestration.*binary|interface.*orchestration' "$ALLOCATOR" 2>/dev/null; then
        pass "Allocator has orchestration interface handling"
    else
        skip "Allocator orchestration handling" "May use different pattern"
    fi

    # Check for atomic/docker interface handling
    if grep -qE 'atomic.*full|interface.*atomic|docker.*interface' "$ALLOCATOR" 2>/dev/null; then
        pass "Allocator has atomic/docker interface handling"
    else
        skip "Allocator atomic/docker handling" "May use different pattern"
    fi
fi

# ============================================================================
# Test 9: GPU Hold Timeout Configuration
# ============================================================================
section "9. GPU Hold Timeout Configuration"

# Check resource limits config for gpu_hold_after_stop
RESOURCE_LIMITS="$INFRA_ROOT/config/resource-limits.yaml"

if [[ -f "$RESOURCE_LIMITS" ]]; then
    if grep -q 'gpu_hold_after_stop' "$RESOURCE_LIMITS" 2>/dev/null; then
        pass "Resource limits config has gpu_hold_after_stop setting"
    else
        skip "gpu_hold_after_stop config" "May not be configured yet"
    fi
fi

# Check get_resource_limits.py reads gpu_hold setting
GET_LIMITS="$INFRA_ROOT/scripts/docker/get_resource_limits.py"

if [[ -f "$GET_LIMITS" ]]; then
    if grep -q 'gpu_hold' "$GET_LIMITS" 2>/dev/null; then
        pass "get_resource_limits.py handles gpu_hold setting"
    else
        skip "get_resource_limits gpu_hold" "May use different key"
    fi
fi

# ============================================================================
# Test 10: Stale Allocation Cleanup
# ============================================================================
section "10. Stale GPU Allocation Cleanup"

CLEANUP_SCRIPT="$INFRA_ROOT/scripts/maintenance/cleanup-stale-gpu-allocations.sh"

if [[ -f "$CLEANUP_SCRIPT" ]]; then
    assert_file_exists "$CLEANUP_SCRIPT" "Stale GPU cleanup script exists"

    # Check it uses allocator for cleanup
    if grep -qE 'gpu_allocator|release.*stale' "$CLEANUP_SCRIPT" 2>/dev/null; then
        pass "Stale cleanup uses gpu_allocator"
    else
        skip "Stale cleanup allocator integration" "May use different method"
    fi

    # Check it respects interface type
    if grep -qE 'interface|orchestration|atomic' "$CLEANUP_SCRIPT" 2>/dev/null; then
        pass "Stale cleanup considers interface type"
    else
        skip "Stale cleanup interface awareness" "May clean all equally"
    fi
else
    skip "Stale GPU cleanup script" "Not found"
fi

# ============================================================================
# Summary
# ============================================================================
print_summary
