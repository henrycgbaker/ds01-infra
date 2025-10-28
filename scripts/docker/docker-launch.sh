#!/bin/bash
# Container launch wrapper

# /opt/ds01-infra/scripts/docker/docker-launch.sh

# Input validation
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <container_name> <image> [gpu_id]"
    exit 1
fi

# Argument handling
CONTAINER_NAME=$1
IMAGE=$2
GPU_ID=${3:-0} # default to 0

# Validate GPU ID for 4 GPUs
if [[ "$GPU_ID" -lt 0 || "$GPU_ID" -gt 3 ]]; then
    echo "Invalid GPU ID. Choose 0-3."
    exit 1
fi

# Strict GPU validation
case "$GPU_ID" in
    0|1|2|3)
        # Valid GPU
        ;;
    *)
        echo "Invalid GPU. Choose 0-3."
        exit 1
        ;;
esac


# Check if container name already exists
if docker ps -a | grep -q "${CONTAINER_NAME}"; then
    echo "Container ${CONTAINER_NAME} already exists. Choose a unique name."
    exit 1
fi

# Logging
echo "Launching container:"
echo "- Name: ${CONTAINER_NAME}"
echo "- Image: ${IMAGE}"
echo "- GPU: ${GPU_ID}"

# Launch container
docker run -d \
  --name "${CONTAINER_NAME}" \
  --gpus "device=${GPU_ID}" \
  --env CUDA_VISIBLE_DEVICES="$GPU_ID" \
  --memory="32g" \
  --memory-swap="32g" \
  --cpus="8" \
  --shm-size="16g" \
  --restart=unless-stopped \
  "${IMAGE}"

# Check container status
if [[ $? -eq 0 ]]; then
    echo "Container launched successfully"
else
    echo "Failed to launch container"
    exit 1
fi