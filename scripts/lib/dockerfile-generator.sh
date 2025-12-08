#!/bin/bash
# dockerfile-generator.sh - Shared Dockerfile generation for DS01
#
# Usage:
#   source /opt/ds01-infra/scripts/lib/dockerfile-generator.sh
#   generate_dockerfile <output_path> <options...>
#
# This library provides a single source of truth for Dockerfile generation,
# used by both project-init and image-create.

# Read packages from requirements.txt file
# Args: $1 = file path
# Outputs: space-separated package list (preserving version specifiers)
read_requirements_packages() {
    local req_file="$1"
    local packages=""

    while IFS= read -r line; do
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Skip empty lines
        [[ -z "${line// }" ]] && continue
        # Skip -r/-e/--requirement/--editable (recursive requirements, editable installs)
        [[ "$line" =~ ^[[:space:]]*- ]] && continue

        # Strip inline comments (everything after #)
        line=$(echo "$line" | sed 's/#.*//')

        # Trim leading/trailing whitespace and normalize version specifiers
        # Handles "torch >= 2.0.1" → "torch>=2.0.1"
        local pkg
        pkg=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
              sed 's/[[:space:]]*\([><=!~]\+\)[[:space:]]*/\1/g')

        if [ -n "$pkg" ]; then
            packages="$packages $pkg"
        fi
    done < "$req_file"

    # Trim leading space
    echo "${packages# }"
}

# Generate a DS01 Dockerfile
#
# Required parameters:
#   --output PATH          Output Dockerfile path
#   --base-image IMAGE     Base Docker image (e.g., from get_base_image)
#   --project NAME         Project name
#   --user-id ID           User ID
#   --username NAME        Username
#
# Optional parameters:
#   --framework NAME       Framework name (pytorch, tensorflow, etc.) [default: pytorch]
#   --requirements FILE    Path to requirements.txt (unpacks packages inline)
#   --system-packages PKG  Space-separated system packages
#   --python-packages PKG  Space-separated Python packages (inline RUN pip install)
#   --skip-system          Skip system packages section
#   --skip-jupyter-config  Skip Jupyter configuration
#   --minimal              Minimal Dockerfile (just FROM + requirements.txt)
#
generate_dockerfile() {
    local output=""
    local base_image=""
    local project=""
    local user_id=""
    local username=""
    local framework="pytorch"
    local requirements=""
    local system_packages=""
    local python_packages=""
    local skip_system=false
    local skip_jupyter=false
    local minimal=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            --base-image) base_image="$2"; shift 2 ;;
            --project) project="$2"; shift 2 ;;
            --user-id) user_id="$2"; shift 2 ;;
            --username) username="$2"; shift 2 ;;
            --framework) framework="$2"; shift 2 ;;
            --requirements) requirements="$2"; shift 2 ;;
            --system-packages) system_packages="$2"; shift 2 ;;
            --python-packages) python_packages="$2"; shift 2 ;;
            --skip-system) skip_system=true; shift ;;
            --skip-jupyter-config) skip_jupyter=true; shift ;;
            --minimal) minimal=true; shift ;;
            *) echo "Unknown option: $1" >&2; return 1 ;;
        esac
    done

    # Validate required params
    if [ -z "$output" ] || [ -z "$base_image" ] || [ -z "$project" ] || [ -z "$user_id" ] || [ -z "$username" ]; then
        echo "Error: Missing required parameters for generate_dockerfile" >&2
        echo "Required: --output, --base-image, --project, --user-id, --username" >&2
        return 1
    fi

    # Create output directory
    mkdir -p "$(dirname "$output")"

    # === HEADER ===
    cat > "$output" << EOF
# DS01 Project Dockerfile
# Project: $project
# Created: $(date)
# Framework: $framework
# Author: $username
#
# Build with: image-update $project
# Or: docker build -t ds01-${user_id}/${project}:latest .

FROM $base_image

# DS01 metadata labels
LABEL maintainer="$username"
LABEL maintainer.id="$user_id"
LABEL ds01.project="$project"
LABEL ds01.framework="$framework"
LABEL ds01.created="$(date -Iseconds)"
LABEL ds01.managed="true"

# Build arguments (set automatically by DS01)
ARG DS01_USER_ID=${user_id}
ARG DS01_GROUP_ID=${user_id}
ARG DS01_USERNAME=${username}

