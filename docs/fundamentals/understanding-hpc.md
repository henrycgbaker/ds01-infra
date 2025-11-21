# Understanding HPC

High-Performance Computing (HPC) concepts for DS01 users. Learn about shared resources, fair scheduling, and cluster computing.

---

## What is HPC?

**High-Performance Computing** = Using powerful, shared computing resources for intensive workloads.

**Key characteristics:**
- **Powerful hardware** - More CPUs, RAM, GPUs than personal computers
- **Shared resources** - Multiple users accessing same infrastructure
- **Fair scheduling** - System ensures everyone gets their turn
- **Batch processing** - Submit jobs, system runs them when resources available

**DS01 is an HPC system** specialized for data science and ML.

---

## HPC vs Personal Computing

| Personal Computer | HPC System (DS01) |
|------------------|-------------------|
| One user | Many users (10-100+) |
| All resources yours | Fair sharing with limits |
| Use anytime | May wait for resources |
| Install anything | Containerized environments |
| Physical access | Remote access (SSH) |
| Consumer hardware | Enterprise hardware |

---

## Core HPC Concepts

### 1. Resource Scheduling

**Problem:** 10 users want GPUs, only 8 available

**Solution:** Priority scheduling
- Higher priority users first
- Fair queuing for equal priority
- Time limits prevent monopolization

**DS01 equivalent:**
```yaml
# config/resource-limits.yaml
priority: 50  # Higher = higher priority
max_gpus: 2   # Per-user limit
```

### 2. Fair Share

**Principle:** Resources distributed fairly among users/groups

**DS01 implementation:**
- Per-user GPU limits (typically 1-2)
- Per-user container limits
- Idle timeouts free resources
- Priority can be adjusted by admin

### 3. Resource Limits (Quotas)

**Prevent monopolization:**
```bash
# Your limits
cat ~/.ds01-limits

# Example:
Max GPUs: 2
Max Containers: 3
Memory per container: 64GB
Max Runtime: 168h (1 week)
Idle Timeout: 48h
```

### 4. Batch Jobs vs Interactive

**Interactive (DS01 default):**
- Immediate access to container
- Work interactively (code, test, debug)
- Like SSH into a machine

**Batch (HPC traditional):**
- Submit job script
- Job queues
- Runs when resources available
- No interaction while running

**DS01 supports both:**
```bash
# Interactive
container-deploy my-project --open

# Batch-style
container-deploy training --background
# Then check results later
```

---

## HPC Terminology

| HPC Term | DS01 Equivalent |
|----------|----------------|
| **Node** | DS01 server |
| **Core** | CPU core |
| **Job** | Container |
| **Queue** | Resource allocation waiting |
| **Walltime** | Max runtime limit |
| **Scheduler** | GPU allocator + resource manager |
| **Allocation** | Resource limits (YAML config) |

---

## Best Practices from HPC

### 1. Be a Good Citizen

**Do:**
- Retire containers when done
- Use appropriate resources (don't request max if you need less)
- Monitor your usage
- Report issues

**Don't:**
- Leave containers idle for days
- Monopolize all GPUs
- Run personal/non-research workloads
- Ignore resource limits

### 2. Optimize for Shared Resources

**Efficient resource use:**
```python
# Load data efficiently (don't load everything into RAM)
dataset = LazyDataset(...)  # Load on demand

# Use appropriate batch size
batch_size = 32  # Don't use 1 if 32 works

# Checkpoint and resume
# (System may need to stop your job)
torch.save(checkpoint, 'latest.pt')
```

### 3. Plan for Wait Times

**You might not get resources immediately:**
- Check availability before starting
- Plan work around peak/off-peak hours
- Have backup tasks for while waiting

```bash
# Check before starting
ds01-dashboard

# If GPUs busy, work on other tasks:
# - Write code (no GPU needed)
# - Prepare data
# - Review results
```

---

## DS01 in the HPC Landscape

### Traditional HPC (SLURM, PBS)

```bash
# SLURM example
sbatch --gres=gpu:1 --time=24:00:00 train.sh
# Job queued, runs when resources available
```

**DS01 equivalent:**
```bash
container-deploy training --gpu 1 --background
# Immediately allocated if available
```

**DS01 is simpler but same concepts**

### Cloud HPC (AWS, GCP)

**AWS:**
```bash
# Request EC2 instance with GPU
aws ec2 run-instances --instance-type p3.2xlarge

# Pay per hour
# Terminate when done
```

**DS01:**
```bash
container-deploy my-project --gpu 1
# Free (included in allocation)
container-retire my-project
# Doesn't cost money, but frees GPU for others
```

**Same workflow, different scale**

---

## Skills You're Learning

**Working on DS01 teaches:**
1. **Resource awareness** - Computing isn't free/unlimited
2. **Fair sharing** - Collaboration in shared environments
3. **Efficiency** - Optimize to use less resources
4. **Planning** - Design experiments within constraints
5. **Cloud-readiness** - AWS/GCP work similarly

**These skills transfer to:**
- Cloud computing (AWS, GCP, Azure)
- University HPC clusters
- Corporate HPC systems
- Production ML systems

---

## When DS01 Acts Like HPC

**Scenarios you'll encounter:**

### 1. Waiting for Resources

```bash
$ container-deploy my-project
Info: No GPUs currently available
Info: 3 users ahead in queue
```

**This is normal in shared systems**

### 2. Time Limits

```
Your container has been running for 160h (max: 168h)
Warning: Will be stopped in 8 hours
```

**Prevents indefinite resource holds**

### 3. Idle Timeouts

```
Container idle for 47h (limit: 48h)
Warning: Will be stopped if idle continues
```

**Frees unused resources**

### 4. Quota Exceeded

```
Cannot deploy: At maximum container limit (3/3)
```

**Ensures fair distribution**

---

## Next Steps

**Understand resources:**
→ [Resource Management](../concepts/resource-management.md)
→ [GPU Computing](gpu-computing.md)

**Learn workflows:**
→ [Daily Usage Patterns](../workflows/daily-usage.md)

**See limits:**
→ [Resource Limits Reference](../reference/resource-limits.md)

---

## Summary

**Key Takeaways:**

1. **HPC = Shared, powerful computing** with fair scheduling
2. **DS01 uses HPC principles** - limits, scheduling, timeouts
3. **Be a good citizen** - Retire containers, use appropriately
4. **Skills transfer** to cloud, clusters, production systems
5. **Resource awareness** is professional skill

**Understanding HPC context makes you a better DS01 user and prepares you for production computing environments.**
