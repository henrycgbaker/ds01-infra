# DS01 Infrastructure - Container Management System

NEED TO UPDATE

## 🏗️ System Architecture

### Overview

The container management system consists of:

1. **Base System**: `aime-ml-containers`
   - Provides core container lifecycle management
   - Image repository with versioned ML frameworks
   - User-specific container isolation

2. **Enhancement Layer**: `ds01-infra` 
   - Resource limits and quotas
   - GPU allocation management  
   - Auto-cleanup of idle containers
   - Monitoring and metrics

3. **User Interface**: Enhanced `mlc-*` CLI commands
   - Student-friendly wrapper scripts
   - Config-driven resource allocation
   - Automatic defaults

### Directory Structure

UPDATE THIS

```
ds01-infra/
├── config/
│   ├── resource-limits.yaml          # Central resource configuration
│   └── container-templates/          # Docker Compose templates (future)
│
├── scripts/
│   ├── docker/
│   │   ├── mlc-create-enhanced       # Main wrapper script
│   │   ├── get_resource_limits.py    # Config parser
│   │   ├── gpu-user-allocation.sh    # GPU tracking
│   │   └── docker-launch.sh          # Low-level launcher
│   │
│   ├── maintenance/
│   │   ├── cleanup-idle-containers.sh
│   │   └── setup-scratch-dirs.sh
│   │
│   └── monitoring/
│       ├── gpu-monitor.sh
│       └── log-metrics-5min.sh
│
└── docs-admin/
    ├── architecture.md
    ├── installation.md
    └── maintenance.md
```

---

## 🔧 Configuration Management

### Resource Limits Config (`config/resource-limits.yaml`)

The central configuration file controlling all resource allocations.

**Key sections**:

1. **defaults**: Base limits for all users
2. **groups**: Define user groups (students, researchers, admins)
3. **user_overrides**: Per-user exceptions
4. **policies**: Behavioral settings (idle timeout, max containers, etc.)

**Example config structure**:
```yaml
defaults:
  gpus: 1
  cpus: 8
  memory: 32g
  
groups:
  students:
    members: [alice, bob, charlie]
    gpus: 1
    cpus: 8
    
  researchers:
    members: [prof_smith]
    gpus: 2
    cpus: 16
```

**Modifying limits**:

```bash
# Edit config
vim /opt/ds01-infra/config/resource-limits.yaml

# Test for specific user
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py alice

# Changes take effect on next container creation
```

---

## 🚀 Deployment

### Installation

1. **Install base system** (if not already):
   ```bash
   cd /opt
   git clone https://github.com/aime-team/aime-ml-containers
   cd aime-ml-containers
   # Follow installation instructions
   ```

2. **Deploy ds01-infra**:
   ```bash
   cd /opt
   git clone hertie-data-science-lab/ds01-infra.git
   cd ds01-infra
   chmod +x scripts/**/*.sh
   chmod +x scripts/docker/*.py
   ```

3. **Create symlinks** (make enhanced scripts available to users):
   ```bash
   ln -sf /opt/ds01-infra/scripts/docker/mlc-create-enhanced /usr/local/bin/mlc-create
   # Alternatively: alias in /etc/bash.bashrc
   ```

4. **Configure resource limits**:
   ```bash
   vim /opt/ds01-infra/config/resource-limits.yaml
   # Add your users to appropriate groups
   ```

5. **Set up monitoring** (cron jobs):
   ```bash
   crontab -e
   
   # Add:
   */5 * * * * /opt/ds01-infra/scripts/monitoring/log-metrics-5min.sh
   0 2 * * * /opt/ds01-infra/scripts/maintenance/cleanup-idle-containers.sh
   ```

---

## 👥 User Management

### Adding New Users

1. **Add to server** (standard Linux user creation):
   ```bash
   sudo adduser newstudent
   sudo usermod -aG docker newstudent
   sudo usermod -aG video newstudent  # For GPU access
   ```

2. **Add to resource config**:
   ```bash
   vim /opt/ds01-infra/config/resource-limits.yaml
   
   # Add to appropriate group:
   groups:
     students:
       members: [alice, bob, newstudent]  # Add here
   ```

3. **Create workspace**:
   ```bash
   sudo mkdir -p /home/newstudent/workspace
   sudo chown newstudent:newstudent /home/newstudent/workspace
   ```

4. **Notify user**:
   - Send them `getting-started.md`
   - Show them office hours
   - Walk through first container creation

### Granting Additional Resources

**Scenario**: Student needs 2 GPUs for thesis work

```bash
vim /opt/ds01-infra/config/resource-limits.yaml

# Add user override:
user_overrides:
  thesis_student:
    gpus: 2
    memory: 64g
    idle_timeout: 168h  # 1 week
    reason: "Thesis - approved by Prof. Smith"
```

---

## 📊 Monitoring

