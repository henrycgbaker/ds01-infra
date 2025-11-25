# Deprecated Scripts

This directory contains scripts that have been deprecated in favor of the new modular command architecture.

**Deprecated on:** 2025-11-10

## Deprecated Scripts

### `create-custom-image.sh`
**Replaced by:** `image-create`
**Reason:** Redundant with Tier 2 image management commands

### `manage-images.sh`
**Replaced by:** `image-create`, `image-list`, `image-update`, `image-delete`
**Reason:** Monolithic script replaced by modular Tier 2 commands

### `student-setup.sh`
**Replaced by:** `user-setup`
**Reason:** Functionality merged into unified onboarding wizard

## Migration Guide

If you have scripts or documentation referencing these old commands:

| Old Command | New Command |
|-------------|-------------|
| `create-custom-image.sh` | `image create` or `image-create` |
| `manage-images.sh` | `image list/create/update/delete` |
| `student-setup.sh` | `user-setup` or `new-user` |

## Removal Timeline

These scripts will remain in this directory for **3 months** (until 2025-02-10) to allow for migration.
After that date, they will be permanently removed from the repository.
