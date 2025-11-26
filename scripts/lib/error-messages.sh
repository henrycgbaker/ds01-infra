#!/bin/bash
# /opt/ds01-infra/scripts/lib/error-messages.sh
# DS01 User-Friendly Error Messages
#
# Translates internal error codes to helpful user messages.
# Source this file to use the functions.

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Contact info for ad-hoc quota requests (edit these to customize)
DS01_LAB_NAME="${DS01_LAB_NAME:-Data Science Lab}"
DS01_ADMIN_NAME="${DS01_ADMIN_NAME:-Henry Baker}"
DS01_ADMIN_ROLE="${DS01_ADMIN_ROLE:-Research Engineer}"
DS01_ADMIN_EMAIL="${DS01_ADMIN_EMAIL:-h.baker@hertie-school.org}"

# Show contact information for resource requests
show_contact_info() {
    echo -e "  ${BLUE}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${BLUE}│${NC}  ${BOLD}Need more resources?${NC}                                    ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  You can discuss arranging larger quotas (ideally in     ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  advance) by contacting the ${DS01_LAB_NAME}.              ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}                                                          ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  Contact: ${BOLD}${DS01_ADMIN_NAME}${NC} (${DS01_ADMIN_ROLE})              ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  Email:   ${BOLD}${DS01_ADMIN_EMAIL}${NC}                   ${BLUE}│${NC}"
    echo -e "  ${BLUE}╰──────────────────────────────────────────────────────────╯${NC}"
}

# Display a resource limit error with guidance
show_limit_error() {
    local error_code="$1"
    local username="${2:-$USER}"
    local container="${3:-}"

    echo ""

    case "$error_code" in
        *USER_AT_LIMIT*)
            # Extract current/max from message like "USER_AT_LIMIT (2/2)"
            local current=$(echo "$error_code" | grep -oP '\((\d+)/' | tr -d '(/')
            local max=$(echo "$error_code" | grep -oP '/(\d+)\)' | tr -d '/)')

            echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║${NC}  ${BOLD}GPU Limit Reached${NC}                                          ${RED}║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  You have ${BOLD}${current}${NC} GPU(s) allocated, which is your maximum of ${BOLD}${max}${NC}."
            echo ""
            echo -e "  ${BOLD}To free up a GPU:${NC}"
            echo "    1. View your containers:  container-list"
            echo "    2. Retire a container:    container-retire <name>"
            echo ""
            echo -e "  ${BOLD}Or run without GPU:${NC}"
            echo "    container-deploy <name> --no-gpu"
            echo ""
            echo -e "  Run ${BLUE}check-limits${NC} to see your full resource status."
            echo ""
            show_contact_info
            ;;

        *FULL_GPU_NOT_ALLOWED*)
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║${NC}  ${BOLD}Full GPU Access Restricted${NC}                                 ${YELLOW}║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "  Your account can only use MIG (GPU slice) instances,"
            echo "  not full GPUs."
            echo ""
            echo -e "  ${BOLD}MIG instances are sufficient for most workloads:${NC}"
            echo "    • Training small/medium models"
            echo "    • Fine-tuning pre-trained models"
            echo "    • Development and debugging"
            echo ""
            echo "  If you need full GPU access for large model training,"
            echo "  you can request researcher access."
            echo ""
            echo -e "  Run ${BLUE}check-limits${NC} to see your current permissions."
            echo ""
            show_contact_info
            ;;

        *No\ GPUs\ available*|*all\ allocated*)
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║${NC}  ${BOLD}No GPUs Currently Available${NC}                                ${YELLOW}║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "  All GPUs are currently in use by other users."
            echo ""
            echo -e "  ${BOLD}Options:${NC}"
            echo "    1. Wait a few minutes and try again"
            echo "    2. Run 'dashboard' to see current GPU usage"
            echo "    3. Start container without GPU:  container-deploy <name> --no-gpu"
            echo -e "    4. ${BLUE}Join notification queue:${NC}  gpu-queue add $username <container> 1"
            echo ""
            echo "  GPUs are usually freed within a few hours as jobs complete."
            echo "  The queue will notify you when a GPU becomes available."
            echo ""
            show_contact_info
            ;;

        *No\ MIG\ instances*|*only\ full\ GPUs*)
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║${NC}  ${BOLD}No MIG Instances Available${NC}                                 ${YELLOW}║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "  All MIG (GPU slice) instances are currently in use."
            echo "  Only full GPUs are free, but your account uses MIG only."
            echo ""
            echo -e "  ${BOLD}Options:${NC}"
            echo "    1. Wait and try again (MIG slots free as containers stop)"
            echo "    2. Run 'dashboard' to see current usage"
            echo "    3. Start without GPU:  container-deploy <name> --no-gpu"
            echo ""
            show_contact_info
            ;;

        *CONTAINER_LIMIT*)
            local current=$(echo "$error_code" | grep -oP '\((\d+)/' | tr -d '(/')
            local max=$(echo "$error_code" | grep -oP '/(\d+)\)' | tr -d '/)')

            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║${NC}  ${BOLD}Container Limit Reached${NC}                                    ${YELLOW}║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  You have ${BOLD}${current:-?}${NC} containers, which is your maximum of ${BOLD}${max:-?}${NC}."
            echo ""
            echo -e "  ${BOLD}To create a new container:${NC}"
            echo "    1. View your containers:  container-list"
            echo "    2. Remove an old one:     container-retire <name>"
            echo ""
            show_contact_info
            ;;

        *)
            # Generic error
            echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║${NC}  ${BOLD}Resource Allocation Failed${NC}                                  ${RED}║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "  Error: $error_code"
            echo ""
            echo -e "  Run ${BLUE}check-limits${NC} to see your resource status."
            echo ""
            show_contact_info
            ;;
    esac

    echo ""
}

