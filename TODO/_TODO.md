# To do

### Questions for Huy
- [ ] how to add users to server access (incl myself & new MDS cohort) 
    - does IT manage that?

### SSH Keys / mosh / hostname
- [x] set up DSL ssh key
- [ ] setup ssh keys rather than passwords for all users (gradually migrate to key-only)
- [x] change dsl passphrase
- [x] set up mosh
- [x] set up hostname again
- [x] write documentation
- [ ] mosh still down
- [ ] improve docs

### User Privacy & Permissions
- [x] Changed UMASK to 077 in /etc/login.defs for new users
- [x] Created script to update all existing home directories to 700 permissions
- [x] Applied 700 permissions to all 82 existing home directories
- [x] Verified USERGROUPS_ENAB setting
- [ ] come back to /readonly & /collaborative dirs -> base access on user groups
    - `sudo chgrp datasciencelab /collaborative`
    - `sudo chmod 2775 /collaborative` 
    - -> currently group ownership is datasciencelab -> change this to be all MDS students?
    - [ ] update the documentation when confirmed
- [x] added /scratch/ dirs (& documentation)
- [ ] change /scratch/ dirs permissions so it's not automatic -> students have to request access (via usergroups)
- [ ] change /scratch/ dirs naming conventions
- [ ] understand & document how to add users to server access 
- [x] set up user groups for more granular permissions
- [ ] tidy up previous user groups
- [ ] write user group documentation
- [ ] !!! where can i find a list of all server users
    - [ ] work out what's going on for how AD users don't appear as users (but they do get a /home dir -> what's goin on with these users) I've tried going all around this, but it's not clear what's happening at all
    - [ ] need to get LDAP query access from IT
    - [ ] add h.baker to `sudo usermod -g ds-admin -G docker-users,gpu-users,gpu-priority h.baker` (currently I'm not a user)
    - [ ] add h.baker to sudo
    - [ ] script to auto add phds/researchers vs students to their respective groups (currently only possible to scan the home dirs - not efficient, where are these dirs being populated from)
    - [ ] add new user -> user group script to cron
- [x] write script to kep dsl in sudo
- [ ] setup new user workflow -> creates relevant dirs + fixes their read/write permiossions

### Shared directories
- [ ] once /readonly & /collaborative sorted: set up shared datasets & models
- [ ] move collaborative/ & read_only/ into data/ into srv (see server access & security chat) (and make sure scratch is auto-purged still)

### Documentation
- [ ] make available both within root folder, and on git
- [ ] set up shared communication for server announcements / ticketing system for students
- [ ] admin docs
    - Cron; backup schedule and restoration process
    - ssh
    - 

### Cron
- [x] implemented some basic scripts, but I don't want them that regular, go back to change regularity & what they are outputting (currently excess info)
- [x] Set up log rotation with 1-year retention
- [ ] identify things to backup
    - /home dirs
    - docker volumes, 
    - infra repo
    - other?
- [x] set up basic cron tasks 
- [x] set up initial logging scripts for resource management
- [x] set up initial audit scripts
- [x] remove GPU audit
- [x] make gpu logging more concise
- [x] clean up output from docker audit
- [x] pull the CPU & GPU & Memory audit stuff about processes & usage into an an improved GPU & CPU & Memory logger (which is then turned into a daily report by the log_analysis_.sh script)
    - idea would be that logger is dynamic stuff, audit tells you general state of the system (a bit more static)
- [ ] log containers being spun up / down, 
    - incl resource allocation 
    - user ID
    - name
    - etc
- [ ] set up workflow somewhere that monitors which containers have been allocated which GPUs currently 
- [ ] once have worked out how users are added / recorded -> update the system audit that tracks users 
    - [ ] + add a tracking of users logging in 
    - [ ] + add tracking of which users are doing which PIDs etc

# SLURM

# Git
- [x] add all logs to .gitignore
- [x] setup repo on DSL 
- [x] restablish the git repo to be the root folder
    - but exlcuidng including all users etc
    - incl all the config files in /etc/ and others

# Containers
- [ ] get it set up so it's launchable from VS Code rather than jupyter
- [ ] create a wrapper for mlc-open that prints explanation
    - explains you're now in /workspace
    -  prints instructions to `exit` + explains what it means for it to be open + when to use `mlc-stop my-container` (when crashed)
    - also workflow to keep container runnint while training, and how to reaccess it later
- [ ] Set up `docker image prune` automation"
- [x]Containers should run with user namespaces:
        Add to /etc/docker/daemon.json:
        json
        {
        "userns-remap": "default"
        }
- [ ] documentation
- [ ] ds01-dashboard doesn't recognise containers
- [ ] when ready, set up the cgroups resource allocation & accounting (see scripts/system/setup-cgroups-slices)

- SETUP WIZRD
    - [ ] the colour formatting (the blue is too dark + also some of the colour formatting doesn't seem to apply)
    - for the container name, does it make sense to have the username before? surely easier just to call it the image/project name?
    - currently mlc-create --show-limits => again it makes more sense to have naming convention more intuitive
    - mlc-stats not working
    - can i block them from baremetal?
    - check it is correctly allocating resource limits
    - improve the mlc-open output text to be more useful
    - exit currently auto closes the container (make it so it can run?) exit > [datasciencelab-test-4] detached from container, container keeps running > [datasciencelab-test-4] container is inactive, stopping container ... same even if do touch /workspace/.keep-alive.. currently there's no way to run containers after exit
    - ds01-git-init doesn't work
    - when robust -> enforce container usage

- [ ] rename some of the instructions e.g. rather than ds01-setup it is setup-wizard 


# privacy
- [x] change so users can't see eachothers directories

# Done
- [x] set up git repo
- [x] set system groups and encrpytd group passwords immutable & protected
- [x] set up audit script
- [x] set up logging script
- [x] set up initial crontab