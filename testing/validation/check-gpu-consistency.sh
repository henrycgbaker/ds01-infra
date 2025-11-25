#!/bin/bash
# Quick GPU allocation consistency checker
# Returns exit code 0 if consistent, 1 if problems found

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
GPU_ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# Get containers from GPU allocator
ALLOCATED_CONTAINERS=$(python3 "$GPU_ALLOCATOR" status 2>/dev/null | grep -E "^\s+- " | sed 's/^\s*- //' | sort)

# Get actual DS01 containers from Docker
DOCKER_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep '\._\.' | sort)

# Check for containers in allocator but not in Docker (STALE)
while IFS= read -r container; do
    [ -z "$container" ] && continue
    if ! echo "$DOCKER_CONTAINERS" | grep -q "^${container}$"; then
        echo -e "${RED}✗ STALE: GPU allocated to non-existent container: $container${NC}"
        ((ERRORS++))
    fi
done <<< "$ALLOCATED_CONTAINERS"

# Get running containers with GPUs from Docker
RUNNING_WITH_GPU=$(docker ps --filter "status=running" --format "{{.Names}}" | grep '\._\.' | while read -r name; do
    gpu=$(docker inspect "$name" --format '{{index .HostConfig.DeviceRequests 0}}' 2>/dev/null | grep -o 'MIG-[a-f0-9-]*' || true)
    if [ -n "$gpu" ]; then
        echo "$name"
    fi
done | sort)

# Check for running containers with GPUs not in allocator (UNTRACKED)
while IFS= read -r container; do
    [ -z "$container" ] && continue
    if ! echo "$ALLOCATED_CONTAINERS" | grep -q "^${container}$"; then
        echo -e "${YELLOW}⚠ UNTRACKED: Running container has GPU but not in allocator: $container${NC}"
        ((ERRORS++))
    fi
done <<< "$RUNNING_WITH_GPU"

# Summary
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ GPU allocations consistent${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS consistency issue(s)${NC}"
    exit 1
fi
