# System Scripts - Administration & Deployment

System administration, deployment, and user management tools.

## Overview

This directory contains scripts for:
- Initial system deployment
- User management (docker group access)
- Command symlink management
- Systemd cgroup configuration
- System maintenance

## Key Scripts

### add-user-to-docker.sh

Add users to docker group for Docker socket access.

**Purpose:** Grant Docker permissions to users

**Usage:**
```bash
sudo scripts/system/add-user-to-docker.sh <username>
```

**What it does:**
1. Verifies docker group exists
2. Adds user to docker group
3. Reminds user to log out and back in

**After running:**
```bash
# User must log out and back in for group membership to take effect
exit
# SSH back in

# Verify
groups | grep docker
docker info  # Should work without sudo
```

**Troubleshooting:**
- If docker group doesn't exist: `sudo groupadd docker`
- If docker daemon not running: `sudo systemctl start docker`

### deploy-commands.sh (alias: `deploy`)

Deploy all DS01 commands to `/usr/local/bin/`.

**Purpose:** Make all DS01 commands globally accessible (copies, not symlinks)

**Usage:**
```bash
sudo deploy
# or
sudo /opt/ds01-infra/scripts/system/deploy-commands.sh
```

**What it does:**
1. Sets permissions on source files (755 for scripts, 644 for configs)
2. Copies all commands to `/usr/local/bin/` (not symlinks, for security)
3. Makes commands accessible to all users

Deploys all 50+ commands organized by tier:

**Tier 4 (Wizards):**
- `user-setup` → `scripts/user/wizards/user-setup`
- `project-init` → `scripts/user/wizards/project-init`
- `project-launch` → `scripts/user/wizards/project-launch`
- Legacy aliases: `new-user` → `user-setup`, `new-project` → `project-init`

**Tier 3 (Orchestrators):**
- `container-deploy` → `scripts/user/orchestrators/container-deploy`
- `container-retire` → `scripts/user/orchestrators/container-retire`
- Dispatchers: `user`, `project`, `container`, `image` → `scripts/user/dispatchers/`

**Tier 2 (Atomic):**
- Container: `container-{create|run|start|stop|list|stats|remove|exit}` → `scripts/user/atomic/`
- Image: `image-{create|list|update|delete}` → `scripts/user/atomic/`

**Helpers:**
- Setup: `shell-setup`, `ssh-setup`, `vscode-setup`, `jupyter-setup` → `scripts/user/helpers/`
- Project: `dir-create`, `git-init`, `readme-create`, `check-limits` → `scripts/user/helpers/`

**Admin commands:**
- `alias-list` → `scripts/admin/alias-list`
- `ds01-dashboard` → `scripts/monitoring/gpu-status-dashboard.py`
- `ds01-status` → `scripts/user/helpers/ds01-status`
- `check-limits` → `scripts/user/helpers/check-limits`

**When to run:**
- After initial deployment
- After adding new commands
- After moving/renaming scripts
- If users report "command not found" errors

**Verify:**
```bash
ls -la /usr/local/bin/ | grep ds01
which container-create
which user-setup
```

### setup-resource-slices.sh

Configure systemd cgroup slices for resource management.

**Purpose:** Set up systemd cgroup hierarchy for resource limits

**Usage:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

**What it does:**

1. **Creates root slice:** `ds01.slice`
   - Top-level slice for all DS01 containers

2. **Creates group slices:** `ds01-{group}.slice`
   - One per group in `config/resource-limits.yaml`
   - Enforces group-wide resource limits
   - Example: `ds01-students.slice`, `ds01-researchers.slice`

3. **Sets resource limits from YAML:**
   - CPU quota
   - Memory limits
   - I/O weights

4. **Enables automatic user slice creation**
   - User slices: `ds01-{group}-{username}.slice`
   - Created automatically on first container creation
   - Enables per-user monitoring

**Systemd hierarchy:**
```
ds01.slice
├── ds01-students.slice
│   ├── ds01-students-alice.slice
│   └── ds01-students-bob.slice
└── ds01-researchers.slice
    ├── ds01-researchers-charlie.slice
    └── ds01-researchers-diana.slice
```

**When to run:**
- After initial deployment
- After modifying `config/resource-limits.yaml` group settings
- After adding new groups

**Verify:**
```bash
systemctl status ds01.slice
systemctl status ds01-students.slice
systemd-cgtop | grep ds01
```

### create-user-slice.sh

Create per-user systemd slice.

**Purpose:** Create individual user slice for monitoring

