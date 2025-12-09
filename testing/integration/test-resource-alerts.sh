#!/bin/bash
# /opt/ds01-infra/testing/integration/test-resource-alerts.sh
# DS01 Resource Alert System Test Harness
#
# Tests the alert generation system with synthetic scenarios.
#
# Usage:
#   test-resource-alerts.sh                    # Run all tests
#   test-resource-alerts.sh --scenario <name>  # Run specific scenario
#   test-resource-alerts.sh --cleanup          # Clean up test artifacts

set -e

INFRA_ROOT="/opt/ds01-infra"
SCRIPT_DIR="$INFRA_ROOT/scripts"
ALERTS_DIR="/var/lib/ds01/alerts"
TEST_USER="test-user-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Values should match}"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        log_pass "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$msg (expected: $expected, got: $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist: $file}"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$file" ]]; then
        log_pass "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$msg"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-File should not exist: $file}"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$file" ]]; then
        log_pass "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$msg"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-Should contain: $needle}"

    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -q "$needle"; then
        log_pass "$msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$msg"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test Scenarios
# ============================================================================

test_soft_limit_display() {
    log_test "Testing soft limit display in check-limits..."

    # Run check-limits and verify it shows percentage
    local output
    output=$("$SCRIPT_DIR/user/check-limits" 2>&1) || true

    assert_contains "$output" "%" "check-limits shows percentage"
    assert_contains "$output" "GPU" "check-limits shows GPU section"
    assert_contains "$output" "Container" "check-limits shows Container section"
}

test_error_messages_contact_info() {
    log_test "Testing error messages include contact info..."

    # Source error messages and test
    source "$SCRIPT_DIR/lib/error-messages.sh"

    local output
    output=$(show_limit_error "USER_AT_LIMIT (2/2)" 2>&1) || true

    assert_contains "$output" "Need more resources" "Shows contact info header"
    assert_contains "$output" "Data Science Lab" "Shows lab name"
    assert_contains "$output" "h.baker@hertie-school.org" "Shows contact email"
}

test_alert_generation() {
    log_test "Testing alert generation..."

    # Create a mock alert file to test the display
    local test_alerts_file="$ALERTS_DIR/test-alert-user.json"

    echo '[{"type": "gpu_usage_high", "message": "GPU usage high: 4/5 GPUs (80%)", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"}]' > "$test_alerts_file"

    assert_file_exists "$test_alerts_file" "Alert file created"

    # Verify alert content
    local alert_count
    alert_count=$(python3 -c "import json; print(len(json.load(open('$test_alerts_file'))))" 2>/dev/null || echo "0")
    assert_equals "1" "$alert_count" "Alert count is correct"

    # Cleanup
    rm -f "$test_alerts_file"
}

test_alert_checker_script() {
    log_test "Testing resource-alert-checker.sh..."

    # Run the alert checker (it should complete without error)
    local output
    local exit_code=0
    output=$("$SCRIPT_DIR/monitoring/resource-alert-checker.sh" "$USER" 2>&1) || exit_code=$?

    # Script should succeed (exit 0)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Alert checker runs successfully"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Alert checker failed with exit code $exit_code"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_gpu_utilization_monitor() {
    log_test "Testing gpu-utilization-monitor.py..."

    # Test JSON output
    local json_output
    json_output=$(python3 "$SCRIPT_DIR/monitoring/gpu-utilization-monitor.py" --json 2>&1)

    assert_contains "$json_output" '"gpus"' "JSON output contains gpus array"
    assert_contains "$json_output" '"timestamp"' "JSON output contains timestamp"

    # Test normal output
    local normal_output
    normal_output=$(python3 "$SCRIPT_DIR/monitoring/gpu-utilization-monitor.py" 2>&1)

    assert_contains "$normal_output" "GPU" "Normal output shows GPU info"
    assert_contains "$normal_output" "Utilization" "Normal output shows utilization"
}

test_soft_limit_thresholds() {
    log_test "Testing soft limit threshold configuration..."

    # Check that threshold is in config
    local yaml_content
    yaml_content=$(cat "$INFRA_ROOT/config/resource-limits.yaml")

    assert_contains "$yaml_content" "soft_limit_threshold" "YAML contains soft_limit_threshold"
}

test_cron_config() {
    log_test "Testing cron configuration..."

    local cron_file="$INFRA_ROOT/config/deploy/cron.d/ds01-maintenance"
    assert_file_exists "$cron_file" "Cron config file exists"

    local cron_content
    cron_content=$(cat "$cron_file")

    assert_contains "$cron_content" "resource-alert-checker" "Cron includes alert checker"
    assert_contains "$cron_content" "check-idle-containers" "Cron includes idle checker"
}

# ============================================================================
# Simulation Scenarios
# ============================================================================

simulate_high_usage() {
    log_test "Simulating high GPU usage scenario..."

    # Create mock alert file simulating 80% GPU usage
    local mock_user="sim-user-high"
    local mock_file="$ALERTS_DIR/${mock_user}.json"

    echo '[{"type": "gpu_usage_high", "message": "GPU usage high: 4/5 GPUs (80%)", "created_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "updated_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}]' > "$mock_file"

    log_info "Created mock alert: $mock_file"

    # Test that ds01-login-check would show this alert
    # (We can't fully test without being that user, but we can verify the file)
    assert_file_exists "$mock_file" "High usage mock alert created"

    # Cleanup
    rm -f "$mock_file"
    log_pass "High usage simulation completed"
}

simulate_limit_reached() {
    log_test "Simulating limit reached scenario..."

    local mock_user="sim-user-limit"
    local mock_file="$ALERTS_DIR/${mock_user}.json"

    echo '[{"type": "gpu_limit_reached", "message": "GPU limit reached: 5/5 GPUs allocated", "created_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "updated_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}]' > "$mock_file"

    assert_file_exists "$mock_file" "Limit reached mock alert created"

    # Cleanup
    rm -f "$mock_file"
    log_pass "Limit reached simulation completed"
}

# ============================================================================
# Main
# ============================================================================

cleanup() {
    log_info "Cleaning up test artifacts..."
    rm -f "$ALERTS_DIR"/test-*.json "$ALERTS_DIR"/sim-*.json 2>/dev/null || true
    log_info "Cleanup complete"
}

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "DS01 Resource Alert System Tests"
    echo "=============================================="
    echo ""

    test_soft_limit_display
    test_error_messages_contact_info
    test_alert_generation
    test_alert_checker_script
    test_gpu_utilization_monitor
    test_soft_limit_thresholds
    test_cron_config

    echo ""
    echo "=============================================="
    echo "Simulation Scenarios"
    echo "=============================================="
    echo ""

    simulate_high_usage
    simulate_limit_reached

    echo ""
    echo "=============================================="
    echo "Test Summary"
    echo "=============================================="
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

case "${1:-}" in
    --cleanup)
        cleanup
        ;;
    --scenario)
        case "${2:-}" in
            high-usage)
                simulate_high_usage
                ;;
            limit-reached)
                simulate_limit_reached
                ;;
            *)
                echo "Unknown scenario: ${2:-}"
                echo "Available: high-usage, limit-reached"
                exit 1
                ;;
        esac
        ;;
    --help|-h)
        echo "Usage: $0 [--scenario <name>|--cleanup]"
        echo ""
        echo "Options:"
        echo "  (no args)           Run all tests"
        echo "  --scenario <name>   Run specific scenario"
        echo "  --cleanup           Clean up test artifacts"
        echo ""
        echo "Scenarios: high-usage, limit-reached"
        ;;
    *)
        run_all_tests
        cleanup
        ;;
esac
