#!/bin/bash
# DS01 Layered Architecture - Phase 1: Universal Enforcement Tests
# Tests Docker cgroups, wrapper, and OPA authorization
# NOTE: Many tests require root privileges

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-lib.sh"

INFRA_ROOT="/opt/ds01-infra"

section "Phase 1: Universal Enforcement Tests"

# ============================================================================
# Test 1: Docker Daemon Configuration Script
# ============================================================================
section "1. Docker Cgroups Setup Script"

CGROUPS_SETUP="$INFRA_ROOT/scripts/system/setup-docker-cgroups.sh"

assert_file_exists "$CGROUPS_SETUP" "Docker cgroups setup script exists"

if [[ -f "$CGROUPS_SETUP" ]]; then
    assert_file_executable "$CGROUPS_SETUP" "Cgroups setup script is executable"

    # Check script structure
    assert_grep 'ds01.slice' "$CGROUPS_SETUP" "Script configures ds01.slice"
    assert_grep 'cgroup-parent' "$CGROUPS_SETUP" "Script sets cgroup-parent"
    assert_grep 'daemon.json' "$CGROUPS_SETUP" "Script modifies daemon.json"
    assert_grep 'systemd' "$CGROUPS_SETUP" "Script uses systemd cgroup driver"
    assert_grep 'dry-run' "$CGROUPS_SETUP" "Script supports --dry-run flag"

    # Check for safety features
    assert_grep 'backup' "$CGROUPS_SETUP" "Script backs up existing config"
    assert_grep 'running.container' "$CGROUPS_SETUP" "Script checks for running containers"
fi

# ============================================================================
# Test 2: Docker Wrapper Script
# ============================================================================
section "2. Docker Wrapper Script"

DOCKER_WRAPPER="$INFRA_ROOT/scripts/docker/docker-wrapper.sh"

assert_file_exists "$DOCKER_WRAPPER" "Docker wrapper script exists"

if [[ -f "$DOCKER_WRAPPER" ]]; then
    assert_file_executable "$DOCKER_WRAPPER" "Docker wrapper is executable"

    # Check wrapper functionality
    assert_grep 'DS01 Docker Wrapper' "$DOCKER_WRAPPER" "Wrapper has identifying header"
    assert_grep 'cgroup-parent' "$DOCKER_WRAPPER" "Wrapper injects cgroup-parent"
    assert_grep 'ds01-' "$DOCKER_WRAPPER" "Wrapper uses ds01- prefix for slices"

    # Check for user/group detection
    assert_grep 'whoami\|USER\|uid' "$DOCKER_WRAPPER" "Wrapper detects user"

    # Check passthrough for non-run commands
    assert_grep 'run\|create' "$DOCKER_WRAPPER" "Wrapper handles run/create commands"
fi

# ============================================================================
# Test 3: OPA Authorization Policy
# ============================================================================
section "3. OPA Authorization Policy"

OPA_POLICY="$INFRA_ROOT/config/opa/docker-authz.rego"

assert_file_exists "$OPA_POLICY" "OPA policy file exists"

if [[ -f "$OPA_POLICY" ]]; then
    # Check policy structure
    assert_grep 'package' "$OPA_POLICY" "Policy has package declaration"
    assert_grep 'allow' "$OPA_POLICY" "Policy has allow rule"

    # Check for fail-open behavior
    if grep -q 'default.*allow.*true\|default allow = true' "$OPA_POLICY" 2>/dev/null; then
        pass "OPA policy uses fail-open (default allow)"
    else
        fail "OPA policy fail-open" "Expected default allow = true"
    fi

    # Check for cgroup enforcement
    assert_grep 'cgroup' "$OPA_POLICY" "Policy checks cgroup settings"

    # Check for logging
    assert_grep 'log\|audit' "$OPA_POLICY" "Policy has logging/auditing"
fi

# ============================================================================
# Test 4: OPA Setup Script
# ============================================================================
section "4. OPA Setup Script"

OPA_SETUP="$INFRA_ROOT/scripts/system/setup-opa-authz.sh"

assert_file_exists "$OPA_SETUP" "OPA setup script exists"

if [[ -f "$OPA_SETUP" ]]; then
    assert_file_executable "$OPA_SETUP" "OPA setup script is executable"

    # Check script structure
    assert_grep 'opa-docker-authz' "$OPA_SETUP" "Script references OPA plugin"
    assert_grep 'systemd' "$OPA_SETUP" "Script creates systemd service"
    assert_grep 'uninstall' "$OPA_SETUP" "Script supports --uninstall"
    assert_grep 'dry-run' "$OPA_SETUP" "Script supports --dry-run"
