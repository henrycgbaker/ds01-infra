#!/bin/bash
# DS01 New User Setup Wizard
# Complete onboarding for first-time users

set -e

BLUE='\033[0;36m'
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
echo "    ____  ____  ____  ____"
echo "   / __ \/ ___\/ __ \/_ _ |"
echo "  / / / /\__ \/ / / /   | |"
echo " / /_/ /___/ / /_/ /    | |"
echo "/_____/_____/\____/     |_/  GPU Server"
echo ""
echo -e "${GREEN}${BOLD}New User Setup Wizard${NC}"
echo ""
echo -e "${CYAN}This wizard will help you:${NC}"
echo "  • Set up SSH keys for remote access (VS Code, PyCharm, terminal)"
echo "  • Create your first project directory structure"
echo "  • Build a custom Docker image with your preferred ML framework"
echo "  • Configure your development environment"
echo ""

# Step 1: Check setup status
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Step 1: Checking Your Setup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

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

# Check if user has any images
if timeout 2 docker info &>/dev/null; then
    USER_IMAGES=$(docker images --format "{{.Repository}}" 2>/dev/null | grep -v "^<none>$" | wc -l)
    if [ "$USER_IMAGES" -eq 0 ]; then
        NEEDS_IMAGE=true
        echo -e "${YELLOW}○${NC} No custom images yet"
    else
        echo -e "${GREEN}✓${NC} $USER_IMAGES custom image(s) found"
    fi
else
    NEEDS_IMAGE=true
    echo -e "${YELLOW}○${NC} Docker images (will check after setup)"
fi

echo ""
read -p "Continue with setup? [Y/n]: " CONTINUE
CONTINUE=${CONTINUE:-Y}
if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
    exit 0
fi

# Step 2: SSH Key Setup
if [ "$NEEDS_SSH" = true ]; then
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Step 2: SSH Key Setup${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Why do you need SSH keys?${NC}"
    echo "SSH keys allow you to connect to this server securely from your local"
    echo "computer using tools like VS Code, PyCharm, or terminal. This is the"
    echo "recommended way to work on the server."
    echo ""
    echo -e "${BOLD}What we'll do:${NC}"
    echo "  1. Generate a new SSH key pair (public + private key)"
    echo "  2. Add the public key to your authorized_keys file"
    echo "  3. Display your public key for configuring local SSH client"
    echo ""

    read -p "Generate SSH keys now? [Y/n]: " DO_SSH
    DO_SSH=${DO_SSH:-Y}

    if [[ "$DO_SSH" =~ ^[Yy] ]]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh

        ssh-keygen -t ed25519 -C "${USERNAME}@ds01-server" -f ~/.ssh/id_ed25519 -N ""
        cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys

        echo ""
        echo -e "${GREEN}✓ SSH keys created successfully${NC}"
        echo ""
        echo -e "${BOLD}Your public key:${NC}"
        echo -e "${BLUE}$(cat ~/.ssh/id_ed25519.pub)${NC}"
        echo ""
        echo -e "${YELLOW}📋 Save this key - you'll need it to configure VS Code Remote-SSH${NC}"
        echo ""
        read -p "Press Enter when ready to continue..."
    fi
else
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Step 2: SSH Key Setup${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}✓ Skipped${NC} - You already have SSH keys configured"
    echo "  Location: ~/.ssh/id_ed25519.pub"
    echo ""
fi

# Step 3: Project Setup
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Step 3: Project Setup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}What is a project?${NC}"
echo "A project is a workspace directory that contains all your code, data, models,"
echo "and outputs. Your project directory is mounted into your container, so all"
echo "changes you make inside the container persist after it stops."
echo ""
echo -e "${BOLD}Why create a project?${NC}"
echo "  • Organized structure (data/, models/, scripts/, notebooks/)"
echo "  • Persistent storage across container restarts"
echo "  • Easy backup and version control"
echo "  • One project per research task/thesis/experiment"
echo ""
echo -e "${YELLOW}Note:${NC} We'll create a standard ML project layout with data/, models/,"
echo "notebooks/, scripts/, and outputs/ directories. This is an industry-standard"
echo "template, but you can customize it however you prefer for your workflow."
echo ""

read -p "Create a new project? [Y/n]: " CREATE_PROJECT
CREATE_PROJECT=${CREATE_PROJECT:-Y}

if [[ "$CREATE_PROJECT" =~ ^[Yy] ]]; then
    echo ""
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
        cat > "$PROJECT_DIR/README.md" <<'READMEEOF'
# PROJECT_NAME_PLACEHOLDER

Created: DATE_PLACEHOLDER
Author: USERNAME_PLACEHOLDER

## Project Structure

```
PROJECT_NAME_PLACEHOLDER/
├── data/           # Raw and processed datasets
├── models/         # Saved model checkpoints
├── notebooks/      # Jupyter notebooks
├── scripts/        # Python scripts
├── outputs/        # Training logs, plots, results
└── README.md       # This file
```

## Getting Started

