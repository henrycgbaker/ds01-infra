#!/bin/bash
# /opt/ds01-infra/scripts/monitoring/resource-alert-checker.sh
# DS01 Resource Alert Checker
#
# Checks resource usage for all users and generates alerts when approaching limits.
# Run via cron to generate alerts that users see on login.
#
# Usage:
#   resource-alert-checker.sh              # Check all users
#   resource-alert-checker.sh <username>   # Check specific user
#   resource-alert-checker.sh --clean      # Remove old alerts

set -e

INFRA_ROOT="/opt/ds01-infra"
SCRIPT_DIR="$INFRA_ROOT/scripts"
ALERTS_DIR="/var/lib/ds01/alerts"
RESOURCE_PARSER="$SCRIPT_DIR/docker/get_resource_limits.py"
GPU_STATE_READER="$SCRIPT_DIR/docker/gpu-state-reader.py"
EVENT_LOGGER="$SCRIPT_DIR/docker/event-logger.py"

# Soft limit threshold (80%)
SOFT_LIMIT_THRESHOLD=80

# Alert retention (hours)
ALERT_RETENTION_HOURS=24

# Ensure alerts directory exists
mkdir -p "$ALERTS_DIR"
chmod 755 "$ALERTS_DIR"

# Log to event system
log_event() {
    local event_type="$1"
    local username="$2"
    local message="$3"

    if [ -f "$EVENT_LOGGER" ]; then
        python3 "$EVENT_LOGGER" "$event_type" \
            --user "$username" \
            --message "$message" 2>/dev/null || true
    fi
}

# Get list of DS01 users (users with containers or in groups)
get_ds01_users() {
    # Get users from container labels
    docker ps -a --filter "label=ds01.managed=true" --format '{{.Label "ds01.user"}}' 2>/dev/null | sort -u
}

# Check GPU usage for a user
check_gpu_alerts() {
    local username="$1"
    local alerts_file="$ALERTS_DIR/${username}.json"

    # Get user's GPU limit
    local max_gpus=$(python3 "$RESOURCE_PARSER" "$username" --max-gpus 2>/dev/null || echo "2")

    # Handle unlimited
    if [ "$max_gpus" = "unlimited" ] || [ "$max_gpus" = "null" ] || [ -z "$max_gpus" ]; then
        return 0
    fi

    # Get current GPU count
    local current_gpus=$(python3 "$GPU_STATE_READER" user "$username" 2>/dev/null | grep -c "gpu_slot" || echo "0")

    # Calculate percentage
    local percent=0
    if [ "$max_gpus" -gt 0 ] 2>/dev/null; then
        percent=$((current_gpus * 100 / max_gpus))
    fi

    # Generate alert if needed
    if [ "$percent" -ge 100 ]; then
        add_alert "$username" "gpu_limit_reached" "GPU limit reached: $current_gpus/$max_gpus GPUs allocated"
        log_event "alert.gpu_limit" "$username" "GPU limit reached: $current_gpus/$max_gpus"
    elif [ "$percent" -ge "$SOFT_LIMIT_THRESHOLD" ]; then
        add_alert "$username" "gpu_usage_high" "GPU usage high: $current_gpus/$max_gpus GPUs (${percent}%)"
        log_event "alert.gpu_warning" "$username" "GPU usage at ${percent}%"
    else
        # Clear GPU alerts if usage is below threshold
        clear_alert "$username" "gpu_usage_high"
        clear_alert "$username" "gpu_limit_reached"
    fi
}

# Check container count for a user
check_container_alerts() {
    local username="$1"

    # Get user's container limit
    local max_containers=$(python3 "$RESOURCE_PARSER" "$username" 2>/dev/null | grep -oP 'max_containers_per_user:\s*\K\S+' || echo "3")

    # Handle unlimited
    if [ "$max_containers" = "unlimited" ] || [ "$max_containers" = "null" ] || [ -z "$max_containers" ]; then
        return 0
    fi

    # Get current container count
    local current_containers=$(docker ps -a --filter "label=ds01.user=$username" --format "{{.Names}}" 2>/dev/null | wc -l)

    # Calculate percentage
    local percent=0
    if [ "$max_containers" -gt 0 ] 2>/dev/null; then
        percent=$((current_containers * 100 / max_containers))
    fi

    # Generate alert if needed
    if [ "$percent" -ge 100 ]; then
        add_alert "$username" "container_limit_reached" "Container limit reached: $current_containers/$max_containers"
        log_event "alert.container_limit" "$username" "Container limit reached: $current_containers/$max_containers"
    elif [ "$percent" -ge "$SOFT_LIMIT_THRESHOLD" ]; then
        add_alert "$username" "container_usage_high" "Container usage high: $current_containers/$max_containers (${percent}%)"
        log_event "alert.container_warning" "$username" "Container usage at ${percent}%"
    else
        clear_alert "$username" "container_usage_high"
        clear_alert "$username" "container_limit_reached"
    fi
}

