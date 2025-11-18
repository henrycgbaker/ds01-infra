#!/bin/bash
# Verbose debugging output for DS01 system state
# Shows everything - for deep debugging

INFRA_ROOT="/opt/ds01-infra"
GPU_STATE_FILE="/var/lib/ds01/gpu-state.json"
GPU_ALLOCATOR="$INFRA_ROOT/scripts/docker/gpu_allocator.py"

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                  DS01 VERBOSE DEBUG OUTPUT                         ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# 1. GPU Allocator State File
echo "═══ 1. GPU State File ($GPU_STATE_FILE) ═══"
if [ -f "$GPU_STATE_FILE" ]; then
    python3 -m json.tool "$GPU_STATE_FILE" 2>/dev/null || cat "$GPU_STATE_FILE"
else
    echo "  [NOT FOUND]"
fi
echo ""

# 2. GPU Allocator Status
echo "═══ 2. GPU Allocator Status ═══"
python3 "$GPU_ALLOCATOR" status 2>&1
echo ""

# 3. All Docker Containers (DS01 naming)
echo "═══ 3. Docker Containers (DS01 naming: .*\._\.) ═══"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}" | grep -E "(NAMES|\._.)" || echo "  [NONE]"
echo ""

# 4. Docker GPU Assignments (HostConfig)
echo "═══ 4. Docker GPU Assignments (HostConfig.DeviceRequests) ═══"
docker ps -a --format "{{.Names}}" | grep '\._\.' | while read -r name; do
    echo "Container: $name"
    docker inspect "$name" --format '  DeviceRequests: {{.HostConfig.DeviceRequests}}' 2>/dev/null
    docker inspect "$name" --format '  Status: {{.State.Status}}' 2>/dev/null
    docker inspect "$name" --format '  Running: {{.State.Running}}' 2>/dev/null
    echo ""
done
echo ""

# 5. Docker Labels (DS01 and AIME)
echo "═══ 5. Docker Labels (DS01 & AIME) ═══"
docker ps -a --format "{{.Names}}" | grep '\._\.' | head -5 | while read -r name; do
    echo "Container: $name"
    docker inspect "$name" --format '{{range $key, $value := .Config.Labels}}{{if or (hasPrefix $key "ds01.") (hasPrefix $key "aime.mlc.")}}  {{$key}}: {{$value}}{{"\n"}}{{end}}{{end}}' 2>/dev/null
    echo ""
done
echo ""

# 6. Container Metadata Files
echo "═══ 6. Container Metadata Files (/var/lib/ds01/container-metadata/) ═══"
if [ -d "/var/lib/ds01/container-metadata" ]; then
    for f in /var/lib/ds01/container-metadata/*.json; do
        [ -f "$f" ] || continue
        echo "File: $(basename "$f")"
        cat "$f" 2>/dev/null | python3 -m json.tool 2>/dev/null || cat "$f"
        echo ""
    done
else
    echo "  [DIRECTORY NOT FOUND]"
fi
echo ""

# 7. MIG Instances from nvidia-smi
echo "═══ 7. NVIDIA MIG Instances (nvidia-smi mig -lgi) ═══"
nvidia-smi mig -lgi 2>&1 || echo "  [ERROR or MIG not enabled]"
echo ""

# 8. Current User Container List (mlc-list)
echo "═══ 8. MLC-List Output ═══"
bash "$INFRA_ROOT/aime-ml-containers/mlc-list" 2>&1 || echo "  [ERROR]"
echo ""

# 9. Recent Container Operations Log
echo "═══ 9. Recent Container Operations (/var/log/ds01/container-operations.log) ═══"
if [ -f "/var/log/ds01/container-operations.log" ]; then
    tail -20 /var/log/ds01/container-operations.log
else
    echo "  [NOT FOUND]"
fi
echo ""

# 10. GPU Allocation Discrepancies
echo "═══ 10. DISCREPANCY ANALYSIS ═══"

# Get containers from allocator
ALLOC_CONTAINERS=$(python3 "$GPU_ALLOCATOR" status 2>/dev/null | grep -E "^\s+- " | sed 's/^\s*- //' | sort)

# Get containers from Docker
DOCKER_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep '\._\.' | sort)

echo "Containers in GPU Allocator: $(echo "$ALLOC_CONTAINERS" | wc -l)"
echo "$ALLOC_CONTAINERS" | sed 's/^/  - /'
echo ""

echo "Containers in Docker: $(echo "$DOCKER_CONTAINERS" | wc -l)"
echo "$DOCKER_CONTAINERS" | sed 's/^/  - /'
echo ""

# Find differences
echo "In Allocator but NOT in Docker (STALE):"
comm -23 <(echo "$ALLOC_CONTAINERS") <(echo "$DOCKER_CONTAINERS") | sed 's/^/  ✗ /' || echo "  [NONE]"
echo ""

echo "In Docker but NOT in Allocator (UNTRACKED):"
docker ps --filter "status=running" --format "{{.Names}}" | grep '\._\.' | while read -r name; do
    gpu=$(docker inspect "$name" --format '{{index .HostConfig.DeviceRequests 0}}' 2>/dev/null | grep -o 'MIG-' || true)
    if [ -n "$gpu" ] && ! echo "$ALLOC_CONTAINERS" | grep -q "^${name}$"; then
        echo "  ⚠ $name"
    fi
done
echo ""

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                    END VERBOSE DEBUG OUTPUT                        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
