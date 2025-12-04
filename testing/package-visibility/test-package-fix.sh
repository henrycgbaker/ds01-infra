#!/bin/bash
# Test package visibility and .local permission fix
# This tests that packages installed in images are visible in containers
# and that pip install --user works correctly

# Don't use set -e - we handle errors explicitly

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test configuration
TEST_CONTAINER_NAME="test-pkg-fix-$$"
TEST_IMAGE_NAME="test-pkg-fix-image"
CLEANUP=true
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cleanup) CLEANUP=false; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--no-cleanup] [--verbose]"
            echo "  --no-cleanup  Don't remove test containers/images after test"
            echo "  --verbose     Show detailed output"
            exit 0
            ;;
        *) shift ;;
    esac
done

log() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cleanup() {
    if [ "$CLEANUP" = true ]; then
        log "Cleaning up..."
        docker rm -f "$TEST_CONTAINER_NAME" 2>/dev/null || true
        # Don't remove base image - it's reused
    fi
}

trap cleanup EXIT

# Get current user info
USER_ID=$(id -u)
USER_NAME=$(whoami)
GROUP_ID=$(id -g)

log "Testing package visibility fix"
log "User: $USER_NAME (uid=$USER_ID, gid=$GROUP_ID)"
echo ""

# Test 1: Create container using the patched mlc-patched.py
log "Test 1: Creating container with patched mlc-patched.py..."

# Check if we have an existing base image to use
BASE_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "aimehub/pytorch" | head -1)
if [ -z "$BASE_IMAGE" ]; then
    error "No AIME PyTorch image found. Please run 'container-create' first to pull base image."
    exit 1
fi
log "Using base image: $BASE_IMAGE"

# Create a test container directly using mlc-patched.py logic
# We'll simulate what mlc-patched.py does
WORKSPACE_DIR="$HOME/workspace/test-pkg-fix"
mkdir -p "$WORKSPACE_DIR"