**Usage:**
```bash
# Usually called automatically by mlc-create-wrapper.sh
sudo scripts/system/create-user-slice.sh <username> <group>
```

**What it does:**
1. Creates `ds01-{group}-{username}.slice`
2. Sets it as child of group slice
3. Enables per-user resource tracking

**When called:**
- Automatically during container creation
- Only if user slice doesn't already exist

**Manual creation:**
```bash
sudo scripts/system/create-user-slice.sh alice students
```

### setup-docker-permissions.sh

Set up per-user container isolation via Docker socket proxy.

**Purpose:** Ensure users can only see and interact with their own containers

**Usage:**
```bash
# Deploy permissions system
sudo scripts/system/setup-docker-permissions.sh

# Uninstall
sudo scripts/system/setup-docker-permissions.sh --uninstall

# Preview changes
sudo scripts/system/setup-docker-permissions.sh --dry-run
```

**What it does:**
1. Creates `ds01-admin` Linux group for admin users
2. Creates `ds01-dashboard` service user for monitoring
3. Configures Docker daemon to listen on `/var/run/docker-real.sock`
4. Starts filter proxy on `/var/run/docker.sock`
5. Starts container ownership sync service

**Architecture:**
```
Users/VS Code → /var/run/docker.sock (proxy) → /var/run/docker-real.sock (daemon)
```

**Services created:**
- `ds01-container-sync` - Syncs container ownership data every 5 seconds
- `ds01-docker-filter` - Filter proxy for container visibility

**User experience:**
- Regular users: `docker ps` only shows their containers
- Regular users: Operations on others' containers return "Permission denied: container owned by \<owner\>"
- Admins (`ds01-admin` group): Full access to all containers

**Adding admins:**
```bash
sudo usermod -aG ds01-admin <username>
```

**Checking status:**
```bash
systemctl status ds01-docker-filter
systemctl status ds01-container-sync
cat /var/lib/ds01/opa/container-owners.json | python3 -m json.tool
```

## Deployment

### Initial Deployment

**1. Clone repository:**
```bash
cd /opt
sudo git clone <repo-url> ds01-infra
cd ds01-infra
```

**2. Set permissions:**
```bash
sudo chown -R root:ds-admin /opt/ds01-infra
sudo chmod -R g+rwX /opt/ds01-infra
```

**3. Make scripts executable:**
```bash
find scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
```

**4. Install dependencies:**
```bash
sudo apt update
sudo apt install -y python3-yaml docker.io nvidia-docker2
sudo pip3 install pyyaml
```

**5. Configure resource limits:**
```bash
sudo vim config/resource-limits.yaml
# Add your users and groups
```

**6. Setup systemd slices:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

**7. Create command symlinks:**
```bash
sudo scripts/system/update-symlinks.sh
```

**8. Verify installation:**
```bash
which user-setup
which container-create
systemctl status ds01.slice
```

### Updating Deployment

**Update code:**
```bash
cd /opt/ds01-infra
sudo git pull
```

**Update symlinks:**
```bash
sudo scripts/system/update-symlinks.sh
```

**Update systemd slices (if config changed):**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

**Reload configuration:**
```bash
# No daemon restart needed - config read per-operation
python3 scripts/docker/get_resource_limits.py <test-user>
```

## User Management

### Adding New User

**Complete workflow:**

```bash
# 1. Create Linux user
sudo adduser newstudent
sudo usermod -aG video newstudent  # GPU access

# 2. Add to docker group
sudo scripts/system/add-user-to-docker.sh newstudent

# 3. Add to resource config
sudo vim config/resource-limits.yaml
# Add to appropriate group under 'members' list

# 4. User logs out and back in
# (Required for docker group membership)

# 5. User runs onboarding
# As newstudent:
user-setup
```

**Verify user setup:**
```bash
# As admin
id newstudent | grep docker
sudo -u newstudent docker info

# As user
groups | grep docker
docker info
```

### Removing User Access

**Remove docker permissions:**
```bash
sudo gpasswd -d <username> docker
```

**Remove from resource config:**
```bash
sudo vim config/resource-limits.yaml
# Remove from groups.members list
```

**Stop and remove user containers:**
```bash
# List user's containers
docker ps -a --filter "name=*._.<username>"

# Stop all user containers
for container in $(docker ps -q --filter "name=*._.<username>"); do
    docker stop $container
done

# Remove all user containers
for container in $(docker ps -aq --filter "name=*._.<username>"); do
    docker rm $container
done

# Release GPU allocations
python3 scripts/docker/gpu_allocator.py release --container <container-name>
```

