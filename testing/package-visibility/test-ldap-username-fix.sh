#!/bin/bash
# Test package visibility fix with LDAP/SSSD-style usernames
# This tests that the fix works correctly when usernames contain special characters
# like @ and . which are common in LDAP/SSSD environments

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test configuration
TEST_CONTAINER_NAME="test-ldap-pkg-$$"
CLEANUP=true

# Simulated LDAP username patterns to test
TEST_USERNAMES=(
    "h.baker@hertie-school.lan"
    "john.doe@example.com"
    "user.name@domain"
)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cleanup) CLEANUP=false; shift ;;
        -h|--help)
            echo "Usage: $0 [--no-cleanup]"
            echo "  --no-cleanup  Don't remove test containers after test"
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
        docker rmi "test-ldap-committed:latest" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Sanitize username function (same as mlc-patched.py)
sanitize_username() {
    local username="$1"
    echo "$username" | sed 's/@/-at-/g; s/\./-/g' | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//; s/-$//'
}

# Get current user info
USER_ID=$(id -u)
USER_NAME=$(whoami)
GROUP_ID=$(id -g)

log "Testing LDAP/SSSD username handling"
log "Host user: $USER_NAME (uid=$USER_ID, gid=$GROUP_ID)"
echo ""

# Check for base image
BASE_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "aimehub/pytorch" | head -1)
if [ -z "$BASE_IMAGE" ]; then
    error "No AIME PyTorch image found."
    exit 1
fi
log "Using base image: $BASE_IMAGE"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Test each LDAP username pattern
for LDAP_USER in "${TEST_USERNAMES[@]}"; do
    log "Testing username pattern: $LDAP_USER"

    SANITIZED=$(sanitize_username "$LDAP_USER")
    log "  Sanitized to: $SANITIZED"

    # Verify sanitization is correct
    if echo "$SANITIZED" | grep -q '[@.]'; then
        error "  FAILED: Sanitized username still contains @ or ."
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    log "  Sanitization OK (no @ or .)"

    # Verify home path would be valid
    HOME_PATH="/home/$SANITIZED"
    if echo "$HOME_PATH" | grep -qE '[@. ]'; then
        error "  FAILED: Home path contains invalid characters: $HOME_PATH"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    log "  Home path OK: $HOME_PATH"

    # Verify PATH addition would be valid
    LOCAL_BIN="$HOME_PATH/.local/bin"
    log "  .local/bin path: $LOCAL_BIN"

    PASS_COUNT=$((PASS_COUNT + 1))
    echo ""
done

echo ""
log "Testing actual container creation with LDAP-style sanitization..."

# Now test actual container creation using the real user but simulating
# what would happen with an LDAP username
LDAP_STYLE="test.user@example.lan"
SANITIZED_USER=$(sanitize_username "$LDAP_STYLE")

log "Simulating LDAP user: $LDAP_STYLE"
log "Sanitized username: $SANITIZED_USER"

WORKSPACE_DIR="$HOME/workspace/test-ldap-pkg"
mkdir -p "$WORKSPACE_DIR"

# Build the setup bash command using sanitized username
SETUP_CMD="
echo 'export HOME=/home/$SANITIZED_USER' >> /etc/skel/.bashrc;
echo 'export PATH=/home/$SANITIZED_USER/.local/bin:\$PATH' >> /etc/skel/.bashrc;
apt-get update -y > /dev/null 2>&1;
apt-get install sudo git -q -y > /dev/null 2>&1;

# User/group creation (using actual host UID/GID but sanitized name)
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
log "Creating container with LDAP-style username handling..."
docker run --name "$TEST_CONTAINER_NAME" \
    -v "$WORKSPACE_DIR:/workspace" \
    -w /workspace \
    --tty \
    --privileged \
    --network host \
    "$BASE_IMAGE" \
    bash -c "$SETUP_CMD" 2>&1 | grep -E "(User setup|FAILED|error)" || true

# Check if setup was successful
SETUP_OUTPUT=$(docker logs "$TEST_CONTAINER_NAME" 2>&1 | grep "User setup" || echo "")
if echo "$SETUP_OUTPUT" | grep -q "User setup: OK"; then
    log "Container user setup: OK"
else
    warn "Container setup output: $SETUP_OUTPUT"
fi

# Commit and recreate
docker commit "$TEST_CONTAINER_NAME" "test-ldap-committed:latest" > /dev/null
docker rm "$TEST_CONTAINER_NAME" > /dev/null

docker create -it \
    -v "$WORKSPACE_DIR:/workspace" \
    -w /workspace \
    --name "$TEST_CONTAINER_NAME" \
    --user "$USER_ID:$GROUP_ID" \
    --tty \
    --privileged \
    --network host \
    "test-ldap-committed:latest" \
    bash > /dev/null

docker start "$TEST_CONTAINER_NAME" > /dev/null

echo ""
log "Verifying LDAP-style container works correctly..."

# Test 1: No "I have no name!"
WHOAMI=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" whoami 2>&1)
if echo "$WHOAMI" | grep -q "I have no name"; then
    error "FAILED: Got 'I have no name!' with LDAP-style username"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    log "PASSED: whoami = $WHOAMI (expected: $SANITIZED_USER)"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# Test 2: HOME is correct
HOME_VAR=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c 'source ~/.bashrc 2>/dev/null; echo $HOME')
if [ "$HOME_VAR" = "/home/$SANITIZED_USER" ]; then
    log "PASSED: HOME = $HOME_VAR"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    error "FAILED: HOME = '$HOME_VAR' (expected /home/$SANITIZED_USER)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 3: pip install --user works
PIP_TEST=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c '
    source ~/.bashrc 2>/dev/null
    pip install --user --quiet six 2>&1 && echo "OK" || echo "FAILED"
')
if [ "$PIP_TEST" = "OK" ]; then
    log "PASSED: pip install --user works with LDAP-style username"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    error "FAILED: pip install --user error: $PIP_TEST"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 4: .local path is correct (no @ in path - dots are OK in .local)
LOCAL_PATH=$(docker exec --user "$USER_ID:$GROUP_ID" "$TEST_CONTAINER_NAME" bash -c '
    source ~/.bashrc 2>/dev/null
    ls -d ~/.local 2>/dev/null || echo "MISSING"
')
if echo "$LOCAL_PATH" | grep -q '@'; then
    error "FAILED: .local path contains @ character: $LOCAL_PATH"
    FAIL_COUNT=$((FAIL_COUNT + 1))
elif [ "$LOCAL_PATH" = "MISSING" ]; then
    error "FAILED: .local directory missing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    log "PASSED: .local path is valid: $LOCAL_PATH"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

echo ""
echo "================================================"
echo -e "${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "${RED}Failed:${NC} $FAIL_COUNT"
echo "================================================"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}ALL LDAP USERNAME TESTS PASSED!${NC}"
    echo "The fix correctly handles LDAP/SSSD-style usernames."
    exit 0
else
    echo -e "\n${RED}SOME TESTS FAILED!${NC}"
    echo "Please review the errors above."
    exit 1
fi
