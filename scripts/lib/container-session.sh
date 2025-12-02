#!/bin/bash
# DS01 Container Session - Unified handler for start/run/attach
# L2 Atomic Commands via symlinks:
#   container-start  -> start container in background
#   container-run    -> start if needed + attach + retire prompt
#   container-attach -> attach to running container + retire prompt
#
# Mode determined by $(basename $0)

set -e

# === PATHS ===
INFRA_ROOT="/opt/ds01-infra"
SCRIPT_DIR="$INFRA_ROOT/scripts"
MLC_OPEN="$INFRA_ROOT/aime-ml-containers/mlc-open"
MLC_START="$INFRA_ROOT/aime-ml-containers/mlc-start"
RESOURCE_PARSER="$SCRIPT_DIR/docker/get_resource_limits.py"

# === SOURCE LIBRARIES ===
if [[ -f "$SCRIPT_DIR/lib/ds01-context.sh" ]]; then
    source "$SCRIPT_DIR/lib/ds01-context.sh"
fi

if [[ -f "$SCRIPT_DIR/lib/interactive-select.sh" ]]; then
    source "$SCRIPT_DIR/lib/interactive-select.sh"
elif [[ -f "/usr/local/lib/interactive-select.sh" ]]; then
    source /usr/local/lib/interactive-select.sh
fi

# === COLORS ===
BLUE='\033[94m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# === USER INFO ===
USERNAME=$(whoami)
USER_ID=$(id -u)

# === MODE DETECTION ===
SCRIPT_NAME=$(basename "$0")
case "$SCRIPT_NAME" in
    container-start)   MODE="start" ;;
    container-run)     MODE="run" ;;
    container-attach)  MODE="attach" ;;
    container-session) MODE="${MODE:-run}" ;;
    *)                 MODE="run" ;;
esac

# === SHARED FUNCTIONS ===

get_user_lifecycle_limits() {
    local username="$1"
    if [[ ! -f "$RESOURCE_PARSER" ]]; then
        echo "None|None|None"
        return
    fi
    local idle_timeout=$(python3 "$RESOURCE_PARSER" "$username" --idle-timeout 2>/dev/null || echo "None")
    local max_runtime=$(python3 "$RESOURCE_PARSER" "$username" --max-runtime 2>/dev/null || echo "None")
    local gpu_hold=$(python3 "$RESOURCE_PARSER" "$username" --gpu-hold-time 2>/dev/null || echo "None")
    echo "${idle_timeout}|${max_runtime}|${gpu_hold}"
}

container_exists() {
    local name="$1"
    local tag="${name}._.${USER_ID}"
    docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${tag}$"
}

container_is_running() {
    local name="$1"
    local tag="${name}._.${USER_ID}"
    docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${tag}$"
}

container_is_paused() {
    local name="$1"
    local tag="${name}._.${USER_ID}"
    local status=$(docker inspect -f '{{.State.Status}}' "$tag" 2>/dev/null || echo "")
    [[ "$status" == "paused" ]]
}

validate_gpu_available() {
    local name="$1"
    local tag="${name}._.${USER_ID}"
    local metadata_file="/var/lib/ds01/container-metadata/${tag}.json"

    if [[ -f "$metadata_file" ]]; then
        local allocated_gpu=$(grep -o '"allocated_gpu": *"[^"]*"' "$metadata_file" 2>/dev/null | cut -d'"' -f4)
        if [[ -n "$allocated_gpu" && "$allocated_gpu" != "null" ]]; then
            local gpu_id
            if [[ "$allocated_gpu" == *":"* ]]; then
                gpu_id=$(echo "$allocated_gpu" | cut -d':' -f1)
            else
                gpu_id="$allocated_gpu"
            fi
            if ! nvidia-smi -i "$gpu_id" &>/dev/null; then
                echo -e "${RED}GPU $allocated_gpu is no longer available${NC}"
                echo ""
                echo -e "Recreate container: ${GREEN}container-remove $name && container-create $name${NC}"
                echo -e "Workspace files are safe in: ${DIM}~/workspace/$name/${NC}"
                return 1
            fi
        fi
    fi
    return 0
}

