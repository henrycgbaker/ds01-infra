#!/bin/bash
# Comprehensive test for DS01 cron job automation
# Tests all 4 cleanup scripts with short time scales

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  DS01 Cron Job Comprehensive Test${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check current configuration
echo -e "${BOLD}1. Current Configuration:${NC}"
echo ""
echo "Current resource limits from YAML:"
python3 "$INFRA_ROOT/scripts/docker/get_resource_limits.py" datasciencelab | grep -E "(max_runtime|idle_timeout|gpu_hold_after_stop|container_hold_after_stop)"
echo ""

# Show current containers
echo -e "${BOLD}2. Current Containers:${NC}"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep -E "(NAMES|\._.)" || echo "No DS01 containers running"
echo ""

# Show current GPU allocations
echo -e "${BOLD}3. Current GPU Allocations:${NC}"
echo ""
python3 "$INFRA_ROOT/scripts/docker/gpu_allocator.py" status
echo ""

# Check log permissions
echo -e "${BOLD}4. Log File Status:${NC}"
echo ""
for logfile in idle-cleanup runtime-enforcement gpu-stale-cleanup container-stale-cleanup; do
    if [ -f "/var/log/ds01/${logfile}.log" ]; then
        stat -c "%n: %U:%G %a (modified: %y)" "/var/log/ds01/${logfile}.log"
    else
        echo -e "${YELLOW}/var/log/ds01/${logfile}.log: NOT FOUND${NC}"
    fi
done
echo ""

# Test 1: Idle timeout check
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TEST 1: Idle Container Check${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Script: $INFRA_ROOT/scripts/monitoring/check-idle-containers.sh"
echo "Schedule: :30 past each hour"
echo "Purpose: Stop containers idle beyond user's idle_timeout"
echo ""
read -p "Run idle check now? (y/n): " RUN_IDLE
if [[ "$RUN_IDLE" == "y" ]]; then
    echo ""
    echo -e "${YELLOW}Running idle check...${NC}"
    sudo bash "$INFRA_ROOT/scripts/monitoring/check-idle-containers.sh"
    echo ""
    echo -e "${GREEN}✓ Check complete. View log:${NC}"
    echo "  sudo tail -30 /var/log/ds01/idle-cleanup.log"
    echo ""
fi

# Test 2: Max runtime enforcement
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TEST 2: Max Runtime Enforcement${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Script: $INFRA_ROOT/scripts/maintenance/enforce-max-runtime.sh"
echo "Schedule: :45 past each hour"
echo "Purpose: Stop containers exceeding user's max_runtime"
echo ""
read -p "Run max runtime check now? (y/n): " RUN_RUNTIME
if [[ "$RUN_RUNTIME" == "y" ]]; then
    echo ""
    echo -e "${YELLOW}Running max runtime check...${NC}"
    sudo bash "$INFRA_ROOT/scripts/maintenance/enforce-max-runtime.sh"
    echo ""
    echo -e "${GREEN}✓ Check complete. View log:${NC}"
    echo "  sudo tail -30 /var/log/ds01/runtime-enforcement.log"
    echo ""
fi

# Test 3: GPU cleanup
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TEST 3: GPU Stale Allocation Cleanup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Script: $INFRA_ROOT/scripts/maintenance/cleanup-stale-gpu-allocations.sh"
echo "Schedule: :15 past each hour"
echo "Purpose: Release GPUs from stopped containers after gpu_hold_after_stop"
echo ""
read -p "Run GPU cleanup now? (y/n): " RUN_GPU
if [[ "$RUN_GPU" == "y" ]]; then
    echo ""
    echo -e "${YELLOW}Running GPU cleanup...${NC}"
    sudo bash "$INFRA_ROOT/scripts/maintenance/cleanup-stale-gpu-allocations.sh"
    echo ""
    echo -e "${GREEN}✓ Check complete. View log:${NC}"
    echo "  sudo tail -30 /var/log/ds01/gpu-stale-cleanup.log"
    echo ""
fi

# Test 4: Container cleanup
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TEST 4: Stale Container Cleanup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Script: $INFRA_ROOT/scripts/maintenance/cleanup-stale-containers.sh"
echo "Schedule: :30 past each hour"
echo "Purpose: Remove stopped containers after container_hold_after_stop"
echo ""
read -p "Run container cleanup now? (y/n): " RUN_CONTAINER
if [[ "$RUN_CONTAINER" == "y" ]]; then
    echo ""
    echo -e "${YELLOW}Running container cleanup...${NC}"
    sudo bash "$INFRA_ROOT/scripts/maintenance/cleanup-stale-containers.sh"
    echo ""
    echo -e "${GREEN}✓ Check complete. View log:${NC}"
    echo "  sudo tail -30 /var/log/ds01/container-stale-cleanup.log"
    echo ""
fi

# Summary
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}TEST SUMMARY${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Check logs for detailed results:"
echo "  sudo tail -f /var/log/ds01/idle-cleanup.log"
echo "  sudo tail -f /var/log/ds01/runtime-enforcement.log"
echo "  sudo tail -f /var/log/ds01/gpu-stale-cleanup.log"
echo "  sudo tail -f /var/log/ds01/container-stale-cleanup.log"
echo ""
echo "Current state:"
echo ""
echo "Containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep -E "(NAMES|\._.)" || echo "No DS01 containers"
echo ""
echo "GPU Allocations:"
python3 "$INFRA_ROOT/scripts/docker/gpu_allocator.py" status
echo ""
