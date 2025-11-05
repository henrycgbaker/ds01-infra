#!/bin/bash
# Update DS01 symlinks after reorganization
# Run with: sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

set -e

echo "Creating/updating DS01 command symlinks..."

# User setup commands
ln -sf /opt/ds01-infra/scripts/user/user-setup /usr/local/bin/new-user
echo "✓ new-user → user-setup"

ln -sf /opt/ds01-infra/scripts/user/user-setup /usr/local/bin/user-setup
echo "✓ user-setup → user-setup"

ln -sf /opt/ds01-infra/scripts/user/user-dispatcher.sh /usr/local/bin/user
echo "✓ user → user-dispatcher.sh"

# Project setup commands
ln -sf /opt/ds01-infra/scripts/user/new-project /usr/local/bin/new-project
echo "✓ new-project → scripts/user/new-project"

# Verify project-init exists (should already be there)
if [ ! -L /usr/local/bin/project-init ]; then
    ln -sf /opt/ds01-infra/scripts/user/project-init /usr/local/bin/project-init
    echo "✓ project-init → scripts/user/project-init"
else
    echo "✓ project-init already exists"
fi

echo ""
echo "All symlinks updated successfully!"
echo ""
echo "User setup commands:"
echo "  - new-user          First-time user onboarding"
echo "  - user-setup        Same as above"
echo "  - user setup        Same as above"
echo "  - user new          Same as above"
echo ""
echo "Project setup commands:"
echo "  - new-project       Create data science project (interactive)"
echo "  - project init      Alias to new-project"
echo ""
