#!/bin/bash
# Verify GPU allocator state matches Docker HostConfig
# Returns exit code 0 if matched, 1 if mismatches found

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
GPU_STATE="/var/lib/ds01/gpu-state.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MISMATCHES=0

if [ ! -f "$GPU_STATE" ]; then
    echo -e "${YELLOW}⚠ No GPU state file${NC}"
    exit 0
fi

# Parse GPU state file to get container→GPU mappings
ALLOCATOR_MAPPINGS=$(python3 -c "
import json, sys
try:
    with open('$GPU_STATE') as f:
        state = json.load(f)
    for gpu_id, gpu_data in state.get('gpus', {}).items():
        for container in gpu_data.get('containers', []):
            uuid = gpu_data.get('uuid', '')
            print(f'{container}:{uuid}')
except Exception as e:
    pass
" | sort)

# Get Docker container→GPU mappings
DOCKER_MAPPINGS=$(docker ps -a --format "{{.Names}}" | grep '\._\.' | while read -r name; do
    uuid=$(docker inspect "$name" --format '{{index .HostConfig.DeviceRequests 0}}' 2>/dev/null | grep -oP 'MIG-[a-f0-9-]+' || echo "none")
    echo "$name:$uuid"
done | grep -v ':none$' | sort)

# Compare mappings
while IFS=: read -r container allocator_uuid; do
    [ -z "$container" ] && continue

    docker_uuid=$(echo "$DOCKER_MAPPINGS" | grep "^${container}:" | cut -d: -f2 || echo "")

    if [ -z "$docker_uuid" ]; then
        echo -e "${YELLOW}⚠ ALLOCATOR-ONLY: $container has GPU in allocator but not in Docker${NC}"
        ((MISMATCHES++))
    elif [ "$docker_uuid" != "$allocator_uuid" ]; then
        echo -e "${RED}✗ MISMATCH: $container allocator=$allocator_uuid docker=$docker_uuid${NC}"
        ((MISMATCHES++))
    fi
done <<< "$ALLOCATOR_MAPPINGS"

# Check for containers in Docker but not in allocator
while IFS=: read -r container docker_uuid; do
    [ -z "$container" ] && continue

    if ! echo "$ALLOCATOR_MAPPINGS" | grep -q "^${container}:"; then
        echo -e "${YELLOW}⚠ DOCKER-ONLY: $container has GPU in Docker but not in allocator${NC}"
        ((MISMATCHES++))
    fi
done <<< "$DOCKER_MAPPINGS"

# Summary
if [ $MISMATCHES -eq 0 ]; then
    echo -e "${GREEN}✓ GPU allocator matches Docker${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $MISMATCHES mismatch(es)${NC}"
    exit 1
fi
