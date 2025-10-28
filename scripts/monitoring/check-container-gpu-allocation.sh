#!/bin/bash
# opt/ds01-infrascripts/check_container_gpu_allocation.sh


echo "GPU Allocation by Container:"
for container in $(docker ps --format '{{.Names}}'); do
    echo -n "$container: "
    docker exec $container nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null || echo "No GPU"
done