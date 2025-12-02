#!/bin/bash
# /opt/ds01-infra/scripts/lib/ds01-context.sh
# DS01 Context Detection Library
#
# Provides functions for conditional output based on invocation context.
#
# Usage in scripts:
#   source /opt/ds01-infra/scripts/lib/ds01-context.sh
#
#   # Show output only in atomic context
#   if is_atomic_context; then
#       echo "Next steps:"
#       echo "  container-start $name"
#   fi
#
# Environment Variables:
#   DS01_CONTEXT: "orchestration" | "atomic" (default: "atomic")
#   DS01_INTERFACE: Label to apply to created containers
#

# Context constants
DS01_CONTEXT_ORCHESTRATION="orchestration"
DS01_CONTEXT_ATOMIC="atomic"

# Default context is atomic (direct invocation)
DS01_CONTEXT="${DS01_CONTEXT:-atomic}"

# Get current context
get_ds01_context() {
    echo "${DS01_CONTEXT:-atomic}"
}

# Check if running in orchestration context
# Returns: 0 if orchestration, 1 if not
is_orchestration_context() {
    [[ "$(get_ds01_context)" == "$DS01_CONTEXT_ORCHESTRATION" ]]
}

# Check if running in atomic context (direct invocation)
# Returns: 0 if atomic, 1 if not
is_atomic_context() {
    [[ "$(get_ds01_context)" == "$DS01_CONTEXT_ATOMIC" ]]
}

# Set context to orchestration (for use by orchestrator scripts)
set_orchestration_context() {
    export DS01_CONTEXT="$DS01_CONTEXT_ORCHESTRATION"
    export DS01_INTERFACE="$DS01_CONTEXT_ORCHESTRATION"
}

# Set context to atomic (for use by atomic scripts)
set_atomic_context() {
    export DS01_CONTEXT="$DS01_CONTEXT_ATOMIC"
    export DS01_INTERFACE="$DS01_CONTEXT_ATOMIC"
}

# Get interface label for container creation
get_interface_label() {
    echo "${DS01_INTERFACE:-${DS01_CONTEXT:-atomic}}"
}

# Show banner only in atomic context (not when called from orchestrator)
# Usage: show_atomic_banner "Container Create"
# Returns: 0 if banner shown, 1 if suppressed (for conditional logic)
show_atomic_banner() {
    local title="$1"
    if is_atomic_context && [[ -z "$DS01_ORCHESTRATOR" ]]; then
        echo -e ""
        echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1m${title}\033[0m"
        echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e ""
        return 0
    fi
    return 1
}

# Show next steps message - only in atomic context
# Usage: show_atomic_next_steps "container-start $name" "container-remove $name"
show_atomic_next_steps() {
    if is_atomic_context; then
        echo -e "\n\033[0;34mNext steps:\033[0m"
        for step in "$@"; do
            echo "  $step"
        done
    fi
}

# Show success message - always shown but format varies
# Usage: show_success "Container created" "my-container"
show_success() {
    local message="$1"
    local detail="${2:-}"

    if is_orchestration_context; then
        # Minimal output for orchestration
        : # Silent - orchestrator handles output
    else
        # Full output for atomic
        echo -e "\033[0;32m[SUCCESS]\033[0m $message${detail:+ ($detail)}"
    fi
}

# Show warning - always shown
# Usage: show_warning "Resource limit reached"
show_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

# Show error - always shown
# Usage: show_error "Container creation failed"
show_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Show info - only in atomic context
# Usage: show_info "Loading configuration..."
show_info() {
    if is_atomic_context; then
        echo -e "\033[0;34m[INFO]\033[0m $1"
    fi
}

# Show debug - only if verbose
# Usage: DS01_VERBOSE=1 show_debug "Checking GPU availability"
show_debug() {
    if [[ "${DS01_VERBOSE:-0}" == "1" ]]; then
        echo -e "\033[0;90m[DEBUG]\033[0m $1"
    fi
}

# Suppress output in orchestration context
# Usage: suppress_in_orchestration echo "This won't show in orchestration"
suppress_in_orchestration() {
    if is_atomic_context; then
        "$@"
    fi
}

# Run command and capture output, show only on error
# Usage: run_quiet docker pull image:tag
run_quiet() {
    local output
    output=$("$@" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "$output" >&2
    fi

    return $exit_code
}

# Export functions for subshells
export -f get_ds01_context is_orchestration_context is_atomic_context
export -f set_orchestration_context set_atomic_context get_interface_label
export -f show_atomic_banner show_atomic_next_steps show_success show_warning show_error show_info show_debug
export -f suppress_in_orchestration run_quiet
