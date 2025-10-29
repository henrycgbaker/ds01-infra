#!/bin/bash
# Student onboarding script - Run once to set up everything
# Usage: bash /opt/ds01-infra/scripts/user/student-setup.sh


#TODO CHANGE THIS SO IT ALSO SETS UP DIRECTORIES AND USER GROUPS AND PERSMISSIONS ETC

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==================================="
echo "DS01 GPU Server - Student Setup"
echo -e "===================================${NC}\n"

# Get student info
read -p "Enter your first name: " FIRST_NAME
read -p "Enter your project name (e.g., thesis, cv-project): " PROJECT_NAME

CONTAINER_NAME="${FIRST_NAME}-${PROJECT_NAME}"
USERNAME=$(whoami)

echo -e "\n${BLUE}Step 1: Creating your container...${NC}"
echo "Container name: $CONTAINER_NAME"

# Check if mlc-create exists
if ! command -v mlc-create &> /dev/null; then
    echo -e "${YELLOW}Warning: mlc-create not found in PATH${NC}"
    echo "Using full path: /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh"
    MLC_CREATE="/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh"
else
    MLC_CREATE="mlc-create"
fi

# Create container
$MLC_CREATE "$CONTAINER_NAME" pytorch

echo -e "\n${BLUE}Step 2: Setting up Jupyter and tools...${NC}"

# Open container and configure
docker exec -it "${CONTAINER_NAME}._.$(id -u)" bash << 'CONTAINER_EOF'

# Install additional packages students commonly need
pip install --quiet \
    transformers \
    datasets \
    wandb \
    tensorboard \
    plotly

# Set up IPython kernel
python -m ipykernel install --user \
    --name=$(hostname | cut -d. -f1) \
    --display-name="GPU (PyTorch)"

# Add auto-start Jupyter to bashrc
if ! grep -q "Auto-start Jupyter" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOF'

# Auto-start Jupyter when container opens
if [[ $- == *i* ]] && ! pgrep -f "jupyter-lab" > /dev/null; then
    TOKEN="$(hostname | cut -d. -f1)-$(id -u)"
    nohup jupyter lab \
        --ip=0.0.0.0 \
        --port=8888 \
        --no-browser \
        --ServerApp.token="$TOKEN" \
        --ServerApp.allow_origin='*' \
        > /workspace/.jupyter.log 2>&1 &
    
    echo "🚀 Jupyter Lab started on port 8888"
    echo "   Token: $TOKEN"
fi
EOF
fi

echo "✅ Container configured!"
CONTAINER_EOF

# Stop container (student will open it when ready)
docker stop "${CONTAINER_NAME}._.$(id -u)" 2>/dev/null || true

echo -e "\n${GREEN}✅ Setup complete!${NC}\n"

# Generate connection info
TOKEN="${CONTAINER_NAME}-$(id -u)"
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}==================================="
echo "Your Container Information"
echo -e "===================================${NC}"
echo "Container name: $CONTAINER_NAME"
echo "Jupyter token:  $TOKEN"
echo "Server:         $SERVER_IP"
echo ""

# Create a config file for the student
mkdir -p ~/ds01-config
cat > ~/ds01-config/connection-info.txt << EOF
DS01 GPU Server - Your Connection Info
======================================

Container: $CONTAINER_NAME
Username:  $USERNAME
Server:    $SERVER_IP
Jupyter Token: $TOKEN

How to connect from VS Code:
1. Install "Remote - SSH" extension
2. Press F1 → "Remote-SSH: Connect to Host"
3. Enter: $USERNAME@$SERVER_IP
4. Open folder: /home/$USERNAME/workspace

How to use Jupyter:
1. Open container: mlc-open $CONTAINER_NAME
2. Jupyter starts automatically
3. In VS Code: Open .ipynb file → Select kernel "GPU (PyTorch)"

Commands:
- Open container:  mlc-open $CONTAINER_NAME
- List containers: mlc-list
- Stop container:  mlc-stop $CONTAINER_NAME

Documentation: /home/shared/docs/getting-started.md
EOF

echo -e "${BLUE}Connection info saved to: ~/ds01-config/connection-info.txt${NC}\n"

echo -e "${GREEN}Next steps:${NC}"
echo "1. Open your container: ${GREEN}mlc-open $CONTAINER_NAME${NC}"
echo "2. On your laptop:"
echo "   - Install VS Code 'Remote - SSH' extension"
echo "   - Connect to: $USERNAME@$SERVER_IP"
echo "   - Open folder: /home/$USERNAME/workspace"
echo "3. Start coding!"
echo ""
echo -e "${YELLOW}Save your Jupyter token: $TOKEN${NC}"
echo ""