# Add an alert for a user
add_alert() {
    local username="$1"
    local alert_type="$2"
    local message="$3"
    local alerts_file="$ALERTS_DIR/${username}.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create or update alerts file
    if [ -f "$alerts_file" ]; then
        # Check if this alert type already exists
        if python3 -c "import json; alerts=json.load(open('$alerts_file')); exit(0 if any(a['type']=='$alert_type' for a in alerts) else 1)" 2>/dev/null; then
            # Update existing alert
            python3 -c "
import json
with open('$alerts_file', 'r') as f:
    alerts = json.load(f)
for a in alerts:
    if a['type'] == '$alert_type':
        a['message'] = '$message'
        a['updated_at'] = '$timestamp'
        break
with open('$alerts_file', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>/dev/null
        else
            # Add new alert
            python3 -c "
import json
with open('$alerts_file', 'r') as f:
    alerts = json.load(f)
alerts.append({'type': '$alert_type', 'message': '$message', 'created_at': '$timestamp', 'updated_at': '$timestamp'})
with open('$alerts_file', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>/dev/null
        fi
    else
        # Create new alerts file
        echo "[{\"type\": \"$alert_type\", \"message\": \"$message\", \"created_at\": \"$timestamp\", \"updated_at\": \"$timestamp\"}]" > "$alerts_file"
    fi

    chmod 644 "$alerts_file"
}

# Clear a specific alert type for a user
clear_alert() {
    local username="$1"
    local alert_type="$2"
    local alerts_file="$ALERTS_DIR/${username}.json"

    if [ -f "$alerts_file" ]; then
        python3 -c "
import json
with open('$alerts_file', 'r') as f:
    alerts = json.load(f)
alerts = [a for a in alerts if a['type'] != '$alert_type']
with open('$alerts_file', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>/dev/null || true
    fi
}

# Clean old alerts
clean_old_alerts() {
    local cutoff=$(date -d "-${ALERT_RETENTION_HOURS} hours" +%s 2>/dev/null || date -v-${ALERT_RETENTION_HOURS}H +%s)

    for alerts_file in "$ALERTS_DIR"/*.json; do
        [ -f "$alerts_file" ] || continue

        python3 -c "
import json
import datetime
cutoff = datetime.datetime.utcfromtimestamp($cutoff)
with open('$alerts_file', 'r') as f:
    alerts = json.load(f)
alerts = [a for a in alerts if datetime.datetime.fromisoformat(a['updated_at'].replace('Z', '+00:00').replace('+00:00', '')) > cutoff]
with open('$alerts_file', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>/dev/null || true

        # Remove empty alert files
        if [ "$(cat "$alerts_file" 2>/dev/null)" = "[]" ]; then
            rm -f "$alerts_file"
        fi
    done
}

# Check alerts for a specific user
check_user() {
    local username="$1"

    check_gpu_alerts "$username"
    check_container_alerts "$username"
}

# Main
main() {
    case "${1:-}" in
        --clean)
            echo "Cleaning old alerts..."
            clean_old_alerts
            echo "Done."
            ;;
        --help|-h)
            echo "Usage: $0 [username|--clean]"
            echo ""
            echo "Options:"
            echo "  <username>  Check alerts for specific user"
            echo "  --clean     Remove alerts older than ${ALERT_RETENTION_HOURS}h"
            echo "  (no args)   Check all DS01 users"
            ;;
        "")
            # Check all users
            echo "Checking resource alerts for all DS01 users..."
            clean_old_alerts

            local user_count=0
            for username in $(get_ds01_users); do
                [ -n "$username" ] || continue
                check_user "$username"
                ((user_count++))
            done

            if [ "$user_count" -eq 0 ]; then
                echo "No DS01 users with containers found."
            else
                echo "Checked $user_count user(s)."
            fi
            echo "Alerts written to: $ALERTS_DIR"
            ;;
        *)
            # Check specific user
            echo "Checking resource alerts for user: $1"
            check_user "$1"

            local alerts_file="$ALERTS_DIR/${1}.json"
            if [ -f "$alerts_file" ]; then
                local alert_count
                alert_count=$(python3 -c "import json; print(len(json.load(open('$alerts_file'))))" 2>/dev/null || echo "0")
                if [ "$alert_count" -gt 0 ]; then
                    echo "Created $alert_count alert(s) for $1"
                    echo "Alerts file: $alerts_file"
                else
                    echo "No alerts needed for $1 (usage below threshold)"
                fi
            else
                echo "No alerts needed for $1 (usage below threshold)"
            fi
            ;;
    esac
}

main "$@"