1. Activate your container: `container-run PROJECT_NAME_PLACEHOLDER-image`
2. Navigate to project: `cd /workspace/PROJECT_NAME_PLACEHOLDER`
3. Start coding!

## Notes

- Save all work in this directory (it persists)
- Checkpoint models regularly
- Document your experiments
READMEEOF

        # Replace placeholders
        sed -i "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/g" "$PROJECT_DIR/README.md"
        sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" "$PROJECT_DIR/README.md"
        sed -i "s/DATE_PLACEHOLDER/$(date)/g" "$PROJECT_DIR/README.md"

        echo ""
        echo -e "${GREEN}✓ Project structure created${NC}"
        echo -e "  Location: ${BLUE}$PROJECT_DIR${NC}"
        echo ""
    fi
else
    PROJECT_NAME="default"
    PROJECT_DIR="$HOME/workspace"
fi

# Step 4: Image Creation
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Step 4: Custom Docker Image${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}What is a Docker image?${NC}"
echo "A Docker image is a template that contains all the software you need:"
echo "  • Base OS (Ubuntu)"
echo "  • ML framework (PyTorch, TensorFlow)"
echo "  • Python packages (numpy, pandas, transformers, etc.)"
echo "  • System tools (git, vim, etc.)"
echo ""
echo -e "${BOLD}Why create a custom image?${NC}"
echo "  • Install exactly the packages YOU need"
echo "  • Avoid conflicts between different projects"
echo "  • Reproducible environment (same setup every time)"
echo "  • Share with collaborators"
echo ""

read -p "Create a custom Docker image for this project? [Y/n]: " CREATE_IMAGE
CREATE_IMAGE=${CREATE_IMAGE:-Y}

if [[ "$CREATE_IMAGE" =~ ^[Yy] ]]; then

    # Image naming (without username prefix)
    IMAGE_NAME="${PROJECT_NAME}-image"

    echo ""
    echo -e "${BOLD}Image will be named: ${CYAN}${IMAGE_NAME}${NC}"
    echo ""

    # Framework selection
    echo -e "${BOLD}Select base ML framework:${NC}"
    echo -e "  ${BOLD}1)${NC} PyTorch 2.5.1 + CUDA 11.8 ${GREEN}(recommended for deep learning)${NC}"
    echo -e "  ${BOLD}2)${NC} TensorFlow 2.14.0 + CUDA 11.8"
    echo -e "  ${BOLD}3)${NC} PyTorch 2.5.1 (CPU only - no GPU support)"
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
    echo ""
    echo -e "${BOLD}Select your use case (pre-configured package bundles):${NC}"
    echo -e "  ${BOLD}1)${NC} Computer Vision (timm, albumentations, opencv)"
    echo -e "  ${BOLD}2)${NC} NLP (transformers, datasets, tokenizers)"
    echo -e "  ${BOLD}3)${NC} Reinforcement Learning (gymnasium, stable-baselines3)"
    echo -e "  ${BOLD}4)${NC} General ML (just the basics) ${GREEN}(default)${NC}"
    echo -e "  ${BOLD}5)${NC} Custom (I'll specify packages manually)"
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
            USECASE_PACKAGES=""
            USECASE_NAME="General ML"
            ;;
    esac

    # Additional packages
    echo ""
    echo -e "${BOLD}Additional Python packages?${NC} (space-separated, or press Enter to skip)"
    echo "Examples: wandb optuna pytorch-lightning"
    read -p "> " ADDITIONAL_PACKAGES

    # System packages
    echo ""
    echo -e "${BOLD}System packages (apt)?${NC} (or press Enter to skip)"
    echo "Examples: git vim htop tmux"
    read -p "> " SYSTEM_PACKAGES

    # Generate Dockerfile
    mkdir -p ~/docker-images
    DOCKERFILE_PATH=~/docker-images/${IMAGE_NAME}.Dockerfile

    cat > "$DOCKERFILE_PATH" <<DOCKERFILEEOF
# DS01 Custom Image: $IMAGE_NAME
# Created: $(date)
# Use case: $USECASE_NAME
# Author: $USERNAME

FROM $BASE_IMAGE

# Docker labels for ownership tracking (instead of name prefix)
LABEL ds01.owner="$USERNAME"
LABEL ds01.project="$PROJECT_NAME"
LABEL ds01.framework="$FRAMEWORK"
LABEL ds01.usecase="$USECASE_NAME"
LABEL ds01.created="$(date -Iseconds)"

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

CMD ["/bin/bash"]
DOCKERFILEEOF

    echo ""
    echo -e "${GREEN}✓ Dockerfile created${NC}"
    echo -e "  Location: ${BLUE}$DOCKERFILE_PATH${NC}"
    echo ""

    # Build image
    read -p "Build image now? (takes 3-5 minutes) [Y/n]: " BUILD_NOW
    BUILD_NOW=${BUILD_NOW:-Y}

    if [[ "$BUILD_NOW" =~ ^[Yy] ]]; then
        echo ""
        echo -e "${CYAN}Building Docker image...${NC}"
        echo -e "${YELLOW}This will take 3-5 minutes. Sit tight!${NC}"
        echo ""

        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" ~/docker-images/

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✓ Image built successfully: ${IMAGE_NAME}${NC}"
            echo ""

            # Save image metadata
            mkdir -p ~/ds01-config/images
            cat > ~/ds01-config/images/${IMAGE_NAME}.info <<INFOEOF
