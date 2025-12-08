#!/bin/bash
# /opt/ds01-infra/scripts/lib/project-metadata.sh
# DS01 Project Metadata Library
#
# Provides functions for managing project metadata in pyproject.toml format.
# DS01 metadata is stored under [tool.ds01] section.
#
# Usage in scripts:
#   source /opt/ds01-infra/scripts/lib/project-metadata.sh
#
#   # Create pyproject.toml with DS01 metadata
#   create_project_pyproject "/home/user/workspace/my-project" "my-project" "cv" "My thesis project"
#
#   # Read metadata
#   project_type=$(read_project_metadata "/home/user/workspace/my-project" "type")
#
#   # List all projects
#   list_projects  # prints: project-name|type|has_metadata
#
#   # Check if image exists
#   if check_project_image "my-project"; then echo "Image ready"; fi
#

# Use-case package definitions
# These are the packages installed for each use-case type
# Synced with image-create get_usecase_packages()
declare -A USECASE_PACKAGES
USECASE_PACKAGES[ml]="xgboost lightgbm catboost optuna shap"
USECASE_PACKAGES[cv]="timm albumentations opencv-python-headless kornia ultralytics"
USECASE_PACKAGES[nlp]="transformers datasets tokenizers accelerate sentencepiece peft safetensors evaluate"
USECASE_PACKAGES[rl]="gymnasium stable-baselines3"
USECASE_PACKAGES[audio]="librosa soundfile audiomentations"
USECASE_PACKAGES[ts]="statsmodels prophet darts"
USECASE_PACKAGES[llm]="vllm bitsandbytes langchain einops"

# Core data science packages (always included)
CORE_PACKAGES="pandas numpy scikit-learn matplotlib seaborn jupyter jupyterlab ipykernel"

# Create pyproject.toml with DS01 metadata section
# Args: project_dir project_name project_type [description]
create_project_pyproject() {
    local project_dir="$1"
    local project_name="$2"
    local project_type="${3:-ml}"
    local description="${4:-}"
    local author
    local user_id

    author=$(whoami)
    user_id=$(id -u)

    local pyproject_path="$project_dir/pyproject.toml"
    local created_date
    created_date=$(date -I)

    # If pyproject.toml exists, update it; otherwise create new
    if [[ -f "$pyproject_path" ]]; then
        # Update existing - use Python for TOML manipulation
        python3 << PYEOF
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib

try:
    import tomli_w
except ImportError:
    # Fallback: just read and append
    pass

pyproject_path = "$pyproject_path"
project_name = "$project_name"
project_type = "$project_type"
description = """$description"""
author = "$author"
user_id = "$user_id"
created_date = "$created_date"

try:
    with open(pyproject_path, 'rb') as f:
        data = tomllib.load(f)
except Exception as e:
    print(f"Warning: Could not read existing pyproject.toml: {e}", file=sys.stderr)
    data = {}

# Ensure sections exist
if 'project' not in data:
    data['project'] = {}
if 'tool' not in data:
    data['tool'] = {}
if 'ds01' not in data['tool']:
    data['tool']['ds01'] = {}

# Update project section
data['project']['name'] = project_name
if description:
    data['project']['description'] = description

# Update tool.ds01 section
data['tool']['ds01']['type'] = project_type
data['tool']['ds01']['created'] = created_date
data['tool']['ds01']['author'] = author
data['tool']['ds01']['image'] = f"ds01-{user_id}/{project_name}:latest"

# Write back using tomli_w if available, otherwise simple format
try:
    import tomli_w
    with open(pyproject_path, 'wb') as f:
        tomli_w.dump(data, f)
except ImportError:
    # Simple TOML writer fallback
    with open(pyproject_path, 'w') as f:
        # [project] section
        f.write('[project]\n')
        f.write(f'name = "{data["project"]["name"]}"\n')
        if data['project'].get('description'):
            f.write(f'description = "{data["project"]["description"]}"\n')
        f.write('\n')

        # [tool.ds01] section
        f.write('[tool.ds01]\n')
        f.write(f'type = "{data["tool"]["ds01"]["type"]}"\n')
        f.write(f'created = "{data["tool"]["ds01"]["created"]}"\n')
        f.write(f'author = "{data["tool"]["ds01"]["author"]}"\n')
        f.write(f'image = "{data["tool"]["ds01"]["image"]}"\n')
PYEOF
    else
        # Create new pyproject.toml
        cat > "$pyproject_path" << TOMLEOF
[project]
name = "$project_name"
$([ -n "$description" ] && echo "description = \"$description\"")

[tool.ds01]
type = "$project_type"
created = "$created_date"
author = "$author"
image = "ds01-${user_id}/${project_name}:latest"
TOMLEOF
    fi
}

# Read a value from pyproject.toml [tool.ds01] section
# Args: project_dir key
# Returns: value or empty string
read_project_metadata() {
    local project_dir="$1"
    local key="$2"
    local pyproject_path="$project_dir/pyproject.toml"

    if [[ ! -f "$pyproject_path" ]]; then
        return 1
    fi

    python3 << PYEOF
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)

try:
    with open("$pyproject_path", 'rb') as f:
        data = tomllib.load(f)
    value = data.get('tool', {}).get('ds01', {}).get('$key', '')
    print(value)
except Exception:
    sys.exit(1)
PYEOF
}

# Read project name from pyproject.toml [project] section
# Args: project_dir
# Returns: project name or empty string
read_project_name() {
    local project_dir="$1"
    local pyproject_path="$project_dir/pyproject.toml"

    if [[ ! -f "$pyproject_path" ]]; then
        return 1
    fi

    python3 << PYEOF
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)

