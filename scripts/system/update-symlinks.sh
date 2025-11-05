#!/bin/bash
# Update DS01 symlinks after reorganization
# Run with: sudo bash /opt/ds01-infra/scripts/system/update-symlinks.sh

set -e

echo "Creating/updating DS01 command symlinks..."

# Unified project setup command
ln -sf /opt/ds01-infra/scripts/user/project-init /usr/local/bin/project-init
echo "✓ project-init → scripts/user/project-init"

ln -sf /opt/ds01-infra/scripts/user/project-dispatcher.sh /usr/local/bin/project
echo "✓ project → project-dispatcher.sh"

# Legacy aliases (for backwards compatibility)
ln -sf /opt/ds01-infra/scripts/user/project-init /usr/local/bin/new-project
echo "✓ new-project → project-init (legacy)"

ln -sf /opt/ds01-infra/scripts/user/project-init /usr/local/bin/new-user
echo "✓ new-user → project-init (legacy, use --guided)"

ln -sf /opt/ds01-infra/scripts/user/project-init /usr/local/bin/user-setup
echo "✓ user-setup → project-init (legacy, use --guided)"

ln -sf /opt/ds01-infra/scripts/user/user-dispatcher.sh /usr/local/bin/user
echo "✓ user → user-dispatcher.sh (legacy)"

echo ""
echo "All symlinks updated successfully!"
echo ""
echo "Primary commands:"
echo "  - project-init             Unified project setup"
echo "  - project init             Same as above (via dispatcher)"
echo "  - project-init --guided    Beginner-friendly mode with explanations"
echo "  - project init --guided    Same as above"
echo ""
echo "Legacy aliases (still work):"
echo "  - new-project              → project-init"
echo "  - new-user                 → project-init --guided"
echo "  - user-setup               → project-init --guided"
echo ""
