#!/bin/bash
# DS01 Container Aliases Configuration
# Single source of truth for all container aliases
# This file is sourced in all containers for all users

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Container Exit Commands
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

alias detach='echo -e "\033[1;33m💡 To detach without stopping: Press Ctrl+P, then Ctrl+Q\033[0m"'
alias exit-stop='echo -e "\033[1;33m💡 To stop container: Type '\''exit'\'' or press Ctrl+D\033[0m"'
alias exit-help='echo -e "\033[1;36m━━━ Exit Options ━━━\033[0m\n  • \033[1;32mdetach\033[0m or \033[1;33mCtrl+P, Ctrl+Q\033[0m - Exit without stopping\n  • \033[1;32mexit\033[0m or \033[1;33mCtrl+D\033[0m - Exit and stop container\n  • Type \033[1;32mdetach\033[0m or \033[1;32mexit-stop\033[0m for reminders\n"'

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
  detach           Show Ctrl+P,Ctrl+Q reminder
  exit-stop        Show exit/Ctrl+D reminder
  exit-help        Show all exit options
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

Need host commands? (container-list, image-list, etc.)
  → Exit container first (Ctrl+P, Ctrl+Q)
  → Run commands on DS01 host
  → Host commands manage containers FROM OUTSIDE

Your custom aliases: /workspace/.ds01_bashrc_custom
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ALIASHELP
'

# Helpful reminder for common mistakes
alias container-list='echo -e "\033[1;33m⚠ container-list is a HOST command\033[0m\nExit this container first (Ctrl+P, Ctrl+Q), then run it on DS01 host"'
alias container-run='echo -e "\033[1;33m⚠ container-run is a HOST command\033[0m\nExit this container first (Ctrl+P, Ctrl+Q), then run it on DS01 host"'
alias alias-list='echo -e "\033[1;33m⚠ alias-list is a HOST command\033[0m\nExit this container first (Ctrl+P, Ctrl+Q), then run it on DS01 host\n\nInside container, use: \033[1;32maliases\033[0m (to see container commands)"'

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
