# To do

# Managing Users

### User Privacy & Permissions
- [ ] develop /readonly & /collaborative dirs -> base access on user groups
    - `sudo chgrp datasciencelab /collaborative`
    - `sudo chmod 2775 /collaborative` 
    - -> currently group ownership is datasciencelab -> change this to be all MDS students?
    - [ ] update the documentation when confirmed
- [ ] delete old users' work 
    - send out email in adv
- [ ] set up new-user workflow more carefully
    - creates relevant dirs 
    - fixes their read/write permiossions 
- [ ] setup script to auto add phds/researchers vs students to their respective groups 
    - could do based on naming conventions
        - staff/researchers/phds: h.baker
        - students: 228755@st
        - system users: datasciencelab
    - currently only possible to scan the home dirs - not efficient, where are these dirs being populated from)
    - add new user -> user group script to cron
- [ ] cron script to kep dsl in sudo
- [x] change so users can't see eachothers directories
- [ ] currently: users can't see within other users dirs -> change: they can't even see other users dirs (only can see their own /home, everything outside doesn't display)

### resource-allocation.yaml
- [ ] much unimplemented functionality described in there 

### Shared directories
- [ ] set up `scratch/` dir & `collab/` dir
    - shared datasets & models, etc
- [ ] move collaborative/ & read_only/ into data/ into srv (see server access & security chat) (and make sure scratch is auto-purged still)

### Documentation
!!! priority
- [ ] write up full user workflow - esp what to do once running a container
    - e.g. 
    - [ ] need to find the specific Python environment where your PyTorch and other packages are installedco
    - [ ] selecting kernel -> local python ev, or global one?

- [ ] add to documentation that docker images routinely prunced -> dockerfiles will be single source of truth / never be deleted
- [ ] pune back existing & make more modular

# Logging
- [ ] add Grafana & Prometheus for logging

# Save Copy of Configs in Git Repo
- [ ] make sure all config mirrors are up to date in the repo -> being tracked

### Cron
- [ ] identify backup items
    - /home dirs
    - docker volumes, 
    - infra repo
    - other?
- [ ] what else should be in the Cron job
- [ ] Set up `docker image prune` automation in cron   
    - this needs much consideration as to what is pruned etc -> write in the documentation that because of this dockerfiles will be single source of truth / never be deleted
- [ ] make sure server's cron tab is fully setup, robust and has all the usual jobs on it. incl (but not limitted to
  - backup / restoration?
  - system maintenance
  - backgup scripts
  - log management
  - performance monitoring
  etc
  - I am new to this - help me setup full cron jobs. Ask as many  questions as you need for this. All cron configs should be documentd in repos' config/ (maybe we should make it clear which of these config dirs are mirrors to be copied out / deployed. We also want dedicated deploy scripts for all configs here. I think they are currently in scripts/



# SLURM
- [ ] to do

# Git
- [x] do versioning

# CLIs

### Admin comamnds
- [ ] clean up redundant commands (esp dashboard)
    - both the `commands` alias list, and the deployed commands

### General Containers
- [ ] incorporate Dev-Containers & VS Code extensions into existing formnat -> labels appropriately added, limits enforced etc
- [ ] enforce container usage and block users from running scripts bare metal





GPU/MIG allocation & 'dashboard'
- target: 
    - containers are created and a GPU/MIG target ID is "assigned". 
    - "Assigned" does not make it actively "allocated" (i,e, reserved"), just that it will try to attatch to that target GPU/MIG on start.
    - If user starts container, then the system will try to "allocate" the "assigned" target GPU/MIG.
    - if it is successfully "allocated", it means it is actively being used and is reserved for exclusive use by the user.
    - If a container's "assigned" GPU?MIG ID is already in use (i.e. is now "allocated" and so reserved) by another user, then it is blocked (not "allocated"), and the user must recreate the container so that a new (available) GPU/MIG can be "assigned"/targeted based on the algorithm.
    - once a container is stopped (either by user, or by cron jon automation), then the GPU is "released". This means it is un-allocated, and goes back into circulations
    - so: assigned = targeted; allocated = reserved; blocked = contended; released = available
- what is it the setup at present
            Current Setup

            No "assigned vs allocated" distinction exists. System is simpler:

            1. Container created → GPU assigned + allocated (reserved) immediately
                - Stored in Docker HostConfig.DeviceRequests (single source of truth)
                - Also logged in /var/lib/ds01/container-metadata/{container}.json
            2. Container stopped → GPU still allocated (remains bound to container)
                - No release on stop - GPU stays reserved
                - Other users cannot use it
            3. Container removed → GPU released (back to pool)


# Refactor
- [ ] do a full refactor of code here
- [ ] better deploy process 
- [ ] Docuemnt ALL relevant configs / setups on this server. They are to be FULLY documented in configs/ - either as mirror / yaml / whatever files/scripts, alongside their deploy scripts. Also, let's build out a proper deploy dispatcher, so we can deploy specific components as needed

# Testing
- [ ] set up unit, functional, integraton tests


# System-wide
## User & Permission Management
### cgroups
- [ ] not sure if i optimally set up cgroups correctly 
- [ ] within user-group slice, each user should then get their own slice -> can see how much each user is using (in logs / reports)?
- [ ] I don't think this is set up properly: `systemctl status ds01.slice` shows it being inactive
- [ ] need to robustly test once I have how a NEW user is added from Huy

#### User groups
- [ ] sort out user groups (incl using docker-users in the scripts, rather than docker -> remove docker group)



