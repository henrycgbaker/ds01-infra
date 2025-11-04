# File: /opt/ds01-infra/scripts/user/ds01-setup-wizard.sh
#!/bin/bash
# DS01 Complete Setup Wizard - One script to rule them all
# Handles: SSH keys, project setup, image creation, VS Code integration

set -e

BLUE='\033[94m'  # Light blue 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

USERNAME=$(whoami)
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Logo
cat << "EOF"
    ____  ____  ____  ____
   / __ \/ ___\/ __ \/_ _ |
  / / / /\__ \/ / / /   | |
 / /_/ /___/ / /_/ /    | |
/_____/_____/\____/     |_/  GPU Server
                            
EOF

echo -e "${GREEN}${BOLD}Onboarding & Setup Wizard${NC}\n"

# Step 1: Check setup status
echo -e "${CYAN}━━━ Step 1: Checking Your Setup ━━━${NC}\n"

NEEDS_SSH=false
NEEDS_PROJECT=false
NEEDS_IMAGE=false

# Check SSH keys
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
    NEEDS_SSH=true
    echo -e "${YELLOW}✗${NC} SSH keys not configured"
else
    echo -e "${GREEN}✓${NC} SSH keys configured"
fi

# Check if user has any projects
if [ ! -d ~/workspace ] || [ -z "$(ls -A ~/workspace 2>/dev/null)" ]; then
    NEEDS_PROJECT=true
    echo -e "${YELLOW}✗${NC} No projects found"
else
    echo -e "${GREEN}✓${NC} Workspace exists: ~/workspace"
fi

# Check if user has any images (skip if docker access fails)
if docker images --format "{{.Repository}}" &>/dev/null; then
    USER_IMAGES=$(docker images --format "{{.Repository}}" 2>/dev/null | grep "^${USERNAME}-" | wc -l)
    if [ "$USER_IMAGES" -eq 0 ]; then
        NEEDS_IMAGE=true
        echo -e "${YELLOW}○${NC} No custom images yet (we'll create one)"
    else
        echo -e "${GREEN}✓${NC} $USER_IMAGES custom image(s) found"
    fi
else
    NEEDS_IMAGE=true
    echo -e "${YELLOW}○${NC} Docker access not configured (will set up later)"
fi

echo ""
read -p "Continue with setup? [Y/n]: " CONTINUE
CONTINUE=${CONTINUE:-Y}
if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
    exit 0
fi

# Step 2: SSH Key Setup (if needed)
if [ "$NEEDS_SSH" = true ]; then
    echo -e "\n${CYAN}━━━ Step 2: SSH Key Setup ━━━${NC}\n"
    echo "Setting up SSH keys for VS Code Remote access..."
    
    ssh-keygen -t ed25519 -C "${USERNAME}@ds01-server" -f ~/.ssh/id_ed25519 -N ""
    cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    echo -e "\n${GREEN}✓ SSH keys created${NC}"
    echo -e "\n${BOLD}Your public key:${NC}"
    echo -e "${BLUE}$(cat ~/.ssh/id_ed25519.pub)${NC}\n"
    
    echo -e "${YELLOW}📋 Save this for VS Code Remote-SSH configuration${NC}"
    read -p "Press Enter when ready to continue..."
fi

# Step 3: Project Setup
echo -e "\n${CYAN}━━━ Step 3: Project Setup ━━━${NC}\n"

read -p "Create a new project? [Y/n]: " CREATE_PROJECT
CREATE_PROJECT=${CREATE_PROJECT:-Y}

if [[ "$CREATE_PROJECT" =~ ^[Yy] ]]; then
    read -p "Project name (e.g., thesis, cv-experiments, nlp-project): " PROJECT_NAME
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    
    PROJECT_DIR="$HOME/workspace/$PROJECT_NAME"
    
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${YELLOW}⚠  Project directory already exists: $PROJECT_DIR${NC}"
        read -p "Use existing directory? [Y/n]: " USE_EXISTING
        if [[ ! "$USE_EXISTING" =~ ^[Yy] ]]; then
            exit 1
        fi
    else
        mkdir -p "$PROJECT_DIR"
        mkdir -p "$PROJECT_DIR"/{data,models,notebooks,scripts,outputs}
        
        # Create basic README
        cat > "$PROJECT_DIR/README.md" << READMEEOF
# $PROJECT_NAME

Created: $(date)
Author: $USERNAME

## Project Structure

