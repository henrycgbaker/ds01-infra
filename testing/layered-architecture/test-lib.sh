#!/bin/bash
# DS01 Layered Architecture Test Library
# Common functions for all test scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Paths
INFRA_ROOT="/opt/ds01-infra"
RESULTS_DIR="$(dirname "$0")/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Verbose mode
VERBOSE=${VERBOSE:-false}

# Initialize results directory
init_results() {
    mkdir -p "$RESULTS_DIR"
    RESULT_FILE="$RESULTS_DIR/$(basename "$0" .sh)-${TIMESTAMP}.log"
    echo "Test run started at $(date)" > "$RESULT_FILE"
    echo "========================================" >> "$RESULT_FILE"
}

# Log to both console and file
log() {
    echo -e "$1"
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$RESULT_FILE" 2>/dev/null
}

# Test assertion functions
pass() {
    local test_name="$1"
    local message="${2:-}"
    ((TESTS_PASSED++))
    log "${GREEN}[PASS]${NC} $test_name"
    [[ -n "$message" && "$VERBOSE" == "true" ]] && log "       $message"
}

fail() {
    local test_name="$1"
    local message="${2:-}"
    ((TESTS_FAILED++))
    log "${RED}[FAIL]${NC} $test_name"
    [[ -n "$message" ]] && log "       ${RED}$message${NC}"
}

skip() {
    local test_name="$1"
    local reason="${2:-}"
    ((TESTS_SKIPPED++))
    log "${YELLOW}[SKIP]${NC} $test_name"
    [[ -n "$reason" ]] && log "       $reason"
}

info() {
    log "${BLUE}[INFO]${NC} $1"
}

section() {
    log ""
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${BOLD}$1${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Assert functions
assert_file_exists() {
    local file="$1"
    local test_name="$2"
    if [[ -f "$file" ]]; then
        pass "$test_name" "File exists: $file"
    else
        fail "$test_name" "File not found: $file"
    fi
}

assert_file_executable() {
    local file="$1"
    local test_name="$2"
    if [[ -x "$file" ]]; then
        pass "$test_name" "File is executable: $file"
    else
        fail "$test_name" "File not executable: $file"
    fi
}

assert_command_exists() {
    local cmd="$1"
    local test_name="$2"
    if command -v "$cmd" &>/dev/null; then
        pass "$test_name" "Command found: $cmd"
    else
        fail "$test_name" "Command not found: $cmd"
    fi
}

assert_grep() {
    local pattern="$1"
    local file="$2"
    local test_name="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        pass "$test_name"
    else
        fail "$test_name" "Pattern '$pattern' not found in $file"
    fi
}

assert_not_grep() {
    local pattern="$1"
    local file="$2"
    local test_name="$3"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        pass "$test_name"
    else
        fail "$test_name" "Pattern '$pattern' unexpectedly found in $file"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected to find '$needle' in output"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Unexpectedly found '$needle' in output"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected exit code $expected, got $actual"
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local test_name="$4"
    local actual=$(echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$field', ''))" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected $field='$expected', got '$actual'"
    fi
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "Entire test suite" "Requires root privileges"
        exit 0
    fi
}

# Check if docker is available
require_docker() {
    if ! docker info &>/dev/null; then
        skip "Entire test suite" "Docker not available or not running"
        exit 0
    fi
}

# Print summary
print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    log ""
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${BOLD}TEST SUMMARY${NC}"
    log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "Total:   $total"
    log "${GREEN}Passed:  $TESTS_PASSED${NC}"
    log "${RED}Failed:  $TESTS_FAILED${NC}"
    log "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    log ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log "${GREEN}${BOLD}All tests passed!${NC}"
        echo ""
        echo "Results saved to: $RESULT_FILE"
        return 0
    else
        log "${RED}${BOLD}Some tests failed!${NC}"
        echo ""
        echo "Results saved to: $RESULT_FILE"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--verbose|-v] [--help|-h]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Initialize
parse_args "$@"
init_results
