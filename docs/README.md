# DS01 Infrastructure Documentation

Welcome to DS01 - a GPU-enabled container infrastructure for data science workloads.

## Choose Your Path

### 🚀 I'm Ready to Start
**Experienced with containers & HPC?** Jump right in:
- [Quick Start Guide](getting-started/quick-start.md) - Get your first container running in 5 minutes
- [Command Reference](reference/command-reference.md) - Complete command documentation

### 🎓 I'm New to This
**First time on a shared server?** We'll guide you through:
1. [Welcome to DS01](getting-started/welcome.md) - What is DS01 and why containers?
2. [First-Time Setup](getting-started/first-time-setup.md) - Complete onboarding walkthrough
3. [Understanding the Fundamentals](getting-started/choosing-your-path.md) - Learning path recommendations

---

## Documentation Sections

### Getting Started
Perfect for your first day on DS01:
- [Welcome to DS01](getting-started/welcome.md) - System overview and philosophy
- [Quick Start](getting-started/quick-start.md) - Fast track for experienced users
- [First-Time Setup](getting-started/first-time-setup.md) - Complete onboarding guide
- [Choosing Your Learning Path](getting-started/choosing-your-path.md) - Customize your learning journey

### Fundamentals
Build foundational knowledge (great for students new to servers):
- [What is a Server?](fundamentals/what-is-a-server.md) - Understanding shared computing resources
- [Linux Basics](fundamentals/linux-basics.md) - Essential commands and directory structure
- [Understanding HPC](fundamentals/understanding-hpc.md) - High-performance computing concepts
- [Containers Explained](fundamentals/containers-explained.md) - Why containers? Docker fundamentals
- [Docker Images](fundamentals/docker-images.md) - Images vs containers, building images
- [Workspaces & Persistence](fundamentals/workspaces-and-persistence.md) - What's saved, what's temporary
- [GPU Computing](fundamentals/gpu-computing.md) - Why GPUs? MIG partitioning explained

### Concepts
Understand DS01's design and industry practices:
- [Ephemeral Containers](concepts/ephemeral-containers.md) - Our container philosophy and why it matters
- [Resource Management](concepts/resource-management.md) - Fair sharing, limits, and priorities
- [Project Structure](concepts/project-structure.md) - Organizing your work effectively
- [Industry Practices](concepts/industry-practices.md) - How this prepares you for production environments

### Workflows
Day-to-day usage and common tasks:
- [Daily Usage Patterns](workflows/daily-usage.md) - Typical workflows from start to finish
- [Creating Projects](workflows/creating-projects.md) - Setting up new data science projects
- [Managing Containers](workflows/managing-containers.md) - Deploy, monitor, and retire containers
- [Building Custom Images](workflows/custom-images.md) - Install packages and frameworks
- [Working with GPUs](workflows/gpu-usage.md) - GPU allocation and monitoring
- [Collaboration](workflows/collaboration.md) - Sharing projects and working in teams

### Reference
Quick lookup documentation:
- [Command Reference](reference/command-reference.md) - All commands with examples
- [Container Commands](reference/container-commands.md) - Container lifecycle management
- [Image Commands](reference/image-commands.md) - Image building and management
- [Project Commands](reference/project-commands.md) - Project initialization and setup
- [Resource Limits](reference/resource-limits.md) - Understanding your quotas
- [Troubleshooting](reference/troubleshooting.md) - Common issues and solutions

### Advanced
Deep dives for power users:
- [Dockerfile Guide](advanced/dockerfile-guide.md) - Writing efficient Dockerfiles
- [SSH Setup](advanced/ssh-setup.md) - SSH keys and remote access
- [VSCode Remote](advanced/vscode-remote.md) - Remote development setup
- [Best Practices](advanced/best-practices.md) - Performance, security, and resource efficiency

---

## Quick Reference Card

### Most Common Commands

```bash
# First-time setup (run once)
user-setup                           # Complete onboarding wizard

# Daily workflow
container-deploy my-project          # Create and start container
container-retire my-project          # Stop and remove (free GPU)
container-list                       # View your containers

# Building custom images
image-create                         # Interactive image builder
image-list                           # View your images

# Project management
project-init                         # Create new project workspace
```

### Getting Help

```bash
# Command help
container-deploy --help              # Show command options
image-create --guided                # Educational mode with explanations

# System status
ds01-dashboard                       # View system resources
container-stats                      # Your resource usage
```

---

## Support & Resources

- **System Status**: Run `ds01-dashboard` to view available GPUs and system health
- **Your Limits**: Check `~/.ds01-limits` for your resource allocations
- **Troubleshooting**: See [Troubleshooting Guide](reference/troubleshooting.md)
- **Admin Contact**: Contact your system administrator for account issues

---

## About This Documentation

This documentation is organized for different learning styles:
- **Task-oriented**: Jump to Workflows for step-by-step guides
- **Understanding-focused**: Read Fundamentals and Concepts
- **Reference-style**: Use Reference section for quick lookups

You don't need to read everything linearly - follow the path that makes sense for your background and goals.

---

**Next Steps:**
- New users: Start with [Welcome to DS01](getting-started/welcome.md)
- Experienced users: Jump to [Quick Start](getting-started/quick-start.md)
- Need something specific? Check [Command Reference](reference/command-reference.md)
