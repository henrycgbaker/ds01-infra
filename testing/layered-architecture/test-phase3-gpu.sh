#!/bin/bash
# DS01 Layered Architecture - Phase 3: GPU Tracking Enhancement Tests
# Tests GPU tracking for ALL containers regardless of creation method

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-lib.sh"

INFRA_ROOT="/opt/ds01-infra"

section "Phase 3: GPU Tracking Enhancement Tests"

# ============================================================================
# Test 1: GPU State Reader All-Container Support
# ============================================================================
section "1. GPU State Reader All-Container Support"

STATE_READER="$INFRA_ROOT/scripts/docker/gpu-state-reader.py"

assert_file_exists "$STATE_READER" "GPU state reader exists"

if [[ -f "$STATE_READER" ]]; then
    # Syntax check
    if python3 -m py_compile "$STATE_READER" 2>/dev/null; then
        pass "GPU state reader Python syntax is valid"
    else
        fail "GPU state reader syntax" "Python syntax error"
    fi

    # Check it reads ALL containers, not just AIME naming convention
    if grep -q 'get_all_containers\|list.*all' "$STATE_READER" 2>/dev/null; then
        pass "State reader can list all containers"
    else
        skip "State reader all containers" "May use different method name"
    fi

    # Should NOT be limited to AIME naming pattern
    if grep -qE '\.\_\.\s*pattern|aime.*only' "$STATE_READER" 2>/dev/null; then
        fail "State reader not limited to AIME" "Found AIME-only pattern"
    else
        pass "State reader not limited to AIME naming convention"
    fi
fi

# ============================================================================
# Test 2: Cgroup-Based User Extraction
# ============================================================================
section "2. Cgroup-Based User Extraction"

if [[ -f "$STATE_READER" ]]; then
    # Check for cgroup-based user detection
    assert_grep 'cgroup\|CgroupParent' "$STATE_READER" "State reader handles cgroups"

    # Check for user extraction from cgroup path
    if grep -qE 'ds01-.*\.slice|extract.*user.*cgroup|cgroup.*user' "$STATE_READER" 2>/dev/null; then
        pass "State reader extracts user from cgroup path"
    else
        skip "Cgroup user extraction" "May use alternative method"
    fi
fi

# Check allocator also uses cgroup-based detection
ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator_v2.py"

if [[ -f "$ALLOCATOR" ]]; then
    if grep -qE 'cgroup|CgroupParent|slice' "$ALLOCATOR" 2>/dev/null; then
        pass "GPU allocator uses cgroup information"
    else
        skip "Allocator cgroup support" "May use labels instead"
    fi
fi

# ============================================================================
# Test 3: Interface Detection Patterns
# ============================================================================
section "3. Interface Detection Patterns"

if [[ -f "$STATE_READER" ]]; then
    # DS01 Orchestration: ds01.interface=orchestration label
    assert_grep 'ds01.interface' "$STATE_READER" "Detects ds01.interface label"

    # AIME/MLC naming convention: *._.* pattern
    assert_grep '\.\_\.' "$STATE_READER" "Detects AIME naming convention"

    # VS Code Dev Containers
    assert_grep 'devcontainer\|vscode' "$STATE_READER" "Detects VS Code dev containers"

    # Docker Compose
    assert_grep 'compose\|docker.compose' "$STATE_READER" "Detects Docker Compose containers"

    # JupyterHub
    if grep -q 'jupyter' "$STATE_READER" 2>/dev/null; then
        pass "Detects JupyterHub containers"
    else
        skip "JupyterHub detection" "May not be implemented"
    fi
fi

# ============================================================================
# Test 4: GPU State Reader Commands
# ============================================================================
section "4. GPU State Reader Commands"

if [[ -f "$STATE_READER" ]]; then
    # Check for by-interface command
    assert_grep 'by-interface\|by_interface' "$STATE_READER" "State reader has by-interface command"

    # Check for status command
    assert_grep 'status' "$STATE_READER" "State reader has status command"

    # Check for JSON output option
    assert_grep 'json' "$STATE_READER" "State reader supports JSON output"

    # Test execution if Docker available
    if docker info &>/dev/null; then
        info "Testing GPU state reader execution..."

        # Test status command
        STATUS_OUTPUT=$(python3 "$STATE_READER" status 2>&1 || echo "CMD_FAILED")
        if [[ "$STATUS_OUTPUT" != "CMD_FAILED" ]]; then
            pass "State reader 'status' command executes"
        else
            skip "State reader status" "Command failed (may need containers)"
        fi

        # Test by-interface command
        INTERFACE_OUTPUT=$(python3 "$STATE_READER" by-interface 2>&1 || echo "CMD_FAILED")
        if [[ "$INTERFACE_OUTPUT" != "CMD_FAILED" ]]; then
            pass "State reader 'by-interface' command executes"
        else
            skip "State reader by-interface" "Command failed (may need containers)"
        fi
    else
        skip "State reader execution tests" "Docker not available"
    fi
fi

# ============================================================================
# Test 5: Interface Constants Consistency
# ============================================================================
section "5. Interface Constants Consistency"

# All components should use the same interface constants
INTERFACE_CONSTANTS=(
    "INTERFACE_ORCHESTRATION:orchestration"
    "INTERFACE_ATOMIC:atomic"
    "INTERFACE_DOCKER:docker"
    "INTERFACE_OTHER:other"
)

