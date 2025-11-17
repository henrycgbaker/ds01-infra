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
    # Get limits - with fallback to defaults if not specified
    MAX_CPUS=$(yq eval ".groups.$GROUP.max_cpus // .defaults.max_cpus" "$CONFIG_FILE")
    MAX_MEMORY=$(yq eval ".groups.$GROUP.memory // .defaults.memory" "$CONFIG_FILE")
    MAX_TASKS=$(yq eval ".groups.$GROUP.max_tasks // .defaults.max_tasks" "$CONFIG_FILE")

    # Convert CPU count to percentage (100% = 1 core)
    CPU_QUOTA=$((MAX_CPUS * 100))

    # Create slice file with base configuration
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
CPUQuota=${CPU_QUOTA}%
MemoryMax=${MAX_MEMORY}
EOF

    # Add TasksMax only if not null (null = infinity)
    if [ "$MAX_TASKS" != "null" ]; then
        echo "TasksMax=${MAX_TASKS}" >> /etc/systemd/system/ds01-${GROUP}.slice
    fi
    
    echo "✓ Created ds01-${GROUP}.slice (CPUs: ${MAX_CPUS}, Memory: ${MAX_MEMORY}, Tasks: ${MAX_TASKS})"
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