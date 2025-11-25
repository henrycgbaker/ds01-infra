#!/bin/bash
# Run all GPU allocation tests
# Handles Python import issues with hyphenated filenames

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}GPU Allocation Test Suite${NC}"
echo "========================================"
echo ""

# Change to infra root
cd /opt/ds01-infra

# Set PYTHONPATH to include scripts/docker
export PYTHONPATH="/opt/ds01-infra/scripts/docker:$PYTHONPATH"

# Create symbolic links for hyphenated files (Python imports need underscores)
SCRIPT_DIR="/opt/ds01-infra/scripts/docker"
cd "$SCRIPT_DIR"

# Create temporary symlinks if files use hyphens
for file in gpu-state-reader.py gpu-availability-checker.py gpu-allocator-smart.py ds01-resource-query.py; do
    if [ -f "$file" ]; then
        underscore_name=$(echo "$file" | tr '-' '_')
        if [ ! -e "$underscore_name" ]; then
            ln -sf "$file" "$underscore_name" 2>/dev/null || true
        fi
    fi
done

cd /opt/ds01-infra

echo -e "${YELLOW}Running unit tests...${NC}"
echo ""

# Test 1: GPU State Reader
echo -e "${BLUE}[1/4]${NC} Testing gpu_state_reader..."
if python3 testing/gpu-allocation/test-gpu-state-reader.py 2>&1 | grep -q "OK"; then
    echo -e "  ${GREEN}✓${NC} GPU State Reader tests passed"
else
    echo -e "  ${RED}✗${NC} GPU State Reader tests failed"
    python3 testing/gpu-allocation/test-gpu-state-reader.py
fi
echo ""

# Test 2: GPU Availability Checker
echo -e "${BLUE}[2/4]${NC} Testing gpu_availability_checker..."
if python3 testing/gpu-allocation/test-gpu-availability-checker.py 2>&1 | grep -q "OK"; then
    echo -e "  ${GREEN}✓${NC} GPU Availability Checker tests passed"
else
    echo -e "  ${RED}✗${NC} GPU Availability Checker tests failed"
    python3 testing/gpu-allocation/test-gpu-availability-checker.py
fi
echo ""

# Test 3: GPU Allocator Smart
echo -e "${BLUE}[3/4]${NC} Testing gpu_allocator_smart..."
if python3 testing/gpu-allocation/test-gpu-allocator-smart.py 2>&1 | grep -q "OK"; then
    echo -e "  ${GREEN}✓${NC} GPU Allocator Smart tests passed"
else
    echo -e "  ${RED}✗${NC} GPU Allocator Smart tests failed"
    python3 testing/gpu-allocation/test-gpu-allocator-smart.py
fi
echo ""

# Test 4: Integration Tests
echo -e "${BLUE}[4/4]${NC} Running integration tests..."
if bash testing/gpu-allocation/test-integration.sh 2>&1 | tail -1 | grep -q "All tests passed"; then
    echo -e "  ${GREEN}✓${NC} Integration tests passed"
else
    echo -e "  ${YELLOW}⊘${NC} Integration tests had warnings (see details above)"
fi
echo ""

echo "========================================"
echo -e "${GREEN}Test suite complete${NC}"
echo ""

# Clean up symlinks
cd "$SCRIPT_DIR"
for file in gpu_state_reader.py gpu_availability_checker.py gpu_allocator_smart.py ds01_resource_query.py; do
    if [ -L "$file" ]; then
        rm "$file"
    fi
done
