#!/bin/bash
# DS01 Container Entrypoint
# Fixes user setup and provides helpful environment

set -e

# Get user info from environment or defaults
USER_ID=${USER_ID:-$(id -u)}
GROUP_ID=${GROUP_ID:-$(id -g)}
USERNAME=${USERNAME:-ds01user}

# Add user to /etc/passwd if not exists (fixes "I have no name!" issue)
if ! getent passwd $USER_ID > /dev/null 2>&1; then
    echo "$USERNAME:x:$USER_ID:$GROUP_ID:DS01 User:/workspace:/bin/bash" >> /etc/passwd
    echo "$USERNAME:x:$GROUP_ID:" >> /etc/group
fi

# Create bashrc with helpful aliases and welcome message
cat > /tmp/.ds01_bashrc << 'BASHRCEOF'
# DS01 Container Environment

# Custom exit commands
alias detach='echo -e "\033[1;33mTo detach: Press Ctrl+P, then Ctrl+Q\033[0m"'
alias exit-help='echo -e "\033[1;36m━━━ Exit Options ━━━\033[0m\n  • \033[1;32mdetach\033[0m or Ctrl+P,Ctrl+Q - Exit without stopping container\n  • \033[1;32mexit\033[0m or Ctrl+D - Exit and stop container\n"'

# Quick workspace navigation
alias cdw='cd /workspace'
alias ws='cd /workspace'

# Helpful GPU check
alias gpu='nvidia-smi'

# Show welcome message on first login
if [ ! -f /workspace/.ds01-welcome-shown ]; then
    echo ""
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;32m✓ Welcome to Your DS01 Container\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e "\033[1mQuick Start:\033[0m"
    echo "  • Your persistent workspace: /workspace"
    echo "  • Check GPU status: nvidia-smi"
    echo "  • Run Python scripts: python your_script.py"
    echo "  • Start Jupyter: jupyter lab --ip=0.0.0.0 --no-browser"
    echo "  • Edit notebooks: Open .ipynb files in Jupyter"
    echo ""
    echo -e "\033[1mExit Options:\033[0m"
    echo -e "  • \033[1;32mCtrl+P, Ctrl+Q\033[0m - Exit without stopping (container keeps running)"
    echo -e "  • \033[1;32mexit\033[0m or \033[1;32mCtrl+D\033[0m - Exit and stop container"
    echo -e "  • Type \033[1;33mexit-help\033[0m for this info anytime"
    echo ""
    echo -e "\033[1mWorking with Code:\033[0m"
    echo "  • \033[1;36mScripts:\033[0m python script.py or ./script.sh"
    echo "  • \033[1;36mNotebooks:\033[0m Launch Jupyter Lab, then open .ipynb files in browser"
    echo "  • \033[1;36mInteractive:\033[0m python or ipython for REPL"
    echo ""
    echo -e "\033[2m💡 Tip: All work in /workspace persists across container restarts\033[0m"
    echo ""

    touch /workspace/.ds01-welcome-shown
fi

BASHRCEOF

# Add to bashrc if running bash
if [ -f ~/.bashrc ]; then
    # Append our custom bashrc if not already there
    if ! grep -q "DS01 Container Environment" ~/.bashrc 2>/dev/null; then
        cat /tmp/.ds01_bashrc >> ~/.bashrc
    fi
elif [ -f /root/.bashrc ]; then
    if ! grep -q "DS01 Container Environment" /root/.bashrc 2>/dev/null; then
        cat /tmp/.ds01_bashrc >> /root/.bashrc
    fi
fi

# If .bashrc doesn't exist, create it
if [ ! -f ~/.bashrc ] && [ ! -f /root/.bashrc ]; then
    mkdir -p ~/.config 2>/dev/null || true
    cat /tmp/.ds01_bashrc > ~/.bashrc || cat /tmp/.ds01_bashrc > /root/.bashrc
fi

# Execute the command passed to entrypoint
exec "$@"
