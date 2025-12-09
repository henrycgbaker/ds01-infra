#!/bin/bash
# DS01 Layered Architecture - Phase 5: Conditional Output System Tests
# Tests context detection, environment variable handling, and conditional output

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-lib.sh"

INFRA_ROOT="/opt/ds01-infra"
CONTEXT_LIB="$INFRA_ROOT/scripts/lib/ds01-context.sh"

section "Phase 5: Conditional Output System Tests"

# ============================================================================
# Test 1: Context Library Existence and Structure
# ============================================================================
section "1. Context Library Validation"

assert_file_exists "$CONTEXT_LIB" "Context library exists"

# Check library has required functions
assert_grep "ds01_is_orchestration_context" "$CONTEXT_LIB" "Library has ds01_is_orchestration_context function"
assert_grep "ds01_get_context" "$CONTEXT_LIB" "Library has ds01_get_context function"
assert_grep "ds01_should_show_next_steps" "$CONTEXT_LIB" "Library has ds01_should_show_next_steps function"
assert_grep "DS01_CONTEXT" "$CONTEXT_LIB" "Library references DS01_CONTEXT variable"

# ============================================================================
# Test 2: Context Library Function Behavior
# ============================================================================
section "2. Context Library Function Tests"

# Source the library for testing
source "$CONTEXT_LIB"

# Test default context (should be atomic when no env var set)
unset DS01_CONTEXT
unset DS01_INTERFACE
result=$(ds01_get_context)
if [[ "$result" == "atomic" || "$result" == "standalone" ]]; then
    pass "Default context is atomic/standalone when no env var"
else
    fail "Default context is atomic/standalone" "Got: $result"
fi

# Test orchestration context detection
export DS01_CONTEXT="orchestration"
if ds01_is_orchestration_context; then
    pass "ds01_is_orchestration_context returns true when DS01_CONTEXT=orchestration"
else
    fail "ds01_is_orchestration_context returns true" "Returned false"
fi

# Test next steps suppression in orchestration context
if ! ds01_should_show_next_steps; then
    pass "ds01_should_show_next_steps returns false in orchestration context"
else
    fail "ds01_should_show_next_steps returns false in orchestration" "Returned true"
fi

# Reset and test atomic context
unset DS01_CONTEXT
if ds01_should_show_next_steps; then
    pass "ds01_should_show_next_steps returns true in atomic/standalone context"
else
    fail "ds01_should_show_next_steps returns true in atomic context" "Returned false"
fi

# ============================================================================
# Test 3: Orchestrator Scripts Set Context
# ============================================================================
section "3. Orchestrator Context Setting"

# Check container-deploy sets orchestration context
DEPLOY_SCRIPT="$INFRA_ROOT/scripts/user/orchestrators/container-deploy"
if [[ -f "$DEPLOY_SCRIPT" ]]; then
    assert_grep 'DS01_CONTEXT.*orchestration' "$DEPLOY_SCRIPT" "container-deploy sets DS01_CONTEXT=orchestration"
    assert_grep 'source.*/ds01-context.sh' "$DEPLOY_SCRIPT" "container-deploy sources context library"
else
    skip "container-deploy sets context" "Script not found"
fi

# Check container-retire sets orchestration context
RETIRE_SCRIPT="$INFRA_ROOT/scripts/user/orchestrators/container-retire"
if [[ -f "$RETIRE_SCRIPT" ]]; then
    assert_grep 'DS01_CONTEXT.*orchestration' "$RETIRE_SCRIPT" "container-retire sets DS01_CONTEXT=orchestration"
    assert_grep 'source.*/ds01-context.sh' "$RETIRE_SCRIPT" "container-retire sources context library"
else
    skip "container-retire sets context" "Script not found"
fi

# Check project-init (L4 wizard) sets orchestration context
PROJECT_INIT="$INFRA_ROOT/scripts/user/project-init"
if [[ -f "$PROJECT_INIT" ]]; then
    assert_grep 'DS01_CONTEXT.*orchestration' "$PROJECT_INIT" "project-init sets DS01_CONTEXT=orchestration"
    assert_grep 'source.*/ds01-context.sh' "$PROJECT_INIT" "project-init sources context library"
else
    skip "project-init sets context" "Script not found"
fi

# Check user-setup (L4 wizard) sets orchestration context
USER_SETUP="$INFRA_ROOT/scripts/user/user-setup"
if [[ -f "$USER_SETUP" ]]; then
    assert_grep 'DS01_CONTEXT.*orchestration' "$USER_SETUP" "user-setup sets DS01_CONTEXT=orchestration"
    assert_grep 'source.*/ds01-context.sh' "$USER_SETUP" "user-setup sources context library"
else
    skip "user-setup sets context" "Script not found"
fi

# ============================================================================
# Test 4: Atomic Commands Source Context Library
# ============================================================================
section "4. Atomic Commands Context Library Integration"

ATOMIC_COMMANDS=(
    "container-create"
    "container-start"
    "container-stop"
    "container-run"
    "container-remove"
)

for cmd in "${ATOMIC_COMMANDS[@]}"; do
    script_path="$INFRA_ROOT/scripts/user/$cmd"
    if [[ -f "$script_path" ]]; then
        assert_grep 'ds01-context.sh' "$script_path" "$cmd sources context library"
    else
        skip "$cmd sources context library" "Script not found: $script_path"
    fi
