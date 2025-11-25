#!/bin/bash
# Diagnose GID mapping issue in containers
# Run this on the DS01 server to investigate the "I have no name!" problem

set -e

BLUE='\033[94m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}DS01 GID Mapping Diagnostic Tool${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get container name from argument
CONTAINER_NAME="${1:-test5}"
USER_ID=$(id -u)
CONTAINER_TAG="${CONTAINER_NAME}._.${USER_ID}"

# Check if container exists
if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_TAG}$"; then
    echo -e "${RED}✗ Container '$CONTAINER_NAME' not found${NC}"
    echo ""
    echo "Available containers:"
    docker ps -a --filter "label=ds01.user=$(whoami)" --format "  {{.Names}}" | sed "s/\._\.${USER_ID}$//"
    exit 1
fi

echo -e "${GREEN}Checking container: $CONTAINER_TAG${NC}"
echo ""

# 1. Check host user info
echo -e "${YELLOW}═══ Host User Information ═══${NC}"
echo "  User: $(whoami)"
echo "  UID: $(id -u)"
echo "  GID: $(id -g)"
echo "  Groups: $(id -G)"
echo "  Group name: $(id -gn)"
echo ""

# 2. Check container /etc/passwd
echo -e "${YELLOW}═══ Container /etc/passwd ═══${NC}"
echo "Looking for UID $(id -u)..."
if docker exec "$CONTAINER_TAG" cat /etc/passwd 2>/dev/null | grep "$(id -u)"; then
    echo -e "${GREEN}✓ User entry found${NC}"
else
    echo -e "${RED}✗ No user entry for UID $(id -u)${NC}"
fi
echo ""

# 3. Check container /etc/group
echo -e "${YELLOW}═══ Container /etc/group ═══${NC}"
echo "Looking for GID $(id -g)..."
if docker exec "$CONTAINER_TAG" cat /etc/group 2>/dev/null | grep ":$(id -g):"; then
    echo -e "${GREEN}✓ Group entry found${NC}"
else
    echo -e "${RED}✗ No group entry for GID $(id -g)${NC}"
fi
echo ""

# 4. Check what container sees when running commands
echo -e "${YELLOW}═══ Container User Context ═══${NC}"
echo "Running 'id' inside container..."
docker exec "$CONTAINER_TAG" id 2>/dev/null || echo -e "${RED}(command failed)${NC}"
echo ""

echo "Running 'whoami' inside container..."
docker exec "$CONTAINER_TAG" whoami 2>/dev/null || echo -e "${RED}(command failed)${NC}"
echo ""

echo "Running 'groups' inside container..."
docker exec "$CONTAINER_TAG" groups 2>/dev/null || echo -e "${RED}(command failed)${NC}"
echo ""

# 5. Check container creation labels
echo -e "${YELLOW}═══ Container Docker Configuration ═══${NC}"
echo "User spec:"
docker inspect "$CONTAINER_TAG" --format '  {{.Config.User}}' 2>/dev/null
echo ""

echo "Image used:"
docker inspect "$CONTAINER_TAG" --format '  {{.Config.Image}}' 2>/dev/null
echo ""

# 6. Check if the committed image has the user
IMAGE=$(docker inspect "$CONTAINER_TAG" --format '{{.Config.Image}}' 2>/dev/null)
if [ -n "$IMAGE" ]; then
    echo -e "${YELLOW}═══ Checking Image: $IMAGE ═══${NC}"
    echo "Does image have user in /etc/passwd?"
    if docker run --rm "$IMAGE" cat /etc/passwd 2>/dev/null | grep "$(id -u)"; then
        echo -e "${GREEN}✓ User entry found in image${NC}"
    else
        echo -e "${RED}✗ No user entry for UID $(id -u) in image${NC}"
    fi
    echo ""

    echo "Does image have group in /etc/group?"
    if docker run --rm "$IMAGE" cat /etc/group 2>/dev/null | grep ":$(id -g):"; then
        echo -e "${GREEN}✓ Group entry found in image${NC}"
    else
        echo -e "${RED}✗ No group entry for GID $(id -g) in image${NC}"
    fi
    echo ""
fi

# 7. Show recommendations
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Diagnosis Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check for the specific error condition
HAS_USER=$(docker exec "$CONTAINER_TAG" cat /etc/passwd 2>/dev/null | grep -c "$(id -u)" || echo "0")
HAS_GROUP=$(docker exec "$CONTAINER_TAG" cat /etc/group 2>/dev/null | grep -c ":$(id -g):" || echo "0")

if [ "$HAS_USER" -eq 0 ] || [ "$HAS_GROUP" -eq 0 ]; then
    echo -e "${RED}ISSUE CONFIRMED: User/group not properly configured in container${NC}"
    echo ""
    echo -e "${YELLOW}The container is running with --user $(id -u):$(id -g)${NC}"
    echo -e "${YELLOW}but /etc/passwd and/or /etc/group don't have entries for these IDs${NC}"
    echo ""
    echo -e "${GREEN}Possible fixes:${NC}"
    echo ""
    echo "1. Check if mlc-patched.py addgroup/adduser commands ran successfully"
    echo "2. Check if docker commit properly saved /etc/passwd and /etc/group"
    echo "3. Verify container-init.sh or container-entrypoint.sh are being executed"
    echo ""
else
    echo -e "${GREEN}User and group entries found - issue may be elsewhere${NC}"
fi
