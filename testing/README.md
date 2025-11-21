# Testing - Test Suites & Validation

Testing procedures and validation tools for DS01 infrastructure.

## Overview

DS01 testing organized into:
- **Unit tests** - Individual component testing
- **Integration tests** - End-to-end workflow testing
- **Validation** - System health checks

## Test Suites

### cleanup-automation/

**Comprehensive test suite for container lifecycle automation.**

Tests for:
- Idle timeout detection and enforcement
- Max runtime enforcement
- GPU release after stop
- Container removal after stop

**Documentation:**
- [cleanup-automation/README.md](cleanup-automation/README.md) - Complete testing guide
- [cleanup-automation/TESTING-GUIDE.md](cleanup-automation/TESTING-GUIDE.md) - Detailed procedures
- [cleanup-automation/FINDINGS.md](cleanup-automation/FINDINGS.md) - Bug analysis
- [cleanup-automation/SUMMARY.md](cleanup-automation/SUMMARY.md) - Executive summary

**Quick start:**
```bash
# Unit tests (fast, no containers needed)
testing/cleanup-automation/test-functions-only.sh

# Integration tests (requires test environment)
# See cleanup-automation/README.md for setup
```

### validation/

**System validation and health checks.**

Validates:
- Configuration correctness
- Component integration
- Resource limit enforcement
- GPU allocation behavior

**Documentation:**
- [validation/README.md](validation/README.md) - Validation procedures
- [validation/VALIDATION-SUMMARY.md](validation/VALIDATION-SUMMARY.md) - Results summary

## Testing Configuration

### Resource Limits

Test with short timeouts for faster feedback:

```yaml
# config/resource-limits.yaml
user_overrides:
  testuser:
    max_mig_instances: 1
    idle_timeout: "0.01h"              # 36 seconds
    max_runtime: "0.02h"               # 72 seconds
    gpu_hold_after_stop: "0.01h"       # 36 seconds
    container_hold_after_stop: "0.01h" # 36 seconds
    priority: 10
```

### Test User Setup

```bash
# Create test user
sudo adduser testuser
sudo scripts/system/add-user-to-docker.sh testuser

# Add to config
sudo vim config/resource-limits.yaml
# Add testuser to user_overrides with short timeouts

# Test user limits
python3 scripts/docker/get_resource_limits.py testuser
```

## Component Testing

### Resource Limits Parser

**Test get_resource_limits.py:**
```bash
# Test specific user
python3 scripts/docker/get_resource_limits.py alice

# Test all users
for user in student1 researcher1 admin1; do
    echo "=== $user ==="
    python3 scripts/docker/get_resource_limits.py $user
done

# Test Docker args format
python3 scripts/docker/get_resource_limits.py alice --docker-args
```

**Expected output:**
```
User: alice
Group: students
Priority: 10
Max MIG Instances: 1
Max CPUs: 8
Memory: 32g
```

### GPU Allocator

**Test gpu_allocator.py:**
```bash
# Check status
python3 scripts/docker/gpu_allocator.py status

# Test allocation
python3 scripts/docker/gpu_allocator.py allocate \
    --user testuser \
    --container test-container \
    --max-gpus 1 \
    --priority 10

# Verify allocation
cat /var/lib/ds01/gpu-state.json

# Test release
python3 scripts/docker/gpu_allocator.py release --container test-container

# Verify release
python3 scripts/docker/gpu_allocator.py status
```

### MIG Configuration

**Test MIG detection:**
```bash
# Check MIG instances
nvidia-smi mig -lgi

# Test MIG parser
python3 scripts/docker/mig-config-parser.py

# Test MIG allocation
python3 scripts/docker/gpu_allocator.py allocate \
    --user testuser \
    --container mig-test \
    --max-gpus 1 \
    --priority 10

# Should allocate MIG instance (e.g., "0:1")
python3 scripts/docker/gpu_allocator.py status
```

### YAML Configuration

**Validate syntax:**
```bash
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"
# No output = valid
```

**Test priority resolution:**
```bash
# Test user override > group > defaults
python3 scripts/docker/get_resource_limits.py special_user --verbose
```

### Systemd Slices

**Test slice creation:**
```bash
# Create slices
sudo scripts/system/setup-resource-slices.sh
sudo systemctl daemon-reload

# Verify
systemctl status ds01.slice
systemctl status ds01-students.slice

# Check resource limits
systemctl show ds01-students.slice | grep -E "CPU|Memory"
```

## Workflow Testing

### Container Creation

**Test container-create flow:**
```bash
# As test user
container-create test-project

# Verify:
# 1. Container created
docker ps | grep test-project

# 2. GPU allocated
python3 scripts/docker/gpu_allocator.py status | grep test-project

# 3. Metadata saved
cat /var/lib/ds01/container-metadata/test-project._.testuser.json

# 4. Resource limits applied
docker inspect test-project._.testuser | grep -A10 "HostConfig"
```

