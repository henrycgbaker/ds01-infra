# VS Code + Container Setup Guide

## Overview

There are **two ways** to use VS Code with DS01 containers. Choose based on your workflow:

1. **Remote SSH** (Edit on host, run in container via terminal)
2. **Dev Containers** (Entire VS Code session runs inside container) ← **RECOMMENDED**

---

## Method 1: Remote SSH (Traditional)

**What happens:**
- VS Code connects to DS01 host via SSH
- You edit files in `~/workspace/your-project`
- You manually enter containers via integrated terminal
- Code runs in container, but IDE is on host

**Setup:**
```bash
# 1. In VS Code, install "Remote - SSH" extension

# 2. Connect to DS01
#    Cmd+Shift+P → "Remote-SSH: Connect to Host"
#    Enter: username@ds01-server

# 3. Open your project folder
#    File → Open Folder → ~/workspace/your-project

# 4. To run code, open terminal and enter container:
container-run my-project
```

**Pros:**
- Simple setup
- Edit multiple projects simultaneously
- Easy to switch between containers

**Cons:**
- Python intellisense uses HOST Python (not container)
- Debugger runs on HOST (not in container)
- Jupyter kernels are on HOST (not container GPUs)
- **NOT A TRUE CONTAINERIZED WORKFLOW**

---

## Method 2: Dev Containers (Recommended for ML)

**What happens:**
- VS Code connects DIRECTLY to running container
- Entire IDE session runs inside container
- Python interpreter, debugger, Jupyter ALL use container
- GPU-accelerated code execution
- **TRUE CONTAINERIZED WORKFLOW** ✅

### Setup Steps:

#### 1. Install Extensions (on your local machine)
```
- Dev Containers (ms-vscode-remote.remote-containers)
- Remote - SSH (ms-vscode-remote.remote-ssh)
```

#### 2. Start Your Container on DS01
```bash
# SSH to DS01 first
ssh username@ds01-server

# Create/start your container
container-run my-project
# Exit with Ctrl+P, Ctrl+Q (keeps it running)
```

#### 3. Connect VS Code to Container

**Option A: Via SSH Tunnel (Recommended)**
```bash
# On your local machine, create SSH tunnel:
ssh -L 2222:localhost:2222 username@ds01-server

# In another terminal on DS01:
docker exec -it my-project._.$(id -u) socat TCP-LISTEN:2222,fork,reuseaddr UNIX-CONNECT:/var/run/docker.sock

# In VS Code:
# Cmd+Shift+P → "Dev Containers: Attach to Running Container..."
# Select your container
```

**Option B: Direct Attach (if on DS01 network)**
```
1. Cmd+Shift+P → "Remote-SSH: Connect to Host" → ds01-server
2. Cmd+Shift+P → "Dev Containers: Attach to Running Container..."
3. Select container: my-project._.1001
```

#### 4. Verify Container Session

Once connected, verify you're INSIDE the container:

```bash
# In VS Code integrated terminal:
pwd
# Should show: /workspace

hostname
# Should show your container name

which python
# Should show container's Python, not host

nvidia-smi
# Should show GPU (if container has GPU access)
```

### Working in Dev Container Mode:

**File Editing:**
- Files in `/workspace` are your persistent workspace
- Edit directly in VS Code

**Running Code:**
- Terminal → runs inside container automatically
- Python interpreter → uses container's Python
- Debugger → debugs inside container
- Jupyter → kernels run in container with GPU access

**Installing Packages:**
```bash
# In VS Code terminal (already inside container):
pip install transformers
# Installs to container environment
```

**GPU Access:**
```python
import torch
print(torch.cuda.is_available())  # Should be True
```

---

## Verifying Your Setup

### ✅ Correct Setup (Running in Container):

```bash
# Check prompt
user@my-project:/workspace$  # Container hostname

# Check Python
which python
# /opt/conda/bin/python (or similar container path)

# Check packages
pip list | grep torch
# Shows container's packages

# Check workspace
ls /workspace
# Shows your project files
```

### ❌ Wrong Setup (Running on Host):

```bash
# Check prompt
user@ds01:/home/username/workspace$  # DS01 hostname

# Check Python
which python
# /usr/bin/python or /home/username/.local/...

# No GPU access in Python
python -c "import torch; print(torch.cuda.is_available())"
# False or module not found
```

---

## Recommended Workflow

### For ML Development:

1. **Use Dev Containers** (Method 2)
2. Connect VS Code directly to running container
3. All development happens in container
4. GPU acceleration works automatically
5. Dependencies are isolated

### For Multi-Project Editing:

1. **Use Remote SSH** (Method 1)
2. Edit files on host
3. Run code by entering containers as needed
4. Good for quick edits across projects

---

## Common Issues

### "Cannot find Python interpreter"
- **Cause:** VS Code is on host, not in container
- **Fix:** Use Dev Containers to attach to container directly

### "CUDA not available"
- **Cause:** Python running on host, not container
- **Fix:** Verify you're in container (check `hostname`)

### "Package not found"
- **Cause:** Using host Python, not container Python
- **Fix:** Use Dev Containers or manually enter container first

### "Permission denied accessing /var/run/docker.sock"
- **Cause:** Container doesn't have docker socket mounted
- **Fix:** Recreate container with `container-create` (new containers have it)

### "Command not found inside container"
- **Cause:** Old container created before DS01 updates
- **Fix:** Create new container - all host commands now work inside containers too

---

## Summary

**For true containerized ML workflows:**
✅ Use **Dev Containers** extension
✅ Attach to running container
✅ Verify with `hostname` and `which python`
✅ All code runs in container with GPU access
✅ All DS01 commands work inside containers (container-list, image-list, etc.)

**Quick editing across projects:**
✅ Use **Remote SSH**
✅ Enter containers manually when running code
✅ Can still manage containers from inside with `container-list`, `container-run`

**Note:** As of latest updates, ALL host commands are available inside containers through docker socket mounting. This means you can manage containers from within containers, list images, etc. - providing a consistent command experience regardless of context.

Choose based on your needs!
