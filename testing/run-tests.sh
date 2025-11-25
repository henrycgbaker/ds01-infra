#!/bin/bash
# DS01 Test Runner
# Unified test runner for all test categories

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults
CATEGORY="all"
VERBOSE=""
MARKERS=""
COVERAGE=""

usage() {
    cat << EOF
DS01 Test Runner

Usage: $0 [OPTIONS] [CATEGORY]

Categories:
  unit          Run unit tests only (fast, no external deps)
  component     Run component tests (single components, may need Docker)
  integration   Run integration tests (multiple components)
  e2e           Run end-to-end tests (full workflows, slow)
  all           Run all tests (default)

Options:
  -v, --verbose     Verbose output
  -m, --marker      Run tests with specific marker (e.g., -m "not slow")
  --coverage        Generate coverage report
  --docker          Only run tests that require Docker
  --no-docker       Skip tests that require Docker
  --gpu             Only run tests that require GPU
  --no-gpu          Skip tests that require GPU
  -h, --help        Show this help

Markers available:
  unit, component, integration, e2e
  slow, requires_docker, requires_gpu, requires_root

Examples:
  $0                        # Run all tests
  $0 unit                   # Run only unit tests
  $0 -v integration         # Verbose integration tests
  $0 --no-docker            # Skip Docker-dependent tests
  $0 -m "not slow"          # Skip slow tests

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        unit|component|integration|e2e|all)
            CATEGORY="$1"
            shift
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -m|--marker)
            MARKERS="$MARKERS -m $2"
            shift 2
            ;;
        --coverage)
            COVERAGE="--cov=/opt/ds01-infra/scripts --cov-report=html"
            shift
            ;;
        --docker)
            MARKERS="$MARKERS -m requires_docker"
            shift
            ;;
        --no-docker)
            MARKERS="$MARKERS -m 'not requires_docker'"
            shift
            ;;
        --gpu)
            MARKERS="$MARKERS -m requires_gpu"
            shift
            ;;
        --no-gpu)
            MARKERS="$MARKERS -m 'not requires_gpu'"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}DS01 Infrastructure Test Suite${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check pytest is available
if ! command -v pytest &>/dev/null; then
    echo -e "${RED}pytest not found. Install with: pip install pytest${NC}"
    exit 1
fi

# Build test path based on category
case $CATEGORY in
    unit)
        TEST_PATH="unit/"
        echo -e "${BLUE}Running: Unit Tests${NC}"
        ;;
    component)
        TEST_PATH="component/"
        echo -e "${BLUE}Running: Component Tests${NC}"
        ;;
    integration)
        TEST_PATH="integration/"
        echo -e "${BLUE}Running: Integration Tests${NC}"
        ;;
    e2e)
        TEST_PATH="e2e/"
        echo -e "${BLUE}Running: End-to-End Tests${NC}"
        ;;
    all)
        TEST_PATH=""
        echo -e "${BLUE}Running: All Tests${NC}"
        ;;
esac

# Show configuration
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Category: $CATEGORY"
echo "  Verbose:  ${VERBOSE:-no}"
echo "  Markers:  ${MARKERS:-none}"
echo "  Coverage: ${COVERAGE:-no}"
echo ""

# Create results directory
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="results/test-run-${TIMESTAMP}.log"

# Run pytest
echo -e "${CYAN}Starting tests...${NC}"
echo ""

# Build command
PYTEST_CMD="pytest $TEST_PATH $VERBOSE $MARKERS $COVERAGE --tb=short"

# Run and capture result
if $PYTEST_CMD 2>&1 | tee "$RESULT_FILE"; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    EXIT_CODE=0
else
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}${BOLD}Some tests failed!${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    EXIT_CODE=1
fi

echo ""
echo "Results saved to: $RESULT_FILE"

# Coverage report location
if [[ -n "$COVERAGE" ]]; then
    echo "Coverage report: htmlcov/index.html"
fi

exit $EXIT_CODE
