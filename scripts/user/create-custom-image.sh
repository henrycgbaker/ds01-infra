#!/bin/bash
# Interactive custom image creator for students
# Creates a personalized Dockerfile with their package requirements

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================="
echo "DS01 - Create Your Custom Docker Image"
echo -e "=========================================${NC}\n"

# Get student info
USERNAME=$(whoami)
read -p "Enter a name for your image (e.g., my-pytorch, thesis-cv): " IMAGE_NAME
IMAGE_NAME="${USERNAME}-${IMAGE_NAME}"

# Framework selection
echo -e "\n${BLUE}Select base framework:${NC}"
echo "1) PyTorch (recommended for most deep learning)"
echo "2) TensorFlow"
echo "3) JAX"
read -p "Choice [1-3]: " FRAMEWORK_CHOICE

case $FRAMEWORK_CHOICE in
    1)
        BASE_IMAGE="pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime"
        FRAMEWORK="pytorch"
        ;;
    2)
        BASE_IMAGE="tensorflow/tensorflow:2.14.0-gpu"
        FRAMEWORK="tensorflow"
        ;;
    3)
        BASE_IMAGE="nvcr.io/nvidia/jax:23.10-py3"
        FRAMEWORK="jax"
        ;;
    *)
        echo "Invalid choice, using PyTorch"
        BASE_IMAGE="pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime"
        FRAMEWORK="pytorch"
        ;;
esac

# Common packages
echo -e "\n${BLUE}Common packages (will be included):${NC}"
COMMON_PACKAGES="jupyter jupyterlab ipykernel numpy pandas matplotlib seaborn scikit-learn"
echo "  $COMMON_PACKAGES"

# Additional packages
echo -e "\n${BLUE}Additional Python packages:${NC}"
echo "Enter package names separated by spaces (or press Enter for none)"
echo "Examples: transformers wandb timm opencv-python"
read -p "> " ADDITIONAL_PACKAGES

# Domain-specific suggestions
echo -e "\n${BLUE}Common use cases:${NC}"
echo "1) Computer Vision (adds: torchvision timm albumentations opencv-python)"
echo "2) NLP (adds: transformers datasets tokenizers)"
echo "3) Reinforcement Learning (adds: gymnasium stable-baselines3)"
echo "4) None / Custom only"
read -p "Choice [1-4]: " USECASE_CHOICE

USECASE_PACKAGES=""
case $USECASE_CHOICE in
    1)
        USECASE_PACKAGES="torchvision timm albumentations opencv-python-headless"
        ;;
    2)
        USECASE_PACKAGES="transformers datasets tokenizers"
        ;;
    3)
        USECASE_PACKAGES="gymnasium stable-baselines3"
        ;;
esac

# System packages
echo -e "\n${BLUE}System packages (apt):${NC}"
echo "Enter system packages separated by spaces (or press Enter for none)"
echo "Examples: git vim htop ffmpeg"
read -p "> " SYSTEM_PACKAGES

# Create directory for Dockerfiles
mkdir -p ~/docker-images
DOCKERFILE_PATH=~/docker-images/${IMAGE_NAME}.Dockerfile

# Generate Dockerfile
cat > "$DOCKERFILE_PATH" << EOF
# Custom Docker Image: $IMAGE_NAME
# Created: $(date)
# Base framework: $FRAMEWORK

FROM $BASE_IMAGE

WORKDIR /workspace

# Install system packages
RUN apt-get update && apt-get install -y \\
    git \\
    vim \\
    curl \\
    wget \\
    ${SYSTEM_PACKAGES} \\
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \\
    # Common packages
    jupyter \\
    jupyterlab \\
    ipykernel \\
    numpy \\
    pandas \\
    matplotlib \\
    seaborn \\
    scikit-learn \\
    scipy \\
    tqdm \\
    tensorboard \\
    Pillow \\
    # Domain-specific packages
    ${USECASE_PACKAGES} \\
    # Your custom packages
    ${ADDITIONAL_PACKAGES}

# Configure Jupyter
RUN jupyter lab --generate-config && \\
    echo "c.ServerApp.ip = '0.0.0.0'" >> ~/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.allow_root = True" >> ~/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.open_browser = False" >> ~/.jupyter/jupyter_lab_config.py

# Create IPython kernel
RUN python -m ipykernel install --user --name=$IMAGE_NAME --display-name="$IMAGE_NAME"

# Auto-start Jupyter script
COPY <<'BASHRC_EOF' /root/.bashrc_jupyter
# Auto-start Jupyter when container opens
if [[ \$- == *i* ]] && ! pgrep -f "jupyter-lab" > /dev/null; then
    TOKEN="\$(hostname | cut -d. -f1)-\$(id -u)"
    nohup jupyter lab \\
        --ip=0.0.0.0 \\
        --port=8888 \\
        --no-browser \\
        --ServerApp.token="\$TOKEN" \\
        --ServerApp.allow_origin='*' \\
        > /workspace/.jupyter.log 2>&1 &
    echo "🚀 Jupyter Lab started on port 8888"
    echo "   Token: \$TOKEN"
fi
BASHRC_EOF

RUN cat /root/.bashrc_jupyter >> /root/.bashrc

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV CUDA_DEVICE_ORDER=PCI_BUS_ID

# Default command
CMD ["/bin/bash"]

# ==================================================
# How to use this image:
# ==================================================
# 
# Build:  docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH .
# Run:    mlc-create-from-image my-container $IMAGE_NAME
# Update: Edit this file, then rebuild
#
# ==================================================
EOF

echo -e "\n${GREEN}✅ Dockerfile created!${NC}"
echo "Location: $DOCKERFILE_PATH"

# Offer to build now
read -p "Build image now? (recommended) [Y/n]: " BUILD_NOW
BUILD_NOW=${BUILD_NOW:-Y}

if [[ "$BUILD_NOW" =~ ^[Yy] ]]; then
    echo -e "\n${BLUE}Building image (this may take 5-10 minutes)...${NC}"
    
    # Build the image
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" ~/docker-images/
    
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✅ Image built successfully!${NC}"
        
        # Save image info
        mkdir -p ~/ds01-config
        cat > ~/ds01-config/${IMAGE_NAME}-info.txt << INFO_EOF
Image Name: $IMAGE_NAME
Base: $BASE_IMAGE
Created: $(date)
Dockerfile: $DOCKERFILE_PATH

Packages:
- Common: $COMMON_PACKAGES
- Use case: $USECASE_PACKAGES
- Additional: $ADDITIONAL_PACKAGES
- System: $SYSTEM_PACKAGES

Commands:
- Create container: mlc-create-from-image my-container $IMAGE_NAME
- Rebuild image:    docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/
- Update packages:  Edit $DOCKERFILE_PATH then rebuild
INFO_EOF
        
        echo -e "\n${GREEN}Next steps:${NC}"
        echo "1. Create a container from your image:"
        echo "   ${GREEN}mlc-create-from-image my-project $IMAGE_NAME${NC}"
        echo ""
        echo "2. To add more packages later:"
        echo "   - Edit: $DOCKERFILE_PATH"
        echo "   - Rebuild: docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/"
        echo "   - Recreate containers from updated image"
        echo ""
        echo -e "${YELLOW}💡 Tip: Keep your Dockerfile in version control!${NC}"
        
    else
        echo -e "\n${YELLOW}⚠️  Build failed. Check Dockerfile: $DOCKERFILE_PATH${NC}"
        exit 1
    fi
else
    echo -e "\n${BLUE}Build later with:${NC}"
    echo "docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/"
fi

echo ""