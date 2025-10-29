# File: /opt/ds01-infra/scripts/system/setup-cgroup-slices.sh
#!/bin/bash
# Set up systemd slices for better container organization

cat > /etc/systemd/system/ds01.slice << 'SLICEEOF'
[Unit]
Description=DS01 GPU Server Container Slice
Before=slices.target

[Slice]
# Resource limits for entire DS01 system
GPUAccounting=true
CPUAccounting=true
MemoryAccounting=true
TasksAccounting=true
SLICEEOF

systemctl daemon-reload
systemctl start ds01.slice

echo "✓ DS01 systemd slice created"
echo ""
echo "Containers will be organized under ds01.slice/user-<uid>.slice/"
echo "View with: systemctl status ds01.slice"