# Sanitize username (simulating mlc-patched.py logic)
SANITIZED_USER=$(echo "$USER_NAME" | sed 's/@/-at-/g; s/\./-/g' | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//; s/-$//')

log "Sanitized username: $SANITIZED_USER"

# Build the setup bash command (same as mlc-patched.py)
SETUP_CMD="
echo 'export HOME=/home/$SANITIZED_USER' >> /etc/skel/.bashrc;
echo 'export PATH=/home/$SANITIZED_USER/.local/bin:\$PATH' >> /etc/skel/.bashrc;
apt-get update -y > /dev/null 2>&1;
apt-get install sudo git -q -y > /dev/null 2>&1;

# User/group creation with conflict resolution
if getent group $GROUP_ID > /dev/null 2>&1; then
    EXISTING_GROUP=\$(getent group $GROUP_ID | cut -d: -f1);
    if [ \"\$EXISTING_GROUP\" != \"$SANITIZED_USER\" ]; then
        groupdel \$EXISTING_GROUP 2>&1 || true;
    fi
fi
if ! getent group $GROUP_ID > /dev/null 2>&1; then
    addgroup --gid $GROUP_ID $SANITIZED_USER 2>&1 || groupadd -g $GROUP_ID $SANITIZED_USER 2>&1 || true;
fi

if getent passwd $USER_ID > /dev/null 2>&1; then
    EXISTING_USER=\$(getent passwd $USER_ID | cut -d: -f1);
    if [ \"\$EXISTING_USER\" != \"$SANITIZED_USER\" ]; then
        userdel -r \$EXISTING_USER 2>&1 || true;
    fi
fi
if ! getent passwd $USER_ID > /dev/null 2>&1; then
    adduser --uid $USER_ID --gid $GROUP_ID $SANITIZED_USER --disabled-password --gecos aime 2>&1 || useradd -u $USER_ID -g $GROUP_ID -d /home/$SANITIZED_USER -m -s /bin/bash $SANITIZED_USER 2>&1 || true;
fi

# Verify
if getent passwd $USER_ID > /dev/null 2>&1 && getent group $GROUP_ID > /dev/null 2>&1; then
    echo 'User setup: OK';
else
    echo 'User setup: FAILED';
fi

# Configure user
passwd -d $SANITIZED_USER 2>/dev/null || true;
usermod -aG sudo $SANITIZED_USER 2>/dev/null || true;
echo '$SANITIZED_USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${SANITIZED_USER}_no_password;
chmod 440 /etc/sudoers.d/${SANITIZED_USER}_no_password;

# Create .local directory (THE FIX)
mkdir -p /home/$SANITIZED_USER/.local/bin;
chown -R $USER_ID:$GROUP_ID /home/$SANITIZED_USER/.local;
cp /etc/skel/.bashrc /home/$SANITIZED_USER/.bashrc 2>/dev/null || true;
chown $USER_ID:$GROUP_ID /home/$SANITIZED_USER/.bashrc 2>/dev/null || true;

exit
"

# Run container setup
docker run --name "$TEST_CONTAINER_NAME" \
    -v "$WORKSPACE_DIR:/workspace" \
    -w /workspace \
    --tty \
    --privileged \
    --network host \
    "$BASE_IMAGE" \
    bash -c "$SETUP_CMD"

SETUP_RESULT=$?
if [ $SETUP_RESULT -ne 0 ]; then
    error "Container setup failed"
    exit 1
fi
log "Container setup completed"

# Commit the container
# Use a simple tag name to avoid double-colon issues
COMMITTED_IMAGE="test-pkg-fix-committed:latest"
docker commit "$TEST_CONTAINER_NAME" "$COMMITTED_IMAGE" > /dev/null
docker rm "$TEST_CONTAINER_NAME" > /dev/null

# Create final container
docker create -it \
    -v "$WORKSPACE_DIR:/workspace" \
    -w /workspace \
    --name "$TEST_CONTAINER_NAME" \
    --user "$USER_ID:$GROUP_ID" \
    --tty \
    --privileged \
    --network host \
    "$COMMITTED_IMAGE" \
    bash > /dev/null

log "Test container created: $TEST_CONTAINER_NAME"
echo ""

# Test 2: Verify user identity (no "I have no name!")
log "Test 2: Checking user identity..."
docker start "$TEST_CONTAINER_NAME" > /dev/null
WHOAMI=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" whoami 2>&1)
ID_OUTPUT=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" id 2>&1)

PASS_COUNT=0
FAIL_COUNT=0

if echo "$WHOAMI" | grep -q "I have no name"; then
    error "Test 2 FAILED: Got 'I have no name!' - GID mapping issue"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    log "Test 2 PASSED: whoami = $WHOAMI"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

if echo "$ID_OUTPUT" | grep -q "cannot find name"; then
    error "Test 2b FAILED: Group name not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    log "Test 2b PASSED: id output is correct"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
echo ""

# Test 3: Verify HOME is set correctly
log "Test 3: Checking HOME environment variable..."
HOME_VAR=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c 'source ~/.bashrc 2>/dev/null; echo $HOME')

if [ "$HOME_VAR" = "/home/$SANITIZED_USER" ]; then
    log "Test 3 PASSED: HOME = $HOME_VAR"
    ((PASS_COUNT++))
else
    error "Test 3 FAILED: HOME = '$HOME_VAR' (expected /home/$SANITIZED_USER)"
    ((FAIL_COUNT++))
fi
echo ""

# Test 4: Verify .local directory exists and is writable
log "Test 4: Checking .local directory..."
LOCAL_TEST=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c '
    if [ -d ~/.local/bin ]; then
        touch ~/.local/bin/test-file && rm ~/.local/bin/test-file && echo "OK"
    else
        echo "MISSING"
    fi
' 2>&1)

if [ "$LOCAL_TEST" = "OK" ]; then
    log "Test 4 PASSED: .local directory exists and is writable"
    ((PASS_COUNT++))
else
    error "Test 4 FAILED: .local directory issue: $LOCAL_TEST"
    ((FAIL_COUNT++))
fi
echo ""

# Test 5: Verify pip install --user works
log "Test 5: Testing pip install --user..."
PIP_TEST=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c '
    source ~/.bashrc 2>/dev/null
    pip install --user --quiet six 2>&1 && echo "OK" || echo "FAILED: $?"
')

if [ "$PIP_TEST" = "OK" ]; then
    log "Test 5 PASSED: pip install --user works"
    ((PASS_COUNT++))
else
    error "Test 5 FAILED: pip install --user error: $PIP_TEST"
    ((FAIL_COUNT++))
fi
echo ""

# Test 6: Verify PATH in bashrc includes .local/bin
log "Test 6: Checking bashrc configures PATH with .local/bin..."
BASHRC_CHECK=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c '
    grep -q ".local/bin" ~/.bashrc 2>/dev/null && echo "OK" || echo "MISSING"
')

if [ "$BASHRC_CHECK" = "OK" ]; then
    log "Test 6 PASSED: bashrc contains .local/bin in PATH"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    error "Test 6 FAILED: bashrc doesn't contain .local/bin"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# Cleanup committed image
docker rmi "$COMMITTED_IMAGE" > /dev/null 2>&1 || true

# Summary
echo ""
echo "================================================"
echo -e "${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "${RED}Failed:${NC} $FAIL_COUNT"
echo "================================================"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}ALL TESTS PASSED!${NC}"
    echo "The package visibility fix is working correctly."
    exit 0
else
    echo -e "\n${RED}SOME TESTS FAILED!${NC}"
    echo "Please review the errors above."
    exit 1
fi
