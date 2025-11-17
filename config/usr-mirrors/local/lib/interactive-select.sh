#!/bin/bash
# DS01 Infrastructure - Interactive Selection Library
# Provides interactive menu selection using bash select
# Source this file: source /usr/local/lib/interactive-select.sh

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Generic selection from a list
# Usage: result=$(select_from_list "Prompt text" "${array[@]}")
select_from_list() {
    local prompt="$1"
    shift
    local items=("$@")

    # Check if we have items
    if [ ${#items[@]} -eq 0 ]; then
        echo ""
        return 1
    fi

    # Show prompt
    echo -e "${CYAN}${prompt}${NC}" >&2
    echo "" >&2

    # Use bash select
    PS3=$'\n'"Select number (or Ctrl+C to cancel): "
    select choice in "${items[@]}"; do
        if [ -n "$choice" ]; then
            echo "$choice"
            return 0
        else
            echo -e "${RED}Invalid selection${NC}" >&2
        fi
    done

    # If we get here, selection was cancelled
    echo ""
    return 1
}

# Select a container (with optional filter)
# Usage: container=$(select_container [all|running|stopped])
select_container() {
    local filter="${1:-all}"
    local user_id=$(id -u)
    local containers=()

    # Get containers based on filter
    case "$filter" in
        running)
            mapfile -t containers < <(docker ps --filter "name=\._\.$user_id" --format "{{.Names}}" | sed "s/\._\.$user_id$//" | sort)
            ;;
        stopped)
            # Find ALL non-running containers (created, exited, stopped, paused, dead, etc.)
            # Get all containers except those with status=running
            mapfile -t containers < <(docker ps -a --filter "name=\._\.$user_id" --format "{{.Names}} {{.Status}}" | \
                grep -v "Up " | \
                awk '{print $1}' | \
                sed "s/\._\.$user_id$//" | \
                sort)
            ;;
        all|*)
            mapfile -t containers < <(docker ps -a --filter "name=\._\.$user_id" --format "{{.Names}}" | sed "s/\._\.$user_id$//" | sort)
            ;;
    esac

    # Check if we found any containers
    if [ ${#containers[@]} -eq 0 ]; then
        case "$filter" in
            running)
                echo -e "${YELLOW}No running containers found${NC}" >&2
                ;;
            stopped)
                echo -e "${YELLOW}No stopped containers found${NC}" >&2
                ;;
            *)
                echo -e "${YELLOW}No containers found${NC}" >&2
                ;;
        esac
        return 1
    fi

    # Select container
    local prompt
    case "$filter" in
        running)
            prompt="Select running container:"
            ;;
        stopped)
            prompt="Select stopped container:"
            ;;
        *)
            prompt="Select container:"
            ;;
    esac

    select_from_list "$prompt" "${containers[@]}"
}

# Select an image owned by the user
# Usage: image=$(select_image)
select_image() {
    local images=()

    # Get user's custom images (exclude base images)
    mapfile -t images < <(docker images --format "{{.Repository}}" | grep -v "^<none>$" | grep -v "^ml-" | grep -v "^aime" | sort -u)

    # Check if we found any images
    if [ ${#images[@]} -eq 0 ]; then
        echo -e "${YELLOW}No custom images found${NC}" >&2
        echo -e "${CYAN}Tip:${NC} Create an image with: ${GREEN}image create${NC}" >&2
        return 1
    fi

    # Select image
    select_from_list "Select image:" "${images[@]}"
}

# Confirm yes/no prompt
# Usage: if confirm "Delete this?"; then ... fi
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    local yn
    if [[ "$default" =~ ^[Yy] ]]; then
        echo -n -e "${CYAN}${prompt}${NC} [Y/n]: " >&2
    else
        echo -n -e "${CYAN}${prompt}${NC} [y/N]: " >&2
    fi

    read -r yn
    yn="${yn:-$default}"

    case "$yn" in
        [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Export functions for use in other scripts
export -f select_from_list
export -f select_container
export -f select_image
export -f confirm