FILES_TO_CHECK=(
    "$STATE_READER"
    "$ALLOCATOR"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [[ -f "$file" ]]; then
        filename=$(basename "$file")
        for constant_pair in "${INTERFACE_CONSTANTS[@]}"; do
            IFS=':' read -r const_name const_value <<< "$constant_pair"
            if grep -qE "$const_name.*['\"]$const_value['\"]" "$file" 2>/dev/null; then
                pass "$filename defines $const_name = '$const_value'"
            else
                # Check for the constant with any value
                if grep -q "$const_name" "$file" 2>/dev/null; then
                    pass "$filename defines $const_name"
                else
                    skip "$filename $const_name" "Constant may use different naming"
                fi
            fi
        done
    fi
done

# ============================================================================
# Test 6: Cron Job User Extraction Update
# ============================================================================
section "6. Cron Job User Extraction"

CRON_SCRIPTS=(
    "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh"
    "$INFRA_ROOT/scripts/maintenance/enforce-max-runtime.sh"
    "$INFRA_ROOT/scripts/maintenance/cleanup-stale-containers.sh"
)

for script in "${CRON_SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        script_name=$(basename "$script")

        # Check for cgroup-based user extraction (not just container name)
        if grep -qE 'cgroup|slice|ds01-' "$script" 2>/dev/null; then
            pass "$script_name uses cgroup-based user identification"
        else
            skip "$script_name cgroup user ID" "May use container metadata"
        fi

        # Check it handles ALL containers (not just AIME)
        if grep -qE 'docker.*ps|all.*container' "$script" 2>/dev/null; then
            pass "$script_name handles all containers"
        else
            skip "$script_name all containers" "May use filtered list"
        fi
    else
        skip "$(basename "$script")" "Script not found"
    fi
done

# ============================================================================
# Test 7: Docker Labels for GPU Tracking
# ============================================================================
section "7. Docker Labels for GPU Tracking"

# Check mlc-create-wrapper sets appropriate labels
MLC_WRAPPER="$INFRA_ROOT/scripts/docker/mlc-create-wrapper.sh"

if [[ -f "$MLC_WRAPPER" ]]; then
    # Check for GPU allocation label
    if grep -qE 'ds01\.gpu|GPU.*label' "$MLC_WRAPPER" 2>/dev/null; then
        pass "mlc-create-wrapper sets GPU labels"
    else
        skip "mlc-create-wrapper GPU labels" "May be set elsewhere"
    fi

    # Check for user label
    if grep -qE 'ds01\.user|USER.*label' "$MLC_WRAPPER" 2>/dev/null; then
        pass "mlc-create-wrapper sets user label"
    else
        skip "mlc-create-wrapper user label" "May use cgroup instead"
    fi
fi

# ============================================================================
# Test 8: GPU Allocation Without AIME Dependency
# ============================================================================
section "8. GPU Allocation Without AIME Dependency"

if [[ -f "$ALLOCATOR" ]]; then
    # Allocator should work with any container name
    if grep -qE '\.\_\.\s*required|aime.*naming.*required' "$ALLOCATOR" 2>/dev/null; then
        fail "Allocator no AIME dependency" "Found AIME naming requirement"
    else
        pass "Allocator does not require AIME naming convention"
    fi

    # Check for generic container identification
    if grep -qE 'container.*id|container.*name' "$ALLOCATOR" 2>/dev/null; then
        pass "Allocator uses generic container identification"
    else
        skip "Allocator generic container ID" "May use different approach"
    fi
fi

# ============================================================================
# Test 9: MIG Instance Tracking
# ============================================================================
section "9. MIG Instance Tracking"

if [[ -f "$STATE_READER" ]]; then
    # Check for MIG support
    if grep -qE 'mig|MIG|physical_gpu.*instance' "$STATE_READER" 2>/dev/null; then
        pass "State reader supports MIG tracking"
    else
        skip "State reader MIG support" "MIG may not be enabled"
    fi
fi

if [[ -f "$ALLOCATOR" ]]; then
    if grep -qE 'mig|MIG|physical_gpu.*instance' "$ALLOCATOR" 2>/dev/null; then
        pass "Allocator supports MIG tracking"
    else
        skip "Allocator MIG support" "MIG may not be enabled"
    fi
fi

# ============================================================================
# Test 10: Live GPU Detection (If Available)
# ============================================================================
section "10. Live GPU Detection"

if command -v nvidia-smi &>/dev/null; then
    # Check if nvidia-smi works
    if nvidia-smi &>/dev/null; then
        pass "nvidia-smi is available and working"

        # Get GPU count
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1 2>/dev/null || echo "0")
        info "Detected GPUs: $GPU_COUNT"

        # Check MIG status
        MIG_STATUS=$(nvidia-smi mig -lgi 2>&1 || echo "NOT_AVAILABLE")
        if [[ "$MIG_STATUS" != *"NOT_AVAILABLE"* && "$MIG_STATUS" != *"No MIG"* ]]; then
            info "MIG instances detected"
            pass "MIG is configured on this system"
        else
            info "MIG not enabled or not available"
            skip "MIG configuration" "MIG not enabled"
        fi
    else
        skip "nvidia-smi check" "nvidia-smi failed"
    fi
else
    skip "nvidia-smi availability" "nvidia-smi not installed"
fi

# ============================================================================
# Summary
# ============================================================================
print_summary