### Container Lifecycle

**Test complete lifecycle:**
```bash
# 1. Create
container-create test-project

# 2. Run
container-run test-project
# Exit container

# 3. Stop
container-stop test-project

# Verify GPU marked stopped
cat /var/lib/ds01/gpu-state.json | grep stopped_at

# 4. Remove
container-remove test-project

# Verify GPU released
python3 scripts/docker/gpu_allocator.py status
```

### Project Initialization

**Test project-init:**
```bash
# Run project init
project-init

# Verify created:
# 1. Directory structure
ls -la ~/workspace/<project>/

# 2. Git repository
cd ~/workspace/<project>/
git status

# 3. Docker image
docker images | grep ds01-$USER

# 4. Container
docker ps | grep <project>

# 5. GPU allocation
python3 scripts/docker/gpu_allocator.py status
```

## Automated Testing

### Cleanup Automation Tests

**See:** [cleanup-automation/README.md](cleanup-automation/README.md)

**Quick test:**
```bash
# Run unit tests
testing/cleanup-automation/test-functions-only.sh

# Run specific test
testing/cleanup-automation/test-idle-detection.sh

# Run full suite (requires setup)
testing/cleanup-automation/run-all-tests.sh
```

### Validation Tests

**See:** [validation/README.md](validation/README.md)

**Run validation:**
```bash
# Validate system
testing/validation/validate-system.sh

# Validate configuration
testing/validation/validate-config.sh

# Validate GPU allocation
testing/validation/validate-gpu-allocation.sh
```

## Manual Testing Checklist

### Initial Deployment

- [ ] Configuration loads without errors
- [ ] Systemd slices created
- [ ] Command symlinks work
- [ ] GPU allocator initializes
- [ ] Test user can create container

### After Configuration Changes

- [ ] YAML syntax validates
- [ ] User limits resolve correctly
- [ ] Systemd slices updated
- [ ] Changes apply to new containers

### Before Production

- [ ] Resource limits enforced
- [ ] GPU allocation works
- [ ] Container lifecycle automation works
- [ ] Monitoring tools work
- [ ] Logs being written
- [ ] Cron jobs scheduled

## Troubleshooting Tests

### Test Failures

**Configuration test fails:**
```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('config/resource-limits.yaml'))"

# Check user exists in config
grep testuser config/resource-limits.yaml
```

**GPU allocation test fails:**
```bash
# Check GPU availability
nvidia-smi

# Check allocator state
cat /var/lib/ds01/gpu-state.json

# Reset state if needed (WARNING: loses allocations)
sudo rm /var/lib/ds01/gpu-state.json
sudo touch /var/lib/ds01/gpu-state.json
echo '{"allocations": {}, "last_updated": ""}' | sudo tee /var/lib/ds01/gpu-state.json
```

**Container creation test fails:**
```bash
# Check docker permissions
docker info

# Check image exists
docker images | grep ds01-$USER

# Check resource limits
python3 scripts/docker/get_resource_limits.py $USER

# Run with debug
bash -x scripts/docker/mlc-create-wrapper.sh test-container test-image $USER
```

## Test Data Cleanup

### Remove Test Containers

```bash
# Stop all test containers
docker stop $(docker ps -q --filter "name=test-")

# Remove all test containers
docker rm $(docker ps -aq --filter "name=test-")
```

### Clean Test User Resources

```bash
# Release GPU allocations
python3 scripts/docker/gpu_allocator.py release --container test-project

# Remove test metadata
sudo rm /var/lib/ds01/container-metadata/test-*.json

# Remove test images
docker rmi ds01-testuser/test-project:latest
```

### Reset Test State

```bash
# Backup current state
sudo cp /var/lib/ds01/gpu-state.json /var/lib/ds01/gpu-state.json.test-backup

# Clear test allocations
# (Manual edit of gpu-state.json or use python script)
```

## Continuous Testing

### Automated Test Schedule

Set up regular validation:

```bash
# /etc/cron.d/ds01-testing
0 2 * * * root /opt/ds01-infra/testing/validation/validate-system.sh >> /var/log/ds01/validation.log 2>&1
```

### Monitoring Test Results

```bash
# View validation logs
tail -f /var/log/ds01/validation.log

# Check test status
ls -lt testing/cleanup-automation/logs/
```

## Related Documentation

- [Root README](../README.md) - System overview
- [cleanup-automation/README.md](cleanup-automation/README.md) - Cleanup testing guide
- [validation/README.md](validation/README.md) - Validation procedures
- [scripts/docker/README.md](../scripts/docker/README.md) - Component testing
- [config/README.md](../config/README.md) - Configuration testing
