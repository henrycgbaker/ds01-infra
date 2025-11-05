# /etc/ds01/ Configuration Mirror

This directory mirrors files that should be deployed to `/etc/ds01/` on the server.

## Files

### container-aliases.sh
**Source:** `/opt/ds01-infra/config/container-aliases.sh`
**Deploy to:** `/etc/ds01/container-aliases.sh`
**Purpose:** Central alias configuration for all container users
**Access:** Read-only, mounted into containers

This file is the single source of truth for all container aliases. It is:
- Maintained in the git repository at `config/container-aliases.sh`
- Mounted read-only into containers at `/etc/ds01/container-aliases.sh`
- Sourced by `container-init.sh` when users enter containers

**Important:** Do NOT manually edit `/etc/ds01/container-aliases.sh` on the server. Instead:
1. Edit `config/container-aliases.sh` in this repository
2. Commit changes to git
3. The file is automatically available via Docker volume mount (no deployment needed)

## Deployment

Unlike other `/etc/` configurations, files in `/etc/ds01/` are typically mounted directly from this repository rather than being copied. This ensures:
- Always in sync with git repository
- No manual deployment steps needed
- Changes take effect immediately for new containers

If you need to deploy to `/etc/ds01/` manually:
```bash
sudo mkdir -p /etc/ds01
sudo cp config/container-aliases.sh /etc/ds01/container-aliases.sh
sudo chmod 644 /etc/ds01/container-aliases.sh
```

However, the standard approach is to mount directly from `/opt/ds01-infra/config/` which happens automatically in `container-create`.
