#!/bin/bash
# /opt/ds01-infra/scripts/system/create-user-slice.sh
# Dynamically creates per-user systemd cgroup slices
#
# This script is called automatically by container-create to ensure
# each user gets their own monitoring slice within their group.
#
# Hierarchy: ds01.slice → ds01-{group}.slice → ds01-{group}-{username}.slice

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Usage check
if [ $# -lt 2 ]; then
    echo "Usage: $0 <group> <username>"
    echo ""
    echo "Example: $0 student alice"
    echo "  Creates: ds01-student-alice.slice under ds01-student.slice"
    exit 1
fi

GROUP="$1"
USERNAME="$2"
SLICE_NAME="ds01-${GROUP}-${USERNAME}.slice"
PARENT_SLICE="ds01-${GROUP}.slice"
SLICE_FILE="/etc/systemd/system/${SLICE_NAME}"

# Check if parent slice exists
if ! systemctl status "$PARENT_SLICE" &>/dev/null; then
    echo "Error: Parent slice $PARENT_SLICE does not exist"
    echo "Run: sudo /opt/ds01-infra/scripts/system/setup-resource-slices.sh"
    exit 1
fi

# Check if user slice already exists
if [ -f "$SLICE_FILE" ]; then
    # Slice already exists, nothing to do
    exit 0
fi

# Create user slice
cat > "$SLICE_FILE" << EOF
[Unit]
Description=DS01 ${GROUP^} - ${USERNAME}
Before=slices.target

[Slice]
Slice=${PARENT_SLICE}
CPUAccounting=true
MemoryAccounting=true
TasksAccounting=true
IOAccounting=true
EOF

# Reload systemd
systemctl daemon-reload

# Note: We don't set resource limits at the user level.
# Resource limits are enforced at:
# 1. Group level (via parent slice)
# 2. Container level (via docker update)
#
# User slices are purely for monitoring/tracking purposes.

exit 0
