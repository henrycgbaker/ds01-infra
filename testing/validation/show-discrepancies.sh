#!/bin/bash
# Show detailed discrepancies between different views of the system
# More verbose than validation checks - for detailed debugging

INFRA_ROOT="/opt/ds01-infra"
GPU_STATE="$INFRA_ROOT/scripts/docker/gpu_allocator.py"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DS01 System State Comparison"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "=== GPU Allocator View ==="
python3 "$GPU_STATE" status | grep -A1 "MIG " | grep -E "(MIG|^\s+-)" | head -20
echo ""

echo "=== Docker Containers with GPUs ==="
docker ps -a --format "{{.Names}}\t{{.Status}}" | grep '\._\.' | while IFS=$'\t' read -r name status; do
    gpu=$(docker inspect "$name" --format '{{index .HostConfig.DeviceRequests 0}}' 2>/dev/null | grep -oP 'MIG-[a-f0-9-]+' || echo "none")
    printf "%-25s %-20s %s\n" "$name" "$status" "$gpu"
done | head -20
echo ""

echo "=== container-list View ==="
bash "$INFRA_ROOT/aime-ml-containers/mlc-list" 2>/dev/null | head -20
echo ""

echo "=== Metadata Files ==="
ls -1 /var/lib/ds01/container-metadata/*.json 2>/dev/null | while read f; do
    basename "$f" .json
done | head -20
echo ""
