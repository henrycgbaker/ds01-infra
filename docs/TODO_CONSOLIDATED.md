# DS01 Infrastructure - Active TODO List

**Last Updated:** 2025-11-29
**Status:** Core system production-ready, polish and expansion in progress

---

## Status Summary

| Priority | Count | Description |
|----------|-------|-------------|
| HIGH | 8 | Blocking or critical for operations |
| MEDIUM | 12 | Important improvements |
| LOW | 8 | Nice to have / future |

---

## HIGH PRIORITY

### User Migration & Access Control

- [ ] **Migrate users to container workflow**
  - Communicate to current users about saving work
  - Block bare metal GPU access
  - Clean up old containers and processes

- [ ] **Get LDAP query access from IT**
  - Need to understand how AD users are managed
  - Enable auto-discovery of new users
  - Currently can only scan /home directories

- [ ] **Document new user workflow**
  - How users get server access (IT-managed)
  - How to add users to appropriate groups
  - Auto-registration script for cron

### Container System

- [ ] **Fix container-stats --filter bug**
  - Error: "unknown flag: --filter"
  - Minor but visible to users

- [ ] **Complete label standardization (ds01.* --> aime.mlc.*)**
  - Files to update: image-create, container-list, monitoring scripts
  - Containers use aime.mlc.*, images still use ds01.*
  - Need unified namespace for filtering

### GPU & Resources

- [ ] **Test with MIG-enabled GPUs**
  - Current tests use physical GPUs
  - Need to verify MIG allocation works in production
  - Test multi-MIG per container scenario

- [ ] **Enable multiple GPU/MIG per container**
  - For large LLM use cases requiring more memory
  - Respect user's `max_mig_instances` limit
  - Update container-create GUI with selection

### System Administration

- [ ] **Set up backup strategy**
  - Identify items: /home dirs, docker volumes, infra repo
  - Implement backup schedule
  - Document restoration process

---

## MEDIUM PRIORITY

### Images & Dockerfiles

- [ ] **Rename image-create --> image-build**
  - Update script, alias, and all dependencies
  - Aligns with Docker terminology

- [ ] **Fix image-create line 1244 bug**
  - Error: "creation: command not found"

- [ ] **Fix image-update rebuild flow**
  - After updating dockerfile, should offer to rebuild image
  - Currently doesn't trigger rebuild option

### Containers

- [ ] **Separate container-start vs container-run in documentation**
  - Clarify when to use each
  - Add --guided explanation of state differences

- [ ] **Add --running, --stopped, --all flags to container-list**
  - More filtering options for users
  - Currently shows all containers

- [ ] **Increase container-stop timeout (>10s)**
  - Currently hits timeout on large containers
  - Consider 30s default

### Monitoring & Logging

- [ ] **Add Grafana & Prometheus**
  - Visual dashboards for metrics
  - Historical data analysis
  - Alerting integration

- [ ] **Audit monitoring scripts for mlc-patched compatibility**
  - Verify all work with new container labels
  - Check GPU tracking accuracy

### Documentation

- [ ] **Update README.md with AIME v2 details**
  - Current focus is architecture, needs integration details

- [ ] **Document user groups and permissions**
  - ds-admin, gpu-users, gpu-priority, docker-users
  - When to add users to each group

- [ ] **Fix architecture documentation**
  - Currently says "4-tiered" in some places
  - Should consistently say "5-layer" hierarchy

### User Setup & Wizards

- [ ] **user-setup doesn't read user's existing images**
  - Shows "No custom images yet" when images exist

- [ ] **VS Code setup positioning in user-setup**
  - Should come after SSH keys, before dir/image setup

---

## LOW PRIORITY / FUTURE

### Nice to Have

- [ ] **Contribute --image flag upstream to AIME**
  - Benefit AIME community
  - 3-4 hours effort for PR

- [ ] **Dynamic MIG configuration**
  - Auto-partition GPUs based on demand
  - Reconfigure MIG profiles on-the-fly

- [ ] **SLURM integration**
  - Job scheduling for batch workloads
  - Deferred - significant complexity

- [ ] **alias-list for inside containers**
  - Show container-specific commands when inside container
  - Mirror host alias-list functionality

### Directory & Permissions

- [ ] **Sort out /collaborative and /readonly permissions**
  - Base access on user groups
  - Update documentation when confirmed

- [ ] **Change /scratch permissions to request-based**
  - Students request access via usergroups
  - Not automatic

### Container Advanced

- [ ] **Container persistence option (--keep-container flag)**
  - For users who need to keep stopped containers
  - Phase 2 of ephemeral model

- [ ] **DS01_CONTEXT for cron-launched containers**
  - Containers from cron should be tracked properly

---

## COMPLETED (Recent Major Items)

For context, here are major items completed in the past month:

- [x] LDAP/SSSD username support and sanitization
- [x] Auto docker group management via PAM
- [x] Dashboard redesign with multiple views
- [x] Resource alerts at 80% of limits
- [x] Layered architecture implementation (5 layers)
- [x] Universal enforcement (cgroups, OPA, Docker wrapper)
- [x] 149-test automated test suite
- [x] mlc-patched.py for custom image support
- [x] GPU allocator integration with container creation
- [x] Container lifecycle automation (idle, runtime, cleanup)
- [x] Image workflow redesign (4-phase package selection)
- [x] Tier 2 command refactoring (container-list, container-stop, etc.)
- [x] --guided flag coverage across all commands
- [x] Interactive selection GUIs

---

## Questions for IT / Stakeholders

1. **How are AD users provisioned?** Need to understand for auto-registration
2. **Can we get LDAP query access?** For user discovery
3. **Backup infrastructure?** Is there existing backup for /home?
4. **Monitoring integration?** Existing Grafana/Prometheus we can use?

---

## Reference Documents

- Architecture: `README.md`
- Audits: `docs/DS01_LAYER_AUDIT.md`, `docs/AIME_FRAMEWORK_AUDIT_v2.md`
- Strategy: `docs/INTEGRATION_STRATEGY_v2.md`, `docs/MLC_PATCH_STRATEGY.md`
- Refactoring: `docs/REFACTORING_PLAN.md`
- Testing: `testing/README.md`