start_container_impl() {
    local name="$1"
    local tag="${name}._.${USER_ID}"

    # Handle paused containers
    if container_is_paused "$name"; then
        echo -e "${YELLOW}Container is paused. Unpausing...${NC}"
        if docker unpause "$tag" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Container unpaused"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to unpause container"
            return 1
        fi
    fi

    # Start container
    echo -e "${CYAN}Starting container...${NC}"
    if [[ -f "$MLC_START" ]]; then
        if bash "$MLC_START" "$name" -s >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Container started"
            return 0
        fi
    fi
    # Fallback to docker start
    if docker start "$tag" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Container started"
        return 0
    fi
    echo -e "${RED}✗${NC} Failed to start container"
    return 1
}

attach_to_container() {
    local name="$1"
    local tag="${name}._.${USER_ID}"

    # Start keep-alive process to prevent auto-stop while user is attached
    if docker ps --format "{{.Names}}" | grep -q "^${tag}$"; then
        docker exec -d "$tag" bash -c 'exec -a "[ds01-keep-alive]" sleep infinity' 2>/dev/null || true
    fi

    # Attach via mlc-open or docker exec
    if [[ -f "$MLC_OPEN" && -x "$MLC_OPEN" ]]; then
        if [[ -n "$DS01_ORCHESTRATOR" ]]; then
            bash "$MLC_OPEN" "$name" 2>/dev/null
        else
            bash "$MLC_OPEN" "$name"
        fi
    else
        docker exec -it "$tag" /bin/bash
    fi

    # Clean up keep-alive
    docker exec "$tag" pkill -f "\[ds01-keep-alive\]" 2>/dev/null || true
}

show_post_exit_menu() {
    local name="$1"
    local tag="${name}._.${USER_ID}"

    # Skip if called from orchestrator
    if [[ -n "$DS01_ORCHESTRATOR" ]]; then
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Container Session Ended${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local status=$(docker inspect -f '{{.State.Status}}' "$tag" 2>/dev/null || echo "missing")

    if [[ "$status" == "running" ]]; then
        echo -e "${GREEN}✓${NC} Container is still running with resources allocated"
        echo ""

        IFS='|' read -r idle_timeout max_runtime gpu_hold <<< "$(get_user_lifecycle_limits "$USERNAME")"

        echo -e "${BOLD}What would you like to do?${NC}"
        echo ""
        echo -e "${CYAN}1)${NC} ${BOLD}Keep running${NC} (exit session, container stays active)"
        echo "   - You can reconnect anytime"
        echo "   - GPU remains allocated to this container"
        if [[ "$idle_timeout" != "None" && "$idle_timeout" != "null" ]]; then
            echo -e "   - Will auto-stop after ${CYAN}$idle_timeout${NC} of GPU inactivity"
        fi
        if [[ "$max_runtime" != "None" && "$max_runtime" != "null" ]]; then
            echo -e "   - Max runtime: ${CYAN}$max_runtime${NC}"
        fi
        echo ""
        echo -e "${CYAN}2)${NC} ${BOLD}Retire container${NC} (stop + remove, free GPU immediately)"
        echo "   - Removes container instance"
        echo "   - GPU freed immediately for others"
        echo "   - Workspace files remain safe"
        echo -e "   - Can recreate anytime with: ${GREEN}container-deploy $name${NC}"
        echo ""

        read -p "Choose [1=keep, 2=retire] (default: 1): " CHOICE </dev/tty
        CHOICE=${CHOICE:-1}

        case "$CHOICE" in
            1)
                echo ""
                echo -e "${GREEN}✓${NC} Container kept running"
                echo ""
                echo -e "${BOLD}Next steps:${NC}"
                echo -e "  Reconnect: ${GREEN}container-run $name${NC}"
                echo -e "  Status:    ${GREEN}container-list${NC}"
                echo ""
                if [[ "$max_runtime" != "None" && "$max_runtime" != "null" ]]; then
                    echo -e "${CYAN}i${NC} ${DIM}Container will auto-retire at max runtime (${max_runtime})${NC}"
                    echo ""
                fi
                echo -e "${YELLOW}Tip:${NC} When done, ${GREEN}container-retire $name${NC} (frees GPU)"
                echo ""
                ;;
            2)
                echo ""
                echo -e "${YELLOW}Retiring container...${NC}"
                echo ""
                docker exec "$tag" pkill -f "\[ds01-keep-alive\]" 2>/dev/null || true
                if [[ -f "$SCRIPT_DIR/user/container-retire" ]]; then
                    bash "$SCRIPT_DIR/user/container-retire" "$name" --skip-initial-confirm
                else
                    echo -e "${RED}✗${NC} container-retire not found"
                    echo "Manual cleanup: ${GREEN}container-retire $name${NC}"
                fi
                ;;
            *)
                echo ""
                echo -e "${YELLOW}Invalid choice. Keeping container running.${NC}"
                echo -e "To retire later: ${GREEN}container-retire $name${NC}"
                echo ""
                ;;
        esac
    else
        echo -e "${YELLOW}Container was stopped${NC}"
        echo ""
        echo -e "${BOLD}Retiring to avoid ambiguous stopped state...${NC}"
        echo ""
        if [[ -f "$SCRIPT_DIR/user/container-retire" ]]; then
            bash "$SCRIPT_DIR/user/container-retire" "$name" --skip-initial-confirm
        fi
    fi
}

