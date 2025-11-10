#!/bin/bash
# Interactive Selection Library for DS01
# Provides user-friendly GUI prompts for selecting containers and images

# Check if we're in an interactive terminal
is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# Select a container from user's containers
# Usage: select_container [filter]
#   filter: "running" for only running containers, "stopped" for only stopped, or omit for all
select_container() {
    local filter="${1:-all}"
    local USERNAME=$(whoami)
    local USER_ID=$(id -u)

    # Colors
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'
    local YELLOW='\033[1;33m'
    local RED='\033[0;31m'
    local BOLD='\033[1m'
    local DIM='\033[2m'
    local NC='\033[0m'

    # Get containers based on filter
    local containers
    case "$filter" in
        running)
            containers=$(docker ps --format "{{.Names}}" --filter "name=._.$USER_ID" 2>/dev/null | sed "s/\._\.$USER_ID//")
            ;;
        stopped)
            containers=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}" --filter "name=._.$USER_ID" 2>/dev/null | sed "s/\._\.$USER_ID//")
            ;;
        *)
            containers=$(docker ps -a --format "{{.Names}}" --filter "name=._.$USER_ID" 2>/dev/null | sed "s/\._\.$USER_ID//")
            ;;
    esac

    # Check if any containers exist
    if [ -z "$containers" ]; then
        case "$filter" in
            running)
                echo -e "${YELLOW}No running containers found${NC}" >&2
                ;;
            stopped)
                echo -e "${YELLOW}No stopped containers found${NC}" >&2
                ;;
            *)
                echo -e "${YELLOW}No containers found${NC}" >&2
                echo -e "Create one with: ${GREEN}container-create <name>${NC}" >&2
                ;;
        esac
        return 1
    fi

    # Convert to array
    local container_array=()
    while IFS= read -r line; do
        [ -n "$line" ] && container_array+=("$line")
    done <<< "$containers"

    local count=${#container_array[@]}

    # If only one container, auto-select it
    if [ "$count" -eq 1 ]; then
        echo "${container_array[0]}"
        return 0
    fi

    # Show selection menu
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BOLD}Select a Container${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2

    # Display containers with status
    local idx=1
    for container in "${container_array[@]}"; do
        local container_tag="${container}._.$USER_ID"
        local status=$(docker ps -a --format "{{.Status}}" --filter "name=^${container_tag}$" 2>/dev/null)
        local image=$(docker inspect --format "{{.Config.Image}}" "$container_tag" 2>/dev/null | cut -d: -f1)

        # Status indicator
        if [[ "$status" == Up* ]]; then
            echo -e "  ${BOLD}${idx})${NC} ${CYAN}${container}${NC} ${GREEN}●${NC} Running" >&2
        else
            echo -e "  ${BOLD}${idx})${NC} ${CYAN}${container}${NC} ${DIM}○${NC} Stopped" >&2
        fi
        echo -e "     ${DIM}Image: $image${NC}" >&2
        echo "" >&2

        idx=$((idx + 1))
    done

    echo -e "  ${BOLD}0)${NC} Cancel" >&2
    echo "" >&2

    # Get user choice
    while true; do
        read -p "$(echo -e "Choice [0-$count]: ")" choice </dev/tty

        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$count" ]; then
            if [ "$choice" -eq 0 ]; then
                return 1
            fi
            echo "${container_array[$((choice - 1))]}"
            return 0
        else
            echo -e "${RED}Invalid choice. Please enter 0-${count}${NC}" >&2
        fi
    done
}

