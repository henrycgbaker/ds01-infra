# SLURM Integration Strategy & Implementation Plan

**Document Version:** 1.0
**Date:** 2025-11-21
**Status:** Strategic Planning
**Author:** DS01 Infrastructure Team

---

## Executive Summary

This document outlines comprehensive strategies for integrating SLURM (Simple Linux Utility for Resource Management) with the DS01 Infrastructure, evaluating three primary approaches:

1. **Full SLURM Replacement** - Replace DS01's custom resource management with native SLURM
2. **Hybrid SLURM + DS01** - Parallel systems with SLURM for batch jobs, DS01 for interactive work
3. **SLURM Frontend with DS01 Backend** - Use SLURM scheduling with DS01 resource enforcement

**Recommendation:** Hybrid approach (Option 2) provides the best balance of HPC capabilities, user experience, and migration risk.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [SLURM Architecture Options](#slurm-architecture-options)
3. [Container Runtime Strategy](#container-runtime-strategy)
4. [GPU Scheduling Strategy](#gpu-scheduling-strategy)
5. [Implementation Phases](#implementation-phases)
6. [Migration Strategy](#migration-strategy)
7. [Risk Analysis](#risk-analysis)
8. [Cost-Benefit Analysis](#cost-benefit-analysis)
9. [Recommendations](#recommendations)

---

## Current State Analysis

### DS01 Infrastructure Capabilities

**Architecture:**
- **Tier 1:** AIME ML Containers (11 core `mlc` commands, 150+ framework images)
- **Tier 2:** Atomic unit commands (container-*, image-*, setup modules)
- **Tier 3:** Orchestrators (container-deploy, container-retire)
- **Tier 4:** Workflow wizards (user-setup, project-init)

**Resource Management:**
```
Resource Limits (YAML)
    ↓
GPU Allocator (Python)
    ↓
Systemd Cgroups
    ↓
Docker Runtime
```

**Key Features:**
- ✓ MIG-aware GPU allocation with priority scheduling
- ✓ Per-user resource limits (CPU, memory, GPU, storage)
- ✓ Automated lifecycle management (idle detection, auto-cleanup)
- ✓ Educational user experience (--guided mode, interactive wizards)
- ✓ Custom image workflow (4-phase: Framework → Jupyter → DS → Use Case)
- ✓ Ephemeral container model (containers temporary, workspaces persistent)

**Limitations:**
- ✗ No job queuing (immediate execution or rejection)
- ✗ No batch job scheduling
- ✗ No fairshare policies
- ✗ No multi-node support
- ✗ No job dependencies
- ✗ No array jobs
- ✗ No checkpoint/restart
- ✗ No accounting database (basic logging only)

### Current User Workflows

**Interactive Development:**
```bash
user-setup              # First-time onboarding
project-init my-ml      # Create project
container-deploy my-ml  # Deploy container
# ... work in container ...
container-retire my-ml  # Release resources
```

**Current Pain Points:**
1. No job queuing - users must retry if resources unavailable
2. No historical usage tracking
3. No advanced scheduling policies (e.g., backfill, preemption)
4. No multi-node distributed training
5. Limited batch job support

---

## SLURM Architecture Options

### Option 1: Full SLURM Replacement

**Description:** Replace DS01's custom resource management entirely with native SLURM.

**Architecture:**
```
User → SLURM → Container Runtime → GPU
         ↓
   Accounting DB
         ↓
    Fairshare
```

**Implementation:**
- Remove: `gpu_allocator.py`, `resource-limits.yaml`, systemd cgroups
- Replace with: SLURM `gres.conf`, `slurm.conf`, SLURM accounting
- User commands: `sbatch`, `srun`, `salloc`, `scancel`, `squeue`

**Pros:**
- ✓ Industry-standard HPC scheduler
- ✓ Advanced features: queuing, fairshare, backfill, preemption
- ✓ Multi-node support
- ✓ Comprehensive accounting database
- ✓ Job dependencies, array jobs, checkpoint/restart
- ✓ Well-documented, large community
- ✓ Integration with many HPC tools (modules, MPI, etc.)

**Cons:**
- ✗ **Major disruption** - complete rewrite of user workflows
- ✗ **Loss of educational UX** - SLURM is complex, not beginner-friendly
- ✗ **No interactive containers** - SLURM designed for batch jobs
- ✗ **Steep learning curve** - users must learn sbatch scripts, SLURM flags
- ✗ **Complexity** - SLURM is heavyweight (slurmd, slurmctld, slurmdbd)
- ✗ **Loss of custom features** - container-deploy/retire, image-create workflow
- ✗ **Docker limitations** - SLURM's Docker support is limited (Singularity preferred)

**Migration Effort:** **HIGH** (6-12 months)
- Rewrite all user-facing commands
- Retrain all users
- Rebuild custom image workflow
- Migrate resource limits to SLURM configuration
- High risk of user resistance

---

### Option 2: Hybrid SLURM + DS01 (Recommended)

**Description:** Run SLURM and DS01 in parallel, each serving different use cases.

**Architecture:**
```
┌─────────────────────────────────────────────┐
│              User Workflows                 │
├──────────────────────┬──────────────────────┤
│  Interactive Work    │    Batch Jobs       │
│  (DS01 Commands)     │  (SLURM Commands)   │
├──────────────────────┼──────────────────────┤
│ container-deploy     │ sbatch train.sh      │
│ container-run        │ srun python train.py │
│ image-create         │ salloc -N 2          │
│ user-setup           │ squeue, scancel      │
└──────────────────────┴──────────────────────┘
         ↓                      ↓
┌──────────────────┐   ┌──────────────────┐
│ DS01 GPU Pool    │   │ SLURM GPU Pool   │
│ (Interactive)    │   │ (Batch)          │
│ GPUs: 0-1        │   │ GPUs: 2-3        │
│ MIG instances    │   │ Full GPUs or MIG │
└──────────────────┘   └──────────────────┘
```

**Implementation:**
- **DS01 Side:** Keep existing system, limit to subset of GPUs (e.g., GPUs 0-1)
- **SLURM Side:** Configure SLURM on separate GPU pool (e.g., GPUs 2-3)
- **Resource Partitioning:** Static GPU allocation between systems
- **User Choice:** Users pick DS01 for interactive, SLURM for batch

**Use Case Mapping:**

| Use Case | System | Why |
|----------|--------|-----|
| Learning/exploration | DS01 | Educational UX, --guided mode |
| Interactive debugging | DS01 | Immediate access, live container |
| Quick experiments | DS01 | Fast deployment (container-deploy) |
| Long training runs | SLURM | Queuing, checkpoint/restart |
| Multi-node distributed | SLURM | Multi-node support |
| Batch hyperparameter sweeps | SLURM | Array jobs |
| Scheduled experiments | SLURM | Job dependencies, scheduling |

**Pros:**
- ✓ **Low migration risk** - DS01 users unaffected
- ✓ **Gradual adoption** - users migrate to SLURM as needed
- ✓ **Best of both worlds** - interactive UX + batch scheduling
- ✓ **Preserve investment** - DS01 development not wasted
- ✓ **Clear separation** - interactive vs batch workloads
- ✓ **Flexibility** - adjust GPU allocation based on demand

**Cons:**
- ✗ **Resource fragmentation** - GPUs split between systems
- ✗ **Dual maintenance** - two systems to manage
- ✗ **User confusion** - which system to use when?
- ✗ **No resource sharing** - idle DS01 GPUs can't help SLURM queue
- ✗ **Double accounting** - need to aggregate usage from both systems

**Migration Effort:** **MEDIUM** (3-6 months)
- Install and configure SLURM
- Partition GPUs between systems
- Document use case decision tree
- Train users on SLURM basics
- Create SLURM job templates

---

### Option 3: SLURM Frontend with DS01 Backend

**Description:** Use SLURM as scheduling frontend, but retain DS01 resource enforcement.

**Architecture:**
```
User Commands
    ↓
sbatch/srun → SLURM Scheduler
    ↓
SLURM Prolog Script
    ↓
DS01 GPU Allocator → gpu_allocator.py
    ↓
Docker + Systemd Cgroups
    ↓
SLURM Epilog Script (cleanup)
```

**Implementation:**
- SLURM handles: Queuing, scheduling, fairshare, accounting
- DS01 handles: GPU allocation, cgroups, container creation
- Bridge: SLURM prolog/epilog scripts call DS01 components

**Prolog Script (on job start):**
```bash
#!/bin/bash
# /etc/slurm/prolog.d/ds01-allocate.sh

USER=$SLURM_JOB_USER
CONTAINER=$SLURM_JOB_NAME
MAX_GPUS=$SLURM_JOB_GPUS
PRIORITY=50

# Allocate GPU via DS01
GPU_ID=$(python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py \
    allocate "$USER" "$CONTAINER" "$MAX_GPUS" "$PRIORITY" | grep DOCKER_ID | cut -d= -f2)

export DS01_GPU_ID=$GPU_ID
```

**Epilog Script (on job end):**
```bash
#!/bin/bash
# /etc/slurm/epilog.d/ds01-release.sh

CONTAINER=$SLURM_JOB_NAME
python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py release "$CONTAINER"
```

**Pros:**
- ✓ **SLURM scheduling** - queuing, fairshare, backfill
- ✓ **DS01 resource management** - proven GPU allocator, cgroups
- ✓ **Unified accounting** - SLURM accounting includes DS01 usage
- ✓ **Reuse DS01 components** - gpu_allocator.py, resource-limits.yaml
- ✓ **Single GPU pool** - no resource fragmentation

**Cons:**
- ✗ **Complex integration** - prolog/epilog scripts can be fragile
- ✗ **SLURM can't see DS01 state** - potential race conditions
- ✗ **Debugging difficulty** - failures span multiple systems
- ✗ **Loss of DS01 UX** - users must use SLURM commands
- ✗ **Container model mismatch** - SLURM expects job completion, DS01 uses long-lived containers

**Migration Effort:** **HIGH** (6-9 months)
- Develop robust prolog/epilog bridge
- Test extensively for race conditions
- Migrate user workflows to SLURM
- Handle state synchronization
- High technical complexity

---

## Container Runtime Strategy

### Current: Docker + AIME ML Containers

**DS01 uses:**
- Docker Engine
- AIME ML Containers v2 (custom framework images)
- UID/GID mapping for security
- Docker labels for metadata

### SLURM Container Options

#### Option A: Keep Docker

**SLURM Docker Support:**
- `scrun` (OCI runtime integration) - **LIMITED** support as of 2025
- Rootless Docker can work with SLURM
- **Major limitation:** SLURM cannot limit Docker resources (must rely on `--cpus`, `--memory` flags)

**Pros:**
- ✓ Keep existing AIME images
- ✓ No image conversion needed
- ✓ Users familiar with Docker

**Cons:**
- ✗ Limited SLURM integration
- ✗ SLURM can't enforce resource limits reliably
- ✗ Not standard HPC practice

#### Option B: Migrate to Singularity/Apptainer (Recommended for Full SLURM)

**SLURM Native Support:**
- Singularity/Apptainer is the **de facto standard** for HPC containers
- Native SLURM integration via `--container` flag
- Resource limits enforced by SLURM
- MPI integration (hybrid method)

**Migration Path:**
```bash
# Convert Docker images to Singularity
singularity build pytorch.sif docker://ds01/pytorch:latest

# Run in SLURM
srun --container pytorch.sif python train.py
```

**Pros:**
- ✓ Native SLURM integration
- ✓ Reliable resource enforcement
- ✓ Better security (no root daemon)
- ✓ HPC standard, well-documented
- ✓ MPI/GPU support excellent

**Cons:**
- ✗ **Major migration effort** - convert all AIME images
- ✗ **User retraining** - different container paradigm
- ✗ **Loss of AIME integration** - custom `mlc` commands won't work
- ✗ **Image build workflow changes** - no `docker build`, must rebuild

#### Option C: Hybrid Docker + Singularity

**For Hybrid Architecture (Option 2):**
- DS01 system: Keep Docker + AIME
- SLURM system: Use Singularity for batch jobs

**Pros:**
- ✓ Each system uses appropriate runtime
- ✓ No disruption to DS01 users
- ✓ SLURM gets proper container support

**Cons:**
- ✗ Dual image management
- ✗ Need to convert images for SLURM use

---

## GPU Scheduling Strategy

### Current DS01 MIG Support

**Implementation:**
- `enable_mig: true` in `resource-limits.yaml`
- `gpu_allocator.py` tracks MIG instances as `"GPU.Instance"` (e.g., "1.0", "1.1")
- Least-allocated strategy with priority awareness
- Dynamic allocation on container start

**MIG Profiles:**
```yaml
gpu_allocation:
  enable_mig: true
  mig_profile: 1g.10gb    # 7 instances per A100
  mig_gpus:
    1:
      enable: true
      profile: 1g.10gb
      instances: 4         # Create 4 instances
    2:
      enable: true
      profile: 1g.10gb
      instances: 4
```

### SLURM MIG Configuration

**SLURM Requirement:**
- MIG partitions must be **pre-configured** (SLURM does not dynamically partition)
- Uses GRES (Generic Resource Scheduling)

**Configuration Files:**

**`gres.conf`:**
```
# GPU 0: Full GPU (no MIG)
NodeName=ds01 Name=gpu Type=a100 File=/dev/nvidia0

# GPU 1: MIG partitioned (4 instances)
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia1 Cores=0-7
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia1 Cores=8-15
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia1 Cores=16-23
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia1 Cores=24-31
```

**`slurm.conf`:**
```
GresTypes=gpu,mig
NodeName=ds01 Gres=gpu:a100:1,mig:1g.10gb:4 CPUs=64 RealMemory=256000
```

**User Job Submission:**
```bash
# Request full GPU
sbatch --gres=gpu:a100:1 train.sh

# Request MIG instance
sbatch --gres=mig:1g.10gb:1 train.sh

# Request 2 MIG instances
sbatch --gres=mig:1g.10gb:2 train.sh
```

**Key Limitations:**
1. **No AutoDetect:** Must manually configure GRES (use `nvidia-mig-discovery` tool)
2. **CUDA Constraint:** CUDA limits MIG enumeration to single device per job in some cases
3. **Static Partitioning:** Can't dynamically switch between MIG/full GPU modes

**Recommendation:**
- Use consistent MIG strategy across all GPUs for batch workloads
- Reserve 1-2 full GPUs for large model training
- Example: GPU 0-1 (full), GPU 2-3 (MIG 4x 1g.10gb each)

---

## Implementation Phases

### Phase 1: Planning & Proof of Concept (2-4 weeks)

**Objectives:**
- Finalize architecture decision
- Set up test SLURM cluster
- Validate GPU scheduling with MIG

**Tasks:**
1. **Decision Meeting:**
   - Present this document to stakeholders
   - Gather user requirements (survey current users)
   - Choose architecture (Option 1, 2, or 3)

2. **Test Environment:**
   - Set up SLURM controller + compute node (can be single machine)
   - Configure MIG partitions on test GPU
   - Test basic job submission

3. **Proof of Concept:**
   - Submit test jobs with GPU allocation
   - Verify MIG instance allocation
   - Test container execution (Docker or Singularity)
   - Measure scheduling latency

**Deliverables:**
- Architecture Decision Document
- Working SLURM test cluster
- PoC test results

---

### Phase 2: Core SLURM Deployment (4-8 weeks)

**Objectives:**
- Deploy production SLURM cluster
- Configure accounting database
- Set up partitions and QoS

**Tasks:**

1. **SLURM Installation:**
```bash
# Install SLURM packages
apt-get install slurm-wlm slurm-wlm-basic-plugins slurmdbd

# Configure slurm.conf
# Configure gres.conf (GPU + MIG)
# Configure slurmdbd.conf (accounting)
```

2. **GPU Configuration:**
```bash
# Configure MIG on designated GPUs
nvidia-smi -i 2 -mig 1
nvidia-smi mig -cgi 1g.10gb -C
nvidia-smi mig -lgi  # List instances

# Run nvidia-mig-discovery to generate gres.conf
git clone https://gitlab.com/nvidia/hpc/slurm-mig-discovery
./slurm-mig-discovery.py --gres-conf
```

3. **Accounting Setup:**
```bash
# Create accounting database
mysql -u root -p
CREATE DATABASE slurm_acct_db;
CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'password';
GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';

# Start slurmdbd
systemctl enable slurmdbd
systemctl start slurmdbd

# Add cluster to accounting
sacctmgr add cluster ds01
```

4. **Partition Configuration:**
```
# slurm.conf
PartitionName=interactive Nodes=ds01 Default=YES MaxTime=8:00:00 State=UP
PartitionName=batch Nodes=ds01 MaxTime=7-00:00:00 State=UP
PartitionName=gpu Nodes=ds01 MaxTime=7-00:00:00 State=UP Gres=gpu:4
```

5. **User Accounts:**
```bash
# Add users to SLURM accounting
for user in $(cat /home/user/ds01-infra/users.txt); do
    sacctmgr add user $user account=ds01
done
```

**Deliverables:**
- Production SLURM cluster
- Accounting database operational
- Users can submit basic jobs

---

### Phase 3A: Integration (Hybrid Architecture) (4-6 weeks)

**For Option 2: Hybrid SLURM + DS01**

**Tasks:**

1. **GPU Partitioning:**
```yaml
# /opt/ds01-infra/config/resource-limits.yaml
gpu_allocation:
  enable_mig: true
  mig_gpus:
    0:
      enable: false  # DS01: Full GPU
    1:
      enable: true   # DS01: MIG 4x instances
      profile: 1g.10gb
      instances: 4
    2:
      enable: false  # SLURM: Full GPU
      reserved: slurm
    3:
      enable: true   # SLURM: MIG 4x instances
      reserved: slurm
```

```bash
# gres.conf (SLURM side - GPUs 2-3 only)
NodeName=ds01 Name=gpu Type=a100 File=/dev/nvidia2
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=0-7
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=8-15
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=16-23
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=24-31
```

2. **Monitoring Dashboard:**
```bash
# Enhanced ds01-dashboard to show both systems
python3 /opt/ds01-infra/scripts/monitoring/unified-dashboard.py
```

3. **Documentation:**
   - User guide: "When to use DS01 vs SLURM"
   - SLURM quickstart for DS01 users
   - Job submission templates

**Deliverables:**
- Partitioned GPU pools
- Unified monitoring
- User documentation

---

### Phase 3B: Integration (Full SLURM) (8-12 weeks)

**For Option 1: Full SLURM Replacement**

**Tasks:**

1. **Container Migration:**
```bash
# Convert AIME images to Singularity
for image in pytorch tensorflow jax; do
    singularity build /opt/ds01-images/$image.sif \
        docker://localhost:5000/ds01/$image:latest
done
```

2. **Wrapper Scripts:**
```bash
# /usr/local/bin/ds01-submit (wrapper for sbatch)
#!/bin/bash
# Translate DS01-style commands to SLURM

case "$1" in
    container-deploy)
        # Interactive allocation
        salloc --gres=gpu:1 --job-name="$2"
        ;;
    container-run)
        # Interactive job with container
        srun --gres=gpu:1 --job-name="$2" \
            --container /opt/ds01-images/pytorch.sif \
            /bin/bash
        ;;
esac
```

3. **Resource Limit Migration:**
```python
# scripts/migration/yaml-to-slurm.py
# Convert resource-limits.yaml to SLURM QoS/accounts

import yaml

with open('config/resource-limits.yaml') as f:
    config = yaml.safe_load(f)

for group, settings in config['groups'].items():
    max_gpus = settings['max_mig_instances']
    priority = settings['priority']

    # Create SLURM account
    print(f"sacctmgr add account {group} cluster=ds01")

    # Create QoS with limits
    print(f"sacctmgr add qos {group} MaxTRESPerUser=gres/gpu={max_gpus} Priority={priority}")
```

4. **User Retraining:**
   - Workshop: "SLURM for DS01 Users"
   - Cheat sheet: DS01 → SLURM command mapping
   - Migration guides

**Deliverables:**
- Converted container images
- Wrapper scripts for compatibility
- User training materials

---

### Phase 4: User Training & Rollout (2-4 weeks)

**Tasks:**

1. **Training Sessions:**
   - Week 1: Introduction to SLURM (batch jobs, scheduling)
   - Week 2: GPU jobs and containers
   - Week 3: Advanced features (array jobs, dependencies)
   - Week 4: Office hours and Q&A

2. **Documentation:**
```
docs/user-guides/
├── slurm-quickstart.md
├── gpu-jobs.md
├── container-jobs.md
├── ds01-to-slurm-migration.md
└── slurm-cheatsheet.md
```

3. **Support:**
   - Dedicated Slack/Discord channel
   - Office hours (2x/week for 1 month)
   - Email support alias

**Deliverables:**
- Trained user base
- Comprehensive documentation
- Support infrastructure

---

### Phase 5: Optimization & Monitoring (Ongoing)

**Tasks:**

1. **Performance Tuning:**
   - Adjust SLURM scheduler parameters
   - Optimize fairshare policies
   - Fine-tune backfill settings

2. **Monitoring:**
```bash
# SLURM monitoring commands
sinfo        # Node status
squeue       # Job queue
sdiag        # Scheduler diagnostics
sacct        # Accounting data

# Custom dashboards
grafana + prometheus + slurm-exporter
```

3. **Policy Refinement:**
   - Review QoS limits based on usage
   - Adjust priority weights
   - Update fairshare tree

4. **Advanced Features:**
   - Job preemption for urgent work
   - Reservations for deadlines
   - Job arrays for hyperparameter tuning
   - Checkpoint/restart for long jobs

**Deliverables:**
- Tuned SLURM configuration
- Monitoring dashboards
- Usage reports

---

## Migration Strategy

### For Hybrid Architecture (Option 2)

**Timeline: 3-6 months**

**Month 1: Planning & Setup**
- Week 1-2: Stakeholder approval, architecture finalization
- Week 3-4: Test SLURM installation, PoC

**Month 2: Deployment**
- Week 1-2: Production SLURM deployment, accounting setup
- Week 3-4: GPU partitioning, container runtime configuration

**Month 3: Integration**
- Week 1-2: Unified monitoring, documentation
- Week 3-4: Pilot user testing

**Month 4: Training & Rollout**
- Week 1-2: User training sessions
- Week 3-4: General availability announcement

**Month 5-6: Optimization**
- Ongoing support and tuning

**User Impact:**
- **Minimal disruption** - DS01 users continue unchanged
- **Opt-in adoption** - users migrate to SLURM as needed
- **No forced retraining** - gradual learning curve

---

### For Full SLURM Replacement (Option 1)

**Timeline: 6-12 months**

**Month 1-2: Planning**
- Architecture finalization
- User requirements gathering
- PoC testing

**Month 3-4: Core Deployment**
- SLURM installation and configuration
- Container runtime migration (Docker → Singularity)
- Resource limit migration

**Month 5-6: Wrapper Development**
- Build compatibility layer (ds01 commands → SLURM)
- Image conversion and testing
- Parallel testing (DS01 + SLURM both running)

**Month 7-8: User Training**
- Training sessions and workshops
- Documentation creation
- Pilot user group testing

**Month 9: Soft Launch**
- SLURM available, DS01 still default
- Users can opt-in to SLURM

**Month 10: Hard Cutover**
- SLURM becomes primary system
- DS01 deprecated (read-only mode)

**Month 11-12: Optimization & Cleanup**
- Remove DS01 components
- Optimize SLURM configuration
- Post-migration support

**User Impact:**
- **High disruption** - complete workflow change
- **Mandatory retraining** - all users must learn SLURM
- **Risk of user resistance** - some may prefer old system

---

## Risk Analysis

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| SLURM-Docker integration issues | High | High | Use Singularity instead (for Option 1) |
| MIG configuration complexity | Medium | Medium | Use nvidia-mig-discovery tool, extensive testing |
| Resource accounting inaccuracy | Low | Medium | Validate accounting with test jobs |
| User workflow disruption (Option 1) | High | Critical | Hybrid approach (Option 2), phased rollout |
| Container image compatibility | Medium | High | Test image conversion thoroughly |
| GPU allocation race conditions (Option 3) | High | High | Avoid Option 3, use Option 2 instead |

### Organizational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| User resistance to change | High | High | Training, documentation, gradual rollout |
| Loss of institutional knowledge | Medium | Medium | Document DS01 design decisions |
| Support burden increase | High | Medium | Office hours, documentation, Slack channel |
| Training time requirement | High | Medium | Recorded sessions, written guides |

### Schedule Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Underestimated migration effort | High | High | Add 50% buffer to timeline |
| Key personnel unavailability | Medium | High | Cross-training, documentation |
| Vendor/tool bugs | Medium | Medium | Test environment, fallback plan |

---

## Cost-Benefit Analysis

### Costs

**Option 1: Full SLURM Replacement**
- **Development:** 400-800 hours (6-12 months)
- **Training:** 40 hours instruction + 200 hours user learning
- **Risk:** High disruption, potential productivity loss during migration
- **Ongoing:** Lower maintenance (standard SLURM), but loss of custom features

**Option 2: Hybrid SLURM + DS01**
- **Development:** 200-400 hours (3-6 months)
- **Training:** 20 hours instruction + 100 hours user learning (opt-in)
- **Risk:** Low disruption, gradual adoption
- **Ongoing:** Higher maintenance (two systems), but flexibility

**Option 3: SLURM Frontend with DS01 Backend**
- **Development:** 400-600 hours (6-9 months)
- **Training:** 40 hours instruction + 200 hours user learning
- **Risk:** Medium-high technical complexity, debugging challenges
- **Ongoing:** High maintenance (complex integration), fragile

### Benefits

**All Options:**
- ✓ Job queuing and scheduling
- ✓ Fairshare resource allocation
- ✓ Comprehensive accounting and reporting
- ✓ Industry-standard HPC skills for students

**Option 1 Only:**
- ✓ Simpler architecture (single system)
- ✓ Standard HPC environment
- ✓ Full SLURM feature set

**Option 2 Only:**
- ✓ Preserves DS01 educational UX
- ✓ Low migration risk
- ✓ Flexibility to adjust over time

### ROI Analysis

**Breakeven Point:**
- **Option 1:** 12-18 months (high initial cost, lower ongoing)
- **Option 2:** 6-9 months (medium initial cost, medium ongoing)
- **Option 3:** 18-24 months (high initial cost, high ongoing)

**Recommendation:** **Option 2** provides best ROI with lowest risk.

---

## Recommendations

### Primary Recommendation: Hybrid Architecture (Option 2)

**Rationale:**
1. **Low Risk:** DS01 users unaffected, gradual SLURM adoption
2. **Best User Experience:** Interactive work keeps educational UX, batch work gets HPC power
3. **Flexibility:** Can adjust GPU allocation based on demand
4. **Reasonable Timeline:** 3-6 months vs 6-12 for full replacement
5. **Skill Building:** Students learn both modern containers (Docker) and HPC (SLURM)

**Implementation Approach:**
```
Phase 1: Planning & PoC (1 month)
Phase 2: SLURM Deployment (1-2 months)
Phase 3: GPU Partitioning & Integration (1-2 months)
Phase 4: Training & Rollout (1 month)
Phase 5: Optimization (ongoing)
```

**Resource Allocation:**
```yaml
# Recommended GPU split (4x A100 GPUs)
DS01 (Interactive):
  - GPU 0: Full A100 (large model development)
  - GPU 1: MIG 4x 1g.10gb (student experiments)

SLURM (Batch):
  - GPU 2: Full A100 (multi-day training jobs)
  - GPU 3: MIG 4x 1g.10gb (hyperparameter sweeps)

# Adjust based on usage patterns after 3 months
```

---

### Alternative Recommendation: Full SLURM (Option 1)

**When to Choose:**
- User base is entirely graduate researchers/advanced users
- Primary use case is batch training (not interactive development)
- Goal is to prepare students specifically for HPC careers
- Willing to invest in major training effort

**Not Recommended If:**
- User base includes undergraduates or beginners
- Interactive development is common workflow
- Limited time/resources for migration
- DS01's educational UX is valued

---

### Not Recommended: SLURM Frontend with DS01 Backend (Option 3)

**Rationale:**
- High technical complexity (prolog/epilog scripts, state synchronization)
- Fragile integration (multiple points of failure)
- Debugging difficulty (errors span systems)
- Longer timeline than hybrid approach
- No clear advantages over Option 2

**Only Consider If:**
- Must have unified GPU pool (no partitioning)
- Must keep DS01 resource management
- Must have SLURM scheduling
- Have significant development resources for integration layer

---

## Next Steps

### Immediate Actions (This Week)

1. **Schedule Decision Meeting:**
   - Present this document to stakeholders
   - Gather initial feedback
   - Set timeline for decision

2. **User Survey:**
   - Send survey to current DS01 users
   - Questions:
     - Current workflow (interactive vs batch)
     - Interest in SLURM features
     - Training time availability
     - Concerns about changes

3. **Resource Assessment:**
   - Current GPU usage patterns (interactive vs long-running)
   - User demographics (undergrad/grad/faculty)
   - Available development time

### Short Term (Next 2 Weeks)

1. **Finalize Architecture Decision**
2. **Set Up Test Environment**
3. **Create Project Plan with Milestones**
4. **Assign Development Team**

### Medium Term (Next Month)

1. **Begin Phase 1: Planning & PoC**
2. **Test SLURM Installation**
3. **Validate MIG Configuration**
4. **Begin Documentation**

---

## Appendix A: SLURM Command Reference for DS01 Users

### Command Mapping: DS01 → SLURM

| DS01 Command | SLURM Equivalent | Notes |
|--------------|------------------|-------|
| `container-deploy my-proj` | `salloc --gres=gpu:1 --job-name=my-proj` | Interactive allocation |
| `container-run my-proj` | `srun --gres=gpu:1 --container=pytorch.sif bash` | Interactive shell |
| `container-stop my-proj` | `scancel my-proj` | Cancel job |
| `container-list` | `squeue -u $USER` | List jobs |
| `container-stats` | `sstat -j <jobid>` | Job stats |
| N/A | `sbatch train.sh` | Submit batch job |
| N/A | `squeue` | View queue |
| N/A | `sacct` | Job history |

### Example SLURM Job Scripts

**Interactive Session:**
```bash
# Request 1 GPU, 8 CPUs, 32GB RAM for 4 hours
salloc --gres=gpu:1 --cpus-per-task=8 --mem=32G --time=4:00:00

# Once allocated, run container
srun --container=/opt/ds01-images/pytorch.sif bash
```

**Batch Job:**
```bash
#!/bin/bash
#SBATCH --job-name=train-resnet
#SBATCH --output=logs/train-%j.out
#SBATCH --error=logs/train-%j.err
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=48:00:00

# Run training
srun --container=/opt/ds01-images/pytorch.sif \
    python train.py --epochs 100
```

**Array Job (Hyperparameter Sweep):**
```bash
#!/bin/bash
#SBATCH --job-name=hp-sweep
#SBATCH --output=logs/hp-%A-%a.out
#SBATCH --error=logs/hp-%A-%a.err
#SBATCH --gres=gpu:1
#SBATCH --array=1-10
#SBATCH --time=12:00:00

# Learning rates to test
LR=$(awk "NR==$SLURM_ARRAY_TASK_ID" lrs.txt)

srun --container=/opt/ds01-images/pytorch.sif \
    python train.py --lr $LR
```

---

## Appendix B: Resource Configuration Examples

### SLURM Configuration Files

**`/etc/slurm/slurm.conf`** (excerpt):
```
# GPU Node
NodeName=ds01 Gres=gpu:a100:2,mig:1g.10gb:8 CPUs=64 RealMemory=256000 State=UNKNOWN

# Partitions
PartitionName=interactive Nodes=ds01 Default=YES MaxTime=8:00:00 State=UP
PartitionName=batch Nodes=ds01 MaxTime=7-00:00:00 State=UP

# Scheduling
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

# Accounting
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
```

**`/etc/slurm/gres.conf`**:
```
# GPU 2: Full A100
NodeName=ds01 Name=gpu Type=a100 File=/dev/nvidia2

# GPU 3: MIG Partitioned (4x 1g.10gb)
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=0-7
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=8-15
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=16-23
NodeName=ds01 Name=mig Type=1g.10gb File=/dev/nvidia3 Cores=24-31
```

### DS01 Resource Limits (Hybrid Mode)

**`/opt/ds01-infra/config/resource-limits.yaml`** (excerpt):
```yaml
gpu_allocation:
  enable_mig: true
  mig_gpus:
    0:
      enable: false          # DS01: Full GPU
      description: "Interactive - Large Models"
    1:
      enable: true           # DS01: MIG
      profile: 1g.10gb
      instances: 4
      description: "Interactive - Student Experiments"
    2:
      enable: false          # SLURM: Reserved
      reserved: slurm
      description: "SLURM - Batch Training"
    3:
      enable: true           # SLURM: Reserved
      reserved: slurm
      profile: 1g.10gb
      instances: 4
      description: "SLURM - Hyperparameter Sweeps"
```

---

## Appendix C: Glossary

**SLURM:** Simple Linux Utility for Resource Management - open-source workload manager for HPC clusters

**GRES:** Generic Resource Scheduling - SLURM's mechanism for scheduling GPUs, MICs, etc.

**MIG:** Multi-Instance GPU - NVIDIA technology to partition A100/H100 GPUs into independent instances

**Fairshare:** SLURM's algorithm to balance resource usage across users over time

**Backfill:** Scheduling algorithm that runs smaller jobs in gaps while large jobs wait for resources

**QoS:** Quality of Service - SLURM's mechanism for resource limits and priorities

**Prolog/Epilog:** Scripts that run before/after jobs (SLURM feature)

**Singularity/Apptainer:** HPC-focused container runtime (Apptainer is Singularity's new name)

**Ephemeral Containers:** DS01's model where containers are temporary, workspaces are permanent

**scrun:** SLURM's OCI container runtime integration (limited Docker support)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-21 | DS01 Team | Initial strategy document |

---

**For Questions or Feedback:**
- Email: ds01-admin@example.com
- Documentation: https://github.com/your-org/ds01-infra
- Office Hours: Tuesdays 2-4pm, Thursdays 10am-12pm
