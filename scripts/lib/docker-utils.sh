#!/bin/bash
# DS01 Docker Utilities Library
# Common Docker query patterns extracted from multiple scripts
#
# Usage: source "${DS01_ROOT:-/opt/ds01-infra}/scripts/lib/docker-utils.sh"

# Ensure we have DS01 paths
DS01_ROOT="${DS01_ROOT:-/opt/ds01-infra}"
DS01_SCRIPTS="${DS01_SCRIPTS:-$DS01_ROOT/scripts}"

# ============================================================================
# Container State Functions
# ============================================================================

ds01_container_exists() {
    # Check if a container exists (running or stopped)
    # Args: container_name (short name, without ._.userid suffix)
    # Returns: 0 if exists, 1 otherwise
    local name="$1"
    local user_id="${2:-$(id -u)}"
    local tag="${name}._.${user_id}"
    docker inspect "$tag" &>/dev/null
}

ds01_container_exists_by_tag() {
    # Check if a container exists by full tag
    # Args: container_tag (full name like my-project._.1001)
    # Returns: 0 if exists, 1 otherwise
    local tag="$1"
    docker inspect "$tag" &>/dev/null
}

ds01_container_running() {
    # Check if a container is running
    # Args: container_name (short name)
    # Returns: 0 if running, 1 otherwise
    local name="$1"
    local user_id="${2:-$(id -u)}"
    local tag="${name}._.${user_id}"
    [[ "$(docker inspect -f '{{.State.Running}}' "$tag" 2>/dev/null)" == "true" ]]
}

ds01_container_running_by_tag() {
    # Check if a container is running by full tag
    # Args: container_tag
    # Returns: 0 if running, 1 otherwise
    local tag="$1"
    [[ "$(docker inspect -f '{{.State.Running}}' "$tag" 2>/dev/null)" == "true" ]]
}

ds01_container_paused() {
    # Check if a container is paused
    # Args: container_name (short name)
    # Returns: 0 if paused, 1 otherwise
    local name="$1"
    local user_id="${2:-$(id -u)}"
    local tag="${name}._.${user_id}"
    local status=$(docker inspect -f '{{.State.Status}}' "$tag" 2>/dev/null || echo "")
    [[ "$status" == "paused" ]]
}

ds01_container_status() {
    # Get container status string
    # Args: container_tag (full name)
    # Returns: status string (running, paused, exited, created, etc.) or empty
    local tag="$1"
    docker inspect -f '{{.State.Status}}' "$tag" 2>/dev/null || echo ""
}

# ============================================================================
# Container Label Functions
# ============================================================================

