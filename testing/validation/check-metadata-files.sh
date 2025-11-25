#!/bin/bash
# Check for orphaned metadata files
# Returns exit code 0 if clean, 1 if orphans found

set -e

METADATA_DIR="/var/lib/ds01/container-metadata"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ORPHANS=0

if [ ! -d "$METADATA_DIR" ]; then
    echo -e "${GREEN}✓ No metadata directory${NC}"
    exit 0
fi

# Check each metadata file
for metadata_file in "$METADATA_DIR"/*.json; do
    [ -f "$metadata_file" ] || continue

    container_name=$(basename "$metadata_file" .json)

    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${YELLOW}⚠ ORPHANED: Metadata exists but container doesn't: $container_name${NC}"
        ((ORPHANS++))
    fi
done

# Summary
if [ $ORPHANS -eq 0 ]; then
    echo -e "${GREEN}✓ No orphaned metadata files${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Found $ORPHANS orphaned metadata file(s)${NC}"
    exit 1
fi
