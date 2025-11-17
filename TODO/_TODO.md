# To do

### Questions for Huy
- [ ] how to add users to server access (incl myself & new MDS cohort) 
    - [x] does IT manage that?
    - [x] does IT manage that?
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
- [ ] (once /readonly & /collaborative sorted) set up shared datasets & models, etc
- [ ] (once /readonly & /collaborative sorted) set up shared datasets & models, etc
- [ ] move collaborative/ & read_only/ into data/ into srv (see server access & security chat) (and make sure scratch is auto-purged still)

### Documentation
- [X] make available both within root folder, and on git
- [ ] set up shared communication for server announcements / ticketing system for students
- [x] admin docs
    - Cron; backup schedule and restoration process
    - ssh
- [ ] architecture described as a '4 tiered structure'. Change to a '3 layer structure' 
    - base: `mlc-*`, 
    - then there's modular functionality implementation (& wrappers of the base layer),
    - then there's the orchestrators as top 'wizard' layer

# Logging
- [x] set up initial logging script
- [x] create sym link to reports in opts
- [ ] add Grafana & Prometheus for logging

# Save Copy of Configs in Git Repo
- [x] have a /usr-mirror in git hub repo as well as etc-mirror, for full documentation
- [ ] architecture described as a '4 tiered structure'. Change to a '3 layer structure' 
    - base: `mlc-*`, 
    - then there's modular functionality implementation (& wrappers of the base layer),
    - then there's the orchestrators as top 'wizard' layer

### Cron
- [x] implemented some basic scripts, but I don't want them that regular, go back to change regularity & what they are outputting (currently excess info)
- [x] set up initial crontab
- [x] set up initial crontab
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
- [x] log containers being spun up / down, 
    - incl resource allocation, user ID, name, etc
    - this will be the basis of the intelligent resource allocation
- [x] set up workflow that monitors which containers have been allocated which GPUs currently
    - plan for this fully documented [here](../docs-admin/gpu-allocation-implementation.md)
    - [ ] incl resource allocation, user ID, name, etc
    - this will be the basis of the intelligent resource allocation
- [x] set up workflow that monitors which containers have been allocated which GPUs currently
    - plan for this fully documented [here](../docs-admin/gpu-allocation-implementation.md)
- [x] check all cron jobs added to auto close & clean up container working!
- [ ] once have worked out how users are added / recorded -> update the system audit that tracks users 
    - [ ] + add a tracking of users logging in 
    - [ ] + add tracking of which users are doing which PIDs etc
- [x] once have clear which containers still needed -> delete old

# SLURM
- delayed / maybe unncessary?

# Git
- [x] add all logs to .gitignore
- [x] setup repo on DSL 
- [x] restablish the git repo to be the root folder
    - but exlcuidng including all users etc
    - incl all the config files in /etc/ and others
- [ ] set AIME lib as a subcommand within ds01 infra -> properly register my patches as a branch / fork? 
    - currently i keep my patched versions separate -> instead, have within the repo, but as my local edits 
    - try with subtree instead!

# Containers

### Dir Create
- [ ] `dir-create` works `dir create` does not. Need alias / symline
- [ ] `dir create`: 
    - BUG: 
    ```
    (base) datasciencelab@ds01:/opt/ds01-infra$ dir create test-2
    dir: cannot access 'create': No such file or directory
    dir: cannot access 'test-2': No such file or directory
    ```
    - [x] needs aesthetic banner at top:
    - if no name provided -> open up GUI (change --guided output once updated this)

### Admin comamnds
- [x] `ds01 run` delete? what does this do that other commands don't? i think its legacy hangover?
- [ ] `ds01 status` needs alias / symlink. Also it's mostly broken. 
    - [ ] replaced by ds01-dashboard?

### Ancillary commands
- [x] `container stats` - BUG: "unknown flag: --filter"

### General Containers
- [x] get it set up so it's launchable from VS Code rather than jupyter
- [ ] Set up `docker image prune` automation in cron
- [ ] once containers robustly implmented, enformce container usage and block users from running scripts bare metal

### CLI Ecosystem / Aliases 
- [x] for all CLIs (symlinks): rename the instructions to follow consistent convention
    - [x] e.g. rather than ds01-setup it is setup-wizard,
    - [x] rather than mlc-create --show-limits => something like containers --show-limits
    - [x] convention: ds01- prefix? => ds01-setup & ds01-container --show-limit & ds01- ????? (or maybe ds01- prefix for sysadming / server infra stuff, then more intuitive user-facing command naming)
- [x] rename ds01-1 to container -run or something like that
- [x] create another container creation wizard, that does similar things to the de01 setup wiard, but without the ssh configs etc, it jsut creates a new container (and a project directory? or maybe gives the recommended option to set up a new project folder for each new container so that it is is a container per project -> each project gets a container and a directory?)
- [x] make sure the commands are all reachable not just be but by all users
- [x] sudo /opt/ds01-infra/scripts/system/setup-user-commands.sh
- [x] Added --info flag support to all dispatchers and Tier 2 commands
- [x] Completed --guided flag coverage across all 16 Tier 2 commands
- [x] Created interactive GUI library for selection menus
- [x] Implemented interactive prompts for image-update, image-delete, container-run, container-stop, container-cleanup
- [x] Deprecated redundant scripts (create-custom-image.sh, manage-images.sh, student-setup.sh)
- [x] Updated symlinks - added 14 new commands
- [x] Fixed alias-list documentation errors
- [ ] build `alias-list` for within containers (ie same command, but now it displays commands to be run inside container)
- [x] ds01-dashboard alias command doesn't do anything useful
    - [x] no MIG config recognised

