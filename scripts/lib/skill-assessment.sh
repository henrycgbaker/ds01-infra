#!/bin/bash
# DS01 Skill Assessment Library
# Provides adaptive UI based on user experience levels
# File: /opt/ds01-infra/scripts/lib/skill-assessment.sh

# Skill levels: 0=beginner (unchecked), 2=expert (checked)
export DS01_SKILL_REMOTE=0   # Remote servers (SSH + VS Code)
export DS01_SKILL_GIT=0      # Version control (Git)
export DS01_SKILL_HPC=0      # Containerized ML/HPC (Docker + GPUs + resources)

# Colors (may already be defined by calling script)
_SA_GREEN=${GREEN:-'\033[0;32m'}
_SA_RED=${RED:-'\033[0;31m'}
_SA_YELLOW=${YELLOW:-'\033[1;33m'}
_SA_CYAN=${CYAN:-'\033[0;36m'}
_SA_BOLD=${BOLD:-'\033[1m'}
_SA_DIM=${DIM:-'\033[2m'}
_SA_NC=${NC:-'\033[0m'}

# Skill area descriptions
SKILL_LABELS=(
    "Remote servers (SSH, VS Code Remote)"
    "Version control (Git)"
    "Containerized ML/HPC (Docker, GPUs, resources)"
)

SKILL_VARS=(
    "DS01_SKILL_REMOTE"
    "DS01_SKILL_GIT"
    "DS01_SKILL_HPC"
)

# Interactive skill selector with y/n for each area
ask_skill_levels() {
    echo -e "${_SA_BOLD}Quick Experience Check${_SA_NC}"
    echo -e "${_SA_DIM}We'll tailor the setup based on your experience.${_SA_NC}"
    echo ""

    export DS01_SKILL_REMOTE=0
    export DS01_SKILL_GIT=0
    export DS01_SKILL_HPC=0

    # Ask about each skill area
    echo -ne "  [ ] Remote servers (SSH, VS Code Remote) - comfortable? [y/N]: "
    read -r answer </dev/tty
    if [[ "$answer" =~ ^[Yy] ]]; then
        export DS01_SKILL_REMOTE=2
        # Move up and rewrite with checkmark
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_GREEN}[✓] Remote servers (SSH, VS Code Remote)${_SA_NC}"
    else
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_RED}[✗] Remote servers (SSH, VS Code Remote)${_SA_NC}"
    fi

    echo -ne "  [ ] Version control (Git) - comfortable? [y/N]: "
    read -r answer </dev/tty
    if [[ "$answer" =~ ^[Yy] ]]; then
        export DS01_SKILL_GIT=2
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_GREEN}[✓] Version control (Git)${_SA_NC}"
    else
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_RED}[✗] Version control (Git)${_SA_NC}"
    fi

    echo -ne "  [ ] Containerized ML/HPC (Docker, GPUs) - comfortable? [y/N]: "
    read -r answer </dev/tty
    if [[ "$answer" =~ ^[Yy] ]]; then
        export DS01_SKILL_HPC=2
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_GREEN}[✓] Containerized ML/HPC (Docker, GPUs)${_SA_NC}"
    else
        echo -ne "\033[1A\033[2K"
        echo -e "  ${_SA_RED}[✗] Containerized ML/HPC (Docker, GPUs)${_SA_NC}"
    fi

    echo ""
}

# Check if user needs guidance for a skill area
# Usage: if needs_guidance "DS01_SKILL_REMOTE"; then ... fi
needs_guidance() {
    local skill_var="$1"
    local skill_value="${!skill_var}"
    [[ "$skill_value" -eq 0 ]]
}

# Check if user is expert in a skill area
# Usage: if is_expert "DS01_SKILL_GIT"; then ... fi
is_expert() {
    local skill_var="$1"
    local skill_value="${!skill_var}"
    [[ "$skill_value" -eq 2 ]]
}

# Show a chunked explanation with pause (for beginners)
# Usage: show_explanation "Title" "Explanation text"
show_explanation() {
    local title="$1"
    local text="$2"

    echo ""
    echo -e "${_SA_BOLD}${title}${_SA_NC}"
    echo -e "${text}"
    echo ""
    read -p "Press Enter to continue..." </dev/tty
}

# Show a brief note (for intermediate users)
# Usage: show_brief "Brief explanation"
show_brief() {
    local text="$1"
    echo -e "${_SA_DIM}${text}${_SA_NC}"
}

# Adaptive explanation - shows appropriate detail based on skill
# Usage: adaptive_explain "DS01_SKILL_REMOTE" "Title" "Full explanation" "Brief note"
adaptive_explain() {
    local skill_var="$1"
    local title="$2"
    local full_text="$3"
    local brief_text="$4"

    if needs_guidance "$skill_var"; then
        show_explanation "$title" "$full_text"
    elif [ -n "$brief_text" ]; then
        show_brief "$brief_text"
    fi
    # Experts get no explanation
}