\`\`\`
$PROJECT_NAME/
├── data/           # Raw and processed datasets
├── models/         # Saved model checkpoints
├── notebooks/      # Jupyter notebooks
├── scripts/        # Python scripts
├── outputs/        # Training logs, plots, results
└── README.md       # This file
\`\`\`

## Getting Started

1. Activate your container: \`mlc-open ${PROJECT_NAME}\`
2. Navigate to project: \`cd /workspace/${PROJECT_NAME}\`
3. Start coding!

## Notes

- Save all work in this directory (it persists)
- Checkpoint models regularly
- Document your experiments
READMEEOF
        
        echo -e "${GREEN}✓ Project structure created: $PROJECT_DIR${NC}"
    fi
else
    PROJECT_NAME="default"
    PROJECT_DIR="$HOME/workspace"
fi

# Step 4: Image Creation Wizard
echo -e "\n${CYAN}━━━ Step 4: Custom Image Setup ━━━${NC}\n"

read -p "Create a custom Docker image for this project? [Y/n]: " CREATE_IMAGE
CREATE_IMAGE=${CREATE_IMAGE:-Y}

if [[ "$CREATE_IMAGE" =~ ^[Yy] ]]; then
    
    # Image naming
    IMAGE_NAME="${USERNAME}-${PROJECT_NAME}"
    
    echo -e "\n${BOLD}Image will be named: ${CYAN}${IMAGE_NAME}${NC}\n"
    
    # Framework selection
    echo "Select base framework:"
    echo -e "  ${BOLD}1)${NC} PyTorch 2.5.1 + CUDA 11.8 (${GREEN}recommended${NC})"
    echo -e "  ${BOLD}2)${NC} TensorFlow 2.14.0 + CUDA 11.8"
    echo -e "  ${BOLD}3)${NC} PyTorch 2.5.1 (CPU only)"
    read -p "Choice [1-3, default: 1]: " FRAMEWORK_CHOICE
    
    case $FRAMEWORK_CHOICE in
        2)
            BASE_IMAGE="tensorflow/tensorflow:2.14.0-gpu"
            FRAMEWORK="tensorflow"
            ;;
        3)
            BASE_IMAGE="pytorch/pytorch:2.5.1-cpu"
            FRAMEWORK="pytorch-cpu"
            ;;
        *)
            BASE_IMAGE="pytorch/pytorch:2.5.1-cuda11.8-cudnn9-runtime"
            FRAMEWORK="pytorch"
            ;;
    esac
    
    # Use case packages
    echo -e "\n${BOLD}Select your use case (for pre-configured packages):${NC}"
    echo -e "  ${BOLD}1)${NC} Computer Vision (timm, albumentations, opencv)"
    echo -e "  ${BOLD}2)${NC} NLP (transformers, datasets, tokenizers)"
    echo -e "  ${BOLD}3)${NC} Reinforcement Learning (gymnasium, stable-baselines3)"
    echo -e "  ${BOLD}4)${NC} General ML (just the basics) (${GREEN}default${NC})"
    echo -e "  ${BOLD}5)${NC} Custom (I'll specify everything)"
    read -p "Choice [1-5, default: 4]: " USECASE_CHOICE
    
    USECASE_PACKAGES=""
    case $USECASE_CHOICE in
        1)
            USECASE_PACKAGES="timm albumentations opencv-python-headless torchvision"
            USECASE_NAME="Computer Vision"
            ;;
        2)
            USECASE_PACKAGES="transformers datasets tokenizers accelerate"
            USECASE_NAME="NLP"
            ;;
        3)
            USECASE_PACKAGES="gymnasium stable-baselines3 tensorboard"
            USECASE_NAME="Reinforcement Learning"
            ;;
        5)
            echo "Enter packages (space-separated):"
            read -p "> " USECASE_PACKAGES
            USECASE_NAME="Custom"
            ;;
        *)
            # Default to General ML (option 4 or invalid input)
            USECASE_PACKAGES=""
            USECASE_NAME="General ML"
            ;;
    esac
    
    # Additional packages
    echo -e "\n${BOLD}Additional packages?${NC} (space-separated, or press Enter to skip)"
    echo "Examples: wandb optuna pytorch-lightning"
    read -p "> " ADDITIONAL_PACKAGES
    
    # System packages
    echo -e "\n${BOLD}System packages (apt)?${NC} (or press Enter to skip)"
    echo "Examples: git vim htop tmux"
    read -p "> " SYSTEM_PACKAGES
    
    # Generate Dockerfile
    mkdir -p ~/docker-images
    DOCKERFILE_PATH=~/docker-images/${IMAGE_NAME}.Dockerfile
    
    cat > "$DOCKERFILE_PATH" << DOCKERFILEEOF
# DS01 Custom Image: $IMAGE_NAME
# Created: $(date)
# Use case: $USECASE_NAME
# Author: $USERNAME

FROM $BASE_IMAGE

LABEL maintainer="$USERNAME"
LABEL project="$PROJECT_NAME"
LABEL created="$(date -Iseconds)"

WORKDIR /workspace

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \\
    git \\
    curl \\
    wget \\
    vim \\
    ${SYSTEM_PACKAGES} \\
    && rm -rf /var/lib/apt/lists/*

# Core Python packages
RUN pip install --no-cache-dir \\
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
    Pillow

# Use case specific packages
$([ -n "$USECASE_PACKAGES" ] && echo "RUN pip install --no-cache-dir $USECASE_PACKAGES")

# Additional user packages
$([ -n "$ADDITIONAL_PACKAGES" ] && echo "RUN pip install --no-cache-dir $ADDITIONAL_PACKAGES")

# Configure Jupyter
RUN jupyter lab --generate-config && \\
    echo "c.ServerApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.allow_root = True" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.open_browser = False" >> /root/.jupyter/jupyter_lab_config.py

# IPython kernel
RUN python -m ipykernel install --user \\
    --name=$IMAGE_NAME \\
    --display-name="$PROJECT_NAME (GPU)"

# Environment
ENV PYTHONUNBUFFERED=1
ENV CUDA_DEVICE_ORDER=PCI_BUS_ID
ENV HF_HOME=/workspace/.cache/huggingface

# Auto-start Jupyter (optional - uncomment if desired)
# COPY <<'BASHRC' /root/.bashrc_jupyter
# if [[ \\\$- == *i* ]] && ! pgrep -f "jupyter-lab" > /dev/null; then
#     nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \\
#         --ServerApp.token="\\\$(hostname)-\\\$(id -u)" \\
#         > /workspace/.jupyter.log 2>&1 &
#     echo "🚀 Jupyter: http://localhost:8888/?token=\\\$(hostname)-\\\$(id -u)"
# fi
# BASHRC
# RUN cat /root/.bashrc_jupyter >> /root/.bashrc

CMD ["/bin/bash"]
DOCKERFILEEOF
    
    echo -e "\n${GREEN}✓ Dockerfile created${NC}"
    echo -e "Location: ${BLUE}$DOCKERFILE_PATH${NC}\n"
    
    # Build image
    read -p "Build image now? (takes 3-5 minutes) [Y/n]: " BUILD_NOW
    BUILD_NOW=${BUILD_NOW:-Y}
    
    if [[ "$BUILD_NOW" =~ ^[Yy] ]]; then
        echo -e "\n${CYAN}Building image... (this takes a few minutes)${NC}\n"
        
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" ~/docker-images/
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✓ Image built successfully: ${IMAGE_NAME}${NC}"
            
            # Save image metadata
            mkdir -p ~/ds01-config
            cat > ~/ds01-config/${IMAGE_NAME}.info << INFOEOF
Image: $IMAGE_NAME
Project: $PROJECT_NAME
Framework: $FRAMEWORK
Use Case: $USECASE_NAME
Created: $(date)
Dockerfile: $DOCKERFILE_PATH

Packages:
$([ -n "$USECASE_PACKAGES" ] && echo "- Use case: $USECASE_PACKAGES")
$([ -n "$ADDITIONAL_PACKAGES" ] && echo "- Additional: $ADDITIONAL_PACKAGES")

Commands:
- Create container: mlc-create-from-image ${PROJECT_NAME} ${IMAGE_NAME}
- Rebuild image: docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/
- Update packages: Edit $DOCKERFILE_PATH, then rebuild
INFOEOF
            
            CONTAINER_NAME="${PROJECT_NAME}"
        else
            echo -e "\n${RED}✗ Image build failed${NC}"
            echo "Check Dockerfile: $DOCKERFILE_PATH"
            exit 1
        fi
    else
        echo "Build later with:"
        echo "  ${CYAN}docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/${NC}"
        CONTAINER_NAME=""
    fi
else
    CONTAINER_NAME=""
    IMAGE_NAME=""
fi

# Step 5: Container Creation
if [ -n "$CONTAINER_NAME" ] && [ -n "$IMAGE_NAME" ]; then
    echo -e "\n${CYAN}━━━ Step 5: Container Creation ━━━${NC}\n"
    
    read -p "Create container from your image? [Y/n]: " CREATE_CONTAINER
    CREATE_CONTAINER=${CREATE_CONTAINER:-Y}
    
    if [[ "$CREATE_CONTAINER" =~ ^[Yy] ]]; then
        echo -e "\n${BLUE}Creating container with user namespace mapping...${NC}"
        
        # Use the mlc-create-from-image script
        bash /opt/ds01-infra/scripts/docker/mlc-create-from-image.sh "$CONTAINER_NAME" "$IMAGE_NAME" "$PROJECT_DIR"
        
        if [ $? -eq 0 ]; then
            CONTAINER_TAG="${CONTAINER_NAME}._.$USER_ID"
            
            # Add user namespace remapping
            docker stop "$CONTAINER_TAG" 2>/dev/null || true
            
            # Update container with user namespace
            docker update \
                --label "ds01.user=$USERNAME" \
                --label "ds01.project=$PROJECT_NAME" \
                "$CONTAINER_TAG" 2>/dev/null
            
            echo -e "\n${GREEN}✓ Container created with user namespaces${NC}"
        fi
    fi
fi


# Step 6: Git Setup
if [ -d "$PROJECT_DIR" ] && [ ! -d "$PROJECT_DIR/.git" ]; then
    echo -e "\n${CYAN}━━━ Step 6: Git Integration ━━━${NC}\n"
    
    read -p "Initialize Git for this project? [Y/n]: " INIT_GIT
    INIT_GIT=${INIT_GIT:-Y}
    
    if [[ "$INIT_GIT" =~ ^[Yy] ]]; then
        bash /opt/ds01-infra/scripts/user/git-setup-project.sh "$PROJECT_DIR"
    fi
fi

# Step 7: VS Code Setup Guide
echo -e "\n${CYAN}━━━ Step 6: VS Code Connection ━━━${NC}\n"

SERVER_IP=$(hostname -I | awk '{print $1}')

cat << VSCODEEOF
${BOLD}Connect from VS Code:${NC}

${YELLOW}1. Install VS Code Extensions:${NC}
   - Remote - SSH
   - Docker (optional but useful)
   - Python
   - Jupyter

${YELLOW}2. Configure SSH Connection:${NC}
   ${CYAN}Command Palette → "Remote-SSH: Open SSH Configuration File"${NC}
   
   Add this entry:
   
   ${BLUE}Host ds01
       HostName $SERVER_IP
       User $USERNAME
       ForwardAgent yes
       ServerAliveInterval 60${NC}

${YELLOW}3. Connect:${NC}
   ${CYAN}Command Palette → "Remote-SSH: Connect to Host" → Select "ds01"${NC}

${YELLOW}4. Open Your Project:${NC}
   ${CYAN}File → Open Folder → /home/$USERNAME/workspace/$PROJECT_NAME${NC}

${YELLOW}5. Work in Container (Terminal in VS Code):${NC}
   ${GREEN}mlc-open $CONTAINER_NAME${NC}
   ${GREEN}cd /workspace/$PROJECT_NAME${NC}

VSCODEEOF

# Summary file
mkdir -p ~/ds01-config
cat > ~/ds01-config/setup-summary.txt << SUMMARYEOF
DS01 Server Setup Summary
========================
Date: $(date)
User: $USERNAME
User ID: $USER_ID

SSH Configuration:
- Keys: ~/.ssh/id_ed25519{,.pub}
- Server: $SERVER_IP

Project Setup:
- Name: $PROJECT_NAME
- Directory: $PROJECT_DIR

$([ -n "$IMAGE_NAME" ] && echo "Docker Image:
- Name: $IMAGE_NAME
- Dockerfile: $DOCKERFILE_PATH
- Framework: $FRAMEWORK
- Packages: $USECASE_PACKAGES $ADDITIONAL_PACKAGES")

$([ -n "$CONTAINER_NAME" ] && echo "Container:
- Name: $CONTAINER_NAME
- Full name: ${CONTAINER_NAME}._.$USER_ID
- Open: mlc-open $CONTAINER_NAME
- Stop: mlc-stop $CONTAINER_NAME")

Quick Commands:
==============
# List containers
mlc-list

# Container lifecycle
mlc-open $CONTAINER_NAME
mlc-stop $CONTAINER_NAME
mlc-stats

# Add packages to image
Edit: $DOCKERFILE_PATH
Rebuild: docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/
Recreate: mlc-remove $CONTAINER_NAME && mlc-create-from-image $CONTAINER_NAME $IMAGE_NAME

VS Code Connection:
==================
ssh $USERNAME@$SERVER_IP

Documentation:
=============
/home/shared/docs/getting-started.md
/home/shared/docs/gpu-usage-guide.md

SUMMARYEOF

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}✓ Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "Summary saved to: ${BLUE}~/ds01-config/setup-summary.txt${NC}\n"

echo -e "${YELLOW}${BOLD}Next Steps:${NC}"
echo "  1. Connect VS Code to: $USERNAME@$SERVER_IP"
echo "  2. Open folder: $PROJECT_DIR"
$([ -n "$CONTAINER_NAME" ] && echo "  3. Start container: ${GREEN}mlc-open $CONTAINER_NAME${NC}")
echo ""
echo -e "${CYAN}💡 Tip: Run this wizard again anytime to create new projects/images${NC}"
echo ""