### User Setup Wizard
- [x] the colour formatting (the blue is too dark + also some of the colour formatting doesn't seem to apply)
- [x] mlc-stats not working
- [x] can i block them from baremetal? -> yes
- [x] check setup / create is correctly allocating resource limits
- [x] improve the mlc-open output text to be more useful
- [x] ds01-git-init doesn't work
- [ ] confirm the initial ssh config setup makes sense
- [x] for the container name, does it make sense to have the username before? surely easier just to call it the image/project name?
    - naming convention: <projet><username><container/image>?
- [ ] resolve container naming convention
    - currently inconsistent: some commandsimplements with username suffix, some don't
    - maybe remove username suffix if the username is in a label -> make sure to remove all dependencies (e.g. list / search / stop / remove etc might search for user-affiliated containers via the label)
- [x]  currently mlc-create --show-limits => again it makes more sense to have naming convention more intuitive
    - [x] i think this functionality got lost, but in the image / container Wizards, have clear arg for inspecting resource allocations
- [x] at all decision point: add clear defaults (ie. to press enter is usually just yes (to proceed). Enter should never default to exit
- [ ] when all other commands working, come back to this as there's streamlining to be done here
- [ ] doesn't read users images
        ```
        ✓ Workspace exists: ~/workspace (16 project(s))
        ○ No custom images yet (will create one)
        ```
- [ ] in the user setup, move the vs code setup to be just after ssh keys setup (i.e. before the dir & image setup: when choose no at ```⚠  Project directory already exists: /home/datasciencelab/workspace/test
Use existing directory? [Y/n]:``` ==> have graceful failover: provide options to 1) overwrite existing dir with new dir (incl warning), 2) rename new project, 3) exit
- [ ] similarly for ```✓ You're already set up!Everything looks good. You can:.... Run full wizard anyway? [y/N]:  ``` if choose no, have graceful failover: options 1) skip to new project init,  2) skip to specific section (e.g. ssh keys / vs code configs / dir set up / new image / container run etc etc), 3) exit


### Project Init
- [x] do i need the project type at the beginning? or is this basically redundant as i do package management in image creation? or does it serve a useful/diff purpose?
- [x] there's an error with a lot of the image types where it crashes out after this unknown option (maybe just remove this type part?): 
- [ ] I'm not really sure what the point of the requirements.txt is in this process? surely it's important to get the packages in the image, then the requirements.txt is just all of them? But project init creates a requirements.txt BEFORE creating an image??
        ```
        Step 4: Creating Project Files
        Creating Project Files
        Creating requirements.txt...
        ✓ README.md created
        ✓ requirements.txt created
        ```

### Image Create
- [x] Add hard coded suffix "-image" to all images, move naming convention: "<project-name>-<user-id>-image"
    - [x] is there a way to tag the user ID, if so -> "<project-name>-image", with the user id as a tag
    - [x] NB: this renaming convention, might upset image-list command
- [x] BUG: when get to ```Create a custom Docker image? [Y/n]: y -> Unknown option: --type=ml``` => it crashes out / doesn't proceed. The issue is with `--type=ml???` Maybe just remove this `type`, is it useful/used?
- [x] I added in 'custom (specify everything) option for base image --> need to omplement this
- [x] make initial package installation more extensive (while having custom as the first option, also the default)
- [x] above the add additional python packages, get it to list out the already included packages (categorised by 'default' and 'use case-specific') -> users can see what they have and what they need to add
- [x] add ipykernel + pip to all image creations 
    - in general, work out what python libs to include as standard
- [x] if users try to create an image/container / run a container beyond their limits (in `ds01-infra/config/resource-limits.yaml`), within the wizard there's a graceful error message to explain what they did wrong and they are unable to progress / redirected back so they can change their settings
- [x] maybe just have this defult to no libraries installed? I'm not really sure how this works once a container is up and running how easy/hard it is to install packages... does it need to be pre-installed, or can you dynanmically add to them. 
- [x] updated to consistent multi-line formatting of packages, w/ separation of system, core python, use-case python, custom additional
- [x] fixed 'image create failed' bug
- [x] maybe separate out image create from docker file create -> at least have the option to just create the dockerfile without the image
    - [x] same with `image updade`: give the option just update the docker file with new packages etc > then offer the option to rebuild the image > then offer the option to re-spin up the container 
- [x] CRITICAL FIRST THING: audit the `image create`/`image update` -> `container create` workflow
    - currently `image create`/`image update` allows lots of editing & customisation of an dockerfile
    - but then, it seems like maybe then the subsequent building of the image / container just pulls an existing AIME template. 
    - what I want is for it to pull the base AIME template, then add any further packages defined through the `image create`/`image update` processes
