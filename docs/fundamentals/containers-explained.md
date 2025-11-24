# Containers Explained

Containers are the foundation of DS01. This guide explains what they are, why we use them, and how they work - no prior Docker knowledge required.

---

## The Problem Containers Solve

### Scenario: 20 Data Scientists, One Server

**Without containers:**
- Alice installs PyTorch 2.8.0 globally → breaks Bob's code (needs 2.5.0)
- Charlie runs `pip install` as root → corrupts system Python
- Dana's experiment uses 100% RAM → crashes everyone's work
- Eve needs TensorFlow, Frank needs JAX → package conflicts
- GPU conflicts when multiple people want GPU:0

**This is chaos.** You can't have 20 people modifying one shared environment.

### The Solution: Isolation

**Containers provide:**
- **Isolated environments**: Your packages don't affect others
- **Resource limits**: Your code can't monopolize CPU/RAM
- **Reproducibility**: Same environment every time
- **GPU sharing**: Fair allocation without conflicts

**Think of containers like apartments in a building:**
- Each apartment (container) is isolated
- Shared utilities (power, water) = shared hardware (CPU, RAM, GPU)
- Can't hear/affect neighbors
- Building manager (DS01) ensures fair resource usage

---

## What is a Container?

### Simple Definition

**A container is a lightweight, isolated environment that runs your code with its own libraries, dependencies, and filesystem - without needing a separate operating system.**

### Key Characteristics

