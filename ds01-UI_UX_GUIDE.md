# DS01 UI/UX Guide

Comprehensive design philosophy and guidelines for consistent, user-friendly CLI design across DS01 commands.

**Purpose:** Enforce consistency and good design practice across all DS01 CLI commands.

**Audience:** Developers writing or modifying DS01 scripts.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Architecture Patterns](#architecture-patterns)
3. [Color Scheme](#color-scheme)
4. [Typography & Layout](#typography--layout)
5. [Banners & Headers](#banners--headers)
6. [Progress & Background Output](#progress--background-output)
7. [Interactive Prompts](#interactive-prompts)
8. [Messages & Notifications](#messages--notifications)
9. [Interface Isolation](#interface-isolation)
10. [Help System](#help-system)
11. [Code Standards](#code-standards)
12. [Common Patterns](#common-patterns)
13. [Anti-Patterns](#anti-patterns)
14. [Quick Reference](#quick-reference)

---

## Design Philosophy

### Core Principles

1. **Compact but Uncluttered** - Terminal space is precious. Avoid excessive blank lines while maintaining readability.

2. **Digestible for Beginners** - Our users are new to terminals, remote servers, and containers. Break up information with clear sections and pauses.

3. **Show the Work** - When complex processes run (builds, deployments), show underlying output so users see what's happening. Dim it to signal "behind the scenes."

4. **One Banner Per Command** - Orchestrators calling subcommands should NOT produce duplicate banners.

5. **Modular, Non-Repetitive** - Avoid conditional paths that output redundant messages (e.g., "Created!" then "Successfully created!").

6. **Interface Isolation** - Users entering at one level (orchestrator vs atomic) should only see references to commands at that level.

---

## Architecture Patterns

### Command Structure

All commands follow the dispatcher pattern:

```bash
command subcommand [args] [--options]
command                     # Interactive wizard mode
command --help              # Concise help
command --info              # Verbose help with explanations
command subcommand --help   # Subcommand-specific help
```

### Aliasing Requirements

Every command MUST be accessible via both formats:
- Space-separated: `container deploy`
- Hyphenated: `container-deploy`

### Dispatcher Implementation

```bash
# scripts/user/container-dispatcher.sh
case "$1" in
    deploy)  shift; exec "$SCRIPT_DIR/container-deploy" "$@" ;;
    retire)  shift; exec "$SCRIPT_DIR/container-retire" "$@" ;;
    list)    shift; exec "$SCRIPT_DIR/container-list" "$@" ;;
    help|--help|-h) show_help ;;
    "")      show_interactive_menu ;;  # No args = interactive
    *)       error "Unknown subcommand: $1" ;;
esac
```

### Layer Rules

| Layer | Type | Can Call | Called By |
|-------|------|----------|-----------|
| L4 | Wizards | L3, L2 | User only |
| L3 | Orchestrators | L2 | User, L4 |
| L2 | Atomic | Docker/MLC only | User, L3, L4 |

**Critical:** L2 Atomic commands are isolated - they cannot call each other.

---

## Color Scheme

### Standard Colors

```bash
# Define at script top - use these exact values
GREEN='\033[0;32m'      # Success, commands, positive actions
YELLOW='\033[1;33m'     # Warnings, cautions, notices
RED='\033[0;31m'        # Errors, failures
CYAN='\033[0;36m'       # Headers, dividers, info labels, paths
BLUE='\033[0;34m'       # Secondary info, next steps
BOLD='\033[1m'          # Emphasis, important text, headings
DIM='\033[2m'           # Background info, hints, behind-the-scenes
NC='\033[0m'            # Reset (No Color)
```

### Semantic Usage

| Color | Use For | Example |
|-------|---------|---------|
| `GREEN` | Success states, command suggestions | `✓ Container created`, `container-deploy` |
| `YELLOW` | Warnings, notices, tips | `⚠ GPU at 80% capacity`, `💡 Tip:` |
| `RED` | Errors, failures | `✗ Build failed`, `Error: Invalid option` |
| `CYAN` | Headers, dividers, paths, info | `━━━━━`, `~/workspace/`, `ℹ` |
| `BOLD` | Section titles, emphasis | `Step 1/3:`, `What would you like to do?` |
| `DIM` | Background output, hints | `(uses container-create internally)` |

### Symbols & Icons

Use limited emoji + ASCII for status:

```bash
# Status symbols (ASCII preferred)
SUCCESS="✓"    # or ✔
FAILURE="✗"    # or ✘
WARNING="⚠"
INFO="ℹ"

# Selective emoji (use sparingly)
TIP="💡"       # Tips and hints only
FOLDER="📁"    # File/directory references (optional)

# Progress indicators (ASCII)
BULLET="•"
ARROW="→"
```

**Rule:** Don't mix styles - pick one and stick with it per script.

---

## Typography & Layout

### Divider Standard

Use **46 characters** for all dividers:

```bash
# Standard divider (46 chars)
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Section sub-divider (shorter, 30 chars)
echo -e "${CYAN}━━━ Section Name ━━━${NC}"
```

### Whitespace Rules

1. **One blank line** between major sections
2. **No trailing blank lines** at end of output
3. **No double blank lines** ever
4. **Single blank line** after banner, before content

```bash
# GOOD
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Header${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Content here..."

# BAD - too much whitespace
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}Header${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo ""
echo -e "Content here..."
```

### Indentation

```bash
# Top-level content: no indent
echo -e "Main content"

# Sub-items: 2 spaces
echo -e "  ${GREEN}•${NC} First item"
echo -e "  ${GREEN}•${NC} Second item"

# Nested details: 4 spaces
echo -e "    ${DIM}Additional detail${NC}"

# Command examples: 2 spaces, command in green
echo -e "  ${GREEN}container-deploy my-project${NC}"
```

### Bullet Lists

Use bullet lists liberally - they break up information into easily digestible chunks:

```bash
# GOOD - scannable bullet list
echo -e "${BOLD}What this does:${NC}"
echo -e "  • Creates a container from your image"
echo -e "  • Allocates GPU resources"
echo -e "  • Mounts your workspace directory"
echo -e "  • Applies resource limits"

# BAD - wall of text
echo "This creates a container from your image, allocates GPU resources, mounts your workspace directory, and applies resource limits."
```

**When to use bullets:**
- Listing features, steps, or options
- Explaining what a command does
- Showing "what just happened" summaries
- Presenting choices before a prompt

---

## Banners & Headers

### Top-Level Command Banner (Boxed)

Use for main entry point of L3/L4 commands:

```bash
show_banner() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}DS01 Container Deploy${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}
```

### Section Headers

```bash
# Major step
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 1/3: Creating Container${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Minor section
echo -e "${CYAN}━━━ Configuring GPU Access ━━━${NC}"
```

### Context-Aware Banners

Subcommands called from orchestrators should NOT show banners:

```bash
# In atomic command (e.g., container-create)
if is_atomic_context && [[ -z "$DS01_ORCHESTRATOR" ]]; then
    show_banner
fi
```

---

## Progress & Background Output

### Long-Running Operations

When showing Docker builds, container creation, etc.:

```bash
echo -e "${CYAN}Building image...${NC}"
echo -e "${DIM}────────────────────────────────────────────────${NC}"

# Run with output visible but dimmed
docker build ... 2>&1 | while IFS= read -r line; do
    echo -e "${DIM}  $line${NC}"
done

echo -e "${DIM}────────────────────────────────────────────────${NC}"
```

### Milestone Markers

Insert milestone markers in long output:

```bash
echo -e "${DIM}  [Step 1/4] Downloading base image...${NC}"
# ... docker output ...
echo -e "${DIM}  [Step 2/4] Installing system packages...${NC}"
# ... more output ...
echo -e "${GREEN}  ✓ Build complete${NC}"
```

### Spinner Pattern (if implementing)

```bash
spinner() {
    local pid=$1
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}${spin:i++%${#spin}:1}${NC} Working..."
        sleep 0.1
    done
    printf "\r"
}

# Usage
long_command &
spinner $!
```

---

## Interactive Prompts

### Stdin Flushing

**ALWAYS** flush stdin before prompts to clear buffered input:

```bash
# Flush pattern - use before every read
read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true
read -p "Your choice: " CHOICE </dev/tty
```

### Press Enter to Continue

Use at section breaks and after dense information:

```bash
# After information-heavy sections
echo -e "  [detailed explanation here]"
echo ""
read -p "Press Enter to continue..." </dev/tty
echo ""
```

### Yes/No Prompts

```bash
# With default (shown in brackets, capital = default)
read -p "Continue? [Y/n]: " CONFIRM </dev/tty
CONFIRM=${CONFIRM:-Y}

# Require explicit answer (no default)
while true; do
    read -p "Delete container? (yes/no): " CONFIRM </dev/tty
    case "$CONFIRM" in
        yes|Yes|YES) break ;;
        no|No|NO) exit 0 ;;
        *) echo "Please enter 'yes' or 'no'" ;;
    esac
done
```

### Selection Menus

```bash
echo -e "${BOLD}Select an option:${NC}"
echo ""
echo -e "  ${CYAN}1)${NC} ${BOLD}First option${NC}"
echo -e "     ${DIM}Description of what this does${NC}"
echo ""
echo -e "  ${CYAN}2)${NC} ${BOLD}Second option${NC}"
echo -e "     ${DIM}Description of what this does${NC}"
echo ""

read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true
read -p "Choice [1-2, default: 1]: " CHOICE </dev/tty
CHOICE=${CHOICE:-1}
```

---

## Messages & Notifications

### Success Messages

```bash
# Final success (end of command)
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}✓ Container Deployed Successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Inline success (during process)
echo -e "${GREEN}✓${NC} Image built"
```

### Error Messages

```bash
# Fatal error
echo -e "${RED}✗ Container creation failed${NC}"
echo ""
echo -e "  ${BOLD}Reason:${NC} GPU limit reached (2/2)"
echo ""
echo -e "  ${BOLD}To fix:${NC}"
echo -e "    ${GREEN}container-retire <old-container>${NC}"
echo ""

# Use error library for resource errors
source /opt/ds01-infra/scripts/lib/error-messages.sh
show_limit_error "$error_code" "$username"
```

### Warnings

```bash
echo -e "${YELLOW}⚠${NC} Container will auto-stop after 2h of inactivity"
```

### Tips (Use Sparingly)

```bash
echo -e "${YELLOW}💡 Tip:${NC} Run ${GREEN}container-retire${NC} when done to free GPU"
```

### Avoiding Bloat

**DON'T** output redundant messages from conditional paths:

```bash
# BAD - redundant
if [ "$created" = true ]; then
    echo -e "${GREEN}✓${NC} Image created"
fi
echo -e "${GREEN}✓ Image successfully created!${NC}"  # Always runs = redundant

# GOOD - single message
if [ "$created" = true ]; then
    echo -e "${GREEN}✓${NC} Image created: $IMAGE_NAME"
fi
```

---

## Interface Isolation

### The Three Interfaces

1. **Orchestrator Interface (Default)**: `container deploy`, `container retire`
2. **Atomic Interface (Advanced)**: `container-create`, `container-start`, etc.
3. **Docker Interface**: Direct docker commands

### Strict Isolation Rules

When user enters via orchestrator commands, they should NEVER see atomic command references:

```bash
# In container-deploy (orchestrator)
echo -e "${BOLD}Next steps:${NC}"
echo -e "  ${GREEN}container-retire $name${NC}"     # Orchestrator command
# NOT: container-stop, container-remove

# In container-create (atomic) - when called directly
if is_atomic_context; then
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "  ${GREEN}container-start $name${NC}"  # Atomic command
fi
```

### Context Detection

```bash
source /opt/ds01-infra/scripts/lib/ds01-context.sh

# Orchestrators set context before calling atomic commands
export DS01_CONTEXT="orchestration"
export DS01_ORCHESTRATOR="deploy"

# Atomic commands check context
if is_atomic_context && [[ -z "$DS01_ORCHESTRATOR" ]]; then
    # Show full output (called directly by user)
    show_next_steps
fi
```

---

## Help System

### Two Help Modes

| Flag | Purpose | Content |
|------|---------|---------|
| `--help`, `-h` | Concise reference | Usage, options, examples |
| `--info` | Verbose explanation | Concepts, detailed descriptions |

### Help Structure

```bash
usage() {
    echo ""
    echo -e "${BOLD}DS01 Container Deploy${NC}"
    echo -e "${DIM}L3 Orchestrator - Creates and starts containers in one command${NC}"
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo "  container-deploy [name] [options]"
    echo "  container-deploy                    # Interactive wizard"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo "  --guided          Show detailed explanations"
    echo "  --background      Start without attaching"
    echo "  -h, --help        Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  ${DIM}# Interactive mode${NC}"
    echo "  container-deploy"
    echo ""
    echo -e "  ${DIM}# Quick deploy${NC}"
    echo "  container-deploy my-project"
    echo ""
}
```

### Guided Mode

Triggered by `--guided` flag. Adds explanations and pauses for beginners.

**Key Principle: Explain BEFORE the choice**

In `--guided` mode, always explain what will happen BEFORE presenting the choice:

```
1. EXPLAIN  → What this step does and why
2. PAUSE    → "Press Enter to continue..."
3. CHOOSE   → User makes selection
4. PROCESS  → Action happens (show progress)
5. CONFIRM  → Brief message of what was done
```

**Guided Mode Example:**

```bash
if [ "$GUIDED" = true ]; then
    # 1. EXPLAIN - what will happen
    echo -e "${CYAN}ℹ${NC} ${BOLD}What is a container?${NC}"
    echo ""
    echo "  A container is like a separate computer that you can"
    echo "  create, use, and throw away. Your files in ~/workspace"
    echo "  are always safe - they exist outside the container."
    echo ""
    echo "  Next, you'll choose which framework to use (PyTorch, etc.)"
    echo ""

    # 2. PAUSE
    read -p "Press Enter to continue..." </dev/tty
    echo ""
fi

# 3. CHOOSE - present options
echo -e "${BOLD}Select framework:${NC}"
echo -e "  1) PyTorch"
echo -e "  2) TensorFlow"
read -p "Choice [1-2]: " CHOICE

# 4. PROCESS - action happens
echo -e "${DIM}Installing PyTorch...${NC}"

# 5. CONFIRM - what was done
echo -e "${GREEN}✓${NC} PyTorch installed"

if [ "$GUIDED" = true ]; then
    echo ""
    echo -e "${BOLD}What Just Happened?${NC}"
    echo "  • Downloaded PyTorch base image"
    echo "  • Configured GPU support"
    echo "  • Set up Python environment"
fi
```

**Default Mode (non-guided): Be Concise**

Without `--guided`, skip explanations and get straight to choices:

```bash
# Default mode - minimal output
echo -e "${BOLD}Select framework:${NC}"
echo -e "  1) PyTorch  2) TensorFlow"
read -p "Choice [1-2, default: 1]: " CHOICE
CHOICE=${CHOICE:-1}

# ... process ...

echo -e "${GREEN}✓${NC} Image built: $IMAGE_NAME"
echo -e "Next: ${GREEN}container-deploy $IMAGE_NAME${NC}"
```

**Summary:**
| Mode | Explanations | Pauses | Confirmation Detail |
|------|--------------|--------|---------------------|
| `--guided` | Full context before each step | Yes, at section breaks | Detailed "What Just Happened" |
| Default | None | Minimal | Single line success message |

---

## Code Standards

### Shebang & Headers

```bash
#!/bin/bash
# DS01 Container Deploy - L3 Orchestrator
# Brief description of what this command does
# File: /opt/ds01-infra/scripts/user/container-deploy

set -e  # Exit on error
```

### Always Use `echo -e`

**CRITICAL:** Always use `echo -e` for ANSI color codes:

```bash
# CORRECT
echo -e "${GREEN}✓${NC} Success"

# WRONG - colors won't render
echo "${GREEN}✓${NC} Success"
```

### Argument Parsing

```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        --guided)
            GUIDED=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --info)
            detailed_help
            exit 0
            ;;
        -*)
            echo -e "${RED}Error:${NC} Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Positional argument
            if [[ -z "$ARG1" ]]; then
                ARG1="$1"
            else
                echo -e "${RED}Error:${NC} Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done
```

### Source Libraries

```bash
# Source context library (for is_atomic_context, etc.)
if [[ -f "/opt/ds01-infra/scripts/lib/ds01-context.sh" ]]; then
    source /opt/ds01-infra/scripts/lib/ds01-context.sh
fi

# Source interactive selection library
if [[ -f "/opt/ds01-infra/scripts/lib/interactive-select.sh" ]]; then
    source /opt/ds01-infra/scripts/lib/interactive-select.sh
fi
```

---

## Common Patterns

### Container Name Resolution

```bash
CONTAINER_NAME="$1"
USER_ID=$(id -u)
CONTAINER_TAG="${CONTAINER_NAME}._.${USER_ID}"

# Interactive selection if no name provided
if [[ -z "$CONTAINER_NAME" ]]; then
    CONTAINER_NAME=$(select_container "running")
    if [[ -z "$CONTAINER_NAME" ]]; then
        echo "No container selected. Exiting."
        exit 0
    fi
fi
```

### Confirmation Pattern

```bash
confirm_action() {
    local message="$1"
    local default="${2:-n}"

    read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true

    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " response </dev/tty
        response=${response:-Y}
    else
        read -p "$message [y/N]: " response </dev/tty
        response=${response:-N}
    fi

    [[ "$response" =~ ^[Yy] ]]
}

# Usage
if confirm_action "Delete container?" "n"; then
    # proceed
fi
```

### Post-Exit Menu

```bash
show_post_exit_menu() {
    local name="$1"

    # Skip if called from orchestrator
    if [[ -n "$DS01_ORCHESTRATOR" ]]; then
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Session Ended${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # ... menu options ...
}
```

---

## Anti-Patterns

### DON'T: Excessive Whitespace

```bash
# BAD
echo ""
echo ""
echo -e "Content"
echo ""
echo ""

# GOOD
echo ""
echo -e "Content"
```

### DON'T: Redundant Success Messages

```bash
# BAD
echo -e "${GREEN}✓${NC} Image created"
echo -e "${GREEN}Image successfully created!${NC}"  # Redundant!

# GOOD
echo -e "${GREEN}✓${NC} Image created: $IMAGE_NAME"
```

### DON'T: Interface Leakage

```bash
# BAD - orchestrator referencing atomic commands
# In container-deploy:
echo "Next: container-start $name"  # Wrong level!

# GOOD
echo "Next: container-retire $name"  # Same level
```

### DON'T: Echo Without -e Flag

```bash
# BAD - colors won't work
echo "${GREEN}Success${NC}"

# GOOD
echo -e "${GREEN}Success${NC}"
```

### DON'T: Unflushed Prompts

```bash
# BAD - may read buffered input
read -p "Continue? " CHOICE

# GOOD
read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true
read -p "Continue? " CHOICE </dev/tty
```

### DON'T: Multiple Banners

```bash
# BAD - container-deploy shows banner, then container-create shows another
# (container-create should check context and suppress)

# GOOD - one banner from entry point only
```

---

## Quick Reference

### Standard Header

```bash
#!/bin/bash
# DS01 Command Name - Layer Type
# Brief description
# File: /opt/ds01-infra/scripts/user/command-name

set -e

# Source libraries
[[ -f "/opt/ds01-infra/scripts/lib/ds01-context.sh" ]] && \
    source /opt/ds01-infra/scripts/lib/ds01-context.sh

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
```

### Standard Prompt

```bash
read -r -t 0.1 -n 10000 discard </dev/tty 2>/dev/null || true
read -p "Choice [1-2]: " CHOICE </dev/tty
```

### Standard Divider

```bash
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
```

### Standard Success

```bash
echo -e "${GREEN}✓${NC} Action completed"
```

### Standard Error

```bash
echo -e "${RED}✗${NC} Action failed"
```

---

## Checklist for New Commands

- [ ] Shebang on line 1, no leading whitespace
- [ ] `set -e` after shebang
- [ ] Source ds01-context.sh
- [ ] Use standard color definitions
- [ ] `echo -e` for all colored output
- [ ] 46-char dividers
- [ ] Flush stdin before all prompts
- [ ] Context-aware banners (suppress in orchestration)
- [ ] Interface-appropriate command references
- [ ] `--help` and `--info` flags implemented
- [ ] Interactive mode when called without args
- [ ] No redundant messages from conditional paths
- [ ] Single blank line between sections, no doubles
- [ ] No trailing blank lines

---

*Last updated: December 2024*
