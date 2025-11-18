#!/bin/bash
# /opt/ds01-infra/scripts/maintenance/enforce-max-runtime.sh
# Enforce max_runtime limits for containers
#
# This script checks running containers against their max_runtime limits
# and stops containers that have exceeded their maximum walltime.

set -e

# Configuration
# Resolve symlinks to get actual script location
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
STATE_DIR="/var/lib/ds01/container-runtime"
LOG_FILE="/var/log/ds01/runtime-enforcement.log"

# Create state and log directories
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Colors for logging
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_color() {
    echo -e "${2}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Get max runtime for user (in hours)
get_max_runtime() {
    local username="$1"

    # Use Python to parse YAML and get max_runtime
    USERNAME="$username" CONFIG_FILE="$CONFIG_FILE" python3 - <<'PYEOF'
import yaml
import sys
import os

try:
    username = os.environ['USERNAME']
    config_file = os.environ['CONFIG_FILE']

    with open(config_file) as f:
        config = yaml.safe_load(f)

    # Check user overrides first
    if 'user_overrides' in config and config['user_overrides'] is not None:
        if username in config['user_overrides']:
            runtime = config['user_overrides'][username].get('max_runtime')
            if runtime:
                print(runtime)
                sys.exit(0)

    # Check groups
    if 'groups' in config and config['groups'] is not None:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and username in group_config['members']:
                runtime = group_config.get('max_runtime')
                if runtime:
                    print(runtime)
                    sys.exit(0)

    # Default runtime
    default_runtime = config.get('defaults', {}).get('max_runtime', 'null')
    print(default_runtime)
except Exception as e:
    print("null", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Convert runtime string (e.g., "48h", "7d") to seconds
runtime_to_seconds() {
    local runtime="$1"

    if [[ "$runtime" == "null" ]] || [[ -z "$runtime" ]]; then
        echo "0"  # No limit
        return
    fi

    local value="${runtime%[a-z]*}"
    local unit="${runtime#${value}}"

    case "$unit" in
        h) echo $((value * 3600)) ;;
        d) echo $((value * 86400)) ;;
        w) echo $((value * 604800)) ;;
        *) echo "0" ;;  # Default no limit
    esac
}

# Get container start time in epoch seconds
get_container_start_time() {
    local container="$1"

    local start_time=$(docker inspect "$container" --format='{{.State.StartedAt}}' 2>/dev/null)
    if [ -z "$start_time" ]; then
        echo "0"
        return
    fi

    date -d "$start_time" +%s 2>/dev/null || echo "0"
}

# Send warning to user
send_warning() {
    local username="$1"
    local container="$2"
    local hours_until_stop="$3"

    # Create warning message in user's home
    local user_home=$(eval echo "~$username")
    local warning_file="$user_home/.ds01-runtime-warning"

    cat > "$warning_file" << WARNEOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  MAX RUNTIME WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container: $container
Status: Approaching maximum runtime limit
Action: Will auto-stop in ~${hours_until_stop} hours

This container will be automatically stopped when it reaches
its maximum runtime limit. Your work in /workspace is safe
and will persist.

To save your work:
  1. Checkpoint your training/model state
  2. Ensure results are saved to /workspace
  3. Consider stopping and restarting if needed

To stop now and restart later:
  container-stop $container
  container-run $container

Questions? Check: ds01-status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WARNEOF

    chown "$username:$username" "$warning_file" 2>/dev/null || true

    # Also send message to container if running
    if docker exec "$container" test -d /workspace 2>/dev/null; then
        docker exec "$container" bash -c "cat > /workspace/.runtime-warning.txt" < "$warning_file" 2>/dev/null || true
    fi

    log_color "Runtime warning sent to $username about container $container" "$YELLOW"
}

