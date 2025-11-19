# usr-mirrors

This directory contains records of symlinks that should be created in `/usr/local/bin/` for user-facing commands.

## Purpose

Similar to `etc-mirrors/`, this directory tracks system-wide command symlinks that are part of the DS01 infrastructure but live outside the repository.

## Structure

```
usr-mirrors/
└── local/
    └── bin/
        ├── container.link
        ├── container-create.link
        ├── image.link
        ├── image-create.link
        └── ...
```

Each `.link` file contains:
- Documentation about the symlink
- The exact `ln -sf` command to create it

## Creating Symlinks

To create all symlinks in `/usr/local/bin/`:

```bash
sudo /opt/ds01-infra/scripts/system/update-symlinks.sh
```

This script:
1. Creates symlinks for all DS01 commands in `/usr/local/bin/`
2. Organized by 4-tier architecture (Base, Atomic, Orchestrators, Workflows)
3. Makes DS01 commands available system-wide

## Verifying Symlinks

```bash
# Check if symlinks exist
ls -l /usr/local/bin/ | grep ds01-infra

# Test a command
container help
image list
```

## Updating Symlinks

If user commands are added or changed:

1. Update the command list in `scripts/system/create-symlink-records.sh`
2. Run: `scripts/system/create-symlink-records.sh`
3. Run: `sudo scripts/system/update-symlinks.sh`
4. Commit the new `.link` files to git
