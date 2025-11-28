#!/bin/bash
# /opt/ds01-infra/testing/ldap-support/test-username-sanitization.sh
# Unit tests for username sanitization functions
#
# Usage:
#   ./test-username-sanitization.sh           # Run all tests
#   ./test-username-sanitization.sh -v        # Verbose mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
LIB_DIR="$INFRA_ROOT/scripts/lib"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERBOSE=false
[[ "$1" == "-v" ]] && VERBOSE=true

PASS_COUNT=0
FAIL_COUNT=0

# Source the library
source "$LIB_DIR/username-utils.sh"

log_pass() {
    ((PASS_COUNT++))
    echo -e "${GREEN}PASS${NC}: $1"
}

log_fail() {
    ((FAIL_COUNT++))
    echo -e "${RED}FAIL${NC}: $1"
    echo -e "       Expected: $2"
    echo -e "       Got:      $3"
}

# Test function for Bash sanitization
test_sanitize_bash() {
    local input="$1"
    local expected="$2"
    local actual
    actual=$(sanitize_username_for_slice "$input")

    if [[ "$actual" == "$expected" ]]; then
        log_pass "sanitize_username_for_slice '$input' -> '$expected'"
    else
        log_fail "sanitize_username_for_slice '$input'" "$expected" "$actual"
    fi
}

# Test function for Bash slice name
test_slice_name() {
    local group="$1"
    local username="$2"
    local expected="$3"
    local actual
    actual=$(get_user_slice_name "$group" "$username")

    if [[ "$actual" == "$expected" ]]; then
        log_pass "get_user_slice_name '$group' '$username' -> '$expected'"
    else
        log_fail "get_user_slice_name '$group' '$username'" "$expected" "$actual"
    fi
}

# Test function for Python sanitization
test_sanitize_python() {
    local input="$1"
    local expected="$2"
    local actual
    actual=$(python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from username_utils import sanitize_username_for_slice
print(sanitize_username_for_slice('$input'))
")

    if [[ "$actual" == "$expected" ]]; then
        log_pass "Python: sanitize_username_for_slice '$input' -> '$expected'"
    else
        log_fail "Python: sanitize_username_for_slice '$input'" "$expected" "$actual"
    fi
}

echo ""
echo "=========================================="
echo "Username Sanitization Tests"
echo "=========================================="
echo ""

echo "--- Bash Library Tests ---"
echo ""

# Basic local usernames (should remain unchanged)
test_sanitize_bash "alice" "alice"
test_sanitize_bash "bob123" "bob123"
test_sanitize_bash "john_doe" "john_doe"
test_sanitize_bash "jane-smith" "jane-smith"

# Usernames with dots
test_sanitize_bash "john.doe" "john-doe"
test_sanitize_bash "first.middle.last" "first-middle-last"

# LDAP/SSSD usernames with @ and domain
test_sanitize_bash "h.baker@hertie-school.lan" "h-baker-at-hertie-school-lan"
test_sanitize_bash "alice@domain.org" "alice-at-domain-org"
test_sanitize_bash "user@sub.domain.edu" "user-at-sub-domain-edu"
test_sanitize_bash "test.user@company.com" "test-user-at-company-com"

# Edge cases
test_sanitize_bash "" ""
test_sanitize_bash "a" "a"
test_sanitize_bash "@leading" "at-leading"
test_sanitize_bash "trailing@" "trailing-at"

# Multiple consecutive special characters (should collapse)
test_sanitize_bash "foo..bar" "foo-bar"
test_sanitize_bash "foo@@bar" "foo-at-at-bar"
test_sanitize_bash "test...name" "test-name"

echo ""
echo "--- Slice Name Tests ---"
echo ""

test_slice_name "student" "alice" "ds01-student-alice.slice"
test_slice_name "student" "h.baker@hertie-school.lan" "ds01-student-h-baker-at-hertie-school-lan.slice"
test_slice_name "researcher" "john.doe" "ds01-researcher-john-doe.slice"
test_slice_name "admin" "root" "ds01-admin-root.slice"

echo ""
echo "--- Python Library Tests ---"
echo ""

# Same tests for Python library to ensure consistency
test_sanitize_python "alice" "alice"
test_sanitize_python "john.doe" "john-doe"
test_sanitize_python "h.baker@hertie-school.lan" "h-baker-at-hertie-school-lan"
test_sanitize_python "user@domain.org" "user-at-domain-org"
test_sanitize_python "" ""

echo ""
echo "--- Cross-Library Consistency Tests ---"
echo ""

# Verify Bash and Python produce identical output
test_cases=(
    "alice"
    "john.doe"
    "h.baker@hertie-school.lan"
    "user@sub.domain.edu"
    "test_user123"
)

for input in "${test_cases[@]}"; do
    bash_result=$(sanitize_username_for_slice "$input")
    python_result=$(python3 -c "
import sys
sys.path.insert(0, '$LIB_DIR')
from username_utils import sanitize_username_for_slice
print(sanitize_username_for_slice('$input'))
")
    if [[ "$bash_result" == "$python_result" ]]; then
        log_pass "Bash/Python match for '$input' -> '$bash_result'"
    else
        log_fail "Bash/Python mismatch for '$input'" "Bash: $bash_result" "Python: $python_result"
    fi
done

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