**Isolation:**
- Your own filesystem (can't see others' files)
- Your own processes (can't interfere with others)
- Your own network (optional isolation)
- Shared kernel (Linux kernel used by all)

**Lightweight:**
- Starts in seconds (vs minutes for VMs)
- Uses MBs of overhead (vs GBs for VMs)
- Shares host OS kernel

**Portable:**
- Same container runs on your laptop, DS01, AWS, anywhere
- "Works on my machine" → "Works everywhere"

---

## Containers vs Virtual Machines

### Virtual Machines (VMs)

```
┌─────────────────────────────────────┐
│        Your Laptop (Host)           │
├─────────────────────────────────────┤
│  ┌───────────┐  ┌───────────┐      │
│  │   VM 1    │  │   VM 2    │      │
│  ├───────────┤  ├───────────┤      │
│  │ Guest OS  │  │ Guest OS  │      │ ← Full OS per VM (GBs)
│  │ (Linux)   │  │ (Windows) │      │
│  ├───────────┤  ├───────────┤      │
│  │   App 1   │  │   App 2   │      │
│  └───────────┘  └───────────┘      │
├─────────────────────────────────────┤
│        Hypervisor (VMware)          │
├─────────────────────────────────────┤
│        Host OS (macOS)              │
└─────────────────────────────────────┘
```

**Characteristics:**
- Each VM has full OS (5-20GB)
- Slow to start (minutes)
- Heavy resource usage
- Strong isolation

### Containers

```
┌─────────────────────────────────────┐
│         DS01 Server (Host)          │
├─────────────────────────────────────┤
│  ┌──────────┐ ┌──────────┐ ┌─────┐ │
│  │Container1│ │Container2│ │Cont3│ │ ← MBs per container
│  ├──────────┤ ├──────────┤ ├─────┤ │
│  │  App 1   │ │  App 2   │ │App 3│ │
│  │Libraries │ │Libraries │ │Libs │ │
│  └──────────┘ └──────────┘ └─────┘ │
├─────────────────────────────────────┤
│       Container Runtime (Docker)    │
├─────────────────────────────────────┤
│         Host OS (Linux)             │ ← Shared kernel
└─────────────────────────────────────┘
```

**Characteristics:**
- Share host OS kernel
- Fast to start (seconds)
- Lightweight (MBs)
- Good isolation (sufficient for most cases)

### Comparison

| Feature | Virtual Machines | Containers |
|---------|-----------------|-----------|
| **Isolation** | Full (separate OS) | Process-level |
| **Startup time** | Minutes | Seconds |
| **Size** | GBs (5-20GB) | MBs (100-500MB) |
| **Performance** | Slower (overhead) | Near-native |
| **Resource usage** | Heavy | Light |
| **Use case** | Different OS needs | App isolation |

**For DS01:** Containers are perfect - lightweight, fast, isolated enough.

---

## Docker: The Container Platform

### What is Docker?

**Docker** is the most popular container platform. It provides:
- **Engine**: Runs containers
- **Images**: Blueprints for containers
- **Registry**: Store and share images
- **Tools**: Build, manage, deploy containers

**Analogy:**
- Docker = Construction company
- Image = Blueprint
- Container = Building built from blueprint

### Images vs Containers

**Docker Image:**
- **Blueprint** for a container
- Contains: OS base, Python, libraries, your code
- Stored on disk
- Read-only
- Can create many containers from one image

**Docker Container:**
- **Running instance** of an image
- Has: Running processes, writable filesystem
- Can be started, stopped, removed
- Ephemeral (temporary)

**Analogy:**
- Image = Class definition (in programming)
- Container = Object instance

**Example:**
```bash
# Image (blueprint)
ds01-alice/my-project:latest
  - Ubuntu 22.04
  - Python 3.10
  - PyTorch 2.8.0
  - My packages (transformers, pandas)

# Containers (instances)
Container 1: my-project._.alice (running)
Container 2: experiment-1._.alice (stopped)

# Both created from same image, but separate instances
```

---

## How Containers Provide Isolation

### 1. Filesystem Isolation

**Each container has its own filesystem:**
```bash
# Inside Container A
$ ls /
bin  boot  dev  home  workspace  ...

# Inside Container B
$ ls /
bin  boot  dev  home  workspace  ...  # Same structure, different files

# Container A cannot see Container B's files
```

**Exception:** Mounted volumes (intentional sharing)
- DS01 mounts `~/workspace/<project>/` → `/workspace` in container
- Persistent storage that survives container removal

### 2. Process Isolation

**Each container sees only its own processes:**
```bash
# Container A
$ ps aux
USER  PID  COMMAND
alice 1    /bin/bash
alice 34   python train.py

# Container A cannot see/kill Container B's processes
```

### 3. Network Isolation

**Each container can have its own network:**
- Own IP address (optional)
- Own ports
- Can't interfere with other containers' network

### 4. Resource Limits (Cgroups)

**Linux control groups** limit resources:
```bash
# DS01 configures for each container:
--memory="64g"              # Max 64GB RAM
--cpus="16"                 # Max 16 CPU cores
--gpus="device=0:1"         # Specific GPU allocation
```

**Your container can't:**
- Use more than allocated RAM (process killed if exceeded)
- Use more CPU than allocated
- Access GPUs not assigned to you

---

## DS01's Container Architecture

### Three Layers

**Layer 1: AIME ML Containers (Base System)**
- 150+ pre-built images with ML frameworks
- PyTorch 2.8.0, TensorFlow 2.16, JAX 0.4.23
- CUDA drivers, cuDNN libraries
- Jupyter Lab, common tools

**Layer 2: DS01 Management**
- GPU allocation and scheduling
- Resource limit enforcement
- User isolation (UID mapping)
- Automated lifecycle management

**Layer 3: Your Custom Images**
- Built on top of AIME images
- Your additional packages
- Your configurations
- Your data and code

### Container Lifecycle on DS01

```
┌──────────────────────────────────────┐
│  1. Build Custom Image               │
│     (image-create)                   │
│     - Choose base: PyTorch 2.8.0     │
│     - Add packages: transformers     │
│     - Result: ds01-alice/proj:latest │
└─────────────┬────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  2. Deploy Container                 │
│     (container-deploy)               │
│     - Allocate GPU                   │
│     - Set resource limits            │
│     - Mount workspace                │
│     - Start container                │
└─────────────┬────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  3. Work Inside Container            │
│     - Train models                   │
│     - Run experiments                │
│     - Files saved to /workspace      │
└─────────────┬────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  4. Retire Container                 │
│     (container-retire)               │
│     - Stop container                 │
│     - Release GPU                    │
│     - Remove container instance      │
│     - Workspace files remain safe    │
└──────────────────────────────────────┘
```

**Image persists** - Can recreate container anytime
**Workspace persists** - Your code and data safe

---

## Inside a Container

### What You See

When you enter a container:
```bash
$ container-run my-project

# Now inside container
alice@my-project:/workspace$ pwd
/workspace

alice@my-project:/workspace$ ls
data/  models/  notebooks/  train.py

alice@my-project:/workspace$ nvidia-smi
# Shows your allocated GPU

alice@my-project:/workspace$ python
Python 3.10.12 (main, ...)
>>> import torch
>>> torch.cuda.is_available()
True
```

### Your Environment

**Inside container, you have:**
- Linux shell (bash)
- Python with packages (PyTorch, etc.)
- GPU access (nvidia-smi works)
- Workspace mounted at `/workspace`
- Network access (can download datasets)
- Root-like capabilities (can pip install)

**You don't have:**
- Access to host system files (except workspace)
- Access to other containers
- Ability to affect host system
- GPUs not allocated to you

---

## Container Namespaces

### What are Namespaces?

**Linux namespaces** provide isolation:

**1. PID Namespace:**
- Processes inside container see different PIDs
- Process 1 in container ≠ Process 1 on host
- Can't see host processes

**2. Mount Namespace:**
- Different filesystem view
- Own `/tmp`, `/var`, etc.
- Mounted volumes (like workspace) are shared

**3. Network Namespace:**
- Own network interfaces
- Own IP address (if configured)
- Can bind to same ports as other containers

**4. User Namespace:**
- UID mapping: You appear as "alice" inside, but different UID outside
- Security: Root inside ≠ root outside

**5. UTS Namespace:**
- Own hostname
- `hostname` inside shows container name

---

## Why Containers Matter for Data Science

### 1. Reproducibility

**Problem:**
"My code works on my laptop but not on the server"

**Solution:**
Same container runs everywhere. Dockerfile = reproducible recipe.

```dockerfile
FROM pytorch:2.8.0
RUN pip install transformers==4.30.0 datasets==2.14.0
```

Anyone can rebuild exact same environment.

### 2. Dependency Management

**Problem:**
Project A needs TensorFlow 2.16, Project B needs 2.10

**Solution:**
Each container has its own dependencies.

```bash
# Container A
python -c "import tensorflow; print(tensorflow.__version__)"
# 2.16.1

# Container B (different container)
python -c "import tensorflow; print(tensorflow.__version__)"
# 2.10.1
```

### 3. Resource Management

**Problem:**
Runaway process uses all RAM, crashes everyone's work

**Solution:**
Container limited to allocated resources.

```bash
# Your container gets:
--memory="64g"          # Killed if exceeds 64GB
--cpus="16"             # Can't use more than 16 cores
```

### 4. GPU Sharing

**Problem:**
Multiple users want GPUs, conflicts occur

**Solution:**
Container gets dedicated GPU allocation.

```bash
# Container A gets GPU 0:0
nvidia-smi
# Shows only GPU 0:0

# Container B gets GPU 0:1
nvidia-smi
# Shows only GPU 0:1
```

### 5. Experiment Tracking

**Problem:**
"What environment did I use for experiment #42?"

**Solution:**
Docker image tag = environment snapshot.

```bash
# Tag image for experiment
docker tag ds01-alice/project:latest ds01-alice/project:experiment-42

# Later: Recreate exact environment
container-deploy --image ds01-alice/project:experiment-42
```

---

## Industry Use of Containers

### Production ML Systems

**Model Training:**
```
AWS SageMaker → Spin up container with PyTorch
              → Train model
              → Save weights to S3
              → Terminate container
```

**Model Serving:**
```
Kubernetes → Deploy model in container
           → Scale to 100 replicas
           → Load balance requests
           → Update via rolling deployment
```

### Software Development

**Microservices:**
- Each service runs in container
- Independent scaling
- Isolated failures
- Easy deployment

**CI/CD Pipelines:**
```
GitHub Actions → Run tests in container
              → Build in container
              → Deploy container to production
```

### Data Engineering

**Airflow/Prefect:**
- Each data pipeline task = container
- Isolated execution
- Resource guarantees
- Retry failed containers

**Spark:**
- Spark drivers/executors in containers
- Kubernetes as scheduler
- Dynamic scaling

---

## DS01 vs Standard Docker

### What's Different?

| Standard Docker | DS01 |
|----------------|------|
| `docker run ...` | `container-deploy` (handles GPU allocation) |
| Manual GPU flags | Automatic GPU scheduling |
| No resource limits | Enforced systemd cgroups |
| Root inside = dangerous | User namespace isolation |
| Manual volume mounts | Auto-mount workspace |

### What's the Same?

- Docker images work identically
- Dockerfiles unchanged
- `docker` commands still available
- Container concepts identical

### Why DS01 Commands?

**DS01 commands add:**
- GPU allocation logic
- Resource limit enforcement
- User-friendly prompts
- State tracking
- Automated cleanup

**You could use Docker directly, but DS01 commands handle complexity for you.**

---

## Common Questions

### "Do I need to learn Docker?"

**Basic DS01 usage:** No, use `container-deploy` and `image-create`
**Custom images:** Basic Dockerfile knowledge helpful
**Advanced usage:** Docker knowledge useful for debugging

**DS01 abstracts Docker complexity - learn as needed.**

### "Can I run Docker commands directly?"

**Yes!** DS01 doesn't restrict Docker access.

```bash
docker ps                   # List containers
docker logs container-name  # View logs
docker exec -it container-name bash  # Enter container
```

**But prefer DS01 commands for creation/management.**

### "Are containers secure?"

**Sufficient isolation for shared academic/research environment:**
- Can't access other users' files
- Can't interfere with other processes
- Resource limits prevent monopolization
- User namespace prevents privilege escalation

**Not absolute security:**
- Kernel vulnerabilities could affect all
- Not for truly hostile multi-tenancy
- Fine for collaborative academic use

### "What happens to my files?"

**Container filesystem:**
- Ephemeral (deleted on container removal)
- Don't save important files here

**Mounted workspace (`/workspace`):**
- Persistent (survives container removal)
- Backed up
- **Always save important work here**

### "Can I have multiple containers?"

**Yes!** Within your resource limits.

```bash
# Check limits
cat ~/.ds01-limits
# Max Containers: 3

# Run multiple
container-deploy project-1
container-deploy project-2
container-deploy project-3
```

Typical use: Different projects or experiments.

---

## Best Practices

### 1. Save Everything Important in Workspace

```bash
# Inside container
cd /workspace               # Your persistent directory

# Good
/workspace/code/
/workspace/data/
/workspace/models/

# Bad
/tmp/important-results.csv  # Lost when container removed
/home/alice/data/           # Not in workspace, won't persist
```

### 2. Build Custom Images for Projects

```bash
# Don't: Install packages every time
container-run my-project
pip install transformers datasets  # Slow, non-reproducible

# Do: Build custom image
image-create  # Add packages to image
container-deploy my-project  # Packages pre-installed
```

### 3. Retire Containers When Done

```bash
# Free GPU for others
container-retire my-project

# Don't leave containers running idle
# (Auto-stopped after idle timeout anyway)
```

### 4. Use Tags for Experiments

```bash
# Snapshot working environment
docker tag ds01-alice/project:latest ds01-alice/project:working-baseline

# Experiment with new packages
image-update project

# Can always return to baseline
container-deploy --image ds01-alice/project:working-baseline
```

---

## Troubleshooting

### Container Won't Start

**Check:**
```bash
# GPU available?
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py status

# Resource limits reached?
cat ~/.ds01-limits
container-list  # How many running?
```

### Can't Find Files

**Remember:**
- Host: `~/workspace/my-project/`
- Container: `/workspace/`

```bash
# On host
ls ~/workspace/my-project/

# In container
ls /workspace/
```

### Package Not Found

**Inside container:**
```bash
pip list | grep torch       # Check if installed
pip install torch           # Install (temporary)
```

**Permanent solution:**
```bash
# Exit container
exit

# Update image
image-update my-project     # Add to Dockerfile
```

---

## Next Steps

### Understand Storage

**Learn persistence:**
→ [Workspaces & Persistence](workspaces-and-persistence.md)

### Build Custom Images

**Create your environment:**
→ [Building Custom Images](../workflows/custom-images.md)
→ [Dockerfile Guide](../advanced/dockerfile-guide.md)

### Daily Usage

**Put knowledge into practice:**
→ [Daily Usage Patterns](../workflows/daily-usage.md)
→ [Managing Containers](../workflows/managing-containers.md)

---

## Summary

**Key Takeaways:**

1. **Containers = Isolated environments** for running your code
2. **Lightweight & fast** - seconds to start, MBs of overhead
3. **Images = blueprints**, Containers = running instances
4. **Isolation via namespaces & cgroups** - can't interfere with others
5. **Industry-standard** - same tech as AWS, Kubernetes, production ML
6. **DS01 abstracts complexity** - use simple commands, get powerful features

**Containers enable fair sharing of powerful hardware while giving you freedom to customize your environment.**

**Ready to build images?** → [Docker Images](docker-images.md)

**Want to start using containers?** → [First-Time Setup](../getting-started/first-time-setup.md)
