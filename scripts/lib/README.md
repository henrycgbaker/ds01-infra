# DS01 Shared Libraries

Reusable shell and Python libraries used across DS01 commands. These provide consistent behavior and reduce code duplication.

## Usage

Source libraries at the top of your script:

```bash
#!/bin/bash
source /opt/ds01-infra/scripts/lib/dockerfile-generator.sh
source /opt/ds01-infra/scripts/lib/aime-images.sh
```

## Libraries

### dockerfile-generator.sh

**Purpose:** Single source of truth for Dockerfile generation. Ensures consistent structure across `project-init` and `image-create`.

**Functions:**

| Function | Description |
|----------|-------------|
| `generate_dockerfile` | Creates a complete DS01 Dockerfile |
| `_write_pip_install` | Helper: writes pip install block with line continuation |
| `add_to_custom_section` | Adds packages to existing Dockerfile's custom section |

**Usage:**

```bash
source /opt/ds01-infra/scripts/lib/dockerfile-generator.sh

generate_dockerfile \
    --output "$PROJECT_DIR/Dockerfile" \
    --base-image "aimehub/pytorch-2.5.1-aime-cuda12.1.1:latest" \
    --project "my-project" \
    --user-id "$(id -u)" \
    --username "$(whoami)" \
    --framework "pytorch" \
    --requirements "$PROJECT_DIR/requirements.txt"
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--output PATH` | Yes | Output Dockerfile path |
| `--base-image IMAGE` | Yes | Base Docker image |
| `--project NAME` | Yes | Project name |
| `--user-id ID` | Yes | User ID |
| `--username NAME` | Yes | Username |
| `--framework NAME` | No | Framework name (default: pytorch) |
| `--requirements FILE` | No | Path to requirements.txt (uses COPY + pip install -r) |
| `--system-packages PKG` | No | Space-separated system packages |
| `--python-packages PKG` | No | Space-separated Python packages |
| `--skip-system` | No | Skip system packages section |
| `--skip-jupyter-config` | No | Skip Jupyter configuration |
| `--minimal` | No | Minimal Dockerfile |

**Generated Dockerfile Structure:**

```dockerfile
# Header (comments, metadata)
FROM <base-image>

# DS01 metadata labels
LABEL ds01.project="<project>"
LABEL ds01.framework="<framework>"
LABEL ds01.created="<timestamp>"
LABEL ds01.managed="true"

# Build arguments
ARG DS01_USER_ID=<uid>
ARG DS01_GROUP_ID=<gid>
ARG DS01_USERNAME=<username>

# System packages (apt-get)
RUN apt-get update && apt-get install -y ...

# Python packages (either COPY requirements.txt OR RUN pip install)
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Custom additional packages section
# (marker for image-update to add packages)

# Jupyter configuration
RUN jupyter lab --generate-config ...

# Footer
WORKDIR /workspace
CMD ["/bin/bash"]
```

---

### aime-images.sh

**Purpose:** Resolves AIME Machine Learning Container base images based on framework and CUDA architecture.

**Functions:**

| Function | Description |
|----------|-------------|
| `detect_cuda_arch` | Detects GPU CUDA architecture (e.g., "ampere") |
| `get_base_image` | Returns appropriate AIME base image for framework |

**Usage:**

```bash
source /opt/ds01-infra/scripts/lib/aime-images.sh

BASE_IMAGE=$(get_base_image "pytorch")
# Returns: aimehub/pytorch-2.5.1-aime-cuda12.1.1:latest
```

---

### ds01-context.sh

**Purpose:** Detects execution context (orchestrator vs standalone) to conditionally suppress output.

**Functions:**

| Function | Description |
|----------|-------------|
| `is_orchestrated` | Returns true if called from an orchestrator |
| `show_next_steps` | Only shows "Next steps" if not orchestrated |

**Usage:**

```bash
source /opt/ds01-infra/scripts/lib/ds01-context.sh

# In orchestrator (L3/L4):
export DS01_CONTEXT="orchestration"

# In atomic command (L2):
if ! is_orchestrated; then
    echo "Next steps: ..."
fi
```

---

### interactive-select.sh

**Purpose:** Provides interactive selection UI for containers and images.

**Functions:**

| Function | Description |
|----------|-------------|
| `select_container` | Interactive container picker |
| `select_image` | Interactive image picker |

---

### container-session.sh

**Purpose:** Unified handler for container start/run/attach operations.

**Functions:**

| Function | Description |
|----------|-------------|
| `start_container_session` | Handles start with optional attach |
| `validate_container_gpu` | Checks if container's GPU still exists |

---

### container-logger.sh

**Purpose:** Wrapper for centralized event logging.

**Functions:**

| Function | Description |
|----------|-------------|
| `log_container_event` | Logs container lifecycle events |
| `log_gpu_event` | Logs GPU allocation events |

