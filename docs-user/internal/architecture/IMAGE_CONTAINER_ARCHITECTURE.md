# DS01 Image/Container Architecture

**Last Updated:** December 2024
**Version:** 2.0 (Post-refactor)

## Core Principle: Images are Permanent, Containers are Ephemeral

```
Dockerfile → docker build → Image → docker create → Container
    ↑                         ↓                          ↓
image-create              permanent                 ephemeral
image-update              (user setup)             (workloads)
```

### Key Design Principles

1. **Images are built from Dockerfiles** (never from containers)
2. **Containers are created from images** (not committed back)
3. **Exception:** `container-retire` allows users to explicitly save container changes back to an image
4. **User/group setup happens at image build time**, not container creation time
5. **One image per user-project**, unlimited containers from that image

---

## Workflow Commands

| Command | What it does | Creates |
|---------|--------------|---------|
| `image-create` | Build Dockerfile → Image | Permanent image with user setup |
| `image-update` | Rebuild Dockerfile → Image | Updated image |
| `image-list` | List user's images | - |
| `image-retire` | Remove image | - |
| `container-deploy` | Create container from image | Ephemeral container |
| `container-list` | List user's containers | - |
| `container-retire` | Remove container (optionally save to image) | - |

---

## Image Naming Convention

```
ds01-{USER_ID}/{PROJECT_NAME}:latest
```

Example: `ds01-1722830498/my-project:latest`

The USER_ID ensures images are namespaced per user while avoiding complex LDAP usernames in image tags.

---

## What's in a DS01 Image

Custom images built with `image-create` contain:

### 1. Base Framework (from AIME Catalog)
- PyTorch, TensorFlow, or JAX with CUDA support
- Source: `aimehub/pytorch-2.x.x-aime-cudaX.X.X`

### 2. User-Selected Packages
- **Jupyter:** jupyterlab, ipykernel, ipywidgets
- **Data Science:** pandas, scipy, scikit-learn, matplotlib
- **Use Case:** CV (timm, albumentations), NLP (transformers), etc.

### 3. User/Group Configuration (DS01 Optimization)
- User created with UID/GID matching host user
- Sudo access configured (NOPASSWD)
- Home directory with `.local/bin` for pip --user installs

### 4. DS01 Labels
```dockerfile
LABEL aime.mlc.DS01_HAS_USER_SETUP="true"
LABEL aime.mlc.DS01_USER_ID="1722830498"
LABEL aime.mlc.DS01_GROUP_ID="1722830498"
LABEL aime.mlc.DS01_USERNAME="h-baker-at-hertie-school-lan"
```

These labels tell `mlc-patched.py` to skip the docker run + commit step.

---

## Container Creation Flow

### New Optimized Flow (DS01 Images with Labels)

```
1. container-deploy test-project
2. mlc-patched.py checks image for DS01_HAS_USER_SETUP label
3. If label exists AND UID/GID match:
   → Skip docker run (user setup)
   → Skip docker commit (no new image created)
   → docker create directly from original image
4. Container ready instantly
```

**Benefits:**
- No 4+ minute docker commit of 18GB images
- No orphaned committed images accumulating
- No disk space issues from image sprawl

### Legacy Flow (AIME Catalog Images)

For standard AIME catalog images (not built via `image-create`):

```
1. container-deploy --image aimehub/pytorch-2.x.x (no DS01 labels)
2. mlc-patched.py runs temp container to set up user/group
3. docker commit creates new image with user setup
4. docker create from committed image
5. Remove temp container
```

This ensures backward compatibility with AIME's standard workflow.

---

## File Ownership and Permissions

### Inside Container
- User: `h-baker-at-hertie-school-lan` (sanitized from LDAP username)
- UID/GID: Matches host user (e.g., 1722830498:1722830498)
- Home: `/home/h-baker-at-hertie-school-lan`
- Workspace: `/workspace` (mounted from host)

### Username Sanitization
LDAP usernames like `h.baker@hertie-school.lan` are sanitized:
- `@` → `-at-`
- `.` → `-`
- Invalid chars → `-`

Result: `h-baker-at-hertie-school-lan`

This ensures compatibility with Linux username requirements and systemd slice names.

---

## Related Files

### Scripts
- `/opt/ds01-infra/scripts/user/image-create` - Image builder wizard
- `/opt/ds01-infra/scripts/docker/mlc-patched.py` - Container creator
- `/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh` - Wrapper script
- `/opt/ds01-infra/scripts/user/container-create` - User-facing command

### Libraries
- `/opt/ds01-infra/scripts/lib/username_utils.py` - Python username sanitization
- `/opt/ds01-infra/scripts/lib/username-utils.sh` - Bash username sanitization

### User Files
- `~/dockerfiles/*.Dockerfile` - User's Dockerfiles
- `~/.ds01-config/images/` - Image metadata

---

## Historical Context

### Before Refactor (November 2024)
- Images built without user/group setup
- Every `container-deploy` ran:
  1. `docker run` to create user/group
  2. `docker commit` entire 18GB image
  3. `docker create` from committed image
- Committed images (`*:*._.* `) accumulated, never cleaned
- Container creation took 4+ minutes, often hung on low disk

### After Refactor (December 2024)
- `image-create` bakes user/group into image at build time
- `container-deploy` skips run+commit for labeled images
- No orphaned committed images
- Container creation is instant
- Backward compatible with legacy AIME images

---

## Troubleshooting

### Container creation still slow?
Check if image has DS01 labels:
```bash
docker inspect --format '{{.Config.Labels}}' ds01-1001/my-project:latest
```

Should include `aime.mlc.DS01_HAS_USER_SETUP:true`

### UID/GID mismatch warning?
Image was built by different user. Rebuild with:
```bash
image-create my-project --force
```

### Finding orphaned committed images
```bash
docker images | grep '\._\.'
```

These are legacy committed images from before the refactor.