# Select an image from user's images
# Usage: select_image
select_image() {
    local USERNAME=$(whoami)

    # Colors
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'
    local YELLOW='\033[1;33m'
    local RED='\033[0;31m'
    local BOLD='\033[1m'
    local DIM='\033[2m'
    local NC='\033[0m'

    # Get user's images
    local images=$(docker images --format "{{.Repository}}" --filter "reference=${USERNAME}-*" 2>/dev/null)

    # Check if any images exist
    if [ -z "$images" ]; then
        echo -e "${YELLOW}No images found${NC}" >&2
        echo -e "Create one with: ${GREEN}image-create <name>${NC}" >&2
        return 1
    fi

    # Convert to array
    local image_array=()
    while IFS= read -r line; do
        [ -n "$line" ] && image_array+=("$line")
    done <<< "$images"

    local count=${#image_array[@]}

    # If only one image, auto-select it
    if [ "$count" -eq 1 ]; then
        echo "${image_array[0]}"
        return 0
    fi

    # Show selection menu
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BOLD}Select an Image${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2

    # Display images
    local idx=1
    for image in "${image_array[@]}"; do
        local size=$(docker images --format "{{.Size}}" "$image" | head -1)
        local created=$(docker images --format "{{.CreatedSince}}" "$image" | head -1)

        echo -e "  ${BOLD}${idx})${NC} ${CYAN}${image}${NC}" >&2
        echo -e "     ${DIM}Size: $size  •  Created: $created${NC}" >&2
        echo "" >&2

        idx=$((idx + 1))
    done

    echo -e "  ${BOLD}0)${NC} Cancel" >&2
    echo "" >&2

    # Get user choice
    while true; do
        read -p "$(echo -e "Choice [0-$count]: ")" choice </dev/tty

        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$count" ]; then
            if [ "$choice" -eq 0 ]; then
                return 1
            fi
            echo "${image_array[$((choice - 1))]}"
            return 0
        else
            echo -e "${RED}Invalid choice. Please enter 0-${count}${NC}" >&2
        fi
    done
}

# Show a selection menu for cleanup operations
# Usage: select_cleanup_action
select_cleanup_action() {
    local USERNAME=$(whoami)
    local USER_ID=$(id -u)

    # Colors
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'
    local YELLOW='\033[1;33m'
    local RED='\033[0;31m'
    local BOLD='\033[1m'
    local DIM='\033[2m'
    local NC='\033[0m'

    # Get stopped containers
    local stopped=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}" --filter "name=._.$USER_ID" 2>/dev/null | sed "s/\._\.$USER_ID//")

    if [ -z "$stopped" ]; then
        echo -e "${GREEN}No stopped containers to clean up${NC}" >&2
        return 1
    fi

    # Convert to array
    local container_array=()
    while IFS= read -r line; do
        [ -n "$line" ] && container_array+=("$line")
    done <<< "$stopped"

    local count=${#container_array[@]}

    # Show selection menu
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BOLD}Container Cleanup${NC}" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2

    echo -e "${BOLD}Found $count stopped container(s)${NC}" >&2
    echo "" >&2

    # List containers
    local idx=1
    for container in "${container_array[@]}"; do
        local container_tag="${container}._.$USER_ID"
        local image=$(docker inspect --format "{{.Config.Image}}" "$container_tag" 2>/dev/null | cut -d: -f1)
        local status=$(docker ps -a --format "{{.Status}}" --filter "name=^${container_tag}$" 2>/dev/null)

        echo -e "  ${idx}. ${CYAN}${container}${NC} ${DIM}($status)${NC}" >&2
        echo -e "     ${DIM}Image: $image${NC}" >&2

        idx=$((idx + 1))
    done

    echo "" >&2
    echo -e "${BOLD}What would you like to do?${NC}" >&2
    echo "" >&2
    echo -e "  ${BOLD}1)${NC} Remove ALL stopped containers" >&2
    echo -e "  ${BOLD}2)${NC} Select specific container to remove" >&2
    echo -e "  ${BOLD}0)${NC} Cancel" >&2
    echo "" >&2

    # Get user choice
    while true; do
        read -p "$(echo -e "Choice [0-2]: ")" choice </dev/tty

        case "$choice" in
            0)
                return 1
                ;;
            1)
                echo "--all"
                return 0
                ;;
            2)
                # Sub-menu for specific container
                echo "" >&2
                echo -e "${BOLD}Select container to remove:${NC}" >&2
                echo "" >&2

                local idx=1
                for container in "${container_array[@]}"; do
                    echo -e "  ${BOLD}${idx})${NC} ${CYAN}${container}${NC}" >&2
                    idx=$((idx + 1))
                done
                echo -e "  ${BOLD}0)${NC} Back" >&2
                echo "" >&2

                while true; do
                    read -p "$(echo -e "Choice [0-$count]: ")" sub_choice </dev/tty

                    if [[ "$sub_choice" =~ ^[0-9]+$ ]] && [ "$sub_choice" -ge 0 ] && [ "$sub_choice" -le "$count" ]; then
                        if [ "$sub_choice" -eq 0 ]; then
                            return 1
                        fi
                        echo "${container_array[$((sub_choice - 1))]}"
                        return 0
                    else
                        echo -e "${RED}Invalid choice. Please enter 0-${count}${NC}" >&2
                    fi
                done
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 0-2${NC}" >&2
                ;;
        esac
    done
}