---

### error-messages.sh

**Purpose:** User-friendly error messages with suggested fixes.

**Functions:**

| Function | Description |
|----------|-------------|
| `show_error` | Displays formatted error with fix suggestions |
| `show_gpu_error` | GPU-specific error messages |
| `show_limit_error` | Resource limit error messages |

---

### project-metadata.sh

**Purpose:** Handles pyproject.toml parsing and creation.

**Functions:**

| Function | Description |
|----------|-------------|
| `read_project_metadata` | Parses pyproject.toml |
| `create_project_toml` | Creates new pyproject.toml |
| `create_project_requirements` | Creates requirements.txt from template |

---

### username-utils.sh

**Purpose:** Username sanitization for systemd slice names.

**Functions:**

| Function | Description |
|----------|-------------|
| `sanitize_username_for_slice` | Converts username to valid slice name |

**Usage:**

```bash
source /opt/ds01-infra/scripts/lib/username-utils.sh

SAFE_NAME=$(sanitize_username_for_slice "h.baker@hertie-school.lan")
# Returns: h_baker_hertie-school_lan
```

---

### validate-resource-limits.sh

**Purpose:** Validates resource limit values.

**Functions:**

| Function | Description |
|----------|-------------|
| `validate_memory_format` | Validates memory strings (e.g., "16g") |
| `validate_cpu_count` | Validates CPU count |

## Adding New Libraries

1. Create script in `/opt/ds01-infra/scripts/lib/`
2. Add documentation to this README
3. Update CLAUDE.md Script Organization section
4. Deploy with `sudo deploy`

## Core Libraries (New)

### init.sh

**Purpose:** Standard initialization for all DS01 bash scripts. Provides consistent paths, colors, and utility functions.

**Usage:**

```bash
#!/bin/bash
source /opt/ds01-infra/scripts/lib/init.sh

# Now you have:
# - $DS01_ROOT, $DS01_CONFIG, $DS01_SCRIPTS paths
# - $RED, $GREEN, $YELLOW, $BLUE, $NC color codes
# - ds01_get_limit, ds01_parse_duration functions
```

**Variables:**

| Variable | Description |
|----------|-------------|
| `DS01_ROOT` | Base path: `/opt/ds01-infra` |
| `DS01_CONFIG` | Config path: `$DS01_ROOT/config` |
| `DS01_SCRIPTS` | Scripts path: `$DS01_ROOT/scripts` |
| `DS01_LIB` | Lib path: `$DS01_SCRIPTS/lib` |
| `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `MAGENTA` | ANSI color codes |
| `BOLD`, `DIM`, `NC` | Text styling codes |

**Functions:**

| Function | Description |
|----------|-------------|
| `ds01_get_limit <user> <flag>` | Get resource limit value (e.g., `--idle-timeout`) |
| `ds01_get_config <flag>` | Get global config value (e.g., `--high-demand-threshold`) |
| `ds01_parse_duration <duration>` | Parse duration string to seconds (e.g., "2h" → 7200) |
| `ds01_format_duration <seconds>` | Format seconds to human-readable duration |
| `ds01_error <msg>` | Print error message to stderr |
| `ds01_warn <msg>` | Print warning message |
| `ds01_success <msg>` | Print success message |
| `ds01_info <msg>` | Print info message |
| `ds01_log <msg> [logfile]` | Log message with timestamp |
| `ds01_require_root` | Exit if not running as root |
| `ds01_current_user` | Get current username |

---

## Python Libraries

### ds01_core.py

**Purpose:** Core Python utilities for centralized, deduplicated infrastructure logic.

**Usage:**

```python
from ds01_core import parse_duration, format_duration, Colors

# Parse duration strings
seconds = parse_duration("2h")  # Returns 7200
seconds = parse_duration("0.5h")  # Returns 1800
seconds = parse_duration("null")  # Returns -1 (unlimited)

# Format durations
text = format_duration(7200)  # Returns "2h"
text = format_duration(-1)  # Returns "unlimited"

# Use colors
print(f"{Colors.GREEN}Success{Colors.NC}")
```

**Classes:**

| Class | Description |
|-------|-------------|
| `Colors` | ANSI color constants (RED, GREEN, YELLOW, BLUE, etc.) |

**Functions:**

| Function | Description |
|----------|-------------|
| `parse_duration(s)` | Parse duration string to seconds |
| `format_duration(secs)` | Format seconds to human-readable |
| `get_container_owner(name)` | Get container owner from AIME naming convention |
| `get_container_gpu(name)` | Get GPU allocation for container |
| `get_user_containers(user)` | List user's containers |

---

### username_utils.py

Python equivalent of username-utils.sh for scripts that need username sanitization in Python.

```python
from username_utils import sanitize_username_for_slice

safe_name = sanitize_username_for_slice("h.baker@hertie-school.lan")
```
