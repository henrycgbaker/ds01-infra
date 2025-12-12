# DS01: Ensure home directory permissions are always private
# Deployed to: /etc/profile.d/ds01-home-enforce.sh
# This runs on every login to enforce home directory privacy

[ -d "$HOME" ] && chmod 700 "$HOME" 2>/dev/null || true
