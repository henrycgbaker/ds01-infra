# File: /opt/ds01-infra/scripts/maintenance/check-idle-containers.sh
#!/bin/bash
# Monitor container activity and handle idle cleanup with warnings

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$INFRA_ROOT/config/resource-limits.yaml"
STATE_DIR="/var/lib/ds01-infra/container-states"
LOG_FILE="/var/log/ds01-infra/idle-cleanup.log"

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
    python3 - <<PYEOF
import yaml
import sys

try:
    with open("$CONFIG_FILE") as f:
        config = yaml.safe_load(f)
    
    # Check user overrides first
    if 'user_overrides' in config and '$username' in config['user_overrides']:
        timeout = config['user_overrides']['$username'].get('idle_timeout')
        if timeout:
            print(timeout)
            sys.exit(0)
    
    # Check groups
    if 'groups' in config:
        for group_name, group_config in config['groups'].items():
            if 'members' in group_config and '$username' in group_config['members']:
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
    
    case "$unit" in
        h) echo $((value * 3600)) ;;
        d) echo $((value * 86400)) ;;
        w) echo $((value * 604800)) ;;
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

To stop now and free resources:
  mlc-stop $(echo $container | cut -d'.' -f1)

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
  mlc-open $(echo $container | cut -d'.' -f1)

To prevent auto-stop in future:
  1. Keep training/scripts running, OR
  2. Create file: touch /workspace/.keep-alive

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTIFEOF
    
    chown "$username:$username" "$notification_file" 2>/dev/null || true
    
    # Stop the container
    docker stop "$container" 2>/dev/null || true
    
    # Clean up state file
    rm -f "$STATE_DIR/${container}.state"
    
    log_color "Container $container stopped successfully" "$GREEN"
}

# Main monitoring loop
monitor_containers() {
    log_color "Starting idle container monitoring" "$BLUE"
    
    # Get all running DS01 containers
    local containers=$(docker ps --filter "label=aime.mlc.DS01_USER" --format "{{.Names}}")
    
    if [ -z "$containers" ]; then
        log "No DS01 containers running"
        return
    fi
    
    for container in $containers; do
        # Extract username and user ID
        local username=$(docker inspect "$container" --format='{{index .Config.Labels "aime.mlc.DS01_USER"}}' 2>/dev/null)
        local user_id=$(docker inspect "$container" --format='{{index .Config.Labels "aime.mlc.DS01_USER_ID"}}' 2>/dev/null)
        
        if [ -z "$username" ]; then
            continue
        fi
        
        # Get timeout for this user
        local timeout_str=$(get_idle_timeout "$username")
        local timeout_seconds=$(timeout_to_seconds "$timeout_str")
        
        # Skip if no timeout set
        if [ "$timeout_seconds" -eq 0 ]; then
            log "Container $container (user: $username) has no idle timeout"
            continue
        fi
        
        # Check if container is active
        local active=$(is_container_active "$container")
        
        if [ "$active" = "true" ]; then
            update_activity "$container" "true"
            log "Container $container (user: $username) is active"
            continue
        fi
        
        # Get last activity time
        local last_activity=$(get_last_activity "$container")
        local now=$(date +%s)
        local idle_seconds=$((now - last_activity))
        local idle_hours=$((idle_seconds / 3600))
        
        # Calculate warning threshold (80% of timeout)
        local warning_seconds=$((timeout_seconds * 80 / 100))
        
        local state_file="$STATE_DIR/${container}.state"
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
        fi
    done
    
    log_color "Idle monitoring check complete" "$BLUE"
}

# Run monitoring
monitor_containers