### Granting Additional Resources

**User overrides:**
```bash
sudo vim config/resource-limits.yaml
```

Add to `user_overrides` section:
```yaml
user_overrides:
  special_user:
    max_mig_instances: 2
    memory: "64g"
    max_cpus: 16
    idle_timeout: "168h"  # 1 week
    priority: 100
    reason: "Thesis work - approved 2025-11-21 by Prof. Smith"
```

**Group changes:**
```yaml
groups:
  researchers:
    members: [alice, bob, charlie]  # Add new member
    max_mig_instances: 2
    memory: "64g"
    priority: 50
```

**Apply changes:**
```bash
# Resource limits: Applied immediately (no restart)
python3 scripts/docker/get_resource_limits.py special_user

# Systemd slices: Need update if group limits changed
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
```

## System Maintenance

### Check System Health

```bash
# Systemd slices status
systemctl status ds01.slice
systemd-cgtop | grep ds01

# Docker status
sudo systemctl status docker

# GPU status
nvidia-smi
python3 scripts/docker/gpu_allocator.py status

# Container count
docker ps | wc -l
docker ps -a | wc -l
```

### Clean Up Stale State

**GPU allocations:**
```bash
# View current allocations
python3 scripts/docker/gpu_allocator.py status

# Release allocation if container deleted manually
python3 scripts/docker/gpu_allocator.py release --container <container-name>
```

**Container metadata:**
```bash
# View metadata
ls -lh /var/lib/ds01/container-metadata/

# Clean up metadata for deleted containers
sudo rm /var/lib/ds01/container-metadata/<container>.json
```

**Orphaned Docker resources:**
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Remove all unused resources
docker system prune
```

### Backup Important Data

**Configuration:**
```bash
sudo cp config/resource-limits.yaml config/resource-limits.yaml.bak
```

**State files:**
```bash
sudo cp /var/lib/ds01/gpu-state.json /var/lib/ds01/gpu-state.json.bak
sudo tar -czf /root/ds01-metadata-backup-$(date +%Y%m%d).tar.gz /var/lib/ds01/container-metadata/
```

**Logs:**
```bash
sudo tar -czf /root/ds01-logs-backup-$(date +%Y%m%d).tar.gz /var/log/ds01/
```

## Cron Jobs

DS01 uses cron for automated maintenance. Cron config files deployed separately.

**Cron jobs:**
- `:45/hour` - Max runtime enforcement
- `:30/hour` - Idle container detection
- `:15/hour` - GPU stale allocation cleanup
- `:30/hour` - Container stale cleanup

**Location:** `/etc/cron.d/ds01-*`

**Logs:**
- `/var/log/ds01/idle-cleanup.log`
- `/var/log/ds01/runtime-enforcement.log`
- `/var/log/ds01/gpu-stale-cleanup.log`
- `/var/log/ds01/container-stale-cleanup.log`

**See:** [scripts/maintenance/README.md](../maintenance/README.md) for details

## Troubleshooting

### Symlinks Not Created

**Symptom:** Commands not found after deployment

**Check:**
```bash
ls -la /usr/local/bin/ | grep ds01
```

**Fix:**
```bash
sudo scripts/system/update-symlinks.sh
```

### Systemd Slices Not Created

**Symptom:** Containers not respecting resource limits

**Check:**
```bash
systemctl status ds01.slice
systemd-cgtop | grep ds01
```

**Fix:**
```bash
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload
systemctl status ds01.slice
```

### Docker Group Not Working

**Symptom:** User still getting permission errors after adding to docker group

**Cause:** User needs to log out and back in

**Solution:**
```bash
# User must exit and SSH back in
exit
# SSH back in
groups | grep docker  # Should show docker now
```

### Resource Config Not Applied

**Symptom:** User getting wrong resource limits

**Check:**
```bash
# Verify YAML syntax
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"

# Test user limits
python3 scripts/docker/get_resource_limits.py <username>
```

**Common issues:**
- YAML syntax errors
- User not in any group
- Group not listed in `groups` section
- Typo in username

## Related Documentation

- [Root README](../../README.md) - System overview
- [config/README.md](../../config/README.md) - Resource configuration
- [scripts/docker/README.md](../docker/README.md) - Container creation, GPU allocation
- [scripts/maintenance/README.md](../maintenance/README.md) - Automated maintenance
- [scripts/monitoring/README.md](../monitoring/README.md) - System monitoring
