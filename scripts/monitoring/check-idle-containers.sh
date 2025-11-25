#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/check-idle-containers.sh
# Monitor container activity and handle idle cleanup with warnings

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
STATE_DIR="/var/lib/ds01/container-states"
LOG_FILE="/var/log/ds01/idle-cleanup.log"

# Create state directory
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

# Get idle timeout for user (in hours)
get_idle_timeout() {
    local username="$1"
    
    # Use Python to parse YAML and get timeout
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
            timeout = config['user_overrides'][username].get('idle_timeout')
            if timeout:
                print(timeout)
                sys.exit(0)

    # Check groups
    if 'groups' in config and config['groups'] is not None:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and username in group_config['members']:
                timeout = group_config.get('idle_timeout')
                if timeout:
                    print(timeout)
                    sys.exit(0)

    # Default timeout
    default_timeout = config.get('defaults', {}).get('idle_timeout', '48h')
    print(default_timeout)
except Exception as e:
    print("48h", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Convert timeout string (e.g., "48h", "7d") to seconds
timeout_to_seconds() {
    local timeout="$1"
    
    if [[ "$timeout" == "null" ]] || [[ -z "$timeout" ]]; then
        echo "0"  # No timeout
        return
    fi
    
    local value="${timeout%[a-z]*}"
    local unit="${timeout#${value}}"
    
    # Use bc for decimal support (e.g., 0.02h)
    case "$unit" in
        h) echo "scale=0; $value * 3600 / 1" | bc ;;
        d) echo "scale=0; $value * 86400 / 1" | bc ;;
        w) echo "scale=0; $value * 604800 / 1" | bc ;;
        *) echo "172800" ;;  # Default 48h
    esac
}

