#!/bin/bash
# /opt/ds01-infra/scripts/lib/init.sh
# DS01 Bash Initialization Library
#
# Standard initialization for all DS01 bash scripts.
# Provides consistent paths, colors, and utility functions.
#
# Usage:
#   source /opt/ds01-infra/scripts/lib/init.sh
#   # or
#   source "${SCRIPT_DIR}/lib/init.sh"
#
# This library is sourced by scripts to:
# - Set standard DS01 paths
# - Define ANSI color codes
# - Provide common utility functions
# - Avoid code duplication across 50+ scripts

# ============================================================================
# Paths (use these instead of hardcoding)
# ============================================================================
export DS01_ROOT="${DS01_ROOT:-/opt/ds01-infra}"
export DS01_CONFIG="${DS01_ROOT}/config"
export DS01_SCRIPTS="${DS01_ROOT}/scripts"
export DS01_LIB="${DS01_SCRIPTS}/lib"

# State and log directories
export DS01_STATE="/var/lib/ds01"
export DS01_LOG="/var/log/ds01"

# ============================================================================
# ANSI Color Codes
# ============================================================================
# Primary colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'

# Styles
export BOLD='\033[1m'
export DIM='\033[2m'
export UNDERLINE='\033[4m'

# Reset
export NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

# Get a resource limit value for a user
# Usage: ds01_get_limit <username> <flag>
# Example: ds01_get_limit alice --idle-timeout
ds01_get_limit() {
    local username="${1:?Usage: ds01_get_limit <username> <flag>}"
    local flag="${2:?Usage: ds01_get_limit <username> <flag>}"
    python3 "${DS01_SCRIPTS}/docker/get_resource_limits.py" "$username" "$flag"
}

# Get a global config value (no username needed)
# Usage: ds01_get_config <flag>
# Example: ds01_get_config --high-demand-threshold
ds01_get_config() {
    local flag="${1:?Usage: ds01_get_config <flag>}"
    python3 "${DS01_SCRIPTS}/docker/get_resource_limits.py" - "$flag"
}

# Parse duration string to seconds using Python library
# Usage: ds01_parse_duration <duration>
# Example: ds01_parse_duration "2h"  -> 7200
ds01_parse_duration() {
    local duration="${1:-}"
    python3 -c "
import sys
sys.path.insert(0, '${DS01_LIB}')
from ds01_core import parse_duration
print(parse_duration('$duration'))
"
}

# Format seconds to human-readable duration
# Usage: ds01_format_duration <seconds>
# Example: ds01_format_duration 7200  -> "2h"
ds01_format_duration() {
    local seconds="${1:-0}"
    python3 -c "
import sys
sys.path.insert(0, '${DS01_LIB}')
from ds01_core import format_duration
print(format_duration($seconds))
"
}

# Print error message to stderr
# Usage: ds01_error "message"
ds01_error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

# Print warning message
# Usage: ds01_warn "message"
ds01_warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

# Print success message
# Usage: ds01_success "message"
ds01_success() {
    echo -e "${GREEN}$1${NC}"
}

# Print info message
# Usage: ds01_info "message"
ds01_info() {
    echo -e "${BLUE}$1${NC}"
}

# Print a section header
# Usage: ds01_header "Section Title"
ds01_header() {
    echo -e "${BOLD}$1${NC}"
}

# Log message with timestamp (for cron/daemon scripts)
# Usage: ds01_log "message" [logfile]
ds01_log() {
    local msg="$1"
    local logfile="${2:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ -n "$logfile" ]; then
        echo "[$timestamp] $msg" | tee -a "$logfile"
    else
        echo "[$timestamp] $msg"
    fi
}

# Check if running as root
# Usage: ds01_require_root
ds01_require_root() {
    if [ "$EUID" -ne 0 ]; then
        ds01_error "This command requires root privileges"
        echo "Run with: sudo $0"
        exit 1
    fi
}

# Get current user's username (handles edge cases)
# Usage: username=$(ds01_current_user)
ds01_current_user() {
    echo "${USER:-$(whoami)}"
}
