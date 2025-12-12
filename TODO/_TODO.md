# To do

# Managing Users

### User Privacy & Permissions
- [ ] set uphigh level: user groups properly. Ask @agent-systems-architect how can leverage this functionality optimally. Blue skies thinking, open to suggestions & strategic planning!
    - [ ] audit current groups - does this make sense? how to improve?
    - [ ] what else can we use user groups for?
- [ ] are resource allocations handled by cgroups currently? is this different from user groups?
- [ ] setup script to auto add admins / faculyt / phds & researchers / students to their respective groups (w/ permissions & resource allocations enforced)
    - could do based on naming conventions?
        - admin: h.baker@hertie-school.lan, h.dang@hertie-school.lan
        - faculty (NB ADD NEW faculty.members LIST): w.lowe@hertie-school.lan, l.kaack@hertie-school.lan
        - researchers/phds: c.fusarbassini@hertie-school.lan, c.sobral@hertie-school.lan
        - students: 228755@hertie-school.lan 
        - system users: datasciencelab
        - BUT (i) THERE'S NO DISTINCTION BETWEEN SOME OF THESE CATEGOIRES; (ii) SOME RESEARCHERS ALSO LOGGED IN VIA STUDENTS-STYLE ACCOUNT (see in the config/groups/researcher.members silke is 204214@hertie-school.lan) - so need to allow for easy manual override
    - currently only possible to scan the home dirs - not efficient? where are these dirs being populated from? is there a db that has metadata we can use?
    - add new user -> user group script to cron
- [ ] develop /readonly & /collaborative dirs -> base access on user groups
    - `sudo chgrp datasciencelab /collaborative`
    - `sudo chmod 2775 /collaborative` 
    - what could we use these shared dirs for?
    - -> currently group ownership is datasciencelab -> change this to be all students?
    - [ ] update the documentation when confirmed
- [ ] delete old users' work 
    - [ ] I will do this manually! but it would be good to get a report on when users last logged in / how long it's been since dirs in /home were last accessed/editted
- [ ] set up new-user workflow more carefully
    - creates relevant dirs 
    - fixes their read/write permiossions 
- [ ] cron script to keep datasciencelab system user always in sudo (in case I accidentally remove from sudo group)
- [ ] carefully think through permissions structure (already done some work, but it is it optimally setup?)
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
- [x] do a full refactor of code here
- [x] better deploy process 
- [x] Docuemnt ALL relevant configs / setups on this server. They are to be FULLY documented in configs/ - either as mirror / yaml / whatever files/scripts, alongside their deploy scripts. Also, let's build out a proper deploy dispatcher, so we can deploy specific components as needed
- [ ] some of the GPU allocation proces

# Testing
- [ ] set up unit, functional, integraton tests

# Meta: Git & Claude
- [ ] set up git workflows
- [ ] optimise claude usage

# System-wide
## User & Permission Management
### cgroups
- [ ] not sure if i optimally set up cgroups correctly 
- [ ] within user-group slice, each user should then get their own slice -> can see how much each user is using (in logs / reports)?
- [ ] I don't think this is set up properly: `systemctl status ds01.slice` shows it being inactive
- [ ] need to robustly test once I have how a NEW user is added from Huy

#### User groups
- [ ] sort out user groups (incl using docker-users in the scripts, rather than docker -> remove docker group)

Add more CLI flags -> more efficient

# Docs
- [ ] merge index.md into README.md

---
Permissions
- see [find ref docs]
- PAM & OPA configs
- a user's `docker ps` or Dev Containers / Container Tools shouldn't show other users' running processes / containers. 
- shouldn't be able to interfere with other users' containers (stop / start / execute etc)
- a lot of work already done on this, but rolled back due to problems caused (see documentation)
- BUT dashboard commands needs see all allocations (it is useful for users to see what is taken)
- also GPU state reader logic needs to be able to see across users etc 
- -> decided to manage this by OPA policy, but I couldn't get this to run 
- CRITICAL: don't break functionality of GPU allocatione etc
- currently what happens if a user does docker image prune / docker system prune  <- this should also be covered by OPA policy
Current Behavior: docker image prune / docker system prune

        These commands are not blocked and will execute normally, but only affect images the user has permission to remove.

        Details:

        1. Docker Wrapper (docker-wrapper.sh):
            - Only intercepts run, create, and ps commands
            - Prune commands pass through unchanged to /usr/bin/docker
        2. OPA Policy (docker-authz.rego):
            - Only protects container operations (start, stop, exec, remove, etc.)
            - No rules for image operations or system-wide commands
            - Default is allow := true (fail-open)
        3. What actually happens:

        Observed in crontab:
                #COME BACK TO: 0 4 1 * * datasciencelab docker image prune -f
                This suggests someone noted this needs attention but commented it out.

            Potential mitigations (not currently implemented):
            1. Block prune commands in docker-wrapper.sh for non-admins
            2. Add OPA rules for image endpoints (/images/prune, /system/prune)
            3. Only allow users to remove images matching ds01-{uid}/* pattern

- see: docs-admin/security/user-privacy.md
- users shouldn't be able to read / cd around folders that aren't their /home/<user-id> or shared/collaborative folder BUT make sure this doesn't break permissions / setup!
    - basic idea: be able to see their work and work in their directory, but can't go altering other peple's work / infra dir on the server
    - but priorury is not to break 
- currently, if users cd out of their /home/<user-id>/ they can't read -> they can't work out how to get back => add home alias that brings them back (add this to setup source bash, also document it clearly in userfacing scripts (in both quickstart.md & un quick-references.md)
- currently users can ls or cd /opt and other dirs of the server. I want this to not be the case
- Create Linux groups (ds01-student, ds01-researcher, ds01-faculty, ds01-admin)
- Add cron job for Linux group sync
- currently datasciencelab has same restricted user permissions
2. audit to all /home dirs -> full report on when last accessed/edited + archived.members (make this about deleting their /home dir)


 16. Set up /data/, /projects/, /scratch/ directories with ACLs
 18. Update container-create to mount shared directories


 add gpu queue functionality