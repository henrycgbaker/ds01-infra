#!/bin/bash
# /opt/ds01-infra/scripts/lib/aime-images.sh
# AIME Machine Learning Container image utilities
# Extracted from image-create for shared use
#
# Usage:
#   source /opt/ds01-infra/scripts/lib/aime-images.sh
#   BASE_IMAGE=$(get_base_image "pytorch")  # or tensorflow, jax

detect_cuda_arch() {
    # Auto-detect appropriate CUDA architecture based on host driver
    # Driver 535+ supports CUDA 12.x, older drivers use CUDA 11.8
    local driver_major
    driver_major=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1)

    if [ -n "$driver_major" ] && [ "$driver_major" -ge 535 ] 2>/dev/null; then
        echo "CUDA_ADA"
    else
        echo "CUDA_AMPERE"
    fi
}

get_base_image() {
    local framework="$1"
    local custom_image="$2"
    local version="$3"  # Optional version parameter

    # Handle custom base image (bypass catalog)
    if [ "$framework" = "custom" ]; then
        echo "$custom_image"
        return 0
    fi

    # Look up in AIME v2 catalog (150+ pre-built framework images)
    local AIME_REPO="/opt/ds01-infra/aime-ml-containers/ml_images.repo"

    if [ -f "$AIME_REPO" ]; then
        # Capitalize framework name (AIME uses Pytorch, Tensorflow)
        local framework_capital=$(echo "$framework" | sed 's/tf/tensorflow/; s/\b\(.\)/\u\1/g')

        # Determine GPU architecture based on host driver (auto-detect if not specified)
        # Driver 535+ supports CUDA 12.x (CUDA_ADA), older drivers use CUDA 11.8 (CUDA_AMPERE)
        local arch="${MLC_ARCH:-$(detect_cuda_arch)}"

        # Look up specific version or latest
        local image=""
        if [ -n "$version" ]; then
            # Find exact version match (architecture in brackets: [CUDA_ADA])
            image=$(awk -F', ' -v fw="$framework_capital" -v ver="$version" -v arch="[$arch]" \
                '$1 == fw && $2 == ver && $3 == arch {print $4; exit}' "$AIME_REPO")
        fi

        # If no version specified or not found, get latest for this architecture
        if [ -z "$image" ]; then
            image=$(awk -F', ' -v fw="$framework_capital" -v arch="[$arch]" \
                '$1 == fw && $3 == arch {print $4; exit}' "$AIME_REPO")
        fi

        if [ -n "$image" ]; then
            echo "$image"
            [ -n "$VERBOSE" ] && echo -e "${GREEN}✓${NC} Using AIME v2 catalog image: ${YELLOW}$image${NC}" >&2
            return 0
        fi
    fi

    # Fallback: AIME catalog not found or framework not in catalog
    [ -n "$VERBOSE" ] && echo -e "${YELLOW}⚠${NC} AIME catalog not available, using Docker Hub fallback" >&2

    case $framework in
        tensorflow|tf)
            echo "tensorflow/tensorflow:2.14.0-gpu"
            ;;
        jax)
            echo "nvcr.io/nvidia/jax:23.10-py3"
            ;;
        pytorch-cpu)
            echo "pytorch/pytorch:2.5.1-cpu"
            ;;
        *)
            # Match fallback to auto-detected architecture
            if [ "$(detect_cuda_arch)" = "CUDA_ADA" ]; then
                echo "pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime"
            else
                echo "pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime"
            fi
            ;;
    esac
}

# Export for subshells
export -f detect_cuda_arch get_base_image
