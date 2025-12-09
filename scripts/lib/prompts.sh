#!/bin/bash
# /opt/ds01-infra/scripts/lib/prompts.sh
# DS01 Shared Prompt Library
#
# Provides safe, consistent prompt functions with:
# - Buffer flushing before all prompts
# - Graceful handling of empty input
# - Default value support
# - Consistent formatting
#
# Usage in scripts:
#   source /opt/ds01-infra/scripts/lib/prompts.sh
#
#   # Prompt with default
#   ds01_prompt "Choice [1-2, default: 1]: " "1" CHOICE
#
#   # Required prompt (loops until non-empty)
#   ds01_prompt_required "Container name: " CONTAINER_NAME
#
#   # Yes/No prompt with default
#   if ds01_confirm "Continue?" "y"; then
#       # user confirmed
#   fi
#
#   # Press Enter to continue
#   ds01_pause
#

# Colors (if not already defined)
: "${GREEN:='\033[0;32m'}"
: "${YELLOW:='\033[1;33m'}"
: "${RED:='\033[0;31m'}"
: "${CYAN:='\033[0;36m'}"
: "${BOLD:='\033[1m'}"
: "${DIM:='\033[2m'}"
: "${NC:='\033[0m'}"

# =============================================================================
# ds01_flush_stdin
# =============================================================================
# Flush any buffered stdin to prevent stale input from being read.
# Call this before any read operation that could be affected by leftover input.
#
# Usage:
#   ds01_flush_stdin
#   read -p "Choice: " CHOICE
#
ds01_flush_stdin() {
    read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true
}

# =============================================================================
# ds01_prompt
# =============================================================================
# Safe prompt with buffer flush and default handling.
# Empty input returns the default value.
#
# Arguments:
#   $1 - Prompt string (should include default hint, e.g., "[default: 1]")
#   $2 - Default value
#   $3 - Variable name to store result
#
# Usage:
#   ds01_prompt "Choice [1-2, default: 1]: " "1" CHOICE
#   echo "You chose: $CHOICE"
#
ds01_prompt() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local input

    ds01_flush_stdin
    read -p "$prompt" input </dev/tty

    # Use default if empty
    if [[ -z "$input" ]]; then
        input="$default"
    fi

    # Set the variable
    eval "$varname=\"\$input\""
}

# =============================================================================
# ds01_prompt_required
# =============================================================================
# Prompt that loops until non-empty input is provided.
# Displays a friendly message on empty input.
#
# Arguments:
#   $1 - Prompt string
#   $2 - Variable name to store result
#   $3 - (Optional) Custom error message
#
# Usage:
#   ds01_prompt_required "Container name: " CONTAINER_NAME
#   ds01_prompt_required "Project name: " PROJECT_NAME "Project name cannot be empty"
#
ds01_prompt_required() {
    local prompt="$1"
    local varname="$2"
    local error_msg="${3:-Input required. Please try again.}"
    local input=""

    while [[ -z "$input" ]]; do
        ds01_flush_stdin
        read -p "$prompt" input </dev/tty

        if [[ -z "$input" ]]; then
            echo -e "${YELLOW}${error_msg}${NC}"
        fi
    done

    eval "$varname=\"\$input\""
}

