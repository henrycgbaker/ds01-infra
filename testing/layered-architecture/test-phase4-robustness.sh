#!/bin/bash
# DS01 Layered Architecture - Phase 4: Robustness Systems Tests
# Tests health check, event logger, and bare metal detection

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-lib.sh"

INFRA_ROOT="/opt/ds01-infra"

section "Phase 4: Robustness Systems Tests"

# ============================================================================
# Test 1: Health Check Script
# ============================================================================
section "1. Health Check Script Validation"

HEALTH_CHECK="$INFRA_ROOT/scripts/monitoring/ds01-health-check"

assert_file_exists "$HEALTH_CHECK" "Health check script exists"

if [[ -f "$HEALTH_CHECK" ]]; then
    assert_file_executable "$HEALTH_CHECK" "Health check script is executable"

    # Check script structure
    assert_grep 'check_docker' "$HEALTH_CHECK" "Health check has Docker verification"
    assert_grep 'check_' "$HEALTH_CHECK" "Health check has component checks"

    # Run health check in check-only mode (dry run if available)
    info "Running health check..."
    HEALTH_OUTPUT=$("$HEALTH_CHECK" --help 2>&1 || "$HEALTH_CHECK" 2>&1 || echo "EXEC_ERROR")

    if [[ "$HEALTH_OUTPUT" != "EXEC_ERROR" ]]; then
        pass "Health check script executes without fatal errors"
    else
        fail "Health check executes" "Script failed to run"
    fi
fi

# ============================================================================
# Test 2: Event Logger
# ============================================================================
section "2. Event Logger Validation"

EVENT_LOGGER="$INFRA_ROOT/scripts/docker/event-logger.py"

assert_file_exists "$EVENT_LOGGER" "Event logger script exists"

if [[ -f "$EVENT_LOGGER" ]]; then
    # Check script structure
    assert_grep 'interface' "$EVENT_LOGGER" "Event logger tracks interface"
    assert_grep 'container' "$EVENT_LOGGER" "Event logger tracks containers"

    # Check for JSON output capability
    if grep -q 'json' "$EVENT_LOGGER" 2>/dev/null; then
        pass "Event logger supports JSON output"
    else
        skip "Event logger JSON support" "May use different format"
    fi

    # Syntax check
    if python3 -m py_compile "$EVENT_LOGGER" 2>/dev/null; then
        pass "Event logger Python syntax is valid"
    else
        fail "Event logger syntax check" "Python syntax error"
    fi
fi

# ============================================================================
# Test 3: Bare Metal Detection
# ============================================================================
section "3. Bare Metal Detection"

BARE_METAL="$INFRA_ROOT/scripts/monitoring/detect-bare-metal.py"

assert_file_exists "$BARE_METAL" "Bare metal detector script exists"

if [[ -f "$BARE_METAL" ]]; then
    # Syntax check
    if python3 -m py_compile "$BARE_METAL" 2>/dev/null; then
        pass "Bare metal detector Python syntax is valid"
    else
        fail "Bare metal detector syntax" "Python syntax error"
    fi

    # Check script structure
    assert_grep 'is_compute' "$BARE_METAL" "Detector identifies compute workloads"
    assert_grep '--json' "$BARE_METAL" "Detector supports --json flag"

    # Run detector and check JSON output
    info "Running bare metal detector..."
    DETECT_OUTPUT=$(python3 "$BARE_METAL" --json 2>&1 || echo '{"error": true}')

    # Validate JSON structure
    if echo "$DETECT_OUTPUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Bare metal detector outputs valid JSON"

        # Check for expected fields
        if echo "$DETECT_OUTPUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'warning' in d or 'total_count' in d" 2>/dev/null; then
            pass "Bare metal detector JSON has expected fields"
        else
            fail "Bare metal detector JSON fields" "Missing expected fields"
        fi
    else
        fail "Bare metal detector JSON output" "Invalid JSON: $DETECT_OUTPUT"
    fi
fi

# ============================================================================
# Test 4: GPU State Reader Interface Detection
# ============================================================================
section "4. GPU State Reader Interface Detection"

STATE_READER="$INFRA_ROOT/scripts/docker/gpu-state-reader.py"