try:
    with open("$pyproject_path", 'rb') as f:
        data = tomllib.load(f)
    value = data.get('project', {}).get('name', '')
    print(value)
except Exception:
    sys.exit(1)
PYEOF
}

# Check if a project has DS01 metadata
# Args: project_dir
# Returns: 0 if metadata exists, 1 otherwise
has_project_metadata() {
    local project_dir="$1"
    local pyproject_path="$project_dir/pyproject.toml"

    if [[ ! -f "$pyproject_path" ]]; then
        return 1
    fi

    # Check if [tool.ds01] section exists with type field
    local project_type
    project_type=$(read_project_metadata "$project_dir" "type" 2>/dev/null)
    [[ -n "$project_type" ]]
}

# List all projects in workspace directory
# Args: [workspace_dir] (defaults to ~/workspace)
# Output: project_name|type|has_metadata (one per line)
list_projects() {
    local workspace_dir="${1:-$HOME/workspace}"

    if [[ ! -d "$workspace_dir" ]]; then
        return 0
    fi

    for project_dir in "$workspace_dir"/*/; do
        [[ -d "$project_dir" ]] || continue
        local project_name
        project_name=$(basename "$project_dir")

        # Skip hidden directories
        [[ "$project_name" == .* ]] && continue

        local project_type="unknown"
        local has_meta="no"

        if has_project_metadata "$project_dir"; then
            project_type=$(read_project_metadata "$project_dir" "type")
            has_meta="yes"
        fi

        echo "$project_name|$project_type|$has_meta"
    done
}

# Check if Docker image exists for a project
# Args: project_name [user_id]
# Returns: 0 if image exists, 1 otherwise
check_project_image() {
    local project_name="$1"
    local user_id="${2:-$(id -u)}"
    local expected_image="ds01-${user_id}/${project_name}:latest"

    # Use docker images to check if image exists
    docker images -q "$expected_image" 2>/dev/null | grep -q .
}

# Get the expected image name for a project
# Args: project_name [user_id]
# Returns: image name
get_project_image_name() {
    local project_name="$1"
    local user_id="${2:-$(id -u)}"
    echo "ds01-${user_id}/${project_name}:latest"
}

# Get Dockerfile path for a project (checks multiple locations)
# Args: project_name
# Returns: path to Dockerfile or empty string
get_project_dockerfile() {
    local project_name="$1"
    local project_dir="$HOME/workspace/$project_name"

    # Priority 1: Per-project Dockerfile (new standard)
    if [[ -f "$project_dir/Dockerfile" ]]; then
        echo "$project_dir/Dockerfile"
        return 0
    fi

    # Priority 2: Centralized ~/dockerfiles/ (legacy)
    if [[ -f "$HOME/dockerfiles/${project_name}.Dockerfile" ]]; then
        echo "$HOME/dockerfiles/${project_name}.Dockerfile"
        return 0
    fi

    # Not found
    return 1
}

# Get use-case packages for a project type
# Args: project_type (ml, cv, nlp, rl, audio, ts, llm, custom)
# Returns: space-separated list of packages
get_usecase_packages() {
    local project_type="$1"
    echo "${USECASE_PACKAGES[$project_type]:-}"
}

# Get all packages for a project type (core + use-case)
# Args: project_type
# Returns: space-separated list of packages
get_all_packages() {
    local project_type="$1"
    local usecase_packages
    usecase_packages=$(get_usecase_packages "$project_type")
    echo "$CORE_PACKAGES $usecase_packages" | tr -s ' '
}

# Create requirements.txt with commented sections
# Args: project_dir project_type [custom_packages]
create_project_requirements() {
    local project_dir="$1"
    local project_type="$2"
    local custom_packages="${3:-}"
    local req_file="$project_dir/requirements.txt"

    local usecase_packages
    usecase_packages=$(get_usecase_packages "$project_type")

    # Human-readable type name
    local type_name
    case "$project_type" in
        ml)    type_name="General ML" ;;
        cv)    type_name="Computer Vision" ;;
        nlp)   type_name="NLP" ;;
        rl)    type_name="Reinforcement Learning" ;;
        audio) type_name="Audio/Speech" ;;
        ts)    type_name="Time Series" ;;
        llm)   type_name="LLM/GenAI" ;;
        *)     type_name="Custom" ;;
    esac

    cat > "$req_file" << EOF
# DS01 Project Requirements
# Generated for project type: $type_name
# Modify as needed - this file is read by image-create

# Core packages (data science essentials)
pandas>=2.0
numpy>=1.24
scikit-learn>=1.3
matplotlib>=3.7
seaborn>=0.12

# Jupyter environment
jupyter
jupyterlab
ipykernel
ipywidgets
EOF

    # Add use-case specific packages
    if [[ -n "$usecase_packages" ]]; then
        echo "" >> "$req_file"
        echo "# $type_name specific packages" >> "$req_file"
        for pkg in $usecase_packages; do
            echo "$pkg" >> "$req_file"
        done
    fi

    # Add custom packages if provided
    if [[ -n "$custom_packages" ]]; then
        echo "" >> "$req_file"
        echo "# Custom packages" >> "$req_file"
        for pkg in $custom_packages; do
            echo "$pkg" >> "$req_file"
        done
    fi
}

# Export functions for subshells
export -f create_project_pyproject read_project_metadata read_project_name
export -f has_project_metadata list_projects
export -f check_project_image get_project_image_name get_project_dockerfile
export -f get_usecase_packages get_all_packages create_project_requirements
