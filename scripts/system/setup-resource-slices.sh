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
    chmod +x /usr/local/bin/yq
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
GROUPS=$(yq eval '.groups | keys | .[]' "$CONFIG_FILE")

for GROUP in $GROUPS; do
    # Get limits - with fallback to defaults if not specified
    MAX_CPUS=$(yq eval ".groups.$GROUP.cpus // .defaults.cpus" "$CONFIG_FILE")
    MAX_MEMORY=$(yq eval ".groups.$GROUP.memory // .defaults.memory" "$CONFIG_FILE")
    MAX_TASKS=$(yq eval ".groups.$GROUP.max_tasks // .defaults.max_tasks" "$CONFIG_FILE")
    
    # Convert CPU count to percentage (100% = 1 core)
    CPU_QUOTA=$((MAX_CPUS * 100))
    
    # Create slice file
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
TasksMax=${MAX_TASKS}
EOF
    
    echo "✓ Created ds01-${GROUP}.slice (CPUs: ${MAX_CPUS}, Memory: ${MAX_MEMORY}, Tasks: ${MAX_TASKS})"
done

systemctl daemon-reload

echo ""
echo "=== Slice Hierarchy Created ==="
echo ""
echo "View with: systemctl status ds01.slice"
echo "Monitor with: systemd-cgtop"
echo ""