# Stop container that exceeded runtime
stop_runtime_exceeded() {
    local username="$1"
    local container="$2"
    local runtime_hours="$3"

    log_color "Stopping container: $container (user: $username, runtime: ${runtime_hours}h)" "$YELLOW"

    # Extract container name (remove ._.uid suffix)
    local container_name=$(echo "$container" | cut -d'.' -f1)

    # Create notification
    local user_home=$(eval echo "~$username")
    local notification_file="$user_home/.ds01-runtime-exceeded"

    cat > "$notification_file" << NOTIFEOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  CONTAINER STOPPED - MAX RUNTIME EXCEEDED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container: $container_name
Stopped: $(date)
Reason: Maximum runtime limit reached (${runtime_hours}h)

Your work in /workspace is safe and persists.

To restart your container:
  container-run $container_name

Note: The container will be subject to the same runtime
limit after restart. If you need more time, please contact
the administrator.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTIFEOF

    chown "$username:$username" "$notification_file" 2>/dev/null || true

    # Stop the container using DS01 workflow
    # First try mlc-stop, fallback to docker stop
    local stopped=false
    local mlc_stop="$INFRA_ROOT/aime-ml-containers/mlc-stop"

    if [ -f "$mlc_stop" ]; then
        if bash "$mlc_stop" "$container_name" -f -s &>/dev/null; then
            stopped=true
            log_color "Stopped via mlc-stop: $container" "$GREEN"
        fi
    fi

    if [ "$stopped" = false ]; then
        if docker stop -t 10 "$container" &>/dev/null; then
            stopped=true
            log_color "Stopped via docker stop: $container" "$GREEN"
        else
            log_color "Failed to stop container: $container" "$RED"
            return 1
        fi
    fi

    # Mark container as stopped in GPU allocator (starts GPU hold timer)
    local gpu_allocator="$INFRA_ROOT/scripts/docker/gpu-allocator-smart.py"
    if [ -f "$gpu_allocator" ]; then
        if python3 "$gpu_allocator" mark-stopped "$container" &>/dev/null; then
            log_color "GPU marked as stopped for: $container" "$GREEN"
        else
            log "Warning: Failed to mark GPU as stopped for: $container"
        fi
    fi

    # Clean up runtime state file
    rm -f "$STATE_DIR/${container}.state"

    log_color "Container $container stopped successfully (GPU hold timer started)" "$GREEN"
}

# Main monitoring function
monitor_containers() {
    log_color "Starting max runtime enforcement" "$BLUE"

    # Get all running containers (using AIME naming convention: name._.uid)
    # This is more robust than relying on labels
    local containers=$(docker ps --format "{{.Names}}" | grep '\._\.' || true)

    if [ -z "$containers" ]; then
        log "No containers running (AIME naming convention)"
        return
    fi

    local monitored_count=0
    local stopped_count=0
    local warned_count=0

    for container in $containers; do
        # Verify container still exists (race condition protection)
        if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log "Container $container no longer exists, skipping"
            continue
        fi

        # Extract user ID from container name (format: name._.uid)
        local user_id=$(echo "$container" | rev | cut -d'.' -f1 | rev)

        # Get username from user ID
        local username=$(getent passwd "$user_id" | cut -d: -f1 2>/dev/null || echo "")

        if [ -z "$username" ]; then
            log "Warning: Cannot resolve username for UID $user_id (container: $container), skipping"
            continue
        fi

        ((monitored_count++))

        # Wrap in error handling to prevent one container from breaking the whole loop
        if ! process_container_runtime "$container" "$username"; then
            log_color "Error processing container $container, continuing with next" "$RED"
            continue
        fi
    done

    log_color "Runtime enforcement complete: monitored=$monitored_count, warned=$warned_count, stopped=$stopped_count" "$BLUE"
}

# Process a single container (extracted for error handling)
process_container_runtime() {
    local container="$1"
    local username="$2"

    # Get max runtime for this user
    local runtime_str=$(get_max_runtime "$username")
    local runtime_seconds=$(runtime_to_seconds "$runtime_str")

    # Skip if no limit set
    if [ "$runtime_seconds" -eq 0 ]; then
        log "Container $container (user: $username) has no runtime limit"
        return 0
    fi

    # Get container start time
    local start_time=$(get_container_start_time "$container")
    if [ "$start_time" -eq 0 ]; then
        log_color "Warning: Could not get start time for $container" "$YELLOW"
        return 0
    fi

    # Calculate runtime
    local now=$(date +%s)
    local runtime_seconds_actual=$((now - start_time))
    local runtime_hours=$((runtime_seconds_actual / 3600))

    # State file for tracking warnings
    local state_file="$STATE_DIR/${container}.state"
    if [ ! -f "$state_file" ]; then
        echo "WARNED=false" > "$state_file"
    fi

    source "$state_file"

    log "Container $container (user: $username): runtime ${runtime_hours}h / limit $runtime_str"

    # Calculate warning threshold (90% of limit)
    local warning_seconds=$((runtime_seconds * 90 / 100))

    # Check if we should warn
    if [ "$runtime_seconds_actual" -ge "$warning_seconds" ] && [ "$WARNED" != "true" ]; then
        local hours_until_stop=$(( (runtime_seconds - runtime_seconds_actual) / 3600 ))
        send_warning "$username" "$container" "$hours_until_stop"
        sed -i "s/^WARNED=.*/WARNED=true/" "$state_file"
    fi

    # Check if we should stop
    if [ "$runtime_seconds_actual" -ge "$runtime_seconds" ]; then
        stop_runtime_exceeded "$username" "$container" "$runtime_hours"
        return 0
    fi

    return 0
}

# Run monitoring
monitor_containers