show_start_success_message() {
    local name="$1"

    # Skip if called from orchestrator
    if [[ -n "$DS01_ORCHESTRATOR" ]]; then
        return 0
    fi

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}    ✓ Container Started${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    IFS='|' read -r idle_timeout max_runtime gpu_hold <<< "$(get_user_lifecycle_limits "$USERNAME")"

    echo -e "${CYAN}i${NC} ${BOLD}Your resource limits:${NC}"
    if [[ "$max_runtime" != "None" && "$max_runtime" != "null" ]]; then
        echo -e "  - Max runtime: ${CYAN}$max_runtime${NC}"
    fi
    if [[ "$idle_timeout" != "None" && "$idle_timeout" != "null" ]]; then
        echo -e "  - Idle timeout: ${CYAN}$idle_timeout${NC} ${DIM}(auto-stop after GPU idle)${NC}"
    fi
    if [[ "$gpu_hold" != "None" && "$gpu_hold" != "null" && "$gpu_hold" != "indefinite" ]]; then
        echo -e "  - GPU hold after stop: ${CYAN}$gpu_hold${NC}"
    fi
    echo ""

    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "  Enter container: ${GREEN}container-run $name${NC}"
    echo -e "  View status:     ${GREEN}container-list${NC}"
    echo -e "  Stop container:  ${GREEN}container-stop $name${NC}"
    echo ""
}

usage() {
    local mode_desc=""
    local examples=""

    case "$MODE" in
        start)
            mode_desc="Start a stopped container in the background"
            examples="  container-start my-project           # Start in background
  container-start my-project --guided  # With explanations"
            ;;
        run)
            mode_desc="Start (if needed) and attach to a container"
            examples="  container-run my-project             # Start and attach
  container-run my-project --guided    # With explanations"
            ;;
        attach)
            mode_desc="Attach to an already running container"
            examples="  container-attach my-project          # Attach to running container
  container-attach my-project --guided # With explanations"
            ;;
    esac

    echo ""
    echo -e "${BOLD}DS01 Container ${MODE^}${NC}"
    echo -e "${DIM}L2 Atomic Command - For granular control. Most users should use: container-deploy${NC}"
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo "  container-$MODE [name] [options]"
    echo "  container-$MODE                   # Interactive selection"
    echo ""
    echo -e "${CYAN}Description:${NC}"
    echo "  $mode_desc"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo "  --guided          Show detailed explanations for beginners"
    echo "  -h, --help        Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "$examples"
    echo ""
    echo -e "${DIM}Run 'help --atomic' to see all atomic container commands.${NC}"
    echo ""
}

# === ARGUMENT PARSING ===
CONTAINER_NAME=""
GUIDED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --guided)
            GUIDED=true
            shift
            ;;
        -h|--help|--info)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$CONTAINER_NAME" ]]; then
                CONTAINER_NAME="$1"
            else
                echo -e "${RED}Too many arguments${NC}"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# === HEADER (only in atomic context) ===