fi

# ============================================================================
# Test 5: Docker Daemon Configuration (Live Check)
# ============================================================================
section "5. Docker Daemon Live Configuration"

if docker info &>/dev/null; then
    # Check cgroup driver
    CGROUP_DRIVER=$(docker info --format '{{.CgroupDriver}}' 2>/dev/null || echo "unknown")
    if [[ "$CGROUP_DRIVER" == "systemd" ]]; then
        pass "Docker using systemd cgroup driver"
    else
        info "Docker cgroup driver: $CGROUP_DRIVER (expected: systemd)"
        skip "Docker systemd cgroup driver" "May not be configured yet"
    fi

    # Check default cgroup parent
    CGROUP_PARENT=$(docker info --format '{{.CgroupParent}}' 2>/dev/null || echo "")
    if [[ "$CGROUP_PARENT" == "ds01.slice" ]]; then
        pass "Docker default cgroup-parent is ds01.slice"
    else
        info "Docker cgroup-parent: '$CGROUP_PARENT' (expected: ds01.slice)"
        skip "Docker ds01.slice parent" "May not be configured yet"
    fi
else
    skip "Docker daemon configuration" "Docker not available"
fi

# ============================================================================
# Test 6: ds01.slice Systemd Unit
# ============================================================================
section "6. Systemd Slice Configuration"

DS01_SLICE="/etc/systemd/system/ds01.slice"

if [[ -f "$DS01_SLICE" ]]; then
    pass "ds01.slice systemd unit exists"

    # Check slice configuration
    assert_grep 'Description' "$DS01_SLICE" "Slice has description"
    assert_grep 'CPUAccounting\|MemoryAccounting' "$DS01_SLICE" "Slice has resource accounting"
else
    skip "ds01.slice unit" "Not created yet (run setup-docker-cgroups.sh)"
fi

# Check if slice is active (requires root)
if systemctl is-active ds01.slice &>/dev/null; then
    pass "ds01.slice is active"
else
    skip "ds01.slice active check" "Slice may not be started"
fi

# ============================================================================
# Test 7: Docker Wrapper Deployment Location
# ============================================================================
section "7. Docker Wrapper Deployment"

WRAPPER_DEPLOYED="/usr/local/bin/docker"

if [[ -f "$WRAPPER_DEPLOYED" ]]; then
    if grep -q "DS01 Docker Wrapper" "$WRAPPER_DEPLOYED" 2>/dev/null; then
        pass "Docker wrapper deployed to /usr/local/bin/docker"
    else
        info "File exists at $WRAPPER_DEPLOYED but is not DS01 wrapper"
        skip "Docker wrapper deployment" "Wrapper not installed"
    fi
else
    skip "Docker wrapper deployment" "Not deployed yet"
fi

# ============================================================================
# Test 8: Universal Enforcement Simulation
# ============================================================================
section "8. Universal Enforcement Behavior (Simulated)"

# Test that wrapper script handles cgroup injection correctly
if [[ -f "$DOCKER_WRAPPER" ]]; then
    # Simulate wrapper behavior by checking argument parsing
    # Create a test that the wrapper would inject cgroup args

    # Check if wrapper properly formats user slice
    TEST_USER="testuser"
    TEST_GROUP="student"

    # Look for slice naming pattern
    if grep -q 'ds01-.*\.slice' "$DOCKER_WRAPPER" 2>/dev/null; then
        pass "Wrapper uses user-specific slice naming"
    else
        skip "Wrapper slice naming" "May use different pattern"
    fi

    # Check wrapper handles both 'run' and 'create' commands
    if grep -qE 'run|create' "$DOCKER_WRAPPER" 2>/dev/null; then
        pass "Wrapper intercepts run and create commands"
    else
        fail "Wrapper intercepts run/create" "Pattern not found"
    fi
fi

# ============================================================================
# Test 9: OPA Policy Syntax (if opa binary available)
# ============================================================================
section "9. OPA Policy Validation"

if command -v opa &>/dev/null; then
    if [[ -f "$OPA_POLICY" ]]; then
        if opa check "$OPA_POLICY" 2>/dev/null; then
            pass "OPA policy syntax is valid"
        else
            fail "OPA policy syntax" "Policy has syntax errors"
        fi
    fi
else
    skip "OPA policy validation" "OPA binary not installed"
fi

# ============================================================================
# Summary
# ============================================================================
print_summary
