#!/bin/bash
# /opt/ds01-infra/scripts/docker/gpu-user-allocation.sh
# Script to manage GPU allocation to users in Docker containers

# Directories
CONFIG_DIR=~/server_infra/configs
LOGS_DIR=~/server_infra/logs/gpu

# Ensure directories exist
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOGS_DIR"

# Configuration file
CONFIG_FILE="$CONFIG_DIR/gpu_allocation.yaml"

# Logging function
log_allocation() {
    local username=$1
    local gpu_id=$2
    local action=$3

    echo "$(date '+%Y-%m-%d %H:%M:%S')|$username|$action|GPU $gpu_id" \
        >> "$LOGS_DIR/gpu_allocations.log"
}

# Allocate GPU to user
allocate_gpu() {
    local username=$1
    local gpu_id=$2

    # Validate GPU number
    if [[ "$gpu_id" -lt 0 || "$gpu_id" -gt 3 ]]; then
        echo "Invalid GPU. Choose 0-3."
        return 1
    }

    # Check if GPU is already allocated
    if grep -q "gpu_$gpu_id: $username" "$CONFIG_FILE"; then
        echo "GPU $gpu_id already allocated to $username"
        return 1
    }

    # Update configuration
    sed -i "/gpu_$gpu_id:/c\    gpu_$gpu_id: $username" "$CONFIG_FILE"

    # Log allocation
    log_allocation "$username" "$gpu_id" "ALLOCATED"

    # Update user's environment
    echo "export CUDA_VISIBLE_DEVICES=$gpu_id" >> "/home/$username/.bashrc"

    echo "GPU $gpu_id allocated to $username"
}

# Release GPU from user
release_gpu() {
    local username=$1
    local gpu_id=$2

    # Remove allocation from config
    sed -i "/gpu_$gpu_id: $username/c\    gpu_$gpu_id: available" "$CONFIG_FILE"

    # Log release
    log_allocation "$username" "$gpu_id" "RELEASED"

    # Remove from user's environment
    sed -i "/export CUDA_VISIBLE_DEVICES=$gpu_id/d" "/home/$username/.bashrc"

    echo "GPU $gpu_id released from $username"
}

# Initialize configuration if not exists
initialize_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
gpu_allocation:
  gpu_0: available
  gpu_1: available
  gpu_2: available
  gpu_3: available
EOF
    fi
}

# Main function
main() {
    initialize_config

    case "$1" in
        allocate)
            allocate_gpu "$2" "$3"
            ;;
        release)
            release_gpu "$2" "$3"
            ;;
        status)
            cat "$CONFIG_FILE"
            ;;
        log)
            cat "$LOGS_DIR/gpu_allocations.log"
            ;;
        *)
            echo "Usage: $0 {allocate|release|status|log} [username] [gpu_id]"
            exit 1
            ;;
    esac
}

# Execute
main "$@"