done

# ============================================================================
# Test 5: L2 Atomic Command Headers Updated
# ============================================================================
section "5. L2 Atomic Command Headers"

for cmd in "${ATOMIC_COMMANDS[@]}"; do
    script_path="$INFRA_ROOT/scripts/user/$cmd"
    if [[ -f "$script_path" ]]; then
        # Check for L2 Atomic Command header
        if grep -q "L2 Atomic Command" "$script_path" 2>/dev/null; then
            pass "$cmd has L2 Atomic Command header"
        else
            # Check for older "Tier 2" header as fallback
            if grep -q "Tier 2" "$script_path" 2>/dev/null; then
                pass "$cmd has Tier 2 header (legacy)"
            else
                fail "$cmd has L2/Tier 2 header" "No layer identifier found"
            fi
        fi
    else
        skip "$cmd header check" "Script not found"
    fi
done

# ============================================================================
# Test 6: Context Environment Variable Propagation
# ============================================================================
section "6. Environment Variable Propagation"

# Test that context propagates through export
export DS01_CONTEXT="orchestration"
export DS01_INTERFACE="orchestration"

# Run a subshell and check context
SUBSHELL_CONTEXT=$(bash -c 'source '"$CONTEXT_LIB"'; ds01_get_context' 2>/dev/null)
if [[ "$SUBSHELL_CONTEXT" == "orchestration" ]]; then
    pass "DS01_CONTEXT propagates to subshells"
else
    fail "DS01_CONTEXT propagates to subshells" "Got: $SUBSHELL_CONTEXT"
fi

# Test with child process
CHILD_RESULT=$(bash -c 'source '"$CONTEXT_LIB"'; ds01_is_orchestration_context && echo yes || echo no' 2>/dev/null)
if [[ "$CHILD_RESULT" == "yes" ]]; then
    pass "Orchestration context propagates to child processes"
else
    fail "Orchestration context propagates to child processes" "Got: $CHILD_RESULT"
fi

# Clean up
unset DS01_CONTEXT
unset DS01_INTERFACE

# ============================================================================
# Test 7: Context Affects Script Output (Simulated)
# ============================================================================
section "7. Context-Conditional Output Behavior"

# Create a simple test script that uses context
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" << 'EOF'
#!/bin/bash
source /opt/ds01-infra/scripts/lib/ds01-context.sh 2>/dev/null || true

echo "Running operation..."

# Conditional "Next steps" output
if ds01_should_show_next_steps 2>/dev/null; then
    echo "Next steps:"
    echo "  - Run container-list to see status"
    echo "  - Run container-run to enter"
fi
echo "Done."
EOF
chmod +x "$TEST_SCRIPT"

# Test in standalone mode (should show next steps)
unset DS01_CONTEXT
STANDALONE_OUTPUT=$("$TEST_SCRIPT" 2>&1)
if [[ "$STANDALONE_OUTPUT" == *"Next steps:"* ]]; then
    pass "Standalone mode shows 'Next steps' output"
else
    fail "Standalone mode shows 'Next steps'" "Output missing 'Next steps'"
fi

# Test in orchestration mode (should NOT show next steps)
export DS01_CONTEXT="orchestration"
ORCH_OUTPUT=$("$TEST_SCRIPT" 2>&1)
if [[ "$ORCH_OUTPUT" != *"Next steps:"* ]]; then
    pass "Orchestration mode suppresses 'Next steps' output"
else
    fail "Orchestration mode suppresses 'Next steps'" "Output contains 'Next steps'"
fi

# Cleanup
rm -f "$TEST_SCRIPT"
unset DS01_CONTEXT

# ============================================================================
# Test 8: Interface Label Constants
# ============================================================================
section "8. Interface Constants Consistency"

# Check GPU state reader has interface constants
STATE_READER="$INFRA_ROOT/scripts/docker/gpu-state-reader.py"
if [[ -f "$STATE_READER" ]]; then
    assert_grep 'INTERFACE_ORCHESTRATION' "$STATE_READER" "gpu-state-reader defines INTERFACE_ORCHESTRATION"
    assert_grep 'INTERFACE_ATOMIC' "$STATE_READER" "gpu-state-reader defines INTERFACE_ATOMIC"
    assert_grep 'INTERFACE_DOCKER' "$STATE_READER" "gpu-state-reader defines INTERFACE_DOCKER"
    assert_grep 'INTERFACE_OTHER' "$STATE_READER" "gpu-state-reader defines INTERFACE_OTHER"
else
    skip "Interface constants in gpu-state-reader" "File not found"
fi

# Check GPU allocator v2 has interface constants
ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator_v2.py"
if [[ -f "$ALLOCATOR" ]]; then
    assert_grep 'INTERFACE_ORCHESTRATION' "$ALLOCATOR" "gpu_allocator_v2 defines INTERFACE_ORCHESTRATION"
    assert_grep 'INTERFACE_ATOMIC' "$ALLOCATOR" "gpu_allocator_v2 defines INTERFACE_ATOMIC"
else
    skip "Interface constants in gpu_allocator_v2" "File not found"
fi

# ============================================================================
# Summary
# ============================================================================
print_summary
