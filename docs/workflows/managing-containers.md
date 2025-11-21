# Managing Containers

Complete guide to container lifecycle management on DS01.

---

## Container Lifecycle

```
┌─────────────┐
│   Image     │ (Blueprint)
└──────┬──────┘
       │ container-create
       ↓
┌─────────────┐
│  Created    │ (Stopped)
│  (GPU       │
│  allocated) │
└──────┬──────┘
       │ container-start or container-run
       ↓
┌─────────────┐
│   Running   │ ← container-run (enter)
└──────┬──────┘
       │ container-stop
       ↓
┌─────────────┐
│   Stopped   │ (GPU held temporarily)
└──────┬──────┘
       │ container-remove
       ↓
┌─────────────┐
│   Removed   │ (GPU freed)
└─────────────┘
       ↑
       │ Workspace and Image persist
```

---

## Basic Operations

### Create Container

```bash
# Interactive creation
container-create my-project

# Specify GPU count
container-create my-project --gpu 2

# Use specific image
container-create my-project --image ds01-$(whoami)/custom:latest
```

**What happens:**
- Checks resource limits
- Allocates GPU
- Creates container (stopped state)
- Mounts workspace

### Start Container

```bash
# Start in background
container-start my-project

# Container runs in background
# Use container-run to enter
```

### Run Container

```bash
# Start (if stopped) and enter
container-run my-project

# You're now inside:
user@my-project:/workspace$

# Exit with: exit or Ctrl+D
# Container keeps running after exit
```

### Stop Container

```bash
# Stop gracefully
container-stop my-project

# Container stopped
# GPU marked for release after timeout
```

### Remove Container

```bash
# Remove stopped container
container-remove my-project

# Force remove running container
container-remove my-project --force

# GPU freed immediately
```

---

## Orchestrated Operations

### Deploy (Create + Start)

```bash
# Interactive
container-deploy my-project

# Open terminal immediately
container-deploy my-project --open

# Start in background
container-deploy my-project --background

# Combines:
container-create my-project
container-run my-project  # or container-start
```

### Retire (Stop + Remove)

```bash
# Interactive
container-retire my-project

# Skip confirmations
container-retire my-project --force

# Also remove image
container-retire my-project --images

# Combines:
container-stop my-project
container-remove my-project
```

---

## Monitoring

### List Containers

```bash
# Running containers
container-list

# All containers (including stopped)
container-list --all

# Docker equivalent
docker ps --filter "name=._.$(whoami)"
docker ps -a --filter "name=._.$(whoami)"
```

### Resource Usage

```bash
# All your containers
container-stats

# Specific container
container-stats my-project

# Real-time monitoring
watch -n 1 container-stats
```

### Container Details

```bash
# Full inspect
docker inspect my-project._.$(whoami)

# Just GPU info
docker inspect my-project._.$(whoami) | grep -i gpu

# Mounts
docker inspect my-project._.$(whoami) | grep -A 10 Mounts
```

---

## Working with Running Containers

### Enter Running Container

```bash
# Preferred method
container-run my-project

# Docker method
docker exec -it my-project._.$(whoami) bash

# As root (debugging)
docker exec -it --user root my-project._.$(whoami) bash
```

### Run One-Off Commands

```bash
# Execute single command
docker exec my-project._.$(whoami) python --version

# Check GPU
docker exec my-project._.$(whoami) nvidia-smi

# List files
docker exec my-project._.$(whoami) ls /workspace
```

### View Logs

```bash
# All logs
docker logs my-project._.$(whoami)

# Last 100 lines
docker logs --tail 100 my-project._.$(whoami)

# Follow logs
docker logs -f my-project._.$(whoami)

# Timestamps
docker logs -t my-project._.$(whoami)
```

---

## Advanced Management

### Multiple Containers

```bash
# Check limits
cat ~/.ds01-limits  # Max Containers: 3

# Deploy multiple
container-deploy project-1 --background
container-deploy project-2 --background
container-deploy project-3 --background

# List all
container-list

# Retire all
container-retire project-1
container-retire project-2
container-retire project-3
```

### Container Restart

