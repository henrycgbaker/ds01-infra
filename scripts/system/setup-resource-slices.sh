#!/bin/bash
# /opt/ds01-infra/scripts/system/setup-resource-slices.sh
# Creates systemd slices based on resource-limits.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/opt/ds01-infra/config/resource-limits.yaml"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check for yq (YAML parser)
if ! command -v yq &> /dev/null; then
    echo "Installing yq..."
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod 755 /usr/local/bin/yq
else
    # Ensure yq has proper permissions (fix if needed)
    chmod 755 /usr/local/bin/yq
fi

echo "=== Creating DS01 Resource Slices ==="
echo ""

# Create parent ds01.slice
cat > /etc/systemd/system/ds01.slice << 'EOF'
[Unit]
Description=DS01 GPU Server Container Slice
Before=slices.target

[Slice]
CPUAccounting=true
MemoryAccounting=true
TasksAccounting=true
IOAccounting=true
EOF

systemctl daemon-reload
echo "✓ Created ds01.slice (parent)"

# Parse YAML and create group slices
GROUP_LIST=$(yq eval '.groups | keys | .[]' "$CONFIG_FILE")

if [ -z "$GROUP_LIST" ]; then
    echo "Error: No groups found in $CONFIG_FILE"
    exit 1
fi

echo "Creating group slices for: $GROUP_LIST"
echo ""

for GROUP in $GROUP_LIST; do
    # Group slices are for ACCOUNTING only, not limiting
    # Resource limits are enforced per-container via docker --cpus, --memory flags
    #
    # Why no limits at group level:
    # - A group slice contains ALL containers for ALL users in that group
    # - If we set CPUQuota=3200% (32 CPUs), only one container could use full allocation
    # - With 10 students × 3 containers × 32 CPUs = 960 CPUs needed (impossible)
    # - Per-container limits via Docker are the correct enforcement point

    # Create slice file with accounting only (no resource limits)
    cat > /etc/systemd/system/ds01-${GROUP}.slice << EOF
[Unit]
Description=DS01 ${GROUP^} Group
Before=slices.target

[Slice]
Slice=ds01.slice
CPUAccounting=true
MemoryAccounting=true
TasksAccounting=true
IOAccounting=true
# Note: No CPUQuota/MemoryMax here - limits enforced per-container via Docker
EOF

    echo "✓ Created ds01-${GROUP}.slice (accounting only, no resource limits)"
done

systemctl daemon-reload

echo ""
echo "=== Slice Hierarchy Created ==="
echo ""
echo "Group slices created. Per-user slices will be created automatically"
echo "when users create their first container."
echo ""
echo "Hierarchy: ds01.slice → ds01-{group}.slice → ds01-{group}-{username}.slice"
echo ""
echo "View with: systemctl status ds01.slice"
echo "Monitor with: systemd-cgtop | grep ds01"
echo ""