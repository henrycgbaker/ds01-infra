#!/bin/bash
# DS01 Container Aliases Configuration
# Single source of truth for all container aliases
# This file is sourced in all containers for all users

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Container Exit Commands
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias exit-help='echo -e "\033[1;36m━━━ Exit Options ━━━\033[0m\n  • \033[1;32mexit\033[0m or \033[1;33mCtrl+D\033[0m - Exit session (container keeps running)\n  • To stop container: Use \033[1;32mcontainer-stop <name>\033[0m on host\n  • Reconnect: Use \033[1;32mcontainer-run <name>\033[0m on host\n\n\033[1;33m💡 Note:\033[0m DS01 uses docker exec - container stays running after exit\n"'

alias how-to-stop='echo -e "\033[1;33m💡 To stop this container:\033[0m\n  1. Type \033[1;32mexit\033[0m to leave container\n  2. On host, run: \033[1;32mcontainer-stop <name>\033[0m\n\nTo check status: \033[1;32mcontainer-list\033[0m (on host)"'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Workspace Navigation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias cdw='cd /workspace'
alias ws='cd /workspace'
alias ll='ls -lah'
alias la='ls -A'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GPU Monitoring
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias gpu='nvidia-smi'
alias gpu-watch='watch -n 1 nvidia-smi'
alias gpu-mem='nvidia-smi --query-gpu=memory.used,memory.total --format=csv'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Jupyter & Notebook Tools
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias jlab='jupyter lab --ip=0.0.0.0 --no-browser --allow-root'
alias jnb='jupyter notebook --ip=0.0.0.0 --no-browser --allow-root'
alias jupyter-start='jupyter lab --ip=0.0.0.0 --no-browser --allow-root'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Development Tools
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias tb='tensorboard --logdir=.'
alias python-info='python --version && which python && pip list | head -20'
alias pip-installed='pip list'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Git Shortcuts
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline -10'
alias gd='git diff'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Help Commands
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Show available commands inside container
alias aliases='cat << "ALIASHELP"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Available Commands Inside Container
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Exit & Navigation:
  exit-help        Show exit options and behavior
  how-to-stop      How to stop this container
  ws / cdw         Go to /workspace
  ll               List files (ls -lah)

GPU & Development:
  gpu              Check GPU status
  gpu-watch        Watch GPU status (live)
  jlab             Start Jupyter Lab
  jnb              Start Jupyter Notebook
  tb               Start TensorBoard

Git Shortcuts:
  gs               git status
  ga               git add
  gc               git commit
  gp               git push
  gl               git log (last 10)
  gd               git diff

Container Management:
  Type 'exit' to leave (container keeps running)
  Use 'container-stop <name>' on host to stop
  Use 'container-run <name>' on host to reconnect

Host Commands (run these on DS01 host, not in container):
  container-list   See all your containers
  container-stats  Check resource usage
  image-list       See available images
  alias-list       See host commands

Your custom aliases: /workspace/.ds01_bashrc_custom
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ALIASHELP
'

# Helpful reminders for common mistakes (host-only commands)
alias container-list='echo -e "\033[1;33m⚠ container-list is a HOST command\033[0m\nType '\''exit'\'' to leave container, then run on DS01 host\n\nFor security, containers cannot manage other containers."'
alias container-run='echo -e "\033[1;33m⚠ container-run is a HOST command\033[0m\nType '\''exit'\'' to leave container, then run on DS01 host"'
alias container-stop='echo -e "\033[1;33m⚠ container-stop is a HOST command\033[0m\nType '\''exit'\'' to leave container, then run on DS01 host"'
alias alias-list='echo -e "\033[1;33m⚠ alias-list is a HOST command\033[0m\nType '\''exit'\'' to leave container, then run on DS01 host\n\nInside container, use: \033[1;32maliases\033[0m"'
alias image-list='echo -e "\033[1;33m⚠ image-list is a HOST command\033[0m\nType '\''exit'\'' to leave container, then run on DS01 host"'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Custom PS1 Prompt (colorized, handles missing username)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Get current user or fallback to container name
CURRENT_USER="${USER:-$(whoami 2>/dev/null || echo 'user')}"
if [ "$CURRENT_USER" = "I have no name!" ] || [ -z "$CURRENT_USER" ]; then
    CURRENT_USER="${USERNAME:-$(hostname 2>/dev/null || echo 'container')}"
fi

# Set colorized prompt: user@host:path$
export PS1='\[\033[1;32m\]'"${CURRENT_USER}"'\[\033[0m\]@\[\033[1;34m\]\h\[\033[0m\]:\[\033[1;36m\]\w\[\033[0m\]\$ '

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Environment Setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Set default editor
export EDITOR=vim

# Python unbuffered output
export PYTHONUNBUFFERED=1

# History settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups:erasedups

# Start in workspace directory
cd /workspace 2>/dev/null || true