### Real-time GPU Status

```bash
# Check GPU usage
nvitop

# Check which containers are using GPUs
/opt/ds01-infra/scripts/monitoring/check-container-gpu-allocation.sh

# Container resource usage
docker stats

# Enhanced container list
mlc-stats
```

### Log Files (currently auto'd as cron jobs)

```bash
# GPU allocation log
cat ~/server_infra/logs/gpu/gpu_allocations.log

# Metrics logs
cat ~/server_infra/logs/metrics/

# Docker logs for specific container
docker logs <container_name>
```

### Setting Up Prometheus + Grafana (Future)

See Medium Priority tasks in work plan. For now, use:
- `log-metrics-5min.sh` → CSV logs
- `report-metrics-daily.sh` → Email digest

---

## 🔧 Maintenance Tasks

### Daily

- Check `mlc-stats` for resource hogs
- Review `nvidia-smi` for GPU utilization
- Check for orphaned containers

### Weekly

- Review idle containers (auto-cleanup should handle this)
- Check disk space usage
- Update resource limits based on usage patterns

### Monthly

- Review user feedback
- Update container templates
- Check for framework updates
- Backup configuration files

### Cleanup Tasks

```bash
# Remove stopped containers (manual)
docker container prune

# Remove unused images
docker image prune -a

# Remove idle containers (automated via cron)
/opt/ds01-infra/scripts/maintenance/cleanup-idle-containers.sh
```

---

## 🐛 Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs <container_name>

# Check resource availability
nvidia-smi
free -h
df -h

# Check if GPU is allocated
cat ~/server_infra/configs/gpu_allocation.yaml
```

### User Can't Create Container

**Common causes**:
1. Already has max containers (check policy in config)
2. No GPUs available (check allocation)
3. Disk space full
4. Docker daemon issue

**Debug**:
```bash
# Check user's containers
docker ps -a --filter label=aime.mlc.USER=<username>

# Check system resources
df -h
docker system df

# Test resource parser
python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py <username>
```

### Out of Disk Space

```bash
# Find large directories
du -h /home | sort -rh | head -20

# Clean Docker
docker system prune -a --volumes

# Clean old logs
find ~/server_infra/logs -mtime +30 -delete
```

---

## 🔒 Security Considerations

1. **Container Isolation**: Users run containers with their own UID/GID
2. **GPU Pinning**: Enforced via `--gpus=device=X` flag
3. **Resource Limits**: Prevent resource exhaustion attacks
4. **Workspace Permissions**: Each user's workspace is private by default

**Best practices**:
- Regular security updates on host system
- Keep Docker engine updated
- Audit container images for vulnerabilities
- Monitor for suspicious activity

---

## 📝 Configuration Examples

### Example 1: Small Lab (10 students)

```yaml
defaults:
  gpus: 1
  cpus: 8
  memory: 32g

groups:
  students:
    members: [alice, bob, charlie, diana, eric, frank, grace, helen, ivan, judy]
    gpus: 1
    cpus: 8
    memory: 32g
    idle_timeout: 48h
    
policies:
  max_containers_per_user: 2
```

### Example 2: Mixed Use (Students + Researchers)

```yaml
defaults:
  gpus: 1
  cpus: 8
  memory: 32g

groups:
  undergrads:
    members: [student1, student2, student3]
    gpus: 1
    cpus: 6
    memory: 24g
    idle_timeout: 24h
    
  grad_students:
    members: [phd1, phd2, masters1]
    gpus: 1
    cpus: 8
    memory: 32g
    idle_timeout: 72h
    
  faculty:
    members: [prof_smith, prof_jones]
    gpus: 2
    cpus: 16
    memory: 64g
    idle_timeout: null  # No timeout
```

---

## 🚀 Future Enhancements

See `TODO/_TODO.md` for full list. Key items:

1. **Slurm Integration**: Job scheduling for fair-share
2. **Web Dashboard**: Real-time monitoring UI
3. **Automated Backups**: Workspace snapshots
4. **Usage Analytics**: Per-user/per-project reports
5. **Cloud Bursting**: Overflow to cloud during peak usage

---

## 📚 Related Documentation

- **For Users**: `../ds01-user-docs/getting-started.md`
- **Troubleshooting**: `../ds01-user-docs/troubleshooting.md`
- **GPU Guide**: `../ds01-user-docs/gpu-usage-guide.md`
- **Original MLC**: `/opt/aime-ml-containers/README.md`

---

## 📞 Support

**Internal**:
- Research Engineer: henry@university.edu
- Lab Slack: #ds01-server-support

**External**:
- AIME MLC Issues: https://github.com/aime-team/aime-mlc/issues
- Docker Docs: https://docs.docker.com/

---

**Last Updated**: 2025-01-28  
**Maintained by**: Data Science Lab Research Engineering Team
