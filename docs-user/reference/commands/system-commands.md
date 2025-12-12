# System Commands

Commands for system status, user setup, and configuration.

---

## Quick Reference

```bash
# System dashboard
dashboard

# First-time setup
user-setup

# Check your limits
check-limits

# SSH and VSCode setup
ssh-setup
vscode-setup

# Help and info
help                     # List all commands
version                  # Show version
```

---

## dashboard

**System status dashboard**

```bash
dashboard [OPTIONS]
```

View GPU availability, container status, and system resources.

**Options:**
| Option | Description |
|--------|-------------|
| `--watch`, `-w` | Continuous monitoring (2s refresh) |
| `--full` | Show all sections expanded |
| `--json` | JSON output for scripting |
| `gpu` | GPU/MIG utilisation only |
| `system` | System resources only |
| `containers` | Container list only |
| `users` | Per-user breakdown |

**Examples:**
```bash
dashboard              # Default view
dashboard --watch      # Live monitoring
dashboard gpu          # GPU section only
dashboard users        # User resource summary
```

---

## user-setup

**Complete onboarding wizard** (L4 wizard)

```bash
user-setup
```

**Aliases:** `user setup`, `new-user`

**What it does:**
1. `ssh-setup` - Creates SSH keys
2. `project-init` - Initializes first project
3. `vscode-setup` - Configures VSCode Remote (optional)

**Time:** 15-20 minutes

**See:** [First-Time Setup Guide](../../getting-started/first-time-setup.md)

---

## check-limits

**View your resource limits and usage**

```bash
check-limits
```

**Example output:**
```
=== Your Resource Limits ===
Max GPUs:       2
Max Containers: 3
Memory/Container: 64GB
Max Runtime:    24h (varies by user)
Idle Timeout:   0.5h (varies by user)

=== Current Usage ===
GPUs:       1 / 2
Containers: 2 / 3
```

---

## ssh-setup

**Configure SSH keys** (L2 atomic)

```bash
ssh-setup [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--guided` | Show detailed explanations for beginners |
| `--force` | Regenerate keys even if they exist |
| `--verify` | Just verify existing setup |

**Examples:**
```bash
ssh-setup              # Interactive setup
ssh-setup --guided     # With explanations
ssh-setup --verify     # Check existing setup
```

**What it does:**
1. Generates SSH key pair (ed25519)
2. Displays public key (add to GitHub/GitLab)
3. Verifies configuration

---

## vscode-setup

**Configure VSCode Remote** (L2 atomic)

```bash
vscode-setup
```

**Example:**
```bash
vscode-setup
# Generates VSCode config for remote development
```

**See:** [VSCode Remote Guide](../../core-guides/vscode-remote.md)

---

## shell-setup

**Fix PATH configuration**

```bash
shell-setup [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--check` | Verify PATH only |
| `--force` | Overwrite existing config |

**Examples:**
```bash
shell-setup --check   # Verify PATH
shell-setup           # Fix PATH
```

**Use when:** DS01 commands not found in PATH

---

## jupyter-setup

**Configure Jupyter Lab access**

```bash
jupyter-setup [OPTIONS]
```

Configures Jupyter Lab access for the DS01 server.

**Options:**
| Option | Description |
|--------|-------------|
| `--guided` | Full setup with detailed explanations |
| `--port-forward` | Show SSH port forwarding commands only |
| `--brief` | Minimal output (for orchestrators) |

**Examples:**
```bash
jupyter-setup                 # Quick VS Code Jupyter extension setup
jupyter-setup --guided        # Full guided setup
jupyter-setup --port-forward  # Just port forwarding commands
```

**Use when:** Setting up Jupyter Lab access from your local machine.

---

## help

**Show all available commands**

```bash
help
```

Lists all DS01 commands organised by category (containers, images, system, etc.).

**Alias:** `commands` (identical functionality)

**Example:**
```bash
help
# Shows categorised list of all DS01 commands
```

---

## version

**Show DS01 version information**

```bash
version
```

Displays the current DS01 infrastructure version and build information.

---

## Getting Help

### Command Help
All commands support `--help`:
```bash
container-deploy --help
image-create --help
```

### Guided Mode
Most commands support `--guided`:
```bash
container-deploy my-project --guided
image-create --guided
```

**Guided mode:**
- Explains each step
- Educational prompts
- Recommended for beginners

---

## Environment Variables

### DS01 Variables
```bash
DS01_LIMITS_FILE=~/.ds01-limits
DS01_INSTALL_DIR=/opt/ds01-infra
DS01_WORKSPACE=~/workspace
```

### Docker Variables
```bash
DOCKER_HOST=unix:///var/run/docker.sock
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Resource unavailable (no GPUs, quota exceeded) |
| 4 | Container/image not found |
| 5 | Permission denied |

**Check exit code:**
```bash
container-deploy my-project
echo $?
```

---

## See Also

- [Container Commands](container-commands.md)
- [Getting Started](../../getting-started/)
- [Troubleshooting](../../troubleshooting/)