# Get last activity time for container
get_last_activity() {
    local container="$1"
    
    # Check multiple activity indicators
    local last_exec=$(docker inspect "$container" --format='{{.State.StartedAt}}' 2>/dev/null || echo "")
    local last_cpu=$(docker stats "$container" --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    local last_mem=$(docker stats "$container" --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    
    # Get current timestamp
    local now=$(date +%s)
    
    # Get container start time
    local start_time=$(docker inspect "$container" --format='{{.State.StartedAt}}' 2>/dev/null)
    local start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "$now")
    
    # Check state file for last known activity
    local state_file="$STATE_DIR/${container}.state"
    
    if [ -f "$state_file" ]; then
        source "$state_file"
        echo "${LAST_ACTIVITY:-$start_epoch}"
    else
        # Initialize state file
        echo "LAST_ACTIVITY=$start_epoch" > "$state_file"
        echo "LAST_CPU=0.0" >> "$state_file"
        echo "WARNED=false" >> "$state_file"
        echo "$start_epoch"
    fi
}

# Update activity state
update_activity() {
    local container="$1"
    local is_active="$2"
    local state_file="$STATE_DIR/${container}.state"
    
    if [ ! -f "$state_file" ]; then
        return
    fi
    
    source "$state_file"
    
    if [ "$is_active" = "true" ]; then
        # Reset activity timestamp
        sed -i "s/^LAST_ACTIVITY=.*/LAST_ACTIVITY=$(date +%s)/" "$state_file"
        sed -i "s/^WARNED=.*/WARNED=false/" "$state_file"
    fi
}

# Check if container is active
is_container_active() {
    local container="$1"
    
    # Check CPU usage
    local cpu=$(docker stats "$container" --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    
    # Consider active if CPU > 1%
    if (( $(echo "$cpu > 1.0" | bc -l) )); then
        echo "true"
        return
    fi
    
    # Check for active processes (excluding bash/sleep)
    local procs=$(docker exec "$container" ps aux 2>/dev/null | grep -v "ps aux" | grep -v "bash" | grep -v "sleep" | wc -l)
    if [ "$procs" -gt 2 ]; then
        echo "true"
        return
    fi
    
    # Check network activity (bytes transmitted in last interval)
    local net_rx=$(docker stats "$container" --no-stream --format "{{.NetIO}}" 2>/dev/null | cut -d'/' -f1 | numfmt --from=iec || echo "0")
    if [ "$net_rx" -gt 1000000 ]; then  # > 1MB
        echo "true"
        return
    fi
    
    echo "false"
}

# Send warning to user
send_warning() {
    local username="$1"
    local container="$2"
    local hours_until_stop="$3"
    
    # Create warning message in user's home
    local user_home=$(eval echo "~$username")
    local warning_file="$user_home/.ds01-idle-warning"
    
    cat > "$warning_file" << WARNEOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  IDLE CONTAINER WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container: $container
Status: IDLE (no activity detected)
Action: Will auto-stop in ~${hours_until_stop} hours

This container will be automatically stopped to free
resources for other users. Your work in /workspace
is safe and will persist.

To keep your container running:
  1. Run any command in the container
  2. Or restart your training/script

To disable this warning (if actively training):
  touch /workspace/.keep-alive

To stop and retire now (frees GPU immediately):
  container-retire $(echo $container | cut -d'.' -f1)

Questions? Email: 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WARNEOF
    
    chown "$username:$username" "$warning_file" 2>/dev/null || true
    
    # Also send message to container if running
    if docker exec "$container" test -d /workspace 2>/dev/null; then
        docker exec "$container" bash -c "cat > /workspace/.idle-warning.txt" < "$warning_file" 2>/dev/null || true
    fi
    
    log_color "Warning sent to $username about container $container" "$YELLOW"
}

# Stop idle container
stop_idle_container() {
    local username="$1"
    local container="$2"

    log_color "Stopping idle container: $container (user: $username)" "$YELLOW"

    # Check for .keep-alive file
    if docker exec "$container" test -f /workspace/.keep-alive 2>/dev/null; then
        log_color "Container $container has .keep-alive file - skipping" "$GREEN"
        return
    fi

    # Create notification
    local user_home=$(eval echo "~$username")
    local notification_file="$user_home/.ds01-stopped-notification"

    cat > "$notification_file" << NOTIFEOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  CONTAINER AUTO-STOPPED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Container: $container
Stopped: $(date)
Reason: Idle timeout reached

Your work in /workspace is safe and persists.

To restart your container:
  container-run $(echo $container | cut -d'.' -f1)

To prevent auto-stop in future:
  1. Keep training/scripts running, OR
  2. Create file: touch /workspace/.keep-alive

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTIFEOF

    chown "$username:$username" "$notification_file" 2>/dev/null || true

     # Stop and remove container directly (designed for automation efficiency)
    # GPU freed automatically when container removed (Docker labels gone = GPU freed)
    # This enforces the "running or removed" principle without user command overhead

    # Stop container (10 second grace period)
    if docker stop -t 10 "$container" &>/dev/null; then
        log_color "Stopped idle container: $container" "$GREEN"

        # Remove container immediately (frees GPU automatically)
        if docker rm "$container" &>/dev/null; then
            log_color "Removed idle container: $container (GPU freed automatically)" "$GREEN"
            logger -t ds01-idle "Retired idle container: $container (user: $username, idle: ${idle_seconds}s)"
        else
            log_color "Warning: Stopped but failed to remove: $container" "$YELLOW"
            # Container is stopped - GPU will be freed by cleanup-stale-gpu-allocations cron
            return 1
        fi
    else
        log_color "Failed to stop idle container: $container" "$RED"
        return 1
    fi

    # Clean up idle monitoring state file
    rm -f "$STATE_DIR/${container}.state"
}

# Main monitoring loop
monitor_containers() {
    log_color "Starting idle container monitoring" "$BLUE"

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

        ((monitored_count += 1))

        # Wrap in error handling to prevent one container from breaking the whole loop
        if ! process_container "$container" "$username"; then
            log_color "Error processing container $container, continuing with next" "$RED"
            continue
        fi
    done

    log_color "Idle monitoring check complete: monitored=$monitored_count, warned=$warned_count, stopped=$stopped_count" "$BLUE"
}

# Process a single container (extracted for error handling)
process_container() {
    local container="$1"
    local username="$2"

    # Get timeout for this user
    local timeout_str=$(get_idle_timeout "$username")
    local timeout_seconds=$(timeout_to_seconds "$timeout_str")

    # Skip if no timeout set
    if [ "$timeout_seconds" -eq 0 ]; then
        log "Container $container (user: $username) has no idle timeout"
        return 0
    fi

    # Check if container is active
    local active=$(is_container_active "$container")

    if [ "$active" = "true" ]; then
        update_activity "$container" "true"
        log "Container $container (user: $username) is active"
        return 0
    fi

    # Get last activity time
    local last_activity=$(get_last_activity "$container")
    local now=$(date +%s)
    local idle_seconds=$((now - last_activity))
    local idle_hours=$((idle_seconds / 3600))

    # Calculate warning threshold (80% of timeout)
    local warning_seconds=$((timeout_seconds * 80 / 100))

    local state_file="$STATE_DIR/${container}.state"

    # Initialize state file if missing
    if [ ! -f "$state_file" ]; then
        log "Initializing state file for $container"
        echo "LAST_ACTIVITY=$last_activity" > "$state_file"
        echo "LAST_CPU=0.0" >> "$state_file"
        echo "WARNED=false" >> "$state_file"
    fi

    source "$state_file"

    log "Container $container (user: $username): idle for ${idle_hours}h (timeout: $timeout_str)"

    # Check if we should warn
    if [ "$idle_seconds" -ge "$warning_seconds" ] && [ "$WARNED" != "true" ]; then
        local hours_until_stop=$(( (timeout_seconds - idle_seconds) / 3600 ))
        send_warning "$username" "$container" "$hours_until_stop"
        sed -i "s/^WARNED=.*/WARNED=true/" "$state_file"
    fi

    # Check if we should stop
    if [ "$idle_seconds" -ge "$timeout_seconds" ]; then
        stop_idle_container "$username" "$container"
        return 0
    fi

    return 0
}

# Run monitoring
monitor_containers