EOF

    # === SYSTEM PACKAGES ===
    if [ "$skip_system" != true ] && [ "$minimal" != true ]; then
        cat >> "$output" << 'EOF'
# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    vim \
    htop \
EOF
        # Add custom system packages
        if [ -n "$system_packages" ]; then
            for pkg in $system_packages; do
                echo "    $pkg \\" >> "$output"
            done
        fi
        echo "    && rm -rf /var/lib/apt/lists/*" >> "$output"
        echo "" >> "$output"
    fi

    # === PYTHON PACKAGES ===
    if [ -n "$requirements" ] && [ -f "$requirements" ]; then
        # Requirements.txt mode - unpack packages inline (not COPY)
        local req_packages
        req_packages=$(read_requirements_packages "$requirements")

        if [ -n "$req_packages" ]; then
            # Show source path (abbreviated)
            local short_req="${requirements/#$HOME/~}"
            echo "# Packages from requirements.txt" >> "$output"
            echo "# Source: $short_req" >> "$output"
            _write_pip_install "$output" "$req_packages"
            echo "" >> "$output"
        fi
    elif [ -n "$python_packages" ]; then
        # Inline packages mode
        echo "# Python packages" >> "$output"
        _write_pip_install "$output" "$python_packages"
        echo "" >> "$output"
    fi

    # === CUSTOM PACKAGES SECTION ===
    cat >> "$output" << 'EOF'
# Custom additional packages
# Add packages here with: image-update <project> then "Add Python packages"
# Or edit this file directly and rebuild

EOF

    # === JUPYTER CONFIGURATION ===
    if [ "$skip_jupyter" != true ] && [ "$minimal" != true ]; then
        cat >> "$output" << EOF
# Configure Jupyter Lab
RUN jupyter lab --generate-config 2>/dev/null || true && \\
    mkdir -p /root/.jupyter && \\
    echo "c.ServerApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.allow_root = True" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.open_browser = False" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.token = ''" >> /root/.jupyter/jupyter_lab_config.py && \\
    echo "c.ServerApp.password = ''" >> /root/.jupyter/jupyter_lab_config.py

EOF
    fi

    # === FOOTER ===
    cat >> "$output" << 'EOF'
# Working directory (mapped to ~/workspace/<project>)
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
EOF

    echo "$output"
}

# Helper: Write pip install block with proper line continuation
# Usage: _write_pip_install <file> "pkg1 pkg2 pkg3"
_write_pip_install() {
    local file="$1"
    local packages="$2"

    if [ -z "$packages" ]; then
        return
    fi

    echo "RUN pip install --no-cache-dir \\" >> "$file"

    local pkg_array=($packages)
    local pkg_count=${#pkg_array[@]}
    local i=0

    for pkg in "${pkg_array[@]}"; do
        ((i++))
        if [ $i -lt $pkg_count ]; then
            echo "    $pkg \\" >> "$file"
        else
            echo "    $pkg" >> "$file"
        fi
    done
}

# Helper: Add packages to existing Dockerfile's custom section
# Usage: add_to_custom_section <dockerfile> "pkg1 pkg2 pkg3"
add_to_custom_section() {
    local dockerfile="$1"
    local packages="$2"

    local custom_line=$(grep -n "^# Custom additional packages" "$dockerfile" | head -1 | cut -d: -f1)

    if [ -z "$custom_line" ]; then
        echo "Error: No '# Custom additional packages' section found" >&2
        return 1
    fi

    # Check if there's already a RUN pip install after the custom section
    local next_line=$((custom_line + 1))
    local next_content=$(sed -n "${next_line}p" "$dockerfile")

    if [[ "$next_content" =~ ^RUN\ pip\ install ]]; then
        # Append to existing RUN block
        # Find last line of RUN block, add backslash, insert packages
        :
    else
        # Insert new RUN block after custom comment
        local temp_file=$(mktemp)
        head -n "$custom_line" "$dockerfile" > "$temp_file"
        _write_pip_install "$temp_file" "$packages"
        echo "" >> "$temp_file"
        tail -n "+$next_line" "$dockerfile" >> "$temp_file"
        mv "$temp_file" "$dockerfile"
    fi
}