if is_atomic_context && [[ -z "$DS01_ORCHESTRATOR" ]]; then
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Container ${MODE^}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e ""
fi

# === GUIDED INTRO ===
if [[ "$GUIDED" == true && -z "$CONTAINER_NAME" ]]; then
    case "$MODE" in
        start)
            echo -e "${CYAN}i${NC} ${BOLD}What does 'start' mean?${NC}"
            echo "  Starts a stopped container in the background."
            echo "  Container will be running but you won't be attached to it."
            echo -e "  To enter: ${GREEN}container-run <name>${NC}"
            echo ""
            ;;
        run)
            echo -e "${CYAN}i${NC} ${BOLD}What does 'run' mean?${NC}"
            echo "  Starts the container (if stopped) and opens a terminal inside."
            echo "  When you exit, you can choose to keep it running or retire it."
            echo ""
            ;;
        attach)
            echo -e "${CYAN}i${NC} ${BOLD}What does 'attach' mean?${NC}"
            echo "  Connects you to an already running container."
            echo "  When you exit, you can choose to keep it running or retire it."
            echo ""
            ;;
    esac
    read -p "Press Enter to continue..." </dev/tty
    echo ""
fi

# === CONTAINER SELECTION ===
if [[ -z "$CONTAINER_NAME" ]]; then
    case "$MODE" in
        start)
            CONTAINER_NAME=$(select_container "stopped")
            ;;
        attach)
            CONTAINER_NAME=$(select_container "running")
            ;;
        run)
            CONTAINER_NAME=$(select_container)
            ;;
    esac

    if [[ -z "$CONTAINER_NAME" ]]; then
        echo "No selection made. Exiting."
        exit 0
    fi
    echo ""
fi

CONTAINER_TAG="${CONTAINER_NAME}._.${USER_ID}"

# === VALIDATION ===
if ! container_exists "$CONTAINER_NAME"; then
    echo -e "${RED}Container '$CONTAINER_NAME' does not exist${NC}"
    echo ""
    echo -e "Create it first: ${GREEN}container-create $CONTAINER_NAME${NC}"
    echo -e "Or list containers: ${GREEN}container-list${NC}"
    exit 1
fi

# === MODE-SPECIFIC LOGIC ===
case "$MODE" in
    start)
        if container_is_running "$CONTAINER_NAME"; then
            echo -e "${YELLOW}Container '$CONTAINER_NAME' is already running${NC}"
            echo ""
            echo -e "Enter it: ${GREEN}container-run $CONTAINER_NAME${NC}"
            exit 0
        fi

        if ! validate_gpu_available "$CONTAINER_NAME"; then
            exit 1
        fi

        if start_container_impl "$CONTAINER_NAME"; then
            show_start_success_message "$CONTAINER_NAME"
        else
            exit 1
        fi
        ;;

    attach)
        if ! container_is_running "$CONTAINER_NAME"; then
            local status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_TAG" 2>/dev/null || echo "unknown")
            echo -e "${YELLOW}Container '$CONTAINER_NAME' is not running${NC} (status: $status)"
            echo ""
            echo -e "Start and attach: ${GREEN}container-run $CONTAINER_NAME${NC}"
            echo -e "Start in background: ${GREEN}container-start $CONTAINER_NAME${NC}"
            exit 1
        fi

        echo -e "${CYAN}Attaching to container '$CONTAINER_NAME'...${NC}"
        echo ""
        attach_to_container "$CONTAINER_NAME"
        show_post_exit_menu "$CONTAINER_NAME"
        ;;

    run)
        if ! validate_gpu_available "$CONTAINER_NAME"; then
            exit 1
        fi

        if ! container_is_running "$CONTAINER_NAME"; then
            if ! start_container_impl "$CONTAINER_NAME"; then
                exit 1
            fi
        fi

        echo -e "${CYAN}Opening container '$CONTAINER_NAME'...${NC}"
        echo ""
        attach_to_container "$CONTAINER_NAME"
        show_post_exit_menu "$CONTAINER_NAME"
        ;;
esac