Image: $IMAGE_NAME
Project: $PROJECT_NAME
Owner: $USERNAME
Framework: $FRAMEWORK
Use Case: $USECASE_NAME
Created: $(date)
Dockerfile: $DOCKERFILE_PATH

Packages:
$([ -n "$USECASE_PACKAGES" ] && echo "- Use case: $USECASE_PACKAGES")
$([ -n "$ADDITIONAL_PACKAGES" ] && echo "- Additional: $ADDITIONAL_PACKAGES")

Commands:
- Create container: container-create ${PROJECT_NAME} ${IMAGE_NAME}
- Rebuild image: docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/
- Update packages: Edit $DOCKERFILE_PATH, then rebuild
INFOEOF

        else
            echo ""
            echo -e "${RED}✗ Image build failed${NC}"
            echo "Check Dockerfile: $DOCKERFILE_PATH"
            exit 1
        fi
    else
        echo ""
        echo "Build later with:"
        echo -e "  ${CYAN}docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/${NC}"
        echo ""
    fi
else
    echo ""
    echo -e "${GREEN}✓ Skipped${NC} - You can create custom images later"
    echo -e "  Use: ${CYAN}image-create${NC} or ${CYAN}new-project-setup${NC}"
    echo ""
    IMAGE_NAME=""
fi

# Step 5: VS Code Setup Guide
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Step 5: VS Code Connection${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${BOLD}Connect from VS Code:${NC}"
echo ""
echo -e "${YELLOW}1. Install VS Code Extensions:${NC}"
echo "   - Remote - SSH"
echo "   - Docker (optional but useful)"
echo "   - Python"
echo "   - Jupyter"
echo ""
echo -e "${YELLOW}2. Configure SSH Connection:${NC}"
echo -e "   ${CYAN}Command Palette → \"Remote-SSH: Open SSH Configuration File\"${NC}"
echo ""
echo "   Add this entry:"
echo ""
echo -e "   ${BLUE}Host ds01"
echo "       HostName $SERVER_IP"
echo "       User $USERNAME"
echo "       ForwardAgent yes"
echo -e "       ServerAliveInterval 60${NC}"
echo ""
echo -e "${YELLOW}3. Connect:${NC}"
echo -e "   ${CYAN}Command Palette → \"Remote-SSH: Connect to Host\" → Select \"ds01\"${NC}"
echo ""
echo -e "${YELLOW}4. Open Your Project:${NC}"
echo -e "   ${CYAN}File → Open Folder → /home/$USERNAME/workspace/$PROJECT_NAME${NC}"
echo ""
if [ -n "$IMAGE_NAME" ]; then
    echo -e "${YELLOW}5. Work in Container (Terminal in VS Code):${NC}"
    echo -e "   ${GREEN}container-create $PROJECT_NAME $IMAGE_NAME${NC}"
    echo -e "   ${GREEN}container-run $PROJECT_NAME${NC}"
    echo ""
fi

# Summary file
mkdir -p ~/ds01-config
cat > ~/ds01-config/setup-summary.txt <<SUMMARYEOF
DS01 Server Setup Summary
=========================
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
- Use case: $USECASE_NAME")

Quick Commands:
===============
# List containers
container-list

# Create container from your image
$([ -n "$IMAGE_NAME" ] && echo "container-create $PROJECT_NAME $IMAGE_NAME")

# Start container
$([ -n "$IMAGE_NAME" ] && echo "container-run $PROJECT_NAME")

# Stop container
$([ -n "$IMAGE_NAME" ] && echo "container-stop $PROJECT_NAME")

# Container stats
container-stats

# Add packages to image
Edit: $DOCKERFILE_PATH
Rebuild: docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH ~/docker-images/

VS Code Connection:
===================
ssh $USERNAME@$SERVER_IP

Documentation:
==============
/home/shared/docs/getting-started.md
/home/shared/docs/gpu-usage-guide.md

SUMMARYEOF

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}✓ Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Summary saved to: ${BLUE}~/ds01-config/setup-summary.txt${NC}"
echo ""
echo -e "${YELLOW}${BOLD}Next Steps:${NC}"
echo "  1. Connect VS Code to: $USERNAME@$SERVER_IP"
echo "  2. Open folder: $PROJECT_DIR"
if [ -n "$IMAGE_NAME" ]; then
    echo -e "  3. Create container: ${GREEN}container-create $PROJECT_NAME $IMAGE_NAME${NC}"
    echo -e "  4. Start container: ${GREEN}container-run $PROJECT_NAME${NC}"
fi
echo ""
echo -e "${CYAN}💡 Tip: Run ${BOLD}new-project-setup${NC}${CYAN} to create additional projects${NC}"
echo ""
