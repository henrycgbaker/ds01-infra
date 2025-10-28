#!/bin/bash
# /opt/ds01-infra/scripts/maintenance/existing-users-permissions.sh
# Fix permissions for all existing home directories

#@TODO get this to run auto whenever new user added

for dir in /home/*; do
    if [ -d "$dir" ]; then
        # Get the directory name
        dirname=$(basename "$dir")
        
        # Skip the special directories if needed
        if [ "$dirname" != "." ] && [ "$dirname" != ".." ]; then
            sudo chmod 700 "$dir"
            echo "Updated: $dir"
        fi
    fi
done

echo "Done! All home directories are now private (700)"