# =============================================================================
# ds01_confirm
# =============================================================================
# Yes/No confirmation prompt with default handling.
# Returns 0 (true) for yes, 1 (false) for no.
#
# Arguments:
#   $1 - Question to ask
#   $2 - Default: "y" for yes, "n" for no (default: "n")
#
# Usage:
#   if ds01_confirm "Continue?" "y"; then
#       echo "Proceeding..."
#   fi
#
#   if ds01_confirm "Delete container?" "n"; then
#       # only runs if user explicitly types y/yes
#   fi
#
ds01_confirm() {
    local question="$1"
    local default="${2:-n}"
    local prompt
    local response

    # Build prompt with appropriate hint
    if [[ "$default" == "y" ]]; then
        prompt="$question [Y/n]: "
    else
        prompt="$question [y/N]: "
    fi

    ds01_flush_stdin
    read -p "$prompt" response </dev/tty

    # Use default if empty
    if [[ -z "$response" ]]; then
        response="$default"
    fi

    # Check response
    case "${response,,}" in
        y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# ds01_confirm_destructive
# =============================================================================
# Confirmation for destructive actions - requires explicit "yes" (no default).
# Returns 0 (true) for yes, 1 (false) for anything else.
#
# Arguments:
#   $1 - Question to ask (should describe the destructive action)
#
# Usage:
#   if ds01_confirm_destructive "Delete container 'my-project' and free GPU?"; then
#       docker rm -f "$CONTAINER"
#   fi
#
ds01_confirm_destructive() {
    local question="$1"
    local response

    ds01_flush_stdin
    read -p "$question (yes/no): " response </dev/tty

    case "${response,,}" in
        yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# ds01_pause
# =============================================================================
# Press Enter to continue pause.
# Use after information-heavy sections to let users digest content.
#
# Arguments:
#   $1 - (Optional) Custom message (default: "Press Enter to continue...")
#
# Usage:
#   echo "Here's a lot of information..."
#   ds01_pause
#   echo "Now continuing..."
#
ds01_pause() {
    local message="${1:-Press Enter to continue...}"

    echo ""
    ds01_flush_stdin
    read -p "$message" </dev/tty
    echo ""
}

# =============================================================================
# ds01_select
# =============================================================================
# Numeric selection menu with default handling.
# Displays options and returns selected index (1-based) or default.
#
# Arguments:
#   $1 - Variable name to store result (1-based index)
#   $2 - Default selection (1-based index)
#   $3+ - Options to display
#
# Usage:
#   ds01_select CHOICE 1 "Option A" "Option B" "Option C"
#   echo "You selected option $CHOICE"
#
ds01_select() {
    local varname="$1"
    local default="$2"
    shift 2
    local options=("$@")
    local count=${#options[@]}
    local i
    local input

    # Display options
    for i in "${!options[@]}"; do
        local num=$((i + 1))
        if [[ "$num" == "$default" ]]; then
            echo -e "  ${BOLD}${num})${NC} ${options[$i]} ${GREEN}(default)${NC}"
        else
            echo -e "  ${BOLD}${num})${NC} ${options[$i]}"
        fi
    done
    echo ""

    ds01_flush_stdin
    read -p "Choice [1-$count, default: $default]: " input </dev/tty

    # Use default if empty
    if [[ -z "$input" ]]; then
        input="$default"
    fi

    # Validate and set
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 ]] && [[ "$input" -le "$count" ]]; then
        eval "$varname=\"\$input\""
    else
        # Invalid input, use default
        echo -e "${YELLOW}Invalid choice, using default.${NC}"
        eval "$varname=\"\$default\""
    fi
}

# =============================================================================
# ds01_select_or_loop
# =============================================================================
# Numeric selection menu that loops on invalid input instead of defaulting.
# Use when a selection is required and there's no sensible default.
#
# Arguments:
#   $1 - Variable name to store result (1-based index)
#   $2+ - Options to display
#
# Usage:
#   ds01_select_or_loop CHOICE "Delete" "Keep" "Cancel"
#
ds01_select_or_loop() {
    local varname="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    local i
    local input
    local valid=false

    # Display options
    for i in "${!options[@]}"; do
        local num=$((i + 1))
        echo -e "  ${BOLD}${num})${NC} ${options[$i]}"
    done
    echo ""

    while [[ "$valid" == false ]]; do
        ds01_flush_stdin
        read -p "Choice [1-$count]: " input </dev/tty

        if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 ]] && [[ "$input" -le "$count" ]]; then
            valid=true
            eval "$varname=\"\$input\""
        else
            echo -e "${YELLOW}Please enter a number between 1 and $count.${NC}"
        fi
    done
}

# Export functions for subshells
export -f ds01_flush_stdin ds01_prompt ds01_prompt_required
export -f ds01_confirm ds01_confirm_destructive ds01_pause
export -f ds01_select ds01_select_or_loop
