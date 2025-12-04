# DS01 Infrastructure Strategic Development Plan

**Version**: 1.0
**Last Updated**: 2025-11-29
**Status**: Approved for Implementation
**Timeline**: Opportunistic (implement as resources allow)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Strategic Vision](#3-strategic-vision)
4. [Architecture Design](#4-architecture-design)
5. [Phase 0: Foundation & Technical Debt](#5-phase-0-foundation--technical-debt)
6. [Phase 1: Web Dashboard](#6-phase-1-web-dashboard)
7. [Phase 2: Experiment Tracking (MLflow)](#7-phase-2-experiment-tracking-mlflow)
8. [Phase 3: Managed Inference (Triton)](#8-phase-3-managed-inference-triton)
9. [Phase 4: SLURM Job Scheduling](#9-phase-4-slurm-job-scheduling)
10. [Phase 5: Cloud Bursting](#10-phase-5-cloud-bursting)
11. [Phase 6: GPU Time-Sharing (MPS)](#11-phase-6-gpu-time-sharing-mps)
12. [Phase 7: Educational & Gamification Features](#12-phase-7-educational--gamification-features)
13. [Phase 8: Green Computing](#13-phase-8-green-computing)
14. [Cross-Cutting Concerns](#14-cross-cutting-concerns)
15. [Implementation Dependencies](#15-implementation-dependencies)
16. [Risk Assessment](#16-risk-assessment)
17. [Success Metrics](#17-success-metrics)
18. [Appendices](#18-appendices)

---

## 1. Executive Summary

### 1.1 Purpose

This document outlines the strategic development roadmap for DS01 Infrastructure, a GPU-enabled container management system for university data science workloads. The plan addresses future-proofing, new capabilities, and user experience improvements while maintaining system stability.

### 1.2 Scope

- **User Base**: Department-scale (30-200 users)
- **Primary Users**: Data science students, researchers, faculty
- **Hardware**: Fixed on-premises GPU infrastructure (NVIDIA A100s with MIG support)
- **Timeline**: Opportunistic implementation as resources permit
- **Deployment**: Private/internal use only

### 1.3 Strategic Goals

| Priority | Goal | Rationale |
|----------|------|-----------|
| 1 | Fix technical debt first | Stable foundation enables new features |
| 2 | Add web-based interfaces | Improve accessibility for all user types |
| 3 | Integrate experiment tracking | Enable reproducible research workflows |
| 4 | Support batch workloads | HPC-style job scheduling for long training |
| 5 | Enable cloud bursting | Elastic capacity for peak demand |
| 6 | Implement GPU sharing | Better utilization for light workloads |
| 7 | Add gamification | Encourage efficient resource usage |
| 8 | Carbon-aware scheduling | Align with university sustainability goals |

### 1.4 Architecture Decision

**Integrator Approach**: Leverage best-of-breed tools (MLflow, SLURM, Triton, JupyterHub) with DS01 as the authentication, quota enforcement, and orchestration layer.

**Rationale**:
- Mature tools with large communities reduce maintenance burden
- Users learn transferable skills (same tools used in industry)
- Conservative stability through battle-tested components
- Future Kubernetes compatibility without immediate migration

### 1.5 Explicitly Out of Scope

The following are **not** being pursued in this planning cycle:
- Complex data pipelines (Airflow, Prefect)
- Feature stores
- Teaching-specific tools (auto-grading, plagiarism detection)
- AR/VR monitoring interfaces
- Voice control / natural language interfaces
- Kubernetes migration (design for compatibility, don't migrate yet)

---

## 2. Current State Analysis

### 2.1 System Overview

DS01 Infrastructure is a mature GPU container management system built on AIME ML Containers v2. It provides:

- **Container Lifecycle**: Create, start, stop, remove with GPU allocation
- **Resource Management**: Per-user/group limits via YAML configuration
- **GPU Allocation**: MIG-aware allocation with file-locking for race safety
- **Monitoring**: Dashboard, event logging, health checks
- **User Onboarding**: Guided wizards for new users

### 2.2 Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CURRENT DS01 ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│   L4: WIZARDS           user-setup, project-init                            │
│   L3: ORCHESTRATORS     container deploy/retire                             │
│   L2: ATOMIC            container-*, image-* commands                       │
│   L1: MLC (HIDDEN)      AIME ML Containers wrappers                         │
│   L0: DOCKER            Base container runtime                              │
├─────────────────────────────────────────────────────────────────────────────┤
│   ENFORCEMENT           Systemd cgroups, Docker wrapper, OPA plugin         │
│   MONITORING            Dashboard, Prometheus-ready, event logging          │
│   CONFIGURATION         resource-limits.yaml (defaults, groups, overrides)  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Strengths

| Strength | Evidence |
|----------|----------|
| Elegant 5-layer architecture | Clear separation of concerns, minimal duplication |
| Strategic AIME integration | 2.2% patch footprint, easy upgrades |
| Comprehensive resource management | YAML-driven, multi-level priority |
| Robust lifecycle automation | 4 coordinated cron jobs |
| Universal enforcement | Defense-in-depth (cgroups, wrapper, OPA) |
| Clean codebase | ~29K LOC, well-organized, good naming |

### 2.4 Known Issues & Technical Debt

| Issue | Severity | Location | Notes |
|-------|----------|----------|-------|
| LDAP groups not populated | High | resource-limits.yaml | "TO DO: autopopulate from LDAP" |
| container-stats --filter bug | Medium | scripts/user/container-stats | Returns "unknown flag" error |
| Label standardization incomplete | Medium | Various | Mixed ds01.* and aime.mlc.* |
| image-create line 1244 bug | Medium | scripts/user/image-create | "creation: command not found" |
| Container-stop timeout too short | Low | Various | 10s default insufficient for large containers |
| No backup strategy documented | Medium | N/A | State files, configs not backed up |
| DEBUG output in mlc-patched.py | Low | scripts/docker/mlc-patched.py | LDAP debugging not cleaned up |

### 2.5 Current Metrics (Baseline)

To be collected before Phase 0:

- [ ] Average GPU utilization (actual compute vs allocated time)
- [ ] Container launch time (time from command to running)
- [ ] User onboarding time (first command to first successful job)
- [ ] Support tickets per month
- [ ] GPU queue wait times (when demand exceeds supply)

---

## 3. Strategic Vision

### 3.1 Target State Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         DS01 INTEGRATOR ARCHITECTURE                        │
├────────────────────────────────────────────────────────────────────────────┤
│  USER INTERFACES                                                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ Web UI   │  │   CLI    │  │ VS Code  │  │ Jupyter  │  │  Notif   │     │
│  │(custom)  │  │(existing)│  │  Ext     │  │   Hub    │  │(push/bot)│     │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘     │
│       └─────────────┴─────────────┴─────────────┴─────────────┘           │
│                                  │                                         │
│  ┌───────────────────────────────┴────────────────────────────────────┐   │
│  │                        DS01 CORE LAYER                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │   │
│  │  │ Auth/SSO    │  │   Quotas    │  │  GPU Alloc  │  │  Metrics  │  │   │
│  │  │  (LDAP)     │  │  (YAML)     │  │  (existing) │  │(Prometheus│  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘  │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                  │                                         │
│  INTEGRATED BEST-OF-BREED TOOLS                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │  MLflow  │  │  Triton  │  │  SLURM   │  │  Cloud   │  │ Grafana  │    │
│  │(tracking)│  │(inference│  │ (batch)  │  │(AWS/GCP) │  │(dashbrd) │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│                                  │                                         │
│  ┌───────────────────────────────┴───────────────────────────────────┐    │
│  │                    COMPUTE LAYER                                   │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐    │    │
│  │  │  Local Docker   │  │   Local SLURM   │  │  Cloud Instances │    │    │
│  │  │   + GPUs        │  │   (future)      │  │   (future)       │    │    │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘    │    │
│  └───────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Design Principles

1. **Leverage, Don't Reinvent**: Use mature tools where they excel
2. **Thin Glue Layer**: DS01 handles auth, quotas, and orchestration only
3. **Transferable Skills**: Users learn industry-standard tools
4. **Conservative Stability**: Each component is battle-tested
5. **Future-Ready**: Design for Kubernetes compatibility without migrating now
6. **Fail-Safe**: Graceful degradation when optional components fail

### 3.3 User Experience Goals

| User Type | Current Experience | Target Experience |
|-----------|-------------------|-------------------|
| New Student | CLI wizard, ~30 min setup | Web wizard OR CLI, <10 min |
| Researcher | CLI for everything | Web dashboard + CLI, real-time monitoring |
| Power User | Full CLI control | Same + batch jobs, cloud bursting |
| Admin | CLI + log files | Web admin panel, Grafana dashboards |

---

## 4. Architecture Design

### 4.1 Component Responsibilities

#### 4.1.1 DS01 Core (Unchanged)

| Component | Responsibility | Changes |
|-----------|---------------|---------|
| Auth/SSO | LDAP integration, user identity | Add LDAP group auto-population |
| Quotas | Per-user/group resource limits | Add hard enforcement, admin override |
| GPU Allocator | MIG-aware allocation, state tracking | Add MPS support |
| Event Logger | Centralized audit trail | Add Prometheus metrics export |

#### 4.1.2 Integrated Tools (New)

| Tool | Purpose | DS01 Integration |
|------|---------|------------------|
| **Prometheus** | Metrics collection | Export DS01 metrics |
| **Grafana** | Visualization | Admin dashboards |
| **MLflow** | Experiment tracking | Auto-configure in containers |
| **Triton** | Model inference | Managed deployment |
| **SLURM** | Job scheduling | DS01 as job executor |
| **JupyterHub** | Notebook access | DS01 as spawner |

### 4.2 API Design

#### 4.2.1 DS01 REST API (Phase 1)

```
Base URL: https://ds01.example.edu/api/v1

Authentication:
  - OAuth2/OIDC with university SSO
  - API tokens for programmatic access

Endpoints:

  # Containers
  GET    /containers                    # List user's containers
  POST   /containers                    # Create container
  GET    /containers/{id}               # Get container details
  DELETE /containers/{id}               # Remove container
  POST   /containers/{id}/start         # Start container
  POST   /containers/{id}/stop          # Stop container

  # Jobs (Phase 4+)
  GET    /jobs                          # List user's jobs
  POST   /jobs                          # Submit job
  GET    /jobs/{id}                     # Get job details
  DELETE /jobs/{id}                     # Cancel job
  GET    /jobs/{id}/logs                # Stream job logs

  # GPUs
  GET    /gpus                          # List GPU status
  GET    /gpus/availability             # Available GPUs for user

  # Users
  GET    /users/me                      # Current user info
  GET    /users/me/quota                # Quota usage
  GET    /users/me/analytics            # Usage analytics

  # Admin (requires admin role)
  GET    /admin/users                   # All users
  PUT    /admin/users/{id}/quota        # Override quota
  GET    /admin/system/health           # System health
  GET    /admin/system/metrics          # Prometheus metrics
```

#### 4.2.2 WebSocket API (Real-time Updates)

```
Endpoint: wss://ds01.example.edu/api/v1/ws

Events:
  - container.status    # Container state changes
  - job.status          # Job state changes
  - gpu.availability    # GPU availability changes
  - quota.alert         # Quota threshold warnings
  - job.completed       # Job completion notifications
```

### 4.3 Data Models

#### 4.3.1 Container

```python
class Container:
    id: str                    # Unique identifier
    name: str                  # User-friendly name
    user: str                  # Owner username
    image: str                 # Docker image
    status: ContainerStatus    # created, running, stopped, removing
    gpu_allocation: list[GPU]  # Allocated GPU(s)
    resources: ResourceLimits  # CPU, memory, etc.
    created_at: datetime
    started_at: datetime | None
    stopped_at: datetime | None
    workspace_path: str        # Mounted workspace
    labels: dict[str, str]     # Container labels
```

#### 4.3.2 Job (Phase 4+)

```python
class Job:
    id: str                    # SLURM job ID
    name: str                  # User-friendly name
    user: str                  # Owner username
    status: JobStatus          # pending, running, completed, failed, cancelled
    script: str                # Job script path
    image: str                 # Docker image
    gpu_request: int           # Requested GPUs
    time_limit: timedelta      # Max runtime
    priority: int              # Queue priority
    submitted_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
    exit_code: int | None
    cloud_target: str | None   # local, aws, gcp, auto
    estimated_cost: float      # Cloud cost estimate
```

#### 4.3.3 User Analytics

```python
class UserAnalytics:
    user: str
    period: str                # week, month, all-time
    gpu_hours: float           # Total GPU time used
    gpu_efficiency: float      # Actual compute / allocated time
    containers_created: int
    jobs_submitted: int
    experiments_logged: int    # MLflow experiments
    models_deployed: int       # Triton deployments
    carbon_kg: float           # Estimated CO2
    achievements: list[str]    # Unlocked achievements
    rank: int                  # Leaderboard position
```

---

## 5. Phase 0: Foundation & Technical Debt

### 5.1 Overview

**Goal**: Establish stable foundation before adding new features
**Estimated Effort**: 2-4 weeks
**Dependencies**: None
**Risk Level**: Low

### 5.2 Priority Fixes

#### 5.2.1 LDAP Integration Completion

**Current State**: Username sanitization works, but user groups empty

**Tasks**:
- [ ] Request LDAP query access from IT (requires ticket)
- [ ] Implement LDAP group discovery script
- [ ] Auto-populate `groups.student.members` and `groups.researcher.members`
- [ ] Add cron job for periodic sync (hourly)
- [ ] Handle edge cases (new users, removed users, group changes)

**Implementation**:

```bash
# scripts/system/sync-ldap-groups.sh
#!/bin/bash
# Sync LDAP groups to resource-limits.yaml

set -e

LDAP_SERVER="ldap://ad.example.edu"
STUDENT_GROUP="CN=ds01-students,OU=Groups,DC=example,DC=edu"
RESEARCHER_GROUP="CN=ds01-researchers,OU=Groups,DC=example,DC=edu"

# Query LDAP for group members
get_group_members() {
    local group_dn="$1"
    ldapsearch -H "$LDAP_SERVER" -b "$group_dn" -s base member \
        | grep "^member:" \
        | sed 's/member: CN=\([^,]*\),.*/\1/' \
        | tr '[:upper:]' '[:lower:]'
}

# Update YAML config
update_config() {
    local students=$(get_group_members "$STUDENT_GROUP" | jq -R . | jq -s .)
    local researchers=$(get_group_members "$RESEARCHER_GROUP" | jq -R . | jq -s .)

    # Use yq to update config
    yq -i ".groups.student.members = $students" /opt/ds01-infra/config/resource-limits.yaml
    yq -i ".groups.researcher.members = $researchers" /opt/ds01-infra/config/resource-limits.yaml
}

# Run sync
update_config
log_event "ldap_sync" "success" "Synced $(echo "$students" | jq length) students, $(echo "$researchers" | jq length) researchers"
```

#### 5.2.2 Bug Fixes

| Bug | File | Fix |
|-----|------|-----|
| container-stats --filter | scripts/user/container-stats | Add --filter flag implementation |
| image-create line 1244 | scripts/user/image-create | Fix syntax error |
| Label standardization | Various | Migrate to consistent ds01.* namespace |
| Container-stop timeout | scripts/user/container-stop | Make timeout configurable (default 30s) |
| DEBUG output cleanup | scripts/docker/mlc-patched.py | Remove LDAP debugging code |

#### 5.2.3 Backup Strategy

**Components to Backup**:

| Component | Location | Frequency | Retention |
|-----------|----------|-----------|-----------|
| GPU state | /var/lib/ds01/gpu-state.json | Hourly | 7 days |
| Container metadata | /var/lib/ds01/container-metadata/ | Hourly | 30 days |
| Resource config | /opt/ds01-infra/config/ | On change | 90 days |
| Event log | /var/log/ds01/events.jsonl | Daily | 1 year |
| User workspaces | /home/*/workspace/ | Daily | 30 days |

**Implementation**:

```bash
# scripts/maintenance/backup-state.sh
#!/bin/bash
# Daily backup of DS01 state

BACKUP_DIR="/var/backups/ds01/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

# State files
cp -a /var/lib/ds01/* "$BACKUP_DIR/state/"

# Configuration
cp -a /opt/ds01-infra/config/* "$BACKUP_DIR/config/"

# Event log (compress)
gzip -c /var/log/ds01/events.jsonl > "$BACKUP_DIR/events.jsonl.gz"

# Cleanup old backups
find /var/backups/ds01 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \;

# Log backup completion
log_event "backup" "success" "Backup completed to $BACKUP_DIR"
```

### 5.3 Observability Upgrades

#### 5.3.1 Prometheus Metrics

**New Metrics to Export**:

```python
# scripts/monitoring/prometheus-exporter.py

from prometheus_client import Gauge, Counter, Histogram

# GPU metrics
gpu_allocated = Gauge('ds01_gpu_allocated_total', 'Total GPUs allocated', ['user', 'type'])
gpu_utilization = Gauge('ds01_gpu_utilization_percent', 'GPU utilization', ['gpu_id', 'type'])
mig_instances_used = Gauge('ds01_mig_instances_used', 'MIG instances in use', ['gpu_id'])

# Container metrics
containers_running = Gauge('ds01_containers_running', 'Running containers', ['user'])
container_start_duration = Histogram('ds01_container_start_seconds', 'Container start time')
container_gpu_hours = Counter('ds01_container_gpu_hours_total', 'GPU hours consumed', ['user'])

# Job metrics (Phase 4+)
jobs_queued = Gauge('ds01_jobs_queued', 'Jobs waiting in queue')
jobs_running = Gauge('ds01_jobs_running', 'Jobs currently running')
job_wait_time = Histogram('ds01_job_wait_seconds', 'Job queue wait time')

# Quota metrics
quota_gpu_used = Gauge('ds01_quota_gpu_used_percent', 'GPU quota used', ['user'])
quota_containers_used = Gauge('ds01_quota_containers_used', 'Container quota used', ['user'])

# System metrics
api_requests = Counter('ds01_api_requests_total', 'API requests', ['endpoint', 'method', 'status'])
api_latency = Histogram('ds01_api_latency_seconds', 'API response time', ['endpoint'])
```

**Prometheus Configuration**:

```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'ds01'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
    metrics_path: /metrics
```

#### 5.3.2 Grafana Dashboards

**Dashboard: DS01 System Overview**

Panels:
1. GPU Utilization (heat map by GPU)
2. Active Containers (time series)
3. GPU Hours by User (bar chart, top 10)
4. Queue Depth (when SLURM added)
5. Container Start Latency (histogram)
6. Quota Alerts (table)

**Dashboard: User Analytics**

Panels:
1. My GPU Usage (gauge)
2. My Efficiency Score (gauge)
3. My Container History (table)
4. Comparison to Average (bar)
5. Quota Remaining (progress bar)

#### 5.3.3 Alertmanager Rules

```yaml
# /etc/prometheus/alerts/ds01.yml
groups:
  - name: ds01
    rules:
      - alert: HighGPUQueueTime
        expr: ds01_job_wait_seconds > 3600
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jobs waiting >1 hour for GPU"

      - alert: UserNearQuota
        expr: ds01_quota_gpu_used_percent > 90
        for: 1m
        labels:
          severity: info
        annotations:
          summary: "User {{ $labels.user }} at 90% GPU quota"

      - alert: GPUUtilizationLow
        expr: ds01_gpu_utilization_percent < 10 and ds01_gpu_allocated_total > 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "GPU allocated but idle for 30+ minutes"
```

### 5.4 Hard Quotas Enhancement

**Current State**: Soft limits with warnings

**Target State**: Hard enforcement with admin override

**Implementation**:

```yaml
# config/resource-limits.yaml additions
quota_enforcement:
  mode: hard                    # soft, hard, or disabled
  grace_period: 5m              # Allow slight overage temporarily
  admin_override_file: /var/lib/ds01/quota-overrides.yaml

# Example override file
# /var/lib/ds01/quota-overrides.yaml
overrides:
  alice:
    max_mig_instances: 4        # Temporarily increased from 2
    expires: 2025-12-31
    reason: "Conference deadline"
    approved_by: admin
```

**Enforcement Logic**:

```python
def check_quota(user: str, requested_gpus: int) -> QuotaResult:
    limits = get_user_limits(user)
    current_usage = get_current_usage(user)
    override = get_override(user)

    effective_limit = override.max_mig_instances if override else limits.max_mig_instances

    if current_usage + requested_gpus > effective_limit:
        if QUOTA_ENFORCEMENT_MODE == "hard":
            return QuotaResult(
                allowed=False,
                message=f"Quota exceeded: {current_usage}/{effective_limit} GPUs used"
            )
        else:
            log_warning(f"Soft quota exceeded for {user}")
            return QuotaResult(allowed=True, warning=True)

    return QuotaResult(allowed=True)
```

### 5.5 Deliverables

- [ ] LDAP group sync script + cron job
- [ ] All bug fixes applied and tested
- [ ] Backup scripts deployed
- [ ] Prometheus exporter running
- [ ] Grafana dashboards configured
- [ ] Alert rules active
- [ ] Hard quota enforcement implemented
- [ ] Admin override mechanism working
- [ ] Documentation updated

---

## 6. Phase 1: Web Dashboard

### 6.1 Overview

**Goal**: Browser-based interface for users and admins
**Estimated Effort**: 4-8 weeks
**Dependencies**: Phase 0 (Prometheus/Grafana)
**Risk Level**: Medium

### 6.2 Requirements

#### 6.2.1 Functional Requirements

**User Features**:
- View own containers and their status
- Launch new containers via web wizard
- Start/stop/remove containers
- View quota usage and remaining allocation
- View personal usage analytics
- Receive job completion notifications
- Access MLflow experiments (when available)

**Admin Features**:
- View all users and their usage
- Override user quotas
- View system health dashboard
- Configure alerts and thresholds
- Manage user groups
- View audit logs

#### 6.2.2 Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| Response time | <200ms for API calls |
| Concurrent users | 100+ simultaneous |
| Uptime | 99.9% availability |
| Security | HTTPS, SSO, CSRF protection |
| Accessibility | WCAG 2.1 AA compliance |
| Mobile | Responsive design |

### 6.3 Technical Design

#### 6.3.1 Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Backend | FastAPI (Python) | Matches existing codebase, async support |
| Frontend | Vue.js 3 + Vite | Modern, fast, good DX |
| UI Framework | Tailwind CSS + Headless UI | Flexible, accessible |
| State Management | Pinia | Vue 3 native, simple |
| Real-time | WebSockets | Native browser support |
| Auth | OAuth2/OIDC | University SSO integration |
| Database | PostgreSQL | Stores sessions, preferences |
| Cache | Redis | Session storage, rate limiting |

#### 6.3.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        NGINX (Reverse Proxy)                     │
│                   - SSL termination                              │
│                   - Static file serving                          │
│                   - Rate limiting                                │
└───────────────┬─────────────────────────────────┬───────────────┘
                │                                 │
                ▼                                 ▼
┌───────────────────────────┐     ┌───────────────────────────────┐
│     FastAPI Backend       │     │      Vue.js Frontend          │
│  ┌─────────────────────┐  │     │  ┌─────────────────────────┐  │
│  │   REST API          │  │     │  │   Dashboard View        │  │
│  │   WebSocket Server  │  │     │  │   Container Manager     │  │
│  │   Auth Middleware   │  │     │  │   Job Submitter         │  │
│  │   Rate Limiter      │  │     │  │   Analytics Charts      │  │
│  └─────────────────────┘  │     │  └─────────────────────────┘  │
│            │              │     └───────────────────────────────┘
│            ▼              │
│  ┌─────────────────────┐  │
│  │   DS01 Core         │  │
│  │   (existing scripts)│  │
│  └─────────────────────┘  │
└───────────────────────────┘
                │
        ┌───────┴───────┐
        ▼               ▼
┌───────────────┐ ┌───────────────┐
│  PostgreSQL   │ │    Redis      │
│  (sessions,   │ │  (cache,      │
│   prefs)      │ │   pubsub)     │
└───────────────┘ └───────────────┘
```

#### 6.3.3 Authentication Flow

```
1. User visits https://ds01.example.edu/
2. Redirect to university SSO (OAuth2 authorize endpoint)
3. User authenticates with university credentials
4. SSO redirects back with authorization code
5. Backend exchanges code for tokens
6. Backend validates tokens, extracts user info
7. Backend creates session, sets secure cookie
8. Frontend loads with user context
```

**Security Considerations**:
- All cookies: `HttpOnly`, `Secure`, `SameSite=Strict`
- CSRF tokens for state-changing operations
- API rate limiting (100 req/min per user)
- Session timeout: 8 hours
- Re-authentication for admin operations

### 6.4 UI/UX Design

#### 6.4.1 User Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│  DS01 Dashboard                              [Alice] [Settings] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ GPU Usage       │  │ Containers      │  │ This Week       │ │
│  │ ████████░░ 80%  │  │ 2 running       │  │ 42 GPU-hours    │ │
│  │ 4/5 instances   │  │ 1 stopped       │  │ 87% efficiency  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  My Containers                              [+ New Container]   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Name          Status    GPU    Created      Actions        ││
│  │ ─────────────────────────────────────────────────────────  ││
│  │ ml-project    Running   MIG-0  2h ago       [Stop] [SSH]   ││
│  │ experiment-1  Running   MIG-1  5h ago       [Stop] [SSH]   ││
│  │ old-test      Stopped   -      3d ago       [Start] [Remove]│
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Recent Activity                                                │
│  • Container "ml-project" started (2h ago)                      │
│  • Experiment logged to MLflow (3h ago)                         │
│  • Container "old-test" stopped due to idle timeout (3d ago)    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 6.4.2 Container Creation Wizard

```
Step 1 of 4: Project Setup
━━━━━━━━━━━━━━━━━━━━━━━━━━

Project Name: [________________]
Description:  [________________]

Workspace:
  ○ Create new workspace
  ● Use existing: [dropdown: my-project, experiment-1, ...]

[Back]                                              [Next →]
```

```
Step 2 of 4: Environment
━━━━━━━━━━━━━━━━━━━━━━━━━━

Base Image:
  ● PyTorch 2.0 + CUDA 12.1
  ○ TensorFlow 2.13 + CUDA 12.1
  ○ Custom Dockerfile

Additional Packages:
  [x] JupyterLab
  [x] pandas, numpy, scikit-learn
  [ ] HuggingFace Transformers
  [ ] OpenCV

[← Back]                                            [Next →]
```

#### 6.4.3 Admin Panel

```
┌─────────────────────────────────────────────────────────────────┐
│  DS01 Admin Panel                          [Admin: root]        │
├─────────────────────────────────────────────────────────────────┤
│  [Users] [GPUs] [Jobs] [Quotas] [Alerts] [Logs]                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  System Health                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ GPUs            │  │ Containers      │  │ Queue           │ │
│  │ 4/8 in use      │  │ 23 running      │  │ 5 waiting       │ │
│  │ ████░░░░ 50%    │  │ 12 users active │  │ ~15min wait     │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  GPU Allocation                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ GPU 0 (A100)  [MIG: 3x 2g.20gb]                            ││
│  │   ├── MIG-0: alice/ml-project (2h)                         ││
│  │   ├── MIG-1: bob/training (5h)                             ││
│  │   └── MIG-2: (available)                                    ││
│  │                                                              ││
│  │ GPU 1 (A100)  [MIG: 3x 2g.20gb]                            ││
│  │   ├── MIG-0: charlie/inference (1h)                        ││
│  │   ├── MIG-1: charlie/inference-2 (1h)                      ││
│  │   └── MIG-2: dave/experiment (30m)                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Quota Overrides                                [+ Add Override]│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ User      Override         Expires     Reason              ││
│  │ alice     4 GPUs (was 2)   2025-12-31  Conference deadline ││
│  │ bob       8h runtime       2025-12-15  Long training job   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.5 Additional Features

#### 6.5.1 User Analytics Dashboard

```python
# API endpoint for user analytics
@router.get("/users/me/analytics")
async def get_user_analytics(
    period: str = "month",  # week, month, all-time
    current_user: User = Depends(get_current_user)
):
    return {
        "period": period,
        "gpu_hours": 142.5,
        "gpu_efficiency": 0.783,  # 78.3%
        "containers_created": 12,
        "experiments_logged": 47,
        "models_deployed": 3,
        "carbon_kg": 2.1,
        "efficiency_trend": [0.72, 0.75, 0.78, 0.81, 0.79, 0.78],  # Weekly
        "rank": 12,
        "total_users": 45,
        "achievements": ["first_experiment", "10_runs", "efficiency_pro"]
    }
```

#### 6.5.2 Office Hours Bot

```python
# Schedule office hours with admin
class OfficeHoursBooking(BaseModel):
    user: str
    requested_time: datetime
    topic: str  # quota, technical, general
    description: str
    status: str  # pending, confirmed, completed, cancelled

@router.post("/office-hours")
async def book_office_hours(
    booking: OfficeHoursBooking,
    current_user: User = Depends(get_current_user)
):
    # Create calendar event
    # Send confirmation email
    # Track in database
    pass
```

#### 6.5.3 Job Completion Notifications

```python
# Notification preferences
class NotificationPreferences(BaseModel):
    email_on_job_complete: bool = True
    email_on_job_failure: bool = True
    webhook_url: str | None = None
    slack_webhook: str | None = None

# Send notification when job completes
async def notify_job_complete(job: Job):
    prefs = get_user_preferences(job.user)

    if prefs.email_on_job_complete:
        send_email(
            to=f"{job.user}@example.edu",
            subject=f"DS01: Job '{job.name}' completed",
            body=f"Your job finished with exit code {job.exit_code}.\n"
                 f"Runtime: {job.runtime}\n"
                 f"View logs: https://ds01.example.edu/jobs/{job.id}"
        )

    if prefs.webhook_url:
        requests.post(prefs.webhook_url, json={
            "event": "job.completed",
            "job_id": job.id,
            "exit_code": job.exit_code
        })
```

### 6.6 Deployment

#### 6.6.1 Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/ssl/certs
      - ./frontend/dist:/usr/share/nginx/html
    depends_on:
      - backend

  backend:
    build: ./backend
    environment:
      - DATABASE_URL=postgresql://ds01:${DB_PASSWORD}@postgres/ds01
      - REDIS_URL=redis://redis:6379
      - SSO_CLIENT_ID=${SSO_CLIENT_ID}
      - SSO_CLIENT_SECRET=${SSO_CLIENT_SECRET}
    volumes:
      - /opt/ds01-infra:/opt/ds01-infra:ro
      - /var/lib/ds01:/var/lib/ds01
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=ds01
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=ds01
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

### 6.7 Deliverables

- [ ] FastAPI backend with all endpoints
- [ ] Vue.js frontend with all views
- [ ] OAuth2/OIDC SSO integration
- [ ] WebSocket real-time updates
- [ ] PostgreSQL schema and migrations
- [ ] Docker Compose deployment
- [ ] Nginx configuration
- [ ] User documentation
- [ ] Admin documentation

---

## 7. Phase 2: Experiment Tracking (MLflow)

### 7.1 Overview

**Goal**: Centralized experiment tracking for reproducible research
**Estimated Effort**: 2-3 weeks
**Dependencies**: Phase 0 (observability)
**Risk Level**: Low

### 7.2 Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  User Container                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  import mlflow                                            │ │
│  │  # Auto-configured by DS01                                │ │
│  │  # MLFLOW_TRACKING_URI=http://mlflow.ds01.internal:5000   │ │
│  │                                                           │ │
│  │  with mlflow.start_run():                                 │ │
│  │      mlflow.log_param("learning_rate", 0.01)             │ │
│  │      mlflow.log_metric("accuracy", 0.95)                 │ │
│  │      mlflow.log_artifact("model.pkl")                    │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  MLflow Tracking Server (managed by DS01)                      │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  MLflow Server                                           │  │
│  │  - Experiment tracking                                   │  │
│  │  - Model registry                                        │  │
│  │  - Artifact storage                                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                              │                                 │
│          ┌───────────────────┼───────────────────┐            │
│          ▼                   ▼                   ▼            │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────┐ │
│  │  PostgreSQL   │  │    MinIO      │  │  DS01 Auth Proxy  │ │
│  │  (metadata)   │  │  (artifacts)  │  │  (user isolation) │ │
│  └───────────────┘  └───────────────┘  └───────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### 7.3 DS01 Integration

#### 7.3.1 Container Environment Variables

```bash
# Automatically set in all containers
MLFLOW_TRACKING_URI=http://mlflow.ds01.internal:5000
MLFLOW_EXPERIMENT_NAME=${DS01_USER}/${DS01_CONTAINER_NAME}
MLFLOW_RUN_TAGS='{"ds01.user":"${DS01_USER}","ds01.container":"${DS01_CONTAINER_ID}"}'
```

#### 7.3.2 User Isolation

```python
# MLflow auth proxy
class MLflowAuthProxy:
    def filter_experiments(self, user: str) -> list[Experiment]:
        """Users see only their own experiments by default."""
        return mlflow.search_experiments(
            filter_string=f"tags.ds01.user = '{user}'"
        )

    def check_access(self, user: str, experiment_id: str) -> bool:
        """Check if user can access experiment."""
        experiment = mlflow.get_experiment(experiment_id)
        owner = experiment.tags.get("ds01.user")

        # Allow access if owner or experiment is public
        return owner == user or experiment.tags.get("public") == "true"
```

#### 7.3.3 Automatic GPU Metrics

```python
# scripts/docker/mlflow-gpu-logger.py
# Runs in container as background thread

import mlflow
import pynvml
import threading
import time

def log_gpu_metrics():
    pynvml.nvmlInit()
    handle = pynvml.nvmlDeviceGetHandleByIndex(0)

    while True:
        if mlflow.active_run():
            util = pynvml.nvmlDeviceGetUtilizationRates(handle)
            memory = pynvml.nvmlDeviceGetMemoryInfo(handle)

            mlflow.log_metrics({
                "gpu_utilization": util.gpu,
                "gpu_memory_used_gb": memory.used / 1e9,
                "gpu_memory_total_gb": memory.total / 1e9,
            })

        time.sleep(60)  # Log every minute

# Start in background
thread = threading.Thread(target=log_gpu_metrics, daemon=True)
thread.start()
```

### 7.4 Deployment

```yaml
# docker-compose.mlflow.yml
version: '3.8'

services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:v2.8.0
    command: >
      mlflow server
      --backend-store-uri postgresql://mlflow:${MLFLOW_DB_PASSWORD}@postgres/mlflow
      --default-artifact-root s3://mlflow-artifacts
      --host 0.0.0.0
      --port 5000
    environment:
      - AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
      - AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
      - MLFLOW_S3_ENDPOINT_URL=http://minio:9000
    ports:
      - "5000:5000"
    depends_on:
      - postgres
      - minio

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=mlflow
      - POSTGRES_PASSWORD=${MLFLOW_DB_PASSWORD}
      - POSTGRES_DB=mlflow
    volumes:
      - mlflow_postgres:/var/lib/postgresql/data

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ACCESS_KEY}
      - MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}
    volumes:
      - mlflow_minio:/data
    ports:
      - "9000:9000"
      - "9001:9001"

volumes:
  mlflow_postgres:
  mlflow_minio:
```

### 7.5 User Guide

```markdown
# Using MLflow with DS01

MLflow is automatically configured in all DS01 containers. No setup required!

## Quick Start

```python
import mlflow

# Start an experiment run
with mlflow.start_run():
    # Log parameters
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_param("batch_size", 32)

    # Train your model...

    # Log metrics
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_metric("loss", 0.05)

    # Save artifacts
    mlflow.log_artifact("model.pkl")

    # Register model
    mlflow.sklearn.log_model(model, "model")
```

## View Experiments

1. Web UI: https://ds01.example.edu/mlflow
2. CLI: `mlflow experiments list`

## Compare Runs

```python
# Find best run
runs = mlflow.search_runs(filter_string="metrics.accuracy > 0.9")
best_run = runs.sort_values("metrics.accuracy", ascending=False).iloc[0]
print(f"Best accuracy: {best_run['metrics.accuracy']}")
```
```

### 7.6 Deliverables

- [ ] MLflow server deployed
- [ ] MinIO artifact storage configured
- [ ] DS01 container integration
- [ ] Auth proxy for user isolation
- [ ] GPU metrics auto-logging
- [ ] Web dashboard integration
- [ ] User documentation
- [ ] Storage quota enforcement

---

## 8. Phase 3: Managed Inference (Triton)

### 8.1 Overview

**Goal**: One-command model deployment with API endpoints
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phase 2 (MLflow model registry)
**Risk Level**: Medium

### 8.2 Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  User Command                                                   │
│  $ model deploy my-classifier.onnx --gpus 0.5                  │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  DS01 Model Controller                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Validate model format (ONNX, TorchScript, TF)       │   │
│  │  2. Allocate GPU (MIG instance or MPS share)            │   │
│  │  3. Create model config for Triton                      │   │
│  │  4. Deploy to Triton server                              │   │
│  │  5. Configure reverse proxy route                        │   │
│  │  6. Return endpoint URL                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Triton Inference Server Pool                                   │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ Triton Instance 1│  │ Triton Instance 2│  ...               │
│  │ GPU: MIG 0:0     │  │ GPU: MIG 0:1     │                    │
│  │ Models:          │  │ Models:          │                    │
│  │ - alice/resnet   │  │ - bob/bert       │                    │
│  │ - alice/yolo     │  │ - charlie/gpt2   │                    │
│  └──────────────────┘  └──────────────────┘                    │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Reverse Proxy (Traefik)                                        │
│  https://inference.ds01.example.edu/alice/resnet/v1/infer      │
│  https://inference.ds01.example.edu/bob/bert/v1/infer          │
└────────────────────────────────────────────────────────────────┘
```

### 8.3 Commands

```bash
# Deploy a model
$ model deploy resnet50.onnx --name my-classifier --gpus 0.5

Validating model format... ONNX detected
Allocating GPU... MIG 0:1 (2g.20gb)
Deploying to Triton... done
Configuring endpoint... done

✓ Model deployed successfully!

Endpoint: https://inference.ds01.example.edu/alice/my-classifier/v1/models/resnet50
GPU: MIG 0:1 (2g.20gb)
Status: Ready

Example request:
  curl -X POST https://inference.ds01.example.edu/alice/my-classifier/v1/models/resnet50/infer \
    -H "Authorization: Bearer $DS01_TOKEN" \
    -d '{"inputs": [{"name": "input", "shape": [1, 3, 224, 224], "datatype": "FP32", "data": [...]}]}'

# List deployed models
$ model list

Name            Status    GPU       Requests/day    Created
my-classifier   Ready     MIG 0:1   1,234           2h ago
text-encoder    Ready     MIG 0:2   567             1d ago

# Get model info
$ model info my-classifier

Name: my-classifier
Endpoint: https://inference.ds01.example.edu/alice/my-classifier/v1/models/resnet50
GPU: MIG 0:1 (2g.20gb)
Format: ONNX
Status: Ready
Created: 2025-11-29 10:30:00
Requests today: 1,234
Avg latency: 12ms
Errors (24h): 0

# Retire a model
$ model retire my-classifier

Stopping model... done
Releasing GPU... MIG 0:1 freed
Removing config... done

✓ Model retired successfully
```

### 8.4 Model Configuration

```python
# scripts/inference/model-config-generator.py

def generate_triton_config(model_path: str, model_name: str) -> str:
    """Generate Triton model configuration."""

    # Detect model format
    if model_path.endswith('.onnx'):
        platform = "onnxruntime_onnx"
        input_shapes = get_onnx_input_shapes(model_path)
    elif model_path.endswith('.pt'):
        platform = "pytorch_libtorch"
        input_shapes = get_torchscript_input_shapes(model_path)
    elif os.path.isdir(model_path) and os.path.exists(f"{model_path}/saved_model.pb"):
        platform = "tensorflow_savedmodel"
        input_shapes = get_tf_input_shapes(model_path)
    else:
        raise ValueError(f"Unsupported model format: {model_path}")

    config = f"""
name: "{model_name}"
platform: "{platform}"
max_batch_size: 8
input [
  {{
    name: "input"
    data_type: TYPE_FP32
    dims: {input_shapes['input']}
  }}
]
output [
  {{
    name: "output"
    data_type: TYPE_FP32
    dims: [-1]
  }}
]
instance_group [
  {{
    count: 1
    kind: KIND_GPU
    gpus: [0]
  }}
]
dynamic_batching {{
  preferred_batch_size: [1, 4, 8]
  max_queue_delay_microseconds: 100
}}
"""
    return config
```

### 8.5 GPU Memory-Aware Scheduling

```python
# scripts/inference/model-scheduler.py

class ModelScheduler:
    def __init__(self):
        self.triton_instances = {}  # GPU -> Triton instance
        self.model_assignments = {}  # model -> GPU

    def find_gpu_for_model(self, model_size_gb: float, user: str) -> str | None:
        """Find a GPU with enough memory for the model."""

        for gpu_id, instance in self.triton_instances.items():
            available_memory = instance.get_available_memory()

            if available_memory >= model_size_gb:
                # Check user quota
                if self.check_inference_quota(user):
                    return gpu_id

        return None

    def deploy_model(self, model_path: str, model_name: str, user: str):
        """Deploy model to Triton."""

        model_size = get_model_size(model_path)
        gpu_id = self.find_gpu_for_model(model_size, user)

        if not gpu_id:
            raise ResourceError("No GPU available with sufficient memory")

        # Copy model to Triton model repository
        model_repo = f"/models/{user}/{model_name}/1"
        os.makedirs(model_repo, exist_ok=True)
        shutil.copy(model_path, f"{model_repo}/model.onnx")

        # Generate config
        config = generate_triton_config(model_path, model_name)
        with open(f"/models/{user}/{model_name}/config.pbtxt", "w") as f:
            f.write(config)

        # Load model in Triton
        self.triton_instances[gpu_id].load_model(f"{user}/{model_name}")

        # Record assignment
        self.model_assignments[f"{user}/{model_name}"] = gpu_id

        return f"https://inference.ds01.example.edu/{user}/{model_name}"
```

### 8.6 Deliverables

- [ ] Triton server deployment
- [ ] Model controller script
- [ ] GPU memory-aware scheduler
- [ ] Reverse proxy configuration
- [ ] CLI commands (model deploy, list, info, retire)
- [ ] Web dashboard integration
- [ ] Request logging and monitoring
- [ ] User documentation

---

## 9. Phase 4: SLURM Job Scheduling

### 9.1 Overview

**Goal**: HPC-style batch job scheduling for long-running workloads
**Estimated Effort**: 4-6 weeks
**Dependencies**: Phase 0 (foundation)
**Risk Level**: High (new subsystem)

### 9.2 Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  User Command                                                   │
│  $ job submit train.py --gpus 2 --time 4h --image my-project   │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  DS01 Job Wrapper                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Validate user quota                                  │   │
│  │  2. Generate SLURM job script                           │   │
│  │  3. Submit to SLURM                                      │   │
│  │  4. Return job ID                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  SLURM Controller                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - Job queue management                                  │   │
│  │  - Priority scheduling (fairshare)                       │   │
│  │  - Resource allocation                                   │   │
│  │  - Node selection                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────┬────────────────────────────────────┘
                            │ When resources available
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  DS01 Job Runner (called by SLURM)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Allocate GPU via DS01 allocator                     │   │
│  │  2. Start Docker container                               │   │
│  │  3. Run user script                                      │   │
│  │  4. Capture logs                                         │   │
│  │  5. Release GPU on completion                            │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Docker Container                                               │
│  - User's custom image                                          │
│  - Mounted workspace                                            │
│  - GPU passthrough                                              │
│  - Script execution                                             │
└────────────────────────────────────────────────────────────────┘
```

### 9.3 SLURM Configuration

```bash
# /etc/slurm/slurm.conf (key settings)

ClusterName=ds01
SlurmctldHost=ds01-head

# Scheduling
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
PriorityType=priority/multifactor
PriorityWeightAge=1000
PriorityWeightFairshare=10000
PriorityWeightJobSize=500
PriorityWeightQOS=2000

# GPU support
GresTypes=gpu
AccountingStorageType=accounting_storage/slurmdbd

# Partitions
PartitionName=gpu Nodes=ds01-gpu[1-4] Default=YES MaxTime=24:00:00 State=UP
PartitionName=interactive Nodes=ds01-gpu[1-4] MaxTime=4:00:00 State=UP

# Node definition
NodeName=ds01-gpu1 CPUs=64 RealMemory=512000 Gres=gpu:a100:8 State=UNKNOWN
```

```bash
# /etc/slurm/gres.conf
NodeName=ds01-gpu1 Name=gpu Type=a100 File=/dev/nvidia[0-7]
```

### 9.4 Commands

```bash
# Submit a batch job
$ job submit train.py --gpus 2 --time 4h --image my-project

Validating quota... OK (2/4 GPUs available)
Submitting job... done

Job submitted successfully!
Job ID: 12345
Estimated start: ~15 minutes (2 jobs ahead)

Track progress: job status 12345
View logs:      job logs 12345 --follow
Cancel:         job cancel 12345

# Submit with more options
$ job submit train.py \
    --gpus 2 \
    --time 8h \
    --image my-project \
    --memory 64G \
    --cpus 16 \
    --name "bert-training" \
    --notify email \
    --env "LEARNING_RATE=0.001" \
    --env "BATCH_SIZE=32"

# Check job status
$ job status

ID      Name           Status    GPUs  Time     Queue Pos
12345   bert-training  Running   2     2h15m    -
12346   eval-script    Pending   1     -        3

$ job status 12345

Job ID: 12345
Name: bert-training
Status: Running
User: alice
GPUs: 2 (GPU 0, GPU 1)
Time elapsed: 2h15m / 8h
Memory: 45G / 64G
Image: alice/my-project:latest
Started: 2025-11-29 08:30:00
Log file: /var/log/ds01/jobs/12345.log

# View logs
$ job logs 12345

[2025-11-29 08:30:15] Starting training...
[2025-11-29 08:30:20] Epoch 1/100, Loss: 2.345
[2025-11-29 08:35:42] Epoch 2/100, Loss: 1.876
...

$ job logs 12345 --follow  # Stream live

# Cancel a job
$ job cancel 12345

Cancelling job 12345... done
GPU released: 2 x A100

# Interactive job (queued, not immediate)
$ job interactive --gpus 1 --time 2h

Waiting for resources... (position 2 in queue)
Resources allocated!
Starting interactive session...
(container) $
```

### 9.5 Job Script Generation

```python
# scripts/slurm/job-wrapper.py

def generate_slurm_script(job_config: JobConfig) -> str:
    """Generate SLURM batch script."""

    return f"""#!/bin/bash
#SBATCH --job-name={job_config.name}
#SBATCH --output=/var/log/ds01/jobs/%j.log
#SBATCH --error=/var/log/ds01/jobs/%j.err
#SBATCH --time={job_config.time_limit}
#SBATCH --gres=gpu:{job_config.gpus}
#SBATCH --mem={job_config.memory}
#SBATCH --cpus-per-task={job_config.cpus}
#SBATCH --partition=gpu

# DS01 job runner
/opt/ds01-infra/scripts/slurm/job-runner.sh \\
    --user "{job_config.user}" \\
    --image "{job_config.image}" \\
    --script "{job_config.script}" \\
    --workspace "{job_config.workspace}" \\
    --gpus "{job_config.gpus}" \\
    --job-id "$SLURM_JOB_ID"
"""

def submit_job(job_config: JobConfig) -> str:
    """Submit job to SLURM."""

    # Check quota
    if not check_job_quota(job_config.user, job_config.gpus):
        raise QuotaError("Insufficient GPU quota for job")

    # Generate script
    script = generate_slurm_script(job_config)
    script_path = f"/tmp/ds01-job-{uuid4()}.sh"
    with open(script_path, "w") as f:
        f.write(script)

    # Submit to SLURM
    result = subprocess.run(
        ["sbatch", script_path],
        capture_output=True,
        text=True
    )

    # Parse job ID
    match = re.search(r"Submitted batch job (\d+)", result.stdout)
    job_id = match.group(1)

    # Log event
    log_event("job_submitted", {
        "job_id": job_id,
        "user": job_config.user,
        "gpus": job_config.gpus,
        "time_limit": job_config.time_limit
    })

    return job_id
```

### 9.6 Job Runner

```bash
#!/bin/bash
# scripts/slurm/job-runner.sh
# Called by SLURM when job starts

set -e

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user) USER="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --script) SCRIPT="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --gpus) GPUS="$2"; shift 2 ;;
        --job-id) JOB_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Allocate GPU via DS01
GPU_ALLOCATION=$(python3 /opt/ds01-infra/scripts/docker/gpu_allocator_v2.py \
    allocate "$USER" "job-$JOB_ID" "$GPUS" 5)

# Extract GPU device IDs
GPU_DEVICES=$(echo "$GPU_ALLOCATION" | jq -r '.devices | join(",")')

# Run container
docker run --rm \
    --gpus "device=$GPU_DEVICES" \
    --user "$(id -u $USER):$(id -g $USER)" \
    -v "$WORKSPACE:/workspace" \
    -v "$SCRIPT:/job/run.py" \
    -w /workspace \
    -e "SLURM_JOB_ID=$JOB_ID" \
    -e "MLFLOW_TRACKING_URI=http://mlflow.ds01.internal:5000" \
    "$IMAGE" \
    python /job/run.py

EXIT_CODE=$?

# Release GPU
python3 /opt/ds01-infra/scripts/docker/gpu_allocator_v2.py \
    release "job-$JOB_ID"

# Log completion
log_event "job_completed" "{\"job_id\": \"$JOB_ID\", \"exit_code\": $EXIT_CODE}"

# Send notification
/opt/ds01-infra/scripts/slurm/notify-completion.sh "$JOB_ID" "$EXIT_CODE"

exit $EXIT_CODE
```

### 9.7 Deliverables

- [ ] SLURM installation and configuration
- [ ] DS01-SLURM integration scripts
- [ ] Job wrapper and runner
- [ ] CLI commands (job submit, status, logs, cancel)
- [ ] Web dashboard integration
- [ ] Queue visualization
- [ ] Notification system
- [ ] User documentation
- [ ] Admin documentation

---

## 10. Phase 5: Cloud Bursting

### 10.1 Overview

**Goal**: Elastic capacity by bursting to AWS/GCP/Azure when local GPUs full
**Estimated Effort**: 6-8 weeks
**Dependencies**: Phase 4 (SLURM)
**Risk Level**: High (cost, complexity)

### 10.2 Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Job Submission                                                 │
│  $ job submit train.py --gpus 4 --cloud auto                   │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────────┐
│  Cloud Router                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Decision factors:                                       │   │
│  │  - Local GPU availability                                │   │
│  │  - Queue wait time                                       │   │
│  │  - Cloud cost                                            │   │
│  │  - User's cloud budget                                   │   │
│  │  - Job requirements                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────┬────────────────────────────────────┘
                            │
           ┌────────────────┼────────────────┐
           ▼                ▼                ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Local SLURM  │  │  AWS Batch    │  │  GCP Batch    │
│               │  │               │  │               │
│  GPU 0-7      │  │  p4d/p5       │  │  A100/H100    │
│  (on-prem)    │  │  (on-demand)  │  │  (on-demand)  │
└───────────────┘  └───────────────┘  └───────────────┘
```

### 10.3 Cloud Provider Configuration

```yaml
# config/cloud-providers.yaml

aws:
  enabled: true
  region: us-east-1
  instance_types:
    - p4d.24xlarge  # 8x A100 40GB
    - p5.48xlarge   # 8x H100 80GB
    - g5.xlarge     # 1x A10G
  spot_enabled: true
  max_spot_price: 5.00  # $/hour
  subnet_id: subnet-abc123
  security_group: sg-abc123
  iam_role: arn:aws:iam::123456789:role/ds01-batch

gcp:
  enabled: true
  project: my-project
  zone: us-central1-a
  machine_types:
    - a2-highgpu-8g  # 8x A100 40GB
    - a3-highgpu-8g  # 8x H100 80GB
  preemptible_enabled: true
  network: default
  service_account: ds01-batch@my-project.iam.gserviceaccount.com

azure:
  enabled: true
  subscription_id: abc123
  resource_group: ds01-batch
  location: eastus
  vm_sizes:
    - Standard_NC24ads_A100_v4  # 1x A100 80GB
    - Standard_ND96asr_v4       # 8x A100 40GB
  spot_enabled: true
```

### 10.4 Cost Tracking

```python
# scripts/cloud/cost-tracker.py

class CostTracker:
    def __init__(self):
        self.db = Database("/var/lib/ds01/cloud-costs.db")

    def record_usage(self, user: str, provider: str, instance_type: str,
                     hours: float, cost: float, job_id: str):
        """Record cloud usage for billing."""
        self.db.insert("cloud_usage", {
            "user": user,
            "provider": provider,
            "instance_type": instance_type,
            "hours": hours,
            "cost": cost,
            "job_id": job_id,
            "timestamp": datetime.now()
        })

    def get_user_spend(self, user: str, period: str = "month") -> float:
        """Get user's cloud spend for period."""
        start_date = self.get_period_start(period)
        return self.db.query(
            "SELECT SUM(cost) FROM cloud_usage WHERE user = ? AND timestamp > ?",
            [user, start_date]
        )[0][0] or 0.0

    def check_budget(self, user: str, estimated_cost: float) -> bool:
        """Check if user has budget for job."""
        current_spend = self.get_user_spend(user, "month")
        budget = get_user_cloud_budget(user)
        return current_spend + estimated_cost <= budget
```

### 10.5 Cloud Job Submission

```bash
$ job submit train.py --gpus 4 --cloud auto

Checking local availability... 0 GPUs free (queue: 5 jobs, ~2h wait)
Checking cloud options...

Cloud Options:
  1. AWS p4d.24xlarge (8x A100)
     - Estimated cost: $32.77/hr x 4hr = $131.08
     - Start time: ~5 minutes

  2. GCP a2-highgpu-8g (8x A100)
     - Estimated cost: $29.39/hr x 4hr = $117.56
     - Start time: ~5 minutes

  3. AWS p4d.24xlarge SPOT
     - Estimated cost: $9.83/hr x 4hr = $39.32 (70% savings!)
     - Start time: ~5 minutes
     - ⚠️  May be interrupted

  4. Wait for local GPU
     - Estimated wait: ~2 hours
     - Cost: $0

Your cloud budget: $200/month ($67.50 used)

Select option [1-4]: 3

Launching spot instance... done
Uploading container image... done
Starting job... done

Job ID: cloud-12345
Provider: AWS (us-east-1)
Instance: p4d.24xlarge (spot)
Estimated cost: $39.32

Track: job status cloud-12345
```

### 10.6 Deliverables

- [ ] Cloud provider integrations (AWS, GCP, Azure)
- [ ] Terraform modules for infrastructure
- [ ] Cloud router logic
- [ ] Cost tracking and budgeting
- [ ] Container image push to cloud registries
- [ ] Workspace sync to cloud storage
- [ ] CLI cloud options
- [ ] Web dashboard integration
- [ ] Cost dashboards
- [ ] User documentation

---

## 11. Phase 6: GPU Time-Sharing (MPS)

### 11.1 Overview

**Goal**: Allow multiple users to share a single GPU efficiently
**Estimated Effort**: 2-3 weeks
**Dependencies**: Phase 0 (foundation)
**Risk Level**: Medium

### 11.2 How MPS Works

NVIDIA Multi-Process Service (MPS) enables:
- Multiple CUDA processes to share a single GPU
- Time-slicing at the CUDA kernel level
- Reduced context switching overhead
- Memory isolation between processes

**Comparison with MIG**:

| Feature | MIG | MPS |
|---------|-----|-----|
| Isolation | Hardware partitions | Software time-slicing |
| Memory | Physically separated | Shared (logically isolated) |
| Overhead | None | Minimal |
| Flexibility | Fixed partitions | Dynamic sharing |
| GPUs | A100, A30, H100 | All CUDA GPUs |
| Best for | Production workloads | Development, inference |

### 11.3 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Physical GPU (A100 80GB)                                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  MPS Control Daemon                                        │  │
│  │  - Manages CUDA contexts                                   │  │
│  │  - Schedules kernel execution                              │  │
│  │  - Enforces memory limits                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Container A   │  │ Container B   │  │ Container C   │       │
│  │ User: alice   │  │ User: bob     │  │ User: carol   │       │
│  │ Share: 33%    │  │ Share: 33%    │  │ Share: 33%    │       │
│  │ Memory: 25GB  │  │ Memory: 25GB  │  │ Memory: 25GB  │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
│                                                                  │
│  Total GPU Memory: 80GB                                         │
│  Reserved for MPS: 5GB                                          │
│  Available for sharing: 75GB                                    │
└─────────────────────────────────────────────────────────────────┘
```

### 11.4 Implementation

```bash
# scripts/gpu/mps-manager.sh

#!/bin/bash
# Manage MPS daemon for GPU sharing

start_mps() {
    local gpu_id=$1

    export CUDA_VISIBLE_DEVICES=$gpu_id
    export CUDA_MPS_PIPE_DIRECTORY=/var/run/nvidia-mps-$gpu_id
    export CUDA_MPS_LOG_DIRECTORY=/var/log/nvidia-mps-$gpu_id

    mkdir -p $CUDA_MPS_PIPE_DIRECTORY $CUDA_MPS_LOG_DIRECTORY

    nvidia-cuda-mps-control -d

    echo "MPS daemon started for GPU $gpu_id"
}

stop_mps() {
    local gpu_id=$1

    export CUDA_MPS_PIPE_DIRECTORY=/var/run/nvidia-mps-$gpu_id

    echo quit | nvidia-cuda-mps-control

    echo "MPS daemon stopped for GPU $gpu_id"
}

set_memory_limit() {
    local gpu_id=$1
    local container_id=$2
    local memory_mb=$3

    export CUDA_MPS_PIPE_DIRECTORY=/var/run/nvidia-mps-$gpu_id

    echo "set_default_device_pinned_mem_limit $container_id $memory_mb M" \
        | nvidia-cuda-mps-control
}
```

### 11.5 Container Integration

```python
# scripts/docker/mps-container-launch.py

def launch_mps_container(user: str, image: str, gpu_share: float):
    """Launch container with MPS GPU sharing."""

    # Find GPU with MPS enabled and available share
    gpu_id = find_mps_gpu_with_capacity(gpu_share)
    if not gpu_id:
        raise ResourceError("No MPS GPU available with requested share")

    # Calculate memory limit
    total_memory = get_gpu_memory(gpu_id)
    memory_limit = int(total_memory * gpu_share * 0.95)  # 5% overhead

    # Set environment for MPS
    mps_env = {
        "CUDA_MPS_PIPE_DIRECTORY": f"/var/run/nvidia-mps-{gpu_id}",
        "CUDA_MPS_LOG_DIRECTORY": f"/var/log/nvidia-mps-{gpu_id}",
    }

    # Launch container
    container = docker.run(
        image=image,
        runtime="nvidia",
        environment={
            **mps_env,
            "CUDA_VISIBLE_DEVICES": str(gpu_id),
            "DS01_GPU_SHARE": str(gpu_share),
        },
        volumes={
            f"/var/run/nvidia-mps-{gpu_id}": {
                "bind": f"/var/run/nvidia-mps-{gpu_id}",
                "mode": "ro"
            }
        },
        labels={
            "ds01.gpu.share": str(gpu_share),
            "ds01.gpu.id": str(gpu_id),
            "ds01.gpu.mode": "mps",
        },
        detach=True,
    )

    # Set memory limit via MPS control
    set_mps_memory_limit(gpu_id, container.id, memory_limit)

    return container
```

### 11.6 Commands

```bash
# Request shared GPU (MPS mode)
$ container deploy my-project --gpu-share 25%

Allocating 25% GPU share... GPU 2 (MPS mode)
Memory limit: 20GB (of 80GB)

Container started in MPS mode.
Note: GPU is shared with other users. For exclusive access, use --gpus 1

# Check GPU sharing status
$ gpu status --mps

GPU 0: Exclusive (alice/training)
GPU 1: MIG mode (3 instances)
GPU 2: MPS mode
  - alice/notebook (25%, 20GB)
  - bob/inference (25%, 20GB)
  - carol/dev (25%, 20GB)
  - Available: 25%, 20GB
GPU 3: Available
```

### 11.7 Deliverables

- [ ] MPS daemon management scripts
- [ ] Container launch with MPS support
- [ ] Memory limit enforcement
- [ ] GPU allocator MPS integration
- [ ] CLI --gpu-share flag
- [ ] Web dashboard MPS view
- [ ] Monitoring for MPS GPUs
- [ ] User documentation

---

## 12. Phase 7: Educational & Gamification Features

### 12.1 Overview

**Goal**: Encourage efficient resource usage through education and gamification
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phase 1 (web dashboard), Phase 0 (metrics)
**Risk Level**: Low

### 12.2 Best Practices Enforcement

#### 12.2.1 Detection Rules

```python
# scripts/best-practices/detector.py

RULES = [
    {
        "id": "memory_overallocation",
        "description": "Requested memory much higher than typical usage",
        "check": lambda req, hist: req.memory > hist.avg_memory * 3,
        "severity": "suggestion",
        "message": "You requested {req.memory}GB but typically use {hist.avg_memory}GB. Consider reducing to save resources."
    },
    {
        "id": "idle_gpu",
        "description": "GPU allocated but idle for extended period",
        "check": lambda metrics: metrics.gpu_util < 5 for > 30 minutes,
        "severity": "warning",
        "message": "Your GPU has been idle for {idle_time}. Consider stopping the container if not in use."
    },
    {
        "id": "no_checkpointing",
        "description": "Long training job without checkpoints",
        "check": lambda job: job.runtime > 2h and not job.has_checkpoints,
        "severity": "suggestion",
        "message": "Your job has been running for {runtime} without saving checkpoints. Add checkpointing to avoid losing progress."
    },
    {
        "id": "single_precision",
        "description": "Training without mixed precision on supported GPU",
        "check": lambda container: container.gpu.supports_fp16 and not container.using_amp,
        "severity": "suggestion",
        "message": "Consider using mixed precision (AMP) to speed up training by ~2x on your A100."
    },
    {
        "id": "small_batch_size",
        "description": "Batch size too small for GPU memory",
        "check": lambda metrics: metrics.gpu_memory_used < 0.3 * metrics.gpu_memory_total,
        "severity": "info",
        "message": "You're only using {pct}% of GPU memory. Increase batch size for better throughput."
    },
]
```

#### 12.2.2 Enforcement Levels

```yaml
# config/best-practices.yaml

enforcement:
  default_level: suggest  # suggest, warn, or block

  rules:
    memory_overallocation:
      level: warn
      threshold: 4x  # Warn if 4x typical usage

    idle_gpu:
      level: warn
      threshold: 30m

    no_checkpointing:
      level: suggest
      threshold: 2h

  admin_overrides:
    - user: alice
      rule: memory_overallocation
      level: disabled
      reason: "Large model training"
      expires: 2025-12-31
```

### 12.3 Leaderboards

```python
# scripts/gamification/leaderboard.py

def calculate_efficiency_score(user: str, period: str = "month") -> float:
    """
    Calculate user's efficiency score (0-100).

    Factors:
    - GPU utilization during allocated time (40%)
    - Job success rate (20%)
    - Resource estimation accuracy (20%)
    - Idle time ratio (20%)
    """

    metrics = get_user_metrics(user, period)

    gpu_score = min(metrics.avg_gpu_util / 80 * 100, 100) * 0.4
    success_score = metrics.job_success_rate * 100 * 0.2
    estimation_score = (1 - abs(metrics.actual_time - metrics.estimated_time) / metrics.estimated_time) * 100 * 0.2
    idle_score = (1 - metrics.idle_ratio) * 100 * 0.2

    return gpu_score + success_score + estimation_score + idle_score

def get_leaderboard(period: str = "month", limit: int = 20) -> list:
    """Get efficiency leaderboard."""

    users = get_active_users(period)
    scores = [(user, calculate_efficiency_score(user, period)) for user in users]
    scores.sort(key=lambda x: x[1], reverse=True)

    return [
        {
            "rank": i + 1,
            "user": user,
            "score": score,
            "gpu_hours": get_gpu_hours(user, period),
        }
        for i, (user, score) in enumerate(scores[:limit])
    ]
```

### 12.4 Achievements

```python
# scripts/gamification/achievements.py

ACHIEVEMENTS = {
    "first_container": {
        "name": "First Steps",
        "description": "Created your first container",
        "icon": "rocket",
        "check": lambda u: get_container_count(u) >= 1,
    },
    "first_experiment": {
        "name": "Scientist",
        "description": "Logged your first MLflow experiment",
        "icon": "flask",
        "check": lambda u: get_experiment_count(u) >= 1,
    },
    "10_experiments": {
        "name": "Researcher",
        "description": "Logged 10 MLflow experiments",
        "icon": "microscope",
        "check": lambda u: get_experiment_count(u) >= 10,
    },
    "100_experiments": {
        "name": "Principal Investigator",
        "description": "Logged 100 MLflow experiments",
        "icon": "award",
        "check": lambda u: get_experiment_count(u) >= 100,
    },
    "efficiency_80": {
        "name": "Efficiency Pro",
        "description": "Maintained 80%+ efficiency for a month",
        "icon": "zap",
        "check": lambda u: get_monthly_efficiency(u) >= 80,
    },
    "first_model": {
        "name": "Model Deployer",
        "description": "Deployed your first inference endpoint",
        "icon": "server",
        "check": lambda u: get_model_count(u) >= 1,
    },
    "green_job": {
        "name": "Eco Warrior",
        "description": "Ran a job during low-carbon hours",
        "icon": "leaf",
        "check": lambda u: has_green_job(u),
    },
    "top_10": {
        "name": "Top Performer",
        "description": "Ranked in top 10 on efficiency leaderboard",
        "icon": "trophy",
        "check": lambda u: get_leaderboard_rank(u) <= 10,
    },
}
```

### 12.5 Resource Analytics Dashboard

```
┌────────────────────────────────────────────────────────────────┐
│                   Your Resource Analytics                       │
│                   November 2025                                 │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Efficiency Score                    Leaderboard Rank          │
│  ┌─────────────────────┐            ┌─────────────────────┐   │
│  │       78.3%         │            │      #12 of 45      │   │
│  │  ████████████░░░░   │            │      Top 27%        │   │
│  └─────────────────────┘            └─────────────────────┘   │
│                                                                 │
│  GPU Hours Used              Carbon Footprint                  │
│  ┌─────────────────────┐    ┌─────────────────────┐           │
│  │      142.5 hrs      │    │     2.1 kg CO₂      │           │
│  │  Up 15% from Oct    │    │  45% below average  │           │
│  └─────────────────────┘    └─────────────────────┘           │
│                                                                 │
│  Weekly Efficiency Trend                                       │
│  100%│                                                         │
│   80%│    ╭──╮   ╭───╮   ╭──╮                                 │
│   60%│───╯    ╰─╯     ╰──╯  ╰───                              │
│   40%│                                                         │
│   20%│                                                         │
│    0%└────────────────────────────────────                     │
│       W1   W2   W3   W4                                        │
│                                                                 │
│  Achievements                                                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ 🚀 First Steps    🔬 Scientist    📈 Efficiency Pro     │  │
│  │ 🧪 Researcher     🖥️ Model Deployer                      │  │
│  │                                                          │  │
│  │ Locked: 🏆 Top Performer, 🌱 Eco Warrior                │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Suggestions                                                    │
│  • Your idle time is 15%. Try stopping containers when not in  │
│    use to improve efficiency.                                   │
│  • Run jobs during off-peak hours (2-6am) to reduce carbon     │
│    footprint and earn the Eco Warrior badge!                   │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### 12.6 Deliverables

- [ ] Best practices detection engine
- [ ] Configurable enforcement levels
- [ ] Leaderboard calculation and display
- [ ] Achievement system
- [ ] Resource analytics dashboard
- [ ] Suggestion engine
- [ ] Notification integration
- [ ] Documentation

---

## 13. Phase 8: Green Computing

### 13.1 Overview

**Goal**: Carbon-aware job scheduling aligned with university sustainability goals
**Estimated Effort**: 2-3 weeks
**Dependencies**: Phase 4 (SLURM)
**Risk Level**: Low

### 13.2 Carbon Intensity Data

```python
# scripts/carbon/intensity-fetcher.py

import requests
from datetime import datetime, timedelta

class CarbonIntensityAPI:
    """Fetch carbon intensity data from electricity grid APIs."""

    PROVIDERS = {
        "electricitymap": {
            "url": "https://api.electricitymap.org/v3/carbon-intensity/forecast",
            "auth": "header",
        },
        "watttime": {
            "url": "https://api2.watttime.org/v2/forecast",
            "auth": "oauth",
        },
        "uk_grid": {
            "url": "https://api.carbonintensity.org.uk/intensity/",
            "auth": None,
        },
    }

    def __init__(self, provider: str, api_key: str = None):
        self.provider = provider
        self.api_key = api_key
        self.cache = {}

    def get_current(self) -> float:
        """Get current carbon intensity in gCO2/kWh."""
        return self._fetch()["current"]

    def get_forecast(self, hours: int = 24) -> list[dict]:
        """Get carbon intensity forecast."""
        return self._fetch()["forecast"][:hours]

    def find_best_window(self, duration_hours: float) -> datetime:
        """Find the best time to run a job to minimize carbon."""

        forecast = self.get_forecast(48)  # 48-hour forecast

        # Sliding window to find minimum average intensity
        best_start = None
        best_avg = float("inf")

        for i in range(len(forecast) - int(duration_hours)):
            window = forecast[i:i + int(duration_hours)]
            avg = sum(w["intensity"] for w in window) / len(window)

            if avg < best_avg:
                best_avg = avg
                best_start = window[0]["datetime"]

        return best_start, best_avg
```

### 13.3 Carbon Tracking

```python
# scripts/carbon/tracker.py

class CarbonTracker:
    """Track carbon emissions from compute jobs."""

    # GPU power consumption estimates (Watts)
    GPU_POWER = {
        "a100_40gb": 400,
        "a100_80gb": 400,
        "h100_80gb": 700,
        "a10g": 150,
        "mig_2g20gb": 133,  # 1/3 of A100
    }

    def __init__(self, intensity_api: CarbonIntensityAPI):
        self.intensity_api = intensity_api
        self.db = Database("/var/lib/ds01/carbon.db")

    def calculate_emissions(self, gpu_type: str, hours: float,
                           when: datetime = None) -> float:
        """Calculate CO2 emissions in kg."""

        # Get power consumption
        power_w = self.GPU_POWER.get(gpu_type, 400)

        # Get carbon intensity at time of computation
        if when:
            intensity = self.get_historical_intensity(when)
        else:
            intensity = self.intensity_api.get_current()

        # Calculate: kWh * gCO2/kWh = gCO2
        kwh = (power_w / 1000) * hours
        g_co2 = kwh * intensity

        return g_co2 / 1000  # Return kg

    def record_job_emissions(self, job_id: str, user: str,
                            gpu_type: str, hours: float):
        """Record carbon emissions for a job."""

        emissions = self.calculate_emissions(gpu_type, hours)

        self.db.insert("carbon_emissions", {
            "job_id": job_id,
            "user": user,
            "gpu_type": gpu_type,
            "hours": hours,
            "emissions_kg": emissions,
            "timestamp": datetime.now(),
        })

        return emissions

    def get_user_footprint(self, user: str, period: str = "month") -> dict:
        """Get user's carbon footprint."""

        start = self.get_period_start(period)

        result = self.db.query("""
            SELECT SUM(emissions_kg) as total,
                   AVG(emissions_kg / hours) as avg_per_hour,
                   COUNT(*) as job_count
            FROM carbon_emissions
            WHERE user = ? AND timestamp > ?
        """, [user, start])

        # Compare to average user
        avg_emissions = self.get_average_emissions(period)

        return {
            "total_kg": result[0]["total"] or 0,
            "avg_per_hour": result[0]["avg_per_hour"] or 0,
            "job_count": result[0]["job_count"] or 0,
            "vs_average": (result[0]["total"] or 0) / avg_emissions if avg_emissions else 0,
        }
```

### 13.4 Green Scheduling

```python
# scripts/carbon/green-scheduler.py

class GreenScheduler:
    """Schedule jobs during low-carbon periods."""

    def __init__(self, carbon_api: CarbonIntensityAPI, slurm: SlurmClient):
        self.carbon_api = carbon_api
        self.slurm = slurm

    def submit_green_job(self, job: Job) -> str:
        """Submit job to run during low-carbon window."""

        # Find best window
        best_start, best_intensity = self.carbon_api.find_best_window(
            job.estimated_hours
        )

        # Calculate savings
        current_intensity = self.carbon_api.get_current()
        savings_pct = (current_intensity - best_intensity) / current_intensity * 100

        # Show user the options
        print(f"""
Carbon-Aware Scheduling

Current intensity: {current_intensity:.0f} gCO2/kWh
Best window: {best_start.strftime('%Y-%m-%d %H:%M')} ({best_intensity:.0f} gCO2/kWh)
Potential savings: {savings_pct:.0f}%

Your job would emit:
  - Run now: {self.calculate_emissions(job, current_intensity):.2f} kg CO2
  - Run at best time: {self.calculate_emissions(job, best_intensity):.2f} kg CO2
        """)

        # Submit with delay
        delayed_start = best_start.strftime("%Y-%m-%dT%H:%M:00")
        job_id = self.slurm.submit(job, begin=delayed_start)

        return job_id
```

### 13.5 Commands

```bash
# Submit job to run when carbon is low
$ job submit train.py --gpus 2 --green

Checking carbon intensity forecast...

Grid Carbon Intensity (next 24h):
├─ Now:    387 gCO2/kWh  ▓▓▓▓▓▓▓░░░ (High)
├─ 2am:    156 gCO2/kWh  ▓▓▓░░░░░░░ (Low)  ⭐ Best window
└─ 8am:    298 gCO2/kWh  ▓▓▓▓▓░░░░░ (Medium)

Your job "train.py" requires ~4 hours

Estimated emissions:
  - Run now:      2.1 kg CO₂
  - Run at 2am:   0.8 kg CO₂  (62% reduction!)

Job scheduled for 2025-11-30 02:00
Job ID: 12345

# Check current carbon intensity
$ carbon status

Current Grid Status: Germany
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Carbon Intensity: 387 gCO2/kWh  ▓▓▓▓▓▓▓░░░ HIGH

Energy Mix:
  Coal: 25%     ████████████░░░░░░░░░░░░░
  Gas: 30%      ██████████████░░░░░░░░░░░
  Nuclear: 10%  █████░░░░░░░░░░░░░░░░░░░░
  Wind: 20%     ██████████░░░░░░░░░░░░░░░
  Solar: 10%    █████░░░░░░░░░░░░░░░░░░░░
  Other: 5%     ██░░░░░░░░░░░░░░░░░░░░░░░

Forecast:
  Next 6h: 350-400 gCO2/kWh (High)
  Tonight: 150-200 gCO2/kWh (Low) ⭐
  Tomorrow: 250-350 gCO2/kWh (Medium)

Recommendation: Delay non-urgent jobs to tonight for 60% carbon savings

# View your carbon footprint
$ carbon report

Your Carbon Footprint - November 2025
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total Emissions:     2.1 kg CO₂
GPU Hours:           142.5 hours
Avg per GPU-hour:    14.7 g CO₂

Comparison:
  You:       ████░░░░░░░░░░░░░░░░ 2.1 kg
  Average:   ██████████░░░░░░░░░░ 4.6 kg

  You're 54% below average! 🌱

Green Jobs: 3 (saved 1.2 kg CO₂)

Tips:
  • Schedule training jobs for 2-6am when renewables are highest
  • Use --green flag to automatically find low-carbon windows
```

### 13.6 Deliverables

- [ ] Carbon intensity API integration
- [ ] Carbon tracking database
- [ ] Green scheduler
- [ ] CLI commands (carbon status, carbon report)
- [ ] Web dashboard carbon view
- [ ] Monthly sustainability reports
- [ ] Integration with achievements
- [ ] Documentation

---

## 14. Cross-Cutting Concerns

### 14.1 Dev Containers

**Goal**: Support VS Code Dev Containers with GPU passthrough

```json
// .devcontainer/devcontainer.json
{
  "name": "DS01 ML Environment",
  "image": "ds01-alice/my-project:latest",
  "runArgs": [
    "--gpus", "device=0",
    "--shm-size=16g"
  ],
  "mounts": [
    "source=/home/alice/workspace/my-project,target=/workspace,type=bind"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-toolsai.jupyter"
      ]
    }
  },
  "remoteUser": "alice"
}
```

### 14.2 JupyterHub Integration

**Options** (to be decided):

**Option A: Central JupyterHub**
- Single JupyterHub instance
- DS01 as custom spawner backend
- Users access via `https://jupyter.ds01/`

**Option B: Per-Container Jupyter**
- Each container runs its own Jupyter
- JupyterHub just routes to correct container

**Option C: Hybrid**
- Hub for quick work (pre-built kernels)
- Full containers for serious training

### 14.3 Notification System

```python
# scripts/notifications/notifier.py

class NotificationService:
    """Multi-channel notification service."""

    def __init__(self):
        self.email = EmailNotifier()
        self.webhook = WebhookNotifier()
        self.slack = SlackNotifier()

    def notify(self, user: str, event: str, data: dict):
        """Send notification based on user preferences."""

        prefs = get_user_preferences(user)

        if event == "job_completed" and prefs.email_on_job_complete:
            self.email.send(
                to=f"{user}@example.edu",
                subject=f"DS01: Job '{data['name']}' completed",
                template="job_completed",
                data=data
            )

        if prefs.webhook_url:
            self.webhook.send(prefs.webhook_url, {
                "event": event,
                **data
            })

        if prefs.slack_webhook:
            self.slack.send(prefs.slack_webhook, {
                "text": self.format_slack_message(event, data)
            })
```

### 14.4 User Support System

**Office Hours Bot**:
- Schedule time with admin
- Track support issues
- FAQ integration
- Ticket routing

---

## 15. Implementation Dependencies

### 15.1 Dependency Graph

```
Phase 0 (Foundation / Tech Debt)
    │
    ├──→ Phase 1 (Web Dashboard)
    │         │
    │         ├──→ Phase 7 (Gamification)
    │         │         │
    │         │         └──→ Phase 8 (Green Computing)
    │         │
    │         └──→ User Analytics, Notifications, Office Hours
    │
    ├──→ Phase 2 (MLflow)
    │         │
    │         └──→ Phase 3 (Inference/Triton)
    │
    ├──→ Phase 4 (SLURM)
    │         │
    │         └──→ Phase 5 (Cloud Bursting)
    │
    └──→ Phase 6 (GPU Time-Sharing/MPS) [independent]
```

### 15.2 Parallel Workstreams

| Stream | Phases | Can Start After |
|--------|--------|-----------------|
| UX | 1 → 7 → 8 | Phase 0 |
| ML Workflow | 2 → 3 | Phase 0 |
| HPC | 4 → 5 | Phase 0 |
| Efficiency | 6 | Phase 0 |

### 15.3 Technology Stack

| Component | Primary | Alternative |
|-----------|---------|-------------|
| Job Scheduler | SLURM | Kubernetes Jobs |
| Web Backend | FastAPI | Flask |
| Web Frontend | Vue.js 3 | React |
| Experiment Tracking | MLflow | Weights & Biases |
| Inference Server | Triton | TensorFlow Serving |
| Monitoring | Prometheus + Grafana | Datadog |
| Cloud IaC | Terraform | Pulumi |
| Carbon API | electricityMap | WattTime |
| Database | PostgreSQL | SQLite (dev) |
| Cache | Redis | Memcached |

---

## 16. Risk Assessment

### 16.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| SLURM complexity | High | High | Start with minimal config, iterate |
| Cloud cost overruns | Medium | High | Hard budget limits, alerts |
| SSO integration issues | Medium | Medium | Early IT engagement |
| MPS stability | Low | Medium | Extensive testing, fallback to MIG |
| MLflow scale issues | Low | Low | Start with local storage |

### 16.2 Organizational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| IT resistance | Medium | High | Early engagement, pilot program |
| User adoption | Medium | Medium | Training, good docs, gradual rollout |
| Resource constraints | High | Medium | Prioritize phases, opportunistic timeline |
| Scope creep | Medium | Medium | Strict phase boundaries |

### 16.3 Contingency Plans

**If SLURM too complex**: Use simple DS01-native job queue
**If cloud bursting too expensive**: Focus on local optimization (MPS, better scheduling)
**If SSO fails**: Fallback to LDAP bind authentication

---

## 17. Success Metrics

### 17.1 Phase 0 Success Criteria

- [ ] All critical bugs fixed
- [ ] LDAP groups auto-populated
- [ ] Prometheus metrics exported
- [ ] Grafana dashboards deployed
- [ ] Backup system operational
- [ ] No new regressions

### 17.2 Overall Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| GPU utilization | TBD | +20% | Prometheus |
| Container start time | TBD | <30s | Prometheus |
| User onboarding time | ~30min | <10min | Survey |
| Support tickets/month | TBD | -30% | Ticket system |
| User satisfaction | TBD | >4.0/5 | Survey |
| Carbon per GPU-hour | TBD | -30% | Carbon tracker |

### 17.3 Phase-Specific Metrics

| Phase | Key Metric | Target |
|-------|------------|--------|
| 1 | Web dashboard adoption | 50% of users |
| 2 | MLflow experiments logged | 100/month |
| 3 | Models deployed | 10 active |
| 4 | Batch jobs submitted | 50/week |
| 5 | Cloud jobs run | 10% of batch jobs |
| 6 | MPS utilization | 30% of GPU time |
| 7 | Efficiency score avg | 75% |
| 8 | Green jobs | 20% of batch jobs |

---

## 18. Appendices

### 18.1 Glossary

| Term | Definition |
|------|------------|
| MIG | Multi-Instance GPU - NVIDIA hardware partitioning |
| MPS | Multi-Process Service - NVIDIA GPU time-sharing |
| SLURM | Simple Linux Utility for Resource Management |
| Triton | NVIDIA Triton Inference Server |
| MLflow | Open-source ML experiment tracking |
| Fairshare | SLURM scheduling policy for equitable access |

### 18.2 Reference Links

- [NVIDIA MIG Documentation](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [NVIDIA MPS Documentation](https://docs.nvidia.com/deploy/mps/)
- [SLURM Documentation](https://slurm.schedmd.com/)
- [MLflow Documentation](https://mlflow.org/docs/latest/)
- [Triton Inference Server](https://github.com/triton-inference-server/server)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Vue.js Documentation](https://vuejs.org/)
- [electricityMap API](https://api.electricitymap.org/)

### 18.3 File Locations

| Component | Location |
|-----------|----------|
| This plan | /opt/ds01-infra/TODO/planning_doc.md |
| Planning session notes | /home/datasciencelab/.claude/plans/snazzy-launching-leaf.md |
| Resource config | /opt/ds01-infra/config/resource-limits.yaml |
| Scripts | /opt/ds01-infra/scripts/ |
| State files | /var/lib/ds01/ |
| Logs | /var/log/ds01/ |
| Web dashboard | /opt/ds01-dashboard/ (future) |
| MLflow | /opt/ds01-mlflow/ (future) |

### 18.4 Change Log

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-11-29 | 1.0 | DS01 Team | Initial version |

---

*End of Document*

---

## 19. Open Issues & Technical Debt

### 19.1 Container Labeling Gap (HIGH PRIORITY)

**Status**: Open  
**Date Identified**: 2025-12-04  
**Related Doc**: `/opt/ds01-infra/docs/docker-permissions-migration.md`

#### Problem

Containers created via Docker API (not CLI) don't receive DS01 ownership labels:

| Creation Method | Gets `ds01.user` Label | Gets `ds01.managed` Label |
|-----------------|------------------------|---------------------------|
| CLI (`docker run`) via wrapper | ✅ Yes | ✅ Yes |
| VS Code Dev Containers | ❌ No | ❌ No |
| Docker Compose | ❌ No | ❌ No |
| Direct Docker API | ❌ No | ❌ No |

**Impact**:
- Cleanup scripts only process containers with `aime.mlc.USER` or `ds01.managed=true` labels
- VS Code dev containers are never auto-removed
- Visibility filtering works (wrapper catches `docker ps`) but ownership tracking incomplete

#### Root Cause

1. **Wrapper limitation**: `/usr/local/bin/docker` only intercepts CLI commands
2. **Docker labels are immutable**: Cannot add labels after container creation
3. **Cleanup script filter**: Uses `--filter "label=aime.mlc.USER"` only

#### Current Workarounds

1. **Sync script** (`sync-container-owners.py`) detects owners from multiple sources:
   - `ds01.user` label
   - `aime.mlc.USER` label  
   - `devcontainer.local_folder` label (extracts username from path)

2. **External JSON** (`/var/lib/ds01/opa/container-owners.json`) tracks all containers

#### Proposed Solutions

**Option A: Update cleanup scripts to use sync logic**
- Modify `cleanup-stale-containers.sh` to detect owners like `sync-container-owners.py`
- Check multiple label sources, not just `aime.mlc.USER`
- Estimated effort: 2-3 hours

**Option B: Add container labeler service**
- Docker event listener that labels new containers post-creation
- Problem: Docker labels are immutable after creation
- Would need to track in external file instead

**Option C: Use external JSON for cleanup decisions**
- Cleanup scripts read `/var/lib/ds01/opa/container-owners.json`
- Already synced by `sync-container-owners.py`
- Estimated effort: 1-2 hours

#### Files Affected

- `/opt/ds01-infra/scripts/maintenance/cleanup-stale-containers.sh` (line 96)
- `/opt/ds01-infra/scripts/docker/sync-container-owners.py` (reference implementation)
- `/opt/ds01-infra/scripts/docker/docker-wrapper.sh` (current labeling)

#### Action Items

- [ ] Decide on solution approach (A, B, or C)
- [ ] Update cleanup script to handle dev containers
- [ ] Test with VS Code dev container
- [ ] Update documentation

---

### 19.2 OPA Authorization Blocking (PARKED)

**Status**: Parked  
**Date Identified**: 2025-12-04  
**Related Doc**: `/opt/ds01-infra/docs/docker-permissions-migration.md`

#### Problem

OPA authorization plugin installed but not functional - cannot block users from exec/stop on other users' containers.

#### Root Cause

The `opa-docker-authz` plugin doesn't support `-data-file` flag. Without external data, the policy can't look up container ownership.

#### Current State

- OPA plugin: Installed at `/usr/local/bin/opa-docker-authz`
- Policy: Ready at `/opt/ds01-infra/config/opa/docker-authz.rego`
- Service: Disabled
- Authorization: Not in `daemon.json`

#### Solution When Resumed

Use OPA in server mode to load both policy and data:

```bash
opa run --server --addr localhost:8181 policy.rego data.json
opa-docker-authz -opa-url http://localhost:8181/v1/data/docker/authz/allow
```

See `/opt/ds01-infra/docs/docker-permissions-migration.md` for full details.