ds01_get_container_label() {
    # Get a specific label from a container
    # Args: container_tag, label_name
    # Returns: label value or empty string
    local container="$1"
    local label="$2"
    local value
    value=$(docker inspect -f "{{index .Config.Labels \"$label\"}}" "$container" 2>/dev/null || echo "")
    # Handle Docker's <no value> placeholder
    if [[ "$value" == "<no value>" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

ds01_get_container_gpu() {
    # Get GPU info for a container (uses gpu-state-reader.py)
    # Args: container_tag
    # Returns: JSON with gpu_uuid, gpu_slot, etc.
    local container="$1"
    python3 "${DS01_SCRIPTS}/docker/gpu-state-reader.py" container "$container" 2>/dev/null
}

ds01_get_container_gpu_uuids() {
    # Get GPU UUIDs from container labels
    # Args: container_tag
    # Returns: comma-separated UUIDs or empty
    local container="$1"
    local uuids
    uuids=$(ds01_get_container_label "$container" "ds01.gpu.uuids")
    if [[ -z "$uuids" ]]; then
        uuids=$(ds01_get_container_label "$container" "ds01.gpu.uuid")
    fi
    echo "$uuids"
}

ds01_get_container_gpu_slots() {
    # Get GPU slots from container labels
    # Args: container_tag
    # Returns: comma-separated slots (e.g., "1.0,1.1") or empty
    local container="$1"
    local slots
    slots=$(ds01_get_container_label "$container" "ds01.gpu.slots")
    if [[ -z "$slots" ]]; then
        slots=$(ds01_get_container_label "$container" "ds01.gpu.allocated")
    fi
    echo "$slots"
}

ds01_get_container_owner() {
    # Get container owner from labels
    # Args: container_tag
    # Returns: username or empty
    local container="$1"
    local owner
    owner=$(ds01_get_container_label "$container" "ds01.user")
    if [[ -z "$owner" ]]; then
        owner=$(ds01_get_container_label "$container" "aime.mlc.USER")
    fi
    echo "$owner"
}

ds01_get_container_interface() {
    # Get container interface (orchestration, atomic, docker, other)
    # Args: container_tag
    # Returns: interface string
    local container="$1"
    local interface
    interface=$(ds01_get_container_label "$container" "ds01.interface")
    if [[ -z "$interface" ]]; then
        # Fallback: detect from container name
        if [[ "$container" == *"._."* ]]; then
            echo "atomic"
        else
            echo "docker"
        fi
    else
        echo "$interface"
    fi
}

# ============================================================================
# User Container Functions
# ============================================================================

ds01_get_user_containers() {
    # List all containers for a user
    # Args: username (optional, defaults to current user)
    # Returns: newline-separated container tags
    local username="${1:-$(whoami)}"
    local user_id
    user_id=$(id -u "$username" 2>/dev/null || echo "$username")
    docker ps -a --filter "name=\._\.${user_id}$" --format "{{.Names}}" 2>/dev/null
}

ds01_get_user_running_containers() {
    # List running containers for a user
    # Args: username (optional)
    # Returns: newline-separated container tags
    local username="${1:-$(whoami)}"
    local user_id
    user_id=$(id -u "$username" 2>/dev/null || echo "$username")
    docker ps --filter "name=\._\.${user_id}$" --format "{{.Names}}" 2>/dev/null
}

ds01_count_user_containers() {
    # Count containers for a user
    # Args: username (optional)
    # Returns: count as integer
    local username="${1:-$(whoami)}"
    ds01_get_user_containers "$username" | wc -l
}

ds01_count_user_running_containers() {
    # Count running containers for a user
    # Args: username (optional)
    # Returns: count as integer
    local username="${1:-$(whoami)}"
    ds01_get_user_running_containers "$username" | wc -l
}

# ============================================================================
# Container Name Helpers
# ============================================================================

ds01_container_name_to_tag() {
    # Convert short container name to full tag
    # Args: container_name, user_id (optional)
    # Returns: full tag (e.g., my-project._.1001)
    local name="$1"
    local user_id="${2:-$(id -u)}"
    echo "${name}._.${user_id}"
}

ds01_tag_to_container_name() {
    # Extract short name from full tag
    # Args: container_tag
    # Returns: short name (e.g., my-project from my-project._.1001)
    local tag="$1"
    echo "$tag" | sed 's/\._\.[0-9]*$//'
}

ds01_tag_to_user_id() {
    # Extract user ID from full tag
    # Args: container_tag
    # Returns: user ID (e.g., 1001 from my-project._.1001)
    local tag="$1"
    echo "$tag" | grep -oP '(?<=\._\.)\d+$'
}

# ============================================================================
# DS01 Container Detection
# ============================================================================

ds01_is_ds01_managed() {
    # Check if a container is managed by DS01
    # Args: container_tag
    # Returns: 0 if DS01-managed, 1 otherwise
    local tag="$1"
    local managed
    managed=$(ds01_get_container_label "$tag" "ds01.managed")
    [[ "$managed" == "true" ]]
}

ds01_is_aime_container() {
    # Check if a container was created via AIME
    # Args: container_tag
    # Returns: 0 if AIME container, 1 otherwise
    local tag="$1"
    # AIME containers follow name._.userid pattern
    [[ "$tag" == *"._."* ]]
}
