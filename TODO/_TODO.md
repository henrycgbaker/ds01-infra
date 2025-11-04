# To do

### Questions for Huy
- [ ] how to add users to server access (incl myself & new MDS cohort) 
    - does IT manage that?
- [ ] understand & document how to add users to server access 
    - need to know how to access their username / user_id for downstream workflows
- [ ] how to get a message to current users -> begin migrating their work over to container workflow -> block bare metal access & clean up old containers

### SSH Keys / mosh / hostname
- [x] set up DSL ssh key
- [ ] setup ssh keys rather than passwords for all users 
    - gradually migrate to key-only
    - only do when robustly setup: communicate to current users in adv
- [x] change dsl passphrase
- [x] set up mosh
- [x] set up hostname again
- [x] write documentation
- [ ] mosh still down
- [x] improve docs

### Managing Users, User Privacy & Permissions
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
- [x] set up user groups for more granular permissions
- [ ] tidy up previous user groups -> sync with cgroups
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
    - i've got this with ds01-setup wizard
- [x] change so users can't see eachothers directories
- [ ] currently: users can't see within other users dirs -> change: they can't even see other users dirs (only can see their own /home, everything outside doesn't display)

### Shared directories
- [ ] once /readonly & /collaborative sorted: set up shared datasets & models
- [ ] move collaborative/ & read_only/ into data/ into srv (see server access & security chat) (and make sure scratch is auto-purged still)

### Documentation
- [X] make available both within root folder, and on git
- [ ] set up shared communication for server announcements / ticketing system for students
- [x] admin docs
    - Cron; backup schedule and restoration process
    - ssh


### Cron
- [x] implemented some basic scripts, but I don't want them that regular, go back to change regularity & what they are outputting (currently excess info)
- [x] Set up log rotation with 1-year retention
- [ ] identify backup items
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
- [ ] set up workflow that monitors which containers have been allocated which GPUs currently 
- [ ] once have worked out how users are added / recorded -> update the system audit that tracks users 
    - [ ] + add a tracking of users logging in 
    - [ ] + add tracking of which users are doing which PIDs etc
- [ ] once have clear which containers still needed -> delete old

# SLURM
- delayed / maybe unncessary?

# Git
- [x] add all logs to .gitignore
- [x] setup repo on DSL 
- [x] restablish the git repo to be the root folder
    - but exlcuidng including all users etc
    - incl all the config files in /etc/ and others

# Containers
- [x] get it set up so it's launchable from VS Code rather than jupyter
- [] create a wrapper for mlc-open that prints explanation
    - explains you're now in /workspace
    -  prints instructions to `exit` + explains what it means for it to be open + when to use `mlc-stop my-container` (when crashed)
    - also workflow to keep container runnint while training, and how to reaccess it later
- [ ] Set up `docker image prune` automation"
- [x]Containers should run with user namespaces:
        Add to /etc/docker/daemon.json:        {"userns-remap": "default"} NB I didn't do this, complicates gpu pids -> instead: cgroups
- [ ] ds01-dashboard doesn't recognise containers
- [ ] when ready, set up the cgroups resource allocation & accounting (see scripts/system/setup-cgroups-slices)
- SETUP WIZRD
    - [ ] the colour formatting (the blue is too dark + also some of the colour formatting doesn't seem to apply)
    - [ ] for the container name, does it make sense to have the username before? surely easier just to call it the image/project name?
    - [ ]  currently mlc-create --show-limits => again it makes more sense to have naming convention more intuitive
    - [ ] mlc-stats not working
    - [x] can i block them from baremetal? -> yes: do once containers robustly implmented
    - [ ] check setup / create is correctly allocating resource limits
    - [ ] improve the mlc-open output text to be more useful
    - [ ] exit currently auto closes the container (make it so it can run?) exit > [datasciencelab-test-4] detached from container, container keeps running > [datasciencelab-test-4] container is inactive, stopping container ... same even if do touch /workspace/.keep-alive.. currently there's no way to run containers after exit
    - [ ] ds01-git-init doesn't work
    - [ ] confirm the initial ssh config setup makes sense
    - [ ] if they try to run a container beyond their limits, within the wizard there's a graceful error message to explain what they did wrong and they are unable to progress / redirected back so they can change their settings
  - [ ] when robust -> enforce container usage
  - [ ] have so that students can get up to 4 MIG instances, but setup wizard defaults to 1, but gives them the option to choose more
  - [ ] update container allocation based on UUID 

- [ ] for all CLIs (symlinks): rename the instructions to follow consistent convention 
    - e.g. rather than ds01-setup it is setup-wizard, 
    - rather than mlc-create --show-limits => something like containers --show-limits
    - convention: ds01- prefix? => ds01-setup & ds01-container --show-limit & ds01- ????? (or maybe ds01- prefix for sysadming / server infra stuff, then more intuitive user-facing command naming)

- [ ] rename ds01-1 to container -run or something like that
- [ ] create another container creation wizard, that does similar things to the de01 setup wiard, but without the ssh configs etc, it jsut creates a new container (and a project directory? or maybe gives the recommended option to set up a new project folder for each new container so that it is is a container per project -> each project gets a container and a directory?)

- [ ] currently only containers launched through ds01-run will be in the ds01.slice hierarchy. Containers launched with plain docker run will still go under the flat docker/ cgroup with no limits. => To enforce it for ALL containers configure Docker daemon (/etc/docker/daemon.json with "cgroup-parent": "ds01.slice") => add to etc-mirror
    - [ ] or at the very least get ds01-setup wizard to call ds01-run

    ### Files Needing Updates:
- [ ] `scripts/docker/mlc-create-wrapper.sh` - Integrate GPU allocator + priority + graceful errors
- [ ] `scripts/system/setup-resource-slices.sh` - Update for new YAML structure


# Wizards 
- [x] make sure the commands are all reachable not just be but by all users 
- [x] sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh 


- [ ] use .link files for all the other mirrors?? what are they?

- [ ] delete all setup scripts (in the scripts/system
)


# Partitioning & GPU allocation
- [ ] I set up 3 MIG instances: Claude thought this was 2g.20gb profile each, but actually I have NVIDIA A100-PCIE-40GB -> so need to update this
- [ ] Set up MIG vs MPS?
- [ ] I set up so that total GPUs allocated hard limit -> change it so that the user limits apply to the containers they can spin up (but not the number of containers total)? or maybe leave it so they have total limit -> means they have to close running containers
- [ ] currently my resource allocation is by GPU -> instead, it should be by MIG partition (?) -> rename in the resource-limits.yaml to max_mig
- [ ] scripts/docker/mlc-create-wrapper.sh - Needs GPU allocator integration!!!!
    - 4. Wrapper Script Integration
    - The mlc-create-wrapper.sh still needs updates to:
        - Call gpu_allocator.py with priority
        - Show graceful error messages
        - Check container limits
        - Register release hook
- [ ] check, is max_mig_per_user
- [ ] check: idle timeout -> how do i set it so that users can run training runs in background, but that it checks when it's done and shuts it if nothing happening?
    

- [ ] not sure if i optimally set up cgroups correctly -> maybe within user-group slice, each user should then get their own slice -> can see how much each user is using (in logs / reports)? It would be useful to see who is doing what....
    - [ ] make sure cgroups & user groups are integrated together / consistent


# cgroups
- [ ] I don't think this is set up properly: `systemctl status ds01.slice` shows it being inactive

# clean up
- [ ] once identified currnet users -> send message out via dsl for saving important work -> begin deleting.
- [ ] many remaining images to clean up (`sudo docker images`) -> `sudo docker image prune -a`

# logging
- [ ] create sym link to reports in opts
- [ ] add grafana & prometheus

# /usr-mirror & etc-mirror/
- [ ] have a /usr-mirror in git hub repo as well as etc-mirror, for full documentation
- [ ] 




# Done
- [x] set up git repo
- [x] set system groups and encrpytd group passwords immutable & protected
- [x] set up audit script
- [x] set up logging script
- [x] set up initial crontab
