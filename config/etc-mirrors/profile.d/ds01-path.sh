#!/bin/sh
# DS01 Infrastructure - System-wide PATH configuration
# Source: /opt/ds01-infra/config/etc-mirrors/profile.d/ds01-path.sh
# Deploy: sudo cp /opt/ds01-infra/config/etc-mirrors/profile.d/ds01-path.sh /etc/profile.d/
#
# Ensures /usr/local/bin is in PATH for all users (domain + local)
# Required for DS01 CLI commands: container-*, image-*, ds01-dashboard, etc.

# Only modify PATH if /usr/local/bin is not already present
case ":${PATH}:" in
    *:/usr/local/bin:*)
        # Already in PATH, do nothing
        ;;
    *)
        # Add /usr/local/bin to PATH
        export PATH="/usr/local/bin:${PATH}"
        ;;
esac
