#!/bin/bash
# Emergency sudo restore for datasciencelab user

echo "Restoring datasciencelab sudo privileges..."
usermod -aG sudo datasciencelab

if [ ! -f /etc/sudoers.d/datasciencelab-admin ]; then
    echo "datasciencelab ALL=(ALL:ALL) ALL" > /etc/sudoers.d/datasciencelab-admin
    chmod 0440 /etc/sudoers.d/datasciencelab-admin
    visudo -c -f /etc/sudoers.d/datasciencelab-admin
fi

echo "Done. Verify with: groups datasciencelab"
