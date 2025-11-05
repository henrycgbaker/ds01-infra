#!/bin/bash
# DS01 Container Initialization
# Sets up user environment and shows welcome message

# Fix "I have no name!" issue by setting up user in /etc/passwd
setup_user() {
    local user_id=$(id -u)
    local group_id=$(id -g)

    # Get hostname for username (container name)
    local container_name=$(hostname 2>/dev/null || echo "ds01user")

    # Check if user exists in /etc/passwd
    if ! getent passwd $user_id > /dev/null 2>&1; then
        # Try to add user (requires root or writable /etc/passwd)
        if [ -w /etc/passwd ] 2>/dev/null; then
            echo "$container_name:x:$user_id:$group_id:DS01 User:/workspace:/bin/bash" >> /etc/passwd 2>/dev/null || true
            echo "$container_name:x:$group_id:" >> /etc/group 2>/dev/null || true
        else
            # Can't write to /etc/passwd, so we'll set env vars and use custom PS1
            export USER="$container_name"
            export USERNAME="$container_name"
            export HOME="/workspace"
            export LOGNAME="$container_name"
        fi
    else
        # User exists, get the username
        local existing_user=$(getent passwd $user_id | cut -d: -f1)
        export USER="$existing_user"
        export USERNAME="$existing_user"
    fi
}

# Load DS01 aliases from central configuration
setup_aliases() {
    # Source system-wide DS01 aliases (mounted from host)
    if [ -f /etc/ds01/container-aliases.sh ]; then
        source /etc/ds01/container-aliases.sh
    fi

    # Also create a copy in workspace for user customization
    local user_bashrc="/workspace/.ds01_bashrc_custom"
    if [ ! -f "$user_bashrc" ]; then
        cat > "$user_bashrc" << 'BASHRCEOF'
# Custom User Aliases
# Add your personal aliases here - they will persist across container restarts

# Example custom aliases:
# alias train='python scripts/train.py'
# alias test='python scripts/test.py'

BASHRCEOF
    fi

    # Source user's custom aliases
    if [ -f "$user_bashrc" ]; then
        source "$user_bashrc"
    fi
}

# Show welcome message (only first time)
show_welcome() {
    if [ ! -f /workspace/.ds01-session-started ]; then
        echo ""
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;32m✓ Inside Container - Ready to Work\033[0m"
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        echo -e "\033[1mYour Workspace:\033[0m"
        echo "  📁 /workspace (persistent storage)"
        echo "  💾 Everything here survives container restarts"
        echo ""
        echo -e "\033[1mRunning Code:\033[0m"
        echo -e "  • \033[1;36mCommand line:\033[0m   python script.py  or  ./script.sh  or  jlab"
        echo -e "  • \033[1;36mIDE/Editor:\033[0m     Edit in VS Code/PyCharm via SSH, run in container"
        echo -e "  • \033[1;36mNotebooks:\033[0m      Launch Jupyter (\033[1;32mjlab\033[0m), connect from browser/IDE"
        echo ""
        echo -e "\033[1mIDE Workflow (2 options):\033[0m"
        echo -e "  Option A: VS Code Dev Containers (recommended for ML)"
        echo -e "    → Attach VS Code directly to THIS container"
        echo -e "    → All code runs in container automatically (GPU access)"
        echo -e "    → See: /opt/ds01-infra/docs/vscode-container-setup.md"
        echo ""
        echo -e "  Option B: VS Code Remote SSH (quick edits)"
        echo -e "    → SSH to DS01 host, edit files in ~/workspace"
        echo -e "    → Enter container manually to run code"
        echo -e "    → Good for editing multiple projects"
        echo ""
        echo -e "\033[1mExiting Container:\033[0m"
        echo -e "  • \033[1;33mCtrl+P, Ctrl+Q\033[0m - Detach (keeps running) - type \033[1;32mdetach\033[0m for reminder"
        echo -e "  • \033[1;33mexit\033[0m or \033[1;33mCtrl+D\033[0m - Exit and stop - type \033[1;32mexit-stop\033[0m for reminder"
        echo -e "  • Type \033[1;32mexit-help\033[0m anytime for exit options"
        echo ""
        echo -e "\033[1mHelpful Aliases:\033[0m"
        echo -e "  \033[1;32mgpu\033[0m          Check GPU status          \033[1;32mgs\033[0m             git status"
        echo -e "  \033[1;32mjlab\033[0m         Start Jupyter Lab         \033[1;32mll\033[0m             List files"
        echo -e "  \033[1;32mws\033[0m           Go to workspace           \033[1;32maliases\033[0m        See all aliases"
        echo ""
        echo -e "\033[2m💡 For host commands (container-list, etc.): Exit with Ctrl+P,Ctrl+Q first\033[0m"
        echo ""
        echo -e "\033[2m💡 Tip: Add custom aliases to /workspace/.ds01_bashrc_custom\033[0m"
        echo ""

        # Mark as shown for this session
        touch /workspace/.ds01-session-started
    fi
}

# Main execution
setup_user
setup_aliases
show_welcome

# Start bash (aliases are already loaded)
exec /bin/bash "$@"
