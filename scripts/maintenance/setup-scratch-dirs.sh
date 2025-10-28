#!/bin/bash
# /opt/ds01-infra/scripts/maintenance/setup-scratch-dirs.sh
# Create scratch subdirectories for all existing users

#TODO set this up for home workspace + scratch  + collab + temp etc on new user creation

SCRATCH_DIR="/scratch"

# Create scratch directories for all users in /home
for user_dir in /home/*; do
    if [ -d "$user_dir" ]; then
        username=$(basename "$user_dir")
        
        # Skip special directories
        if [ "$username" != "." ] && [ "$username" != ".." ]; then
            # Create user's scratch directory
            user_scratch="$SCRATCH_DIR/$username"
            
            if [ ! -d "$user_scratch" ]; then
                sudo mkdir -p "$user_scratch"
                # Get the actual owner and group from the home directory
                owner=$(stat -c '%U' "$user_dir")
                group=$(stat -c '%G' "$user_dir")
                sudo chown "$owner":"$group" "$user_scratch"
                sudo chmod 700 "$user_scratch"
                echo "Created scratch directory for: $username"
            else
                echo "Scratch directory already exists for: $username"
            fi
        fi
    fi
done

echo "Done! All user scratch directories created."
echo "Users can now use: /scratch/\$USER/"