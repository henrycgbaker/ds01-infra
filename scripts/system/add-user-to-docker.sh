#!/bin/bash
# Add user to docker group for Docker access
# Run with: sudo bash /opt/ds01-infra/scripts/system/add-user-to-docker.sh <username>

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

USERNAME="${1:-}"

if [ -z "$USERNAME" ]; then
    echo "Usage: sudo bash $0 <username>"
    echo ""
    echo "Example: sudo bash $0 student1"
    exit 1
fi

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' does not exist"
    exit 1
fi

# Check if docker group exists
if ! getent group docker &>/dev/null; then
    echo "Error: docker group does not exist. Docker may not be installed."
    exit 1
fi

# Add user to docker group
echo "Adding $USERNAME to docker group..."
usermod -aG docker "$USERNAME"

echo ""
echo "✓ $USERNAME has been added to the docker group"
echo ""
echo "IMPORTANT: The user must log out and log back in for this to take effect."
echo ""
echo "To verify after logging back in, the user can run:"
echo "  groups"
echo ""
echo "They should see 'docker' in the list of groups."
echo ""
