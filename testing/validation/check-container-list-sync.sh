#!/bin/bash
# Check if container-list and Docker show same containers
# Returns exit code 0 if synced, 1 if differences found

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
MLC_LIST="$INFRA_ROOT/aime-ml-containers/mlc-list"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
USER_ID=$(id -u)

# Get containers from mlc-list (what container-list shows)
if [ -f "$MLC_LIST" ]; then
    MLC_CONTAINERS=$(bash "$MLC_LIST" 2>/dev/null | grep -oP '^\[\K[^\]]+' | sort || true)
else
    echo -e "${YELLOW}⚠ mlc-list not found, skipping${NC}"
    exit 0
fi

# Get actual containers from Docker for current user
DOCKER_CONTAINERS=$(docker ps -a --filter "name=._.$USER_ID" --format "{{.Names}}" | sed 's/\._.*//' | sort)

# Check for containers in Docker but not in mlc-list
while IFS= read -r container; do
    [ -z "$container" ] && continue
    if ! echo "$MLC_CONTAINERS" | grep -q "^${container}$"; then
        echo -e "${RED}✗ MISSING: Container exists but not in container-list: $container${NC}"
        ((ERRORS++))
    fi
done <<< "$DOCKER_CONTAINERS"

# Check for containers in mlc-list but not in Docker
while IFS= read -r container; do
    [ -z "$container" ] && continue
    if ! echo "$DOCKER_CONTAINERS" | grep -q "^${container}$"; then
        echo -e "${YELLOW}⚠ PHANTOM: Listed in container-list but not in Docker: $container${NC}"
        ((ERRORS++))
    fi
done <<< "$MLC_CONTAINERS"

# Summary
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ container-list in sync with Docker${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS sync issue(s)${NC}"
    exit 1
fi