```bash
# Restart running container
docker restart my-project._.$(whoami)

# Stop, then start
container-stop my-project
container-start my-project
```

### Container Rename

```bash
# Rename container
docker rename my-project._.$(whoami) new-name._.$(whoami)

# Update metadata
# (DS01 tracks containers by name)
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs my-project._.$(whoami)

# Check GPU still exists
nvidia-smi

# Recreate
container-remove my-project
container-create my-project
```

### Container Stopped Unexpectedly

**Check cause:**
```bash
# Recent logs
docker logs --tail 200 my-project._.$(whoami)

# Check for OOM kill
docker inspect my-project._.$(whoami) | grep OOMKilled

# Check exit code
docker inspect my-project._.$(whoami) | grep ExitCode
```

**Common causes:**
- Out of memory (OOM)
- Idle timeout
- Max runtime exceeded
- Code crashed

**Recovery:**
```bash
# Restart
container-start my-project

# Or recreate
container-retire my-project
container-deploy my-project
```

---

## Best Practices

### 1. Retire When Done

```bash
# End of day
container-retire my-project

# Switching projects
container-retire old-project
container-deploy new-project
```

**Benefits:**
- Frees GPU for others
- Clean slate when you return
- No idle timeout worries

### 2. Monitor Resources

```bash
# Before deploying
ds01-dashboard  # Check availability

# While running
container-stats  # Check usage

# Inside container
nvidia-smi  # GPU usage
```

### 3. Use Background Mode

**For long jobs:**
```bash
# Deploy in background
container-deploy training --background

# Start training with nohup
container-run training
nohup python train.py > /workspace/logs/train.log 2>&1 &
exit

# Check later
tail ~/workspace/training/logs/train.log
```

### 4. Name Containers Meaningfully

```bash
# Good names
container-deploy transformer-training
container-deploy experiment-20231121
container-deploy baseline-model

# Bad names
container-deploy test
container-deploy asdf
container-deploy container1
```

---

## Container States Explained

### Created/Stopped

**State:**
- Container exists
- GPU allocated
- Not running

**When:**
- After `container-create`
- After `container-stop`

**Actions:**
- Can start: `container-start`
- Can remove: `container-remove`
- GPU held (for timeout period)

### Running

**State:**
- Container executing
- GPU in use
- Workspace accessible

**When:**
- After `container-start`
- After `container-run`

**Actions:**
- Can enter: `container-run`
- Can stop: `container-stop`
- Can remove: `container-remove --force`

### Removed

**State:**
- Container deleted
- GPU freed
- Can't recover (must recreate)

**When:**
- After `container-remove`
- After `container-retire`

**What persists:**
- Workspace files
- Docker image
- Can recreate identical container

---

## Automation

### Startup Scripts

Create `~/workspace/my-project/startup.sh`:
```bash
#!/bin/bash
cd /workspace
source activate myenv  # If using conda
jupyter lab --ip=0.0.0.0 --no-browser &
```

Use:
```bash
container-run my-project
/workspace/startup.sh
```

### Auto-Deploy Alias

Add to `~/.bashrc`:
```bash
alias start-work='container-deploy my-main-project --open && cd /workspace'
```

Usage:
```bash
start-work  # Instant deployment
```

---

## Quick Reference

```bash
# Lifecycle
container-deploy <proj> --open    # Create + start + enter
container-retire <proj>            # Stop + remove

# Manual control
container-create <proj>            # Create only
container-start <proj>             # Start
container-run <proj>               # Enter
container-stop <proj>              # Stop
container-remove <proj>            # Remove

# Monitoring
container-list                     # List containers
container-stats                    # Resource usage

# Inspection
docker logs <name>                 # View logs
docker inspect <name>              # Details
docker exec <name> <cmd>           # Run command
```

---

## Next Steps

**Learn workflows:**
→ [Daily Usage Patterns](daily-usage.md)

**Understand containers:**
→ [Containers Explained](../fundamentals/containers-explained.md)

**Build images:**
→ [Building Custom Images](custom-images.md)

---

**Master container management and DS01 becomes effortless!**
