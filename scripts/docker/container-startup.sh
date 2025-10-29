#!/bin/bash
# Auto-start Jupyter when container opens
# This gets added to container's .bashrc

# Only start if not already running and in interactive shell
if [[ $- == *i* ]] && ! pgrep -f "jupyter-lab" > /dev/null; then
    # Get container name from hostname or default
    CONTAINER_NAME=$(hostname | cut -d. -f1 2>/dev/null || echo "jupyter")
    
    # Use container name as token for easy access
    TOKEN="${CONTAINER_NAME}-$(id -u)"
    
    # Start Jupyter in background
    nohup jupyter lab \
        --ip=0.0.0.0 \
        --port=8888 \
        --no-browser \
        --ServerApp.token="$TOKEN" \
        --ServerApp.allow_origin='*' \
        > /workspace/.jupyter.log 2>&1 &
    
    echo "🚀 Jupyter Lab started!"
    echo "   Token: $TOKEN"
    echo "   Port: 8888"
    echo "   Log: /workspace/.jupyter.log"
    echo ""
fi