- [x] need to rethink image create quite a it following refactor 
    - design principle: need to work from principle that aime image is the base we are inheriting from
    - so it needs to first ask which base framework to use (which i think these need updating in light of aime v2)
    - then (depending on base frameowrk image selection) it prints a list of ALL the pkgs that are ALREADY included within that base to the user (this will be the same logic as `image update` when it looks inside the base imaghe to retrieve existing preincluded pkgs)
    - then let's strategise here: apriori I'm just not sure how thorough these AIME base images are; if they are thorough then maybe there's no need for installing system pkgs, or base data science python packages, or use pkgs etc. 
    - strategy: let's now look at what's in the AIME base images, then we can strategise what options and defaults to offer the user in the `image creation` process
So as part of redesigning `image create` GUI:
- keep the separation between pulling AIME base image > customising the dockerfile > offering the build the dockerfile into an image executable. Make sure --guided offers clear explanation
- is it possible to call mlc-create here, or does the dockerfile to image creation require dedicated logic - strategise this and come back to me with suggested options
- [x] first ask which base framework to use (which i think the choice of need updating in light of aime v2, ds01's image creator GUI is out of date). Also option: "Custom (specify base image)", also "Custom (specify no image)" - build out both of these workflows.
- [x] then (depending on base framework image selection) it prints a list of KEY pkgs ALREADY included within the base image (if they're pretty consistent between images we can just use ". conda, numpy, pillow tqdm, torch, torch audio, torchvision" and an option to more closely inspect the image
- [x] then offer to include core Python & interactive (Jupyter) pkgs as default (give list of examples) (keep ds01's option set: 1) Yes - Install defaults (recommended)  2) No - Skip core Python packages   3) Custom - Specify core Python packages manually. Choice [1-3, default: 1]: 1
- [x] then offer to include core Data Science pkgs as default (give a few examples) -> install as default (recommended), otherwise none 
- [x] then offer to include use case-specific packages - offer same use cases, but offer more pkgs per use case, make this robust and fully developed.
- strategise if this phased setup makes sense, or if another slightly different categorisation of the phases makes sense instead. Suggest alternatives to me, I'll choose
- [x] Once we have confirmed design of phased `image create`, `image update` should follow the same logic: .e.g. 
        AIME base image: aimehub/pytorch-2.8.0-aime-cuda12.6.3
        Key AIME preinstalled pkgs: conda, numpy, pillow tqdm, torch, torch audio, torchvision (IS THIS THE CASE FOR ALL THE AIME IMAGES?)
        System pkgs: 
        Core Python & Interactive pkgs: 
        Core Data Science pkgs:
        Use case defaults {the use case type}: 
        Custom-installed: 
    OR, if we change this design for `image create`, the same logic should be applied for `image update
- [x] for both `image create` and `image update` - allow pkg versioning functionlity! think how best to handle this for ease of use (defaults) vs ability. to specify when necessary 
- [x] just check again that `image create` strictly follows workflow from integration strategy `.md`s - that it pulls base aime image, then buiilds on there.
- [x] add/separate out another layer of install categorisation:
    - (1) base framework (i.e. AIME base image <- need to see what's in there already)
    - (2) base interactive envs (jupyter, jupyterlab, ipykernel, ipywidgets)
    - (3) default data science (numpy pandas matplotlib seaborn scikit-learn scipy tqdm tensorboard Pillow python-dotenv)
    - (4) specific use case (comp-vis, nlp etc)
    - = separating out 2 & 3, which are currently combined
    - also: add in a bit more description into the wizard as to what's included
    - TODO first: check what is included in AIME and confirm that these base images are being called, as i'm not sure they are.....???
- [x] related to above: review which libs are preinstalled -> plan out what would be optimal
    - [x] add torch & pytorth etc into the preinstalled libs for pytorch framework??? Surely they should already be there, or are they there underthe hood somehow from the AIME base image? I THINK THESE ARE IN FACT INCLUDED IN AIME -> SEE WHAT'S ALREADY IN THERE?
    - [x] also maybe make custom (i.e. no default packages / frameworks) more prominent / the default?
- [x] add in hugging face image (that uses hugging face rather than pytorch?)
- [x] add in a nice banner at the top of the wizard (it has them from 
- [x] remove from `container create` all the image create functionality -> it just offers to select from existing image files created by the user, The --guided flag explains how containers are created from image executables are created from dockerfiles, and gives the bash command to image create
- [x] Make all Tier 2 much more modular & isolated! Currently they are entangled, call eachother, and duplicate functionality. The design principle for all Tier 2 commands is to make them isolated and unique functionality. The --guided mode can make it clear where this step is in the overall workflow, and define prerequisities (and give the bash command to call it), or even suggest the next step (and give the bash command), but in terms of actually implemented fucntionality Sthey should be strictly isolated, de-linked and avoid any duplication
- [x] refactor / review both Tier 3 orchestrators (`project init` and `user setup`) - make sure they are still properly orchestrating Tier 2 commands
- [x] BUG: error message in output: " => WARN: NoEmptyContinuation: Empty continuation line (line 25)   "
- [x] Image create refactor Strategise: change `image create` and how it assigns/names REPOSITORY & TAG -> make it align with industry standards!
- [ ] BUG: `/usr/local/bin/image-create: line 1244: creation: command not found`
- [ ] REFACTOR: rename as `image build` (both the script itself, the command alias, and all dependencies)

### Image list 
- [x] update based on naming changes in image create

### Image Update
- [x]add aesthetic entry banner at top
- [x] BUG: when listing all available images, it's buggy. `image list` command gets this right, so call directly there! 
- [x] BUG: either the currently installed packages list is not up to date, or it's not able to add new packages correctly, or both. All my images have the same 4 "Current Python packages" listed, then whwenever you try to add more python packages, it says it's already in the dockerfile, no matter "which package. Take the same package reading logic as in `image create`
-  [x] BUG: the option 4: "  4) Edit Dockerfile directly (advanced)" -> `/usr/local/bin/image-update: line 300: vim: command not found`
- [x] BUG: it's not refreshing / listing / adding pkgs correctly. E.g. with `test-datasciencelab` I'm adding torch, but then it doesn't show up when it prints the Current python packages. It also let's me add it multiple times (whereas it SHOULD) give a notification saying that that package is already in the image (and gracefully direct me to readding more)
- [x] nice to have: the `image list` call is directly edited before output so that it forms a selection screen, rather than being printed, then a duplicate selection screen below.
- [ ] after updating the docker file, give the option to recreate the image - I dont' think this currently happens?
- [x] sort out the logic between `image create` and `image update` about when to write the `pip install` command if/when there are packages after.
- [x] add a notification output after the image is rebuild to the new dockerfile specs so the user is aware 
- [x] after adding / removing a python / system package, 
    - 1) explain very briefly (if no --guided) that dockerfile blueprint updated, but still need to rebuild the image (and later to recreate container based on rebuild image). More in depth if --guided flat on.
    - 2) offer to continue to rebuild, or loop back gracefully to the "What would you like to do?" menu.
- [ ] get the initial list just to call `image list` (or use exactly the same search logic & format)
    - why is it currently showing old images, whereas `image list` does not -> what's the difference between their search logics?

### Image delete
- [x] accept multiple image names as arguments -> will delete in bulk
- [x] the GUI after providing no image names -> only see users own images
- [ ] make sdure that when a user does `docker image prune` it only cleans up their images (or at least blocks them with sudo)
    - or is this already sudo?
- [ ] currently once image removed 
    --- a)  "Dockerfile backed up to: `/home/datasciencelab/ds01-config/images/deleted/datasciencelab-test-20251111-165620.Dockerfile`" ... why? back it up somewhere in tmp or other? (and zip/compress it), but not in this folder.
    --- b) "💡 Tip: Clean up dangling images with: docker image prune" => i) check that if a user runs this they do not delete other people's images (that this needs sudo) , ii) remove this, and just add this prunung as an admin script for crontab


### Image miscellaneous
- [x] distinguish between image vs dockerfile appropriately 
    - e.g. currently there's a dir created called /home/<user-name>/docker-images/ -> this should in fact use a directory like /home/<user-name>/my-project/dockerfiles/, so it is stored within the project. You can see how project directories are currently structured from using the `project init` command -> figure out how best to store dockerfiles with this in mind. 
    - in the GUIs and explanatory content of all my commands I'm not sure I appropriately use dockerfile vs image correctly. Go through it all and make sure it is correctly distinguished between.
- [x] related: maybe separate out / specify logic between `image create` from `dockerfile create`? 
    - [x] at least in `image create` commend have the option to just create the dockerfile without the image
    - [x] same with `image updade`: give the option just update the docker file with new packages etc > then offer the option to rebuild the image > then offer the option to re-spin up the container 


### Container Create
- [x] BUG: `✗ mlc-create-wrapper not found at: /usr/local/docker/mlc-create-wrapper.sh
    The system may not be fully configured.` 
- [x] BUG: when listing all images (if using existing image), it lists a lot of them, not just the user created ones. `image list` command gets this right, so call directly there! 
- [x]  also when just running container create, make the name optional (if not provided it opens up a full GUI, with name, ability to create custom image, or use existing template)
- [x] !! when chosing the `create custom image` option -> make it call to `image create` (to avoid current duplication of functionality which is bad!)
- [x] manually just add some initial explanation that to create a container we need an image (literally one line, add by hand)
- [x] make `container create` default to (1) a call to `image create` to create custom image, with possiblitlites to chose PyTorch or Tensorflow (currently it has it's own workflow - this is duplication!)
- Resource allocation workflow
    - [x] SEE TODOS IN `ds01-infra/docs-admin/gpu-allocation-implementation.md`
    - [ ] have so that students can get up to 4 MIG instances, but setup wizard defaults to 1, but gives them the option to choose more
    - [x] if users try to create an image/container / run a container beyond their limits (in `ds01-infra/config/resource-limits.yaml`), within the wizard there's a graceful error message to explain what they did wrong and they are unable to progress / redirected back so they can change their settings
- [ ] BUG: (is this under `container create` or `container run`?) currently only containers launched through ds01-run will be in the ds01.slice hierarchy. Containers launched with plain docker run will still go under the flat docker/ cgroup with no limits. => To enforce it for ALL containers configure Docker daemon (/etc/docker/daemon.json with "cgroup-parent": "ds01.slice") => add to etc-mirror
- [x] container create's option to `1) use existing image` -> lists too many images. Instead, call to `image-list` command (which does this properly), and set up output as bash selection.
Creating container via mlc-create-wrapper...
- [x] `container create` -> move the --guided explanation of "understanding containers" BEFORE asking user for selections! --guided users should ALWAYS have explanation FIRST before making selections, so they can make informed choices!
    - [x] do the same for`container run`:- -guided users should ALWAYS have explanation FIRST before making selections, so they can make informed choices! Put the 'Entering Container' explanation before selection of container (although the IDE access explanation can stay after selection)
    - [x] check & do the same for all other commands: --guided users should ALWAYS have explanation FIRST before making selections, so they can make informed choices!
- [x] `container create` -> after getting name: check that there is not already a container with same name, do same workflow as `image create` (yellow warning, y/n, graceful loop back if necessary)

### Container start
- [x] does container start not see 'created' containers, only 'stopped'? 
-   if so, what's the logic of that?
- [x] I would expect both container start and `container run` should be robust to all non running containers? but maybe I'm missing something??
- [ ] separate out `container start` vs `container run` in documentation

### Container start & stop
- [ ] add to the guided explanation a bit to explain what is lost when starting (.e.g state & other processes etc) and what is/is not resumed when started

### Running Containers
- [x] develop wrapper for mlc-open that prints explanation
    - [x] explains you're now in /workspace, what that means etc
    - [x] prints instructions to `exit` + explains what it means for it to be open + when to use `mlc-stop my-container` (when crashed)
    - [x] also explains workflow to keep container running while training (vs when will be auto stopped by system, and how to ask DSL if need for longer), and how to reaccess it later, etc
- [ ] Containers should run with user namespaces:
        - Add to /etc/docker/daemon.json:        {"userns-remap": "default"} NB I did NOT do this, complicates gpu pids -> instead use cgroups....
        - currently if run through Dev Containers then it all works, but if run through `container run` which calls `mlc-create` then it doesn't display properly,
- [x] aesthetics: remove the last part: "[pset3_delete] exists and will be opened. > [pset3_delete] container already running. > [pset3_delete] opening shell to container... > (REMOVE FROM HERE:) To run a command as administrator (user "root"), use "sudo <command>". > See "man sudo_root" for details."
- [x] `container run` to list table of users' containers with their basic stats -> make selection

- [ ] when INSIDE a container, make `alias-list` list all the available commands INSIDE container (just as alias-list lists availbale host commands when OUTSIDE container)
- [ ] TODO: INTEGRATE DEV CONTAINERS INTO SCRIPTS / WIZARDS
    - [ ] when using Dev Container: currently ALL images are visible -> need to set view permissions to only user's images -> can't view / start / stop / open / inspect othehr users' images!
    - [ ] if integrate this workflow into a script: automate setting of the workspace!
        - currently i just connects to /home/datasciencelab/ and if you try to connect it additionally to ...workspace/<workspace_name> it errors to it doesn't exist; I can navigate this with setting up configs in the Dev Container tools., but it seems to .... I THINK THIS GOT FIXED IF YOU CHANGE THE CONFIGURATION FILES TO BE "workspaceFolder": "/workspace" <-- they need to set `open folder` directory setup properly when running from Dev Containers directly 
- [ ] sort out how venvs work in container -> can you just build directly within notebook based on workspace dependencies, or does the `image create` make a requirements file that needs to be unpacked? and do we need to use venvs, or is that self contained within the container so can use directly
    - A Docker container already acts as the ultimate form of a virtual environment. It isolates the entire operating system, filesystem, and all installed packages from the host machine and from all other containers.
- WHEN SELECTING KERNEL IN JUPYTER NOTEBOOK IT RECOMMENDS TO DO QUICK CREATE THAT CREATES A VENV FROM WORKSPACE DEPENDENCEIS -> IS THAT ALL THE INLCUDED PACKAGES IN THE IMAGE?
- [x] when ready, set up the cgroups resource allocation & accounting (see scripts/system/setup-cgroups-slices)
- [x] `container run` needs aesthetic banner at top:

### Exiting Containers
- [x] exit currently auto closes the container (make it so it can run?) exit > [datasciencelab-test-4] detached from container, container keeps running > [datasciencelab-test-4] container is inactive, stopping container ... same even if do touch /workspace/.keep-alive.. currently there's no way to run containers after exit
- [x] clarify the exit / detatch system 
    - should be auto-stopped after 12(?) hrs, but with the option to request overrides 
    - actually: the info IS there if you do --guided => add a miniumal amount of info there in the default (non guided)          

- [x] include explanation in --guided wizards for running / exiting / detatching containers
    - [x] when enter a container with container run -> have better print out for available commands / how to use it / how long it will run for / how to exit it (detatch/exit/stop) (I thought I had this, where has it gone???)
- related: CONTAINER STOP
    - [ ] increase timeout >10s?
    - [ ] add default Yes to ```⚠ This will STOP the container...Continue? [y/N]: ```
- [ ] `container stop` - is it stopping it gracefully or hitting the timeout? does it matter if it hits the timeout? if it does, should we extend the timeout?
- [x] `container exit --guided` prints "Auto-Stop Policy: 48h of idle GPU time" - this comes from `${YELLOW}$(get_idle_timeout "$USERNAME")${NC} of idle GPU time"` BUT the default in the yaml is 24h, and the admin user (datasciencelab) gets `null` in the idle_timeout? IS DATASCIENCELAB A RESEARCHER THEN? they get 48hs???


### Container-stop
- [ ] the current design problem: resource allocation happens at container create (assigned GPU/MIG) ==> if after a task/work done, user keeps same container (but not running, just stopped), then it still has the same GPU/MIG ID allocated. The problem is that that GPU/MIG may no longer be available (if keeping container around just to reload it another day). I.e. the resource availability landscape may have changed. This might lead to failure to re-start/re-run the container? 
    - Refactor: What is best prctice here in industry?
    - one option: move resource allocation to the container start /sop stage?
        - plus, force / automate / encourage removal of containers after a work task complete?
            - e.g. at the end of the `container stop` GUI (give y/n option to remove container with default=y)
            - e.g. as a crontab job (just as GPU is removed after 0.5h (resource yaml: `gpu_hold_after_stop: 0.25h `) -> automate container removal (add in `container_remove_after_stop`)after e.g. 0.5h of being stopped)
            - e.g. as a warning message when a user ties to restart an old container and (if resource no longer available) they get a resource allocation problem notification -> instructs them to remove container and recreate it.
            - or add in a --rm flag into the docker call? or does this stop it being interactive?
        - SLURM / K8s?


### Container-cleanup
- [x] container-cleanup → calls mlc-remove + GPU cleanup ==> need to check this GPU cleanup logic is safe!
- [x] `container cleanup` -> no way to just delete volumes without naming them:
    - container cleanup --volumes => goes to GUI to select stopped containers, instead get it to open up all volumes to select (gracefully loop back after each deletion, to be able to reselect more)
    - container cleanup --volumes --all => first deletes containers, THEN deletes volumes (change it to only delete volumes)
    - also when deleting all (container cleanup --volumes --all), list the found volumes (and their number) first, so user can confirm to continue or not
- [ ] REFACTOR BUIT FIRST CHECK WHAT'S THERE & HOW IT BEHAVES
    - keep `container stop` as is 
    - then `container cleanup` -> `container remove` (rename all scripts cmd aliases, dependencies etc),
    - `container remove` with arguments -> acts directly as a script (e.g. <container-name> --images --volumes)
    - `container remove` currently also removes images (and maybe also volumes??). 
        - Default GUI behaviour should remove JUST container by default -> but presents user with a choice (with yellow warning) -> y/n also remove 1) image, 2) volumes ('no' by default). 
        - in the --guided mode, include explanation (.e.g if remove images then still have dockerfille + explain what happens if remove volumes, etc)
        - if comes with arguments --images and --volumes, unless the -f / --force flag there, then flash warnings -> require: y/n confirmation
    - 
    - for both GUI / as script: include prompt to 


# Container starts
- [x] a new command from AIME v2 -> test + add to documentation around CLI ecosystem (esp to alias-listcont)

### GPU allocation  
- [x] Check logging all works

### for all dockerfile > image > container workflow
- [x] make more modular at same-tier level:
    - avoid duplication of functionality
    - currently there's a lot of parallel tier commands calling eachother = bad design
    -  instead: at end of completion of that command's core function, it should gives concise output of what was done, and what command to run next to continue the workflow (rather than calling that command itself)
    - this makes each command at each level more independent / isolated: they don't do parallel calls; only commands at a higher tier can call comamnds at a lower tier = good design
    - principle: all tier 2 commands should be isolated from eachtoerh -> Tier 3 workflow orchestrators bring this together
    - instead of calling eachother: they same-tier commands give user concise update what they did and bash command to implement next stage
- [x] also make sure ALL Tier 1 base commands from aime are fully incorporated into ds01 3 tier structure.

### Container Cleanup

### Container Stats 
- [x] buggy: "unknown flag: --filter"
- [x] check the description is correct

## Container code refactor
- [ ] reorganise scripts dir to make more sense between admin vs user vs docker, etc scripts 
    - admin is too broad -> it should be dissagregated by functionality

### ds01 dashboard
- [ ] currently shows full GPU utilisation % -> ALSO show each MIG's util %
- [ ] currently showws each MIG's containers -> ALSO show full GPU's containers
- [ ] resolve the ds01-managed issue
    - i think this comes from `ds01-run`
    - this command will be depreciated soon, as I don't think it does anything useful??
    - [ ] instead everything will go through `container create` -> this process needs to be associated with approrpiate cgroup
        - [ ] all under ds01 slice
            - students -> under student group (and then within that each user's own slice for granular monitoring)
            - researchers-> under researcher group (and then within that each user's own slice for granular monitoring)
            - admin -> under admin group (and then within that each user's own slice for granular monitoring)
        - [ ] strategise first: is this sufficient for monitoring, allocating, tracking? or is there a better way to structure this?
    - [ ] once this is implemented, and `ds01-run` removed, clean up the ds01 dashboard 
        - [ ] e.g. do not need "DS01 System Containers:"
        - [ ] e.g. active users should be ALL users on the server - like actually all of them, not just "No DS01-managed containers currently running"
- [ ] I would like the GPU / MIG allocation and tracking sytem (and the dashboard & logs) to be robust to occasional changes in MIG configs
    - might be that we have only full G/PUs sometimes, or only MIGs, or different sized MIGs, or some other combination
    - the whole system needs to be robust to those changed

# Resource Allocation
- [x] work on MIG instance partitioning script (/opt/ds01-infra/scripts/admin/ds01-mig-partition)
    - currently it fails
- [x] add alias: ds01 mig-partition
- [x] update container allocation based on UUID system (see `/docs-admin/gpu-allocation-implementation.md`) 
    - this is a bit of a mess, make indexing more intuitive to users!
- [x] currently the system is not auto setup: (are these cron jobs? or is there better system to automate?)
    - [x] stopping idle container 
    - [x] enforcing max runtime limits
    - [x] cleaning up stopped containers (GPU hold limit)
- [ ] update design so that resource allocation happens at `container start / run` not `container create`
    - this will require quite a lot of refactoring + moving away from `mlc-open` -> `mlc-open-patched` OR direct docker command that also replicates as much of `mlc-open` as possible.
    - see below:
    ARCHITECTURE CHANGES

    Core Allocation Flow:
    1. ✅ Remove GPU allocation from container-create
    2. ✅ Add GPU allocation to container-run and container-start
    3. ✅ Release GPU immediately on container-stop (no hold timer)
    4. ✅ Remove GPU release from container-cleanup (already released)
    5. ✅ Implement CUDA_VISIBLE_DEVICES injection into container

    Technical Implementation:
    - Create containers with --gpus all (or --gpus count=MAX_GPUS)
    - Allocate GPU when user runs container-run/container-start
    - Set CUDA_VISIBLE_DEVICES via docker exec -e when entering
    - Release GPU when container-stop (no hold period)
    - have clear separation between `container start` vs `container run` 

    ---
    DETAILED CHECKLIST

    1. Core Scripts - Allocation Logic

    - /opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh
        - Remove gpu_allocator.py allocate call
        - Change from --gpus device=$GPU_ID to --gpus count=$MAX_GPUS or --gpus all
        - Keep resource limits enforcement (CPU, memory, etc.)
    - /opt/ds01-infra/scripts/user/container-run
        - Add gpu_allocator.py allocate call before entering container
        - Replace mlc-open with custom docker exec -e CUDA_VISIBLE_DEVICES=$GPU_ID
        - Handle auto-start if container stopped
        - Update guided mode explanations (GPU allocated now, not at create)
    - /opt/ds01-infra/scripts/user/container-start
        - Add gpu_allocator.py allocate call
        - Store GPU allocation in metadata
        - Update guided explanations
    - /opt/ds01-infra/scripts/user/container-stop
        - Add gpu_allocator.py release call (immediate release)
        - Remove all "GPU hold" messaging
        - Update guided explanations (GPU freed immediately on stop)
    - /opt/ds01-infra/scripts/user/container-cleanup
        - Remove gpu_allocator.py release call (already released on stop)
        - Update "Cleanup vs Stop" explanations
        - Remove gpu_hold from comparison messaging

    2. GPU Allocator State Management

    - /opt/ds01-infra/scripts/docker/gpu_allocator.py
        - Remove mark_stopped() function (no longer needed)
        - Remove release_stale() function (GPUs released on stop)
        - Remove stopped_at timestamp logic
        - Simplify to: allocate (on run), release (on stop)
        - Keep orphan cleanup (for crashed/deleted containers)
    - /opt/ds01-infra/scripts/maintenance/cleanup-stale-gpu-allocations.sh
        - Simplify to only clean orphaned allocations (container deleted but allocation remains)
        - Remove hold timeout logic
        - Or delete entirely if not needed
    - /etc/cron.d/ds01-gpu-cleanup (if exists)
        - Update or remove depending on cleanup script changes

    3. Configuration

    - /opt/ds01-infra/config/resource-limits.yaml
        - Remove gpu_hold_after_stop parameter from all groups
        - Keep idle_timeout (still auto-stops idle running containers)
        - Keep max_runtime (absolute max running time)
    - /opt/ds01-infra/scripts/docker/get_resource_limits.py
        - Remove --gpu-hold-time flag
        - Update get_user_lifecycle_limits() to only return 2 values (idle_timeout, max_runtime)

    4. User-Facing Scripts - Update Messaging

    - /opt/ds01-infra/scripts/user/container-exit
        - Remove gpu_hold from get_user_lifecycle_limits() call
        - Remove GPU hold messaging from output
        - Update resource limits display (only show idle_timeout, max_runtime)
        - Update "Exit vs Stop vs Cleanup" section
    - /opt/ds01-infra/scripts/user/get-limits
        - Remove gpu_hold_after_stop from display
        - Update resource limits section
    - /opt/ds01-infra/scripts/user/container-list
        - Update GPU status display (only show "Allocated" for running containers)
        - Stopped containers show "None" for GPU

    5. Monitoring & Dashboard

    - /opt/ds01-infra/scripts/monitoring/gpu-status-dashboard.py
        - Update to show allocations only for running containers
        - Remove stopped container GPU tracking
    - /opt/ds01-infra/scripts/monitoring/mlc-stats-wrapper.sh
        - Should work as-is (shows actual GPU usage)
    - /opt/ds01-infra/scripts/monitoring/container-dashboard.sh
        - Update GPU allocation display if needed

    6. Documentation

    - /opt/ds01-infra/CLAUDE.md
        - Rewrite "GPU Allocation Flow" section (allocate at run, not create)
        - Update "On Container Stop" (immediate release, no hold)
        - Update "Automatic GPU Release" (orphan cleanup only)
        - Remove "GPU Hold After Stop" from recent changes
        - Update all lifecycle documentation
    - /opt/ds01-infra/docs/gpu-allocation-implementation.md (if exists)
        - Update allocation strategy documentation
    - /opt/ds01-infra/README.md
        - Update GPU allocation description if mentioned

    7. Testing & Validation

    - Test container-create (should work without GPU allocation)
    - Test container-run (should allocate GPU dynamically)
    - Test container-stop (should release GPU immediately)
    - Test container-start (should allocate GPU)
    - Test container-cleanup (should work without GPU release)
    - Test competing for scarce GPUs (multiple users)
    - Test CUDA_VISIBLE_DEVICES inside containers (nvidia-smi, pytorch)
    - Verify no orphaned allocations in /var/lib/ds01/gpu-state.json

    ---
    CRITICAL TECHNICAL DECISION

    How to inject CUDA_VISIBLE_DEVICES?

    Option 1: Replace mlc-open with custom docker exec
    docker exec -it -e CUDA_VISIBLE_DEVICES=$GPU_ID $CONTAINER_TAG bash

    Option 2: Modify container env via docker update before entering
    docker update --env CUDA_VISIBLE_DEVICES=$GPU_ID $CONTAINER_TAG
    docker exec -it $CONTAINER_TAG bash  # env persists

    Recommendation: Option 1 (per-session env var, cleaner, more flexible)

    # Robustness Checks
    - [ ] test for local / admin / student / researcher users

    ### Files Needing Updates:
    - [x] `scripts/docker/mlc-create-wrapper.sh` - Integrate GPU allocator + priority + graceful errors
    - [x] `scripts/system/setup-resource-slices.sh` - Update for new YAML structure
    ### Files Needing Updates:
    - [x] `scripts/docker/mlc-create-wrapper.sh` - Integrate GPU allocator + priority + graceful errors
    - [x] `scripts/system/setup-resource-slices.sh` - Update for new YAML structure



    # Configs
    - [ ] when fully set up: delete the setup scripts (in the /opt/scripts/system)

    # Miscellaneous

    # Partitioning & GPU allocation
    - [x] I set up 3 MIG instances: Claude thought this was 2g.20gb profile each, but actually I have NVIDIA A100-PCIE-40GB -> so need to update this
    - [x] Set up MIG vs MPS?
    - [x] I set up 3 MIG instances: Claude thought this was 2g.20gb profile each, but actually I have NVIDIA A100-PCIE-40GB -> so need to update this
    - [x] Set up MIG vs MPS?
    - [x] implement GPU allocation properly
    - [x] I set up so that total GPUs allocated hard limit -> change it so that the user limits apply to the containers they can spin up (but not the number of containers total)? or maybe leave it so they have total limit -> means they have to close running containers
    - [x] currently my resource allocation is by GPU -> instead, it should be by MIG partition (?) -> rename in the resource-limits.yaml to max_mig
    - [x] scripts/docker/mlc-create-wrapper.sh - Needs GPU allocator integration!!!!
        - 4. Wrapper Script Integration
        - The mlc-create-wrapper.sh still needs updates to:
            - Call gpu_allocator.py with priority
            - Show graceful error messages
            - Check container limits
            - Register release hook
    - [x] check, is max_mig_per_user
    - [x] check: idle timeout -> how do i set it so that users can run training runs in background, but that it checks when it's done and shuts it if nothing happening?
    - [ ] Dynamic MIG configuration
    - Auto-partition GPUs based on demand
    - Reconfigure MIG profiles on-the-fly
    - [ ] Container migration
    - Move containers between GPUs
    - Live migration for maintenance


# Testing
- [ ] set up unit, functional, integraton tests
    
# User & Permission Management
### cgroups
- [ ] not sure if i optimally set up cgroups correctly 
- [ ] within user-group slice, each user should then get their own slice -> can see how much each user is using (in logs / reports)?
- [ ] I don't think this is set up properly: `systemctl status ds01.slice` shows it being inactive
- [ ] need to robustly test once I have how a NEW user is added from Huy

#### User groups
- [ ] sort out user groups (incl using docker-users in the scripts, rather than docker -> remove docker group)

# File/Dir Clean Up of SSD
- [ ] once identified current users -> send message out via dsl for saving important work -> begin deleting.
- [ ] clean up disk
- [ ] clean up old / images / containers
    - [ ] many remaining images to clean up (`sudo docker images`) -> `sudo docker image prune -a`

