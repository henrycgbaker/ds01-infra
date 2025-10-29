#!/bin/bash
# Manage custom Docker images

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

USERNAME=$(whoami)

show_menu() {
    cat << EOF

${GREEN}========================================
DS01 - Manage Your Docker Images
========================================${NC}

1) List my images
2) Rebuild an image (update packages)
3) Delete an image
4) Show image details
5) Create new image
6) Export image (for backup/sharing)
7) Import image
8) Exit

EOF
}

list_images() {
    echo -e "\n${BLUE}Your Docker images:${NC}\n"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" \
        --filter "reference=${USERNAME}-*"
    echo ""
}

rebuild_image() {
    list_images
    read -p "Enter image name to rebuild: " IMAGE_NAME
    
    DOCKERFILE=~/docker-images/${IMAGE_NAME}.Dockerfile
    
    if [ ! -f "$DOCKERFILE" ]; then
        echo -e "${YELLOW}Dockerfile not found: $DOCKERFILE${NC}"
        read -p "Enter path to Dockerfile: " DOCKERFILE
    fi
    
    if [ -f "$DOCKERFILE" ]; then
        echo -e "\n${BLUE}Rebuilding $IMAGE_NAME...${NC}"
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" ~/docker-images/
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✅ Image rebuilt successfully!${NC}"
            echo -e "\n${YELLOW}⚠️  Recreate containers to use updated image:${NC}"
            echo "  1. mlc-remove old-container"
            echo "  2. mlc-create-from-image new-container $IMAGE_NAME"
        fi
    else
        echo "Dockerfile not found"
    fi
}

delete_image() {
    list_images
    read -p "Enter image name to delete: " IMAGE_NAME
    read -p "Are you sure? This cannot be undone! [y/N]: " CONFIRM
    
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        # Check for running containers
        CONTAINERS=$(docker ps -a --filter "ancestor=$IMAGE_NAME" --format "{{.Names}}")
        if [ -n "$CONTAINERS" ]; then
            echo -e "${YELLOW}Warning: These containers use this image:${NC}"
            echo "$CONTAINERS"
            read -p "Delete them too? [y/N]: " DELETE_CONTAINERS
            if [[ "$DELETE_CONTAINERS" =~ ^[Yy]$ ]]; then
                echo "$CONTAINERS" | xargs -r docker rm -f
            else
                echo "Aborted. Remove containers first."
                return
            fi
        fi
        
        docker rmi "$IMAGE_NAME"
        echo -e "${GREEN}✅ Image deleted${NC}"
    fi
}

show_details() {
    list_images
    read -p "Enter image name: " IMAGE_NAME
    
    echo -e "\n${BLUE}Image: $IMAGE_NAME${NC}"
    docker image inspect "$IMAGE_NAME" --format='
Size: {{.Size | printf "%.2f MB" (div . 1048576)}}
Created: {{.Created}}
Architecture: {{.Architecture}}
OS: {{.Os}}
'
    
    # Show Dockerfile if available
    DOCKERFILE=~/docker-images/${IMAGE_NAME}.Dockerfile
    if [ -f "$DOCKERFILE" ]; then
        echo -e "\n${BLUE}Dockerfile location:${NC} $DOCKERFILE"
    fi
    
    # Show containers using this image
    echo -e "\n${BLUE}Containers using this image:${NC}"
    docker ps -a --filter "ancestor=$IMAGE_NAME" --format "  - {{.Names}} ({{.Status}})" || echo "  None"
}

export_image() {
    list_images
    read -p "Enter image name to export: " IMAGE_NAME
    OUTPUT_FILE=~/docker-images/${IMAGE_NAME}.tar
    
    echo -e "\n${BLUE}Exporting to $OUTPUT_FILE...${NC}"
    docker save -o "$OUTPUT_FILE" "$IMAGE_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Exported successfully!${NC}"
        echo "Size: $(du -h $OUTPUT_FILE | cut -f1)"
        echo ""
        echo "To import on another machine:"
        echo "  docker load -i ${IMAGE_NAME}.tar"
    fi
}

import_image() {
    read -p "Enter path to .tar file: " TAR_FILE
    
    if [ -f "$TAR_FILE" ]; then
        echo -e "\n${BLUE}Importing...${NC}"
        docker load -i "$TAR_FILE"
        echo -e "${GREEN}✅ Imported successfully!${NC}"
    else
        echo "File not found: $TAR_FILE"
    fi
}

# Main loop
while true; do
    show_menu
    read -p "Choice [1-8]: " choice
    
    case $choice in
        1) list_images ;;
        2) rebuild_image ;;
        3) delete_image ;;
        4) show_details ;;
        5) bash /opt/ds01-infra/scripts/user/create-custom-image.sh ;;
        6) export_image ;;
        7) import_image ;;
        8) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid choice" ;;
    esac
    
    read -p "Press Enter to continue..."
done