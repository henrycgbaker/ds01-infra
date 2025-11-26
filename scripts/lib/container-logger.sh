#!/bin/bash
# /opt/ds01-infra/scripts/lib/container-logger.sh
# Container Operation Logger - Wrapper for centralized event logging
#
# All container lifecycle events go through event-logger.py for consistent
# JSON-lines format in /var/log/ds01/events.jsonl
#
# Usage:
#   source /opt/ds01-infra/scripts/lib/container-logger.sh
#   log_event "container.created" user="$USER" container="my-proj" gpu="1.2"

# Path to event logger
EVENT_LOGGER="/opt/ds01-infra/scripts/docker/event-logger.py"

# Log an event to the centralized event log
# Usage: log_event <event_type> [key=value ...]
# Example: log_event "container.started" user="alice" container="proj._.alice"
log_event() {
    local event_type="$1"
    shift

    # Call event-logger.py, silently fail if not available
    python3 "$EVENT_LOGGER" log "$event_type" "$@" 2>/dev/null || true
}

# Legacy function - maps to new event types for backwards compatibility
log_container_operation() {
    local operation="$1"    # create, start, stop, remove, failed_create, etc.
    local user="$2"         # username
    local container="$3"    # container name with ._.uid
    local gpu_id="$4"       # GPU ID or "none"
    local status="$5"       # success, failed, warning
    local details="$6"      # Additional details/error message

    # Map old operations to new event types
    local event_type
    case "$operation" in
        create|created)
            event_type="container.created"
            ;;
        start|started)
            event_type="container.started"
            ;;
        stop|stopped)
            event_type="container.stopped"
            ;;
        remove|removed)
            event_type="container.removed"
            ;;
        failed_create|create_failed)
            event_type="container.create_failed"
            ;;
        *)
            event_type="container.$operation"
            ;;
    esac

    # Build arguments
    local args=()
    [[ -n "$user" ]] && args+=("user=$user")
    [[ -n "$container" ]] && args+=("container=$container")
    [[ -n "$gpu_id" && "$gpu_id" != "none" ]] && args+=("gpu=$gpu_id")
    [[ -n "$status" ]] && args+=("status=$status")
    [[ -n "$details" ]] && args+=("details=$details")

    log_event "$event_type" "${args[@]}"
}

# Convenience functions for common events
log_container_created() {
    local user="$1" container="$2" gpu="${3:-}" interface="${4:-atomic}"
    log_event "container.created" user="$user" container="$container" \
        ${gpu:+gpu="$gpu"} interface="$interface"
}

log_container_started() {
    local user="$1" container="$2"
    log_event "container.started" user="$user" container="$container"
}

log_container_stopped() {
    local user="$1" container="$2" reason="${3:-manual}"
    log_event "container.stopped" user="$user" container="$container" reason="$reason"
}

log_container_removed() {
    local user="$1" container="$2" gpu_released="${3:-false}"
    log_event "container.removed" user="$user" container="$container" \
        gpu_released="$gpu_released"
}

log_gpu_allocated() {
    local user="$1" container="$2" gpu="$3"
    log_event "gpu.allocated" user="$user" container="$container" gpu="$gpu"
}

log_gpu_released() {
    local user="$1" container="$2" gpu="$3" reason="${4:-manual}"
    log_event "gpu.released" user="$user" container="$container" gpu="$gpu" reason="$reason"
}

log_gpu_rejected() {
    local user="$1" container="$2" reason="$3"
    log_event "gpu.rejected" user="$user" container="$container" reason="$reason"
}

log_health_check() {
    local status="$1" passed="${2:-0}" failed="${3:-0}"
    log_event "health.check" status="$status" checks_passed="$passed" checks_failed="$failed"
}

log_bare_metal_warning() {
    local user="$1" pids="$2" message="$3"
    log_event "bare_metal.warning" user="$user" pids="$pids" message="$message"
}

# Export functions for use in other scripts
export -f log_event log_container_operation
export -f log_container_created log_container_started log_container_stopped log_container_removed
export -f log_gpu_allocated log_gpu_released log_gpu_rejected
export -f log_health_check log_bare_metal_warning
