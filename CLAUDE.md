# CLAUDE.md

Instructions for AI assistants working with this repository.

## Guidelines

- Be concise
- No audit.md/summary.md docs unless explicitly requested
- If uncertain, discuss in-chat then implement directly
- Update CLAUDE.md if necessary, but don't create extra documentation unless requested
- Store tests in relevant `/testing` directory for reuse

## System Overview

DS01 Infrastructure: GPU-enabled container management for multi-user data science workloads.

**Core capabilities:**
- Dynamic MIG-aware GPU allocation with priority scheduling
- Per-user/group resource limits (YAML config + systemd cgroups)
- Container lifecycle automation (idle detection, auto-cleanup)
- Monitoring and metrics collection

## Architecture Design Principles

### Tiered Hierarchical Design

DS01 uses a **modular, layered architecture** that wraps and enhances AIME MLC without replacing it:

**TIER 1: Base System** (`aime-ml-containers` v2)
- 11 core `mlc` commands providing container lifecycle management
- 150+ pre-built framework images (PyTorch 2.8.0, TensorFlow 2.16.1, etc.)
- Container naming: `{container-name}._.{user-id}` (AIME convention)
- **DS01 approach**: Wrap strategically (mlc-create, mlc-stats), use directly (mlc-open, mlc-list, mlc-stop, etc.)

**TIER 2: Modular Unit Commands** (Single-purpose, reusable)
- Container management: `container-{create|run|start|stop|list|stats|remove|exit}`
- Image management: `image-{create|list|update|delete}`
- Project setup: `{dir|git|readme|ssh|vscode}-{create|init|setup}`
- All support `--guided` flag for educational mode
- Can be used standalone or orchestrated

**TIER 3: Workflow Orchestrators** (Multi-step workflows)
- `project-init`: Orchestrates dir-create → git-init → readme-create → image-create → container-create → container-run
- Command dispatchers: Support both `container list` and `container-list` syntax
- 58.5% code reduction through modularization vs monolithic design

**TIER 4: Workflow Wizards** (Complete onboarding)
- `user-setup`: Full onboarding (ssh-setup → project-init → vscode-setup)
- Educational focus for first-time users
- 69.4% code reduction vs original monolithic version

### AIME Integration Strategy

**mlc-patched.py**: Minimal modification (2.5% change) to support custom images
- Adds `--image` flag to bypass AIME catalog
- Validates local image existence
- Adds DS01 labels (`DS01_MANAGED`, `CUSTOM_IMAGE`)
- 97.5% of AIME logic preserved (easy to upgrade)

**Naming conventions:**
- Images: `ds01-{user-id}/{project-name}:latest`
- Containers: `{project-name}._.{user-id}` (AIME convention)
- Dockerfiles: `~/dockerfiles/{project-name}.Dockerfile`

**Integration flow:** image-create (4 phases) → builds custom image → container-create → mlc-patched.py → resource limits → GPU allocation

## Documentation Structure

**Root level (you are here):**
- `README.md` - System architecture, installation, admin guide
- `CLAUDE.md` - This file (concise AI assistant reference)

**Module-specific READMEs (detailed docs):**
- `scripts/docker/README.md` - Resource management, GPU allocation, container creation
- `scripts/user/README.md` - User commands, workflows, tier system details
- `scripts/system/README.md` - System administration, deployment, user management
- `scripts/monitoring/README.md` - Monitoring tools, dashboards, metrics collection
- `scripts/maintenance/README.md` - Cleanup automation, cron jobs, lifecycle management
- `config/README.md` - YAML configuration, resource limits, policy reference
- `testing/README.md` - Testing overview, test suites, validation procedures

## Key Paths

**Standard deployment:**
- Config: `/opt/ds01-infra/config/resource-limits.yaml`
- Scripts: `/opt/ds01-infra/scripts/`
- State: `/var/lib/ds01/` (gpu-state.json, container-metadata/)
- Logs: `/var/log/ds01/` (gpu-allocations.log, cron logs)
- User dockerfiles: `~/dockerfiles/`

**Base system:**
- AIME MLC: `/opt/aime-ml-containers`

## Essential Conventions

**Bash:**
- Use `set -e`, include usage functions
- Use `echo -e` for ANSI color codes (not plain `echo`)
- Shebang must be line 1 (no leading whitespace)

**Python:**
- Use argparse, provide `main()` function
- For heredocs in bash: Use quoted delimiter `<<'PYEOF'` and pass variables via environment

**Configuration:**
- YAML: Use `null` for unlimited/disabled
- Priority: user_overrides (100) > groups (varies) > defaults
- Logging: Pipe-delimited format `timestamp|event|user|container|gpu_id|reason`

**Commands:**
- All support `-h`, `--help`, `--info`
- Tier 2 support `--guided` for educational mode
- Image naming: `{project}-image` format

## Quick Testing

**Resource limits:**
```bash
python3 scripts/docker/get_resource_limits.py <username>
```

**GPU allocator:**
```bash
python3 scripts/docker/gpu_allocator.py status
python3 scripts/docker/gpu_allocator.py allocate <user> <container> <max_gpus> <priority>
```

**Validate YAML:**
```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
```

See module-specific READMEs for detailed testing procedures.

## Common Operations

**Add user to docker:**
```bash
sudo scripts/system/add-user-to-docker.sh <username>
```

**Update symlinks:**
```bash
sudo scripts/system/update-symlinks.sh
```

**Setup systemd slices:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

**Monitor system:**
```bash
ds01-dashboard                           # Admin dashboard
python3 scripts/docker/gpu_allocator.py status
tail -f /var/log/ds01/gpu-allocations.log
```

## Security Notes

- User isolation via AIME's UID/GID mapping
- GPU pinning via `--gpus device=X` prevents cross-user access
- Systemd cgroups prevent resource exhaustion
- Never store secrets in YAML (readable by all users)
- Never allow cgroup-parent override (bypasses limits)

## Dependencies

- Docker with NVIDIA Container Toolkit
- Python 3.8+ with PyYAML
- systemd, nvidia-smi, git, yq
- `aime-ml-containers` at `/opt/aime-ml-containers`
- `docker` group for Docker socket access