# Show bare metal warning (for users running processes outside containers)
show_bare_metal_warning() {
    local process_count="${1:-1}"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}⚠ Running Processes Outside Containers${NC}                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  You have ${BOLD}${process_count}${NC} compute process(es) running on bare metal."
    echo ""
    echo -e "  ${BOLD}Important:${NC} We are transitioning to container-only workflows."
    echo "  In the future, bare metal processes will be restricted."
    echo ""
    echo -e "  ${BOLD}Benefits of containers:${NC}"
    echo "    • Guaranteed GPU access and resource isolation"
    echo "    • Reproducible environments"
    echo "    • Persistent workspaces saved automatically"
    echo "    • No conflicts with other users"
    echo ""
    echo -e "  ${BOLD}To migrate your workflow:${NC}"
    echo "    1. Create a container:    container-deploy my-project"
    echo "    2. Install your packages: pip install ..."
    echo "    3. Your files in ~/workspace persist across sessions"
    echo ""
    echo "  Questions? Run 'container-deploy --help' or ask your admin."
    echo ""
}

# Show quota warning
show_quota_warning() {
    local usage_percent="${1:-0}"
    local storage_limit="${2:-100G}"

    if [[ $usage_percent -ge 95 ]]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}⚠ Storage Almost Full${NC}                                       ${RED}║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "  You are using ${BOLD}${usage_percent}%${NC} of your ${storage_limit} quota."
        echo ""
        echo -e "  ${BOLD}Actions needed:${NC}"
        echo "    1. Find large files:    du -sh * | sort -h"
        echo "    2. Clean up cache:      rm -rf ~/.cache/*"
        echo "    3. Remove old data:     (review and delete unneeded files)"
        echo ""
    elif [[ $usage_percent -ge 80 ]]; then
        echo ""
        echo -e "${YELLOW}ℹ Storage Notice:${NC} Using ${usage_percent}% of ${storage_limit} quota."
        echo "  Run 'quota-check' for details."
        echo ""
    fi
}

# Export functions
export -f show_contact_info show_limit_error show_bare_metal_warning show_quota_warning
