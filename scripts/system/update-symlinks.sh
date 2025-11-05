#!/bin/bash
# Update DS01 symlinks after reorganization
# Run with: sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

set -e

echo "Creating/updating DS01 command symlinks..."

# User setup commands (now pointing to project-init-beginner)
ln -sf /opt/ds01-infra/scripts/user/project-init-beginner /usr/local/bin/project-init-beginner
echo "✓ project-init-beginner → scripts/user/project-init-beginner"

ln -sf /opt/ds01-infra/scripts/user/project-init-beginner /usr/local/bin/new-user
echo "✓ new-user → project-init-beginner (legacy)"

ln -sf /opt/ds01-infra/scripts/user/project-init-beginner /usr/local/bin/user-setup
echo "✓ user-setup → project-init-beginner (legacy)"

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
echo "Beginner setup commands:"
echo "  - project-init-beginner    Beginner-friendly setup (primary)"
echo "  - new-user                 Alias to above (legacy)"
echo "  - user-setup               Alias to above (legacy)"
echo "  - user setup               Alias to above (via dispatcher)"
echo "  - user new                 Alias to above (via dispatcher)"
echo ""
echo "Quick setup commands:"
echo "  - new-project              Streamlined setup (experienced users)"
echo "  - project init             Alias to new-project"
echo ""