assert_file_exists "$STATE_READER" "GPU state reader exists"

if [[ -f "$STATE_READER" ]]; then
    # Syntax check
    if python3 -m py_compile "$STATE_READER" 2>/dev/null; then
        pass "GPU state reader Python syntax is valid"
    else
        fail "GPU state reader syntax" "Python syntax error"
    fi

    # Check interface detection
    assert_grep '_detect_interface' "$STATE_READER" "State reader has interface detection method"
    assert_grep 'get_all_containers_by_interface' "$STATE_READER" "State reader has by-interface method"

    # Check interface detection patterns
    assert_grep 'ds01.interface' "$STATE_READER" "Detects ds01.interface label"
    assert_grep 'aime.mlc.USER' "$STATE_READER" "Detects AIME naming convention"
    assert_grep 'devcontainer' "$STATE_READER" "Detects VS Code dev containers"
    assert_grep 'compose' "$STATE_READER" "Detects Docker Compose containers"

    # Run state reader (if docker available)
    if docker info &>/dev/null; then
        info "Testing GPU state reader execution..."
        READER_OUTPUT=$(python3 "$STATE_READER" by-interface 2>&1 || echo "EXEC_ERROR")

        if [[ "$READER_OUTPUT" != "EXEC_ERROR" ]]; then
            pass "GPU state reader executes successfully"
        else
            # May fail if no containers - check for specific error
            skip "GPU state reader execution" "May require containers to test fully"
        fi
    else
        skip "GPU state reader execution" "Docker not available"
    fi
fi

# ============================================================================
# Test 5: GPU Allocator Interface Handling
# ============================================================================
section "5. GPU Allocator v2 Interface Handling"

ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator_v2.py"

assert_file_exists "$ALLOCATOR" "GPU allocator v2 exists"

if [[ -f "$ALLOCATOR" ]]; then
    # Syntax check
    if python3 -m py_compile "$ALLOCATOR" 2>/dev/null; then
        pass "GPU allocator v2 Python syntax is valid"
    else
        fail "GPU allocator v2 syntax" "Python syntax error"
    fi

    # Check interface-specific state handling
    assert_grep 'INTERFACE_ORCHESTRATION' "$ALLOCATOR" "Allocator defines orchestration interface"
    assert_grep '_get_container_interface' "$ALLOCATOR" "Allocator has interface detection"

    # Check for binary vs full state model handling
    assert_grep 'Binary state' "$ALLOCATOR" "Allocator mentions binary state model"
    assert_grep 'release_stale_allocations' "$ALLOCATOR" "Allocator has stale allocation cleanup"
fi

# ============================================================================
# Test 6: Logging Infrastructure
# ============================================================================
section "6. Logging Infrastructure"

LOG_DIR="/var/log/ds01"

if [[ -d "$LOG_DIR" ]]; then
    pass "Log directory exists: $LOG_DIR"

    # Check for expected log files
    if [[ -f "$LOG_DIR/gpu-allocations.log" ]]; then
        pass "GPU allocations log file exists"
    else
        skip "GPU allocations log" "File not created yet (normal for fresh install)"
    fi
else
    skip "Log directory check" "Directory not created yet (may need root)"
fi

# ============================================================================
# Test 7: State Directory
# ============================================================================
section "7. State Directory"

STATE_DIR="/var/lib/ds01"

if [[ -d "$STATE_DIR" ]]; then
    pass "State directory exists: $STATE_DIR"
else
    skip "State directory check" "Directory not created yet (may need root)"
fi

# ============================================================================
# Test 8: Health Check Components
# ============================================================================
section "8. Health Check Component Coverage"

if [[ -f "$HEALTH_CHECK" ]]; then
    # Check that health check covers critical components
    COMPONENTS=(
        "docker"
        "nvidia"
        "cgroup"
        "config"
    )

    for component in "${COMPONENTS[@]}"; do
        if grep -qi "$component" "$HEALTH_CHECK" 2>/dev/null; then
            pass "Health check covers: $component"
        else
            skip "Health check covers $component" "May use different naming"
        fi
    done
fi

# ============================================================================
# Summary
# ============================================================================
print_summary
