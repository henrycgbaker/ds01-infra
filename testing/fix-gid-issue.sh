#!/bin/bash
# Fix GID mapping issue in existing containers
# This adds user/group entries to /etc/passwd and /etc/group if missing

set -e

BLUE='\033[94m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get container name from argument
CONTAINER_NAME="${1}"
if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${RED}Usage: $0 <container-name>${NC}"
    echo ""
    echo "Example: $0 test5"
    exit 1
fi

USER_ID=$(id -u)
GROUP_ID=$(id -g)
USER_NAME=$(whoami)
CONTAINER_TAG="${CONTAINER_NAME}._.${USER_ID}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Fixing GID Mapping for Container: $CONTAINER_NAME${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if container exists
if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_TAG}$"; then
    echo -e "${RED}✗ Container '$CONTAINER_NAME' not found${NC}"
    exit 1
fi

# Check if container is running
IS_RUNNING=false
if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_TAG}$"; then
    IS_RUNNING=true
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${YELLOW}○ Container is stopped. Starting it...${NC}"
    docker start "$CONTAINER_TAG" > /dev/null 2>&1
    sleep 2
fi
echo ""

echo -e "${YELLOW}Host user info:${NC}"
echo "  User: $USER_NAME"
echo "  UID: $USER_ID"
echo "  GID: $GROUP_ID"
echo ""

# Check current state
echo -e "${YELLOW}Checking current container state...${NC}"
HAS_USER=$(docker exec "$CONTAINER_TAG" sh -c "getent passwd $USER_ID" 2>/dev/null | wc -l)
HAS_GROUP=$(docker exec "$CONTAINER_TAG" sh -c "getent group $GROUP_ID" 2>/dev/null | wc -l)

if [ "$HAS_USER" -gt 0 ]; then
    echo -e "${GREEN}✓ User entry exists${NC}"
else
    echo -e "${RED}✗ User entry missing${NC}"
fi

if [ "$HAS_GROUP" -gt 0 ]; then
    echo -e "${GREEN}✓ Group entry exists${NC}"
else
    echo -e "${RED}✗ Group entry missing${NC}"
fi
echo ""

# Apply fix if needed
if [ "$HAS_USER" -eq 0 ] || [ "$HAS_GROUP" -eq 0 ]; then
    echo -e "${YELLOW}Applying fix...${NC}"
    echo ""

    # Create a fix script to run inside container
    FIX_SCRIPT=$(cat <<'FIXEOF'
#!/bin/bash
USER_ID=%USER_ID%
GROUP_ID=%GROUP_ID%
USER_NAME=%USER_NAME%

# Check if group exists, if not create it
if ! getent group $GROUP_ID > /dev/null 2>&1; then
    # Check if group name exists
    if getent group $USER_NAME > /dev/null 2>&1; then
        # Group name exists with different GID, delete it
        groupdel $USER_NAME 2>/dev/null || true
    fi
    # Create group
    groupadd -g $GROUP_ID $USER_NAME 2>/dev/null || addgroup --gid $GROUP_ID $USER_NAME 2>/dev/null || true
fi

# Check if user exists, if not create it
if ! getent passwd $USER_ID > /dev/null 2>&1; then
    # Check if username exists
    if getent passwd $USER_NAME > /dev/null 2>&1; then
        # Username exists with different UID, delete it
        userdel $USER_NAME 2>/dev/null || true
    fi
    # Create user
    useradd -u $USER_ID -g $GROUP_ID -d /workspace -s /bin/bash $USER_NAME 2>/dev/null || \
        adduser --uid $USER_ID --gid $GROUP_ID --home /workspace --shell /bin/bash --disabled-password --gecos "" $USER_NAME 2>/dev/null || true
fi

# Verify
echo "Verification:"
getent passwd $USER_ID
getent group $GROUP_ID
FIXEOF
)

    # Replace placeholders
    FIX_SCRIPT="${FIX_SCRIPT//%USER_ID%/$USER_ID}"
    FIX_SCRIPT="${FIX_SCRIPT//%GROUP_ID%/$GROUP_ID}"
    FIX_SCRIPT="${FIX_SCRIPT//%USER_NAME%/$USER_NAME}"

    # Execute fix script as root inside container
    echo "$FIX_SCRIPT" | docker exec -i -u root "$CONTAINER_TAG" bash

    echo ""
    echo -e "${GREEN}✓ Fix applied${NC}"
    echo ""

    # Verify fix
    echo -e "${YELLOW}Verifying fix...${NC}"
    echo ""

    if docker exec "$CONTAINER_TAG" sh -c "getent passwd $USER_ID" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ User entry now exists${NC}"
        docker exec "$CONTAINER_TAG" sh -c "getent passwd $USER_ID"
    else
        echo -e "${RED}✗ User entry still missing${NC}"
    fi

    if docker exec "$CONTAINER_TAG" sh -c "getent group $GROUP_ID" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Group entry now exists${NC}"
        docker exec "$CONTAINER_TAG" sh -c "getent group $GROUP_ID"
    else
        echo -e "${RED}✗ Group entry still missing${NC}"
    fi
    echo ""

    # Test 'id' command
    echo -e "${YELLOW}Testing 'id' command...${NC}"
    docker exec "$CONTAINER_TAG" id || echo -e "${RED}(command failed)${NC}"
    echo ""

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Fix Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} This fix is temporary and only affects this container instance."
    echo "If you recreate the container, you'll need to apply this fix again,"
    echo "or use the patched mlc-patched.py which prevents this issue."
    echo ""
    echo -e "${GREEN}You can now open the container:${NC}"
    echo "  container-run $CONTAINER_NAME"
    echo ""
else
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}No fix needed - user/group entries exist${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

# Stop container if it wasn't running before
if [ "$IS_RUNNING" = false ]; then
    echo -e "${YELLOW}Stopping container (it wasn't running before)...${NC}"
    docker stop "$CONTAINER_TAG" > /dev/null 2>&1
fi
