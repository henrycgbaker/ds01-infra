# Docker Images

Understanding Docker images - the blueprints for containers.

## Images vs Containers

**Image = Blueprint (class definition)**
- Contains: OS, Python, packages, your setup
- Immutable (read-only)
- Can create many containers from one image

**Container = Instance (object)**
- Running instance of an image
- Writable filesystem layer
- Ephemeral (temporary)

## DS01 Image Hierarchy

```
┌────────────────────────────────────┐
│ Base AIME Image                    │
│ (PyTorch 2.8.0 + CUDA + Ubuntu)    │
└──────────────┬─────────────────────┘
               │ FROM
               ↓
┌────────────────────────────────────┐
│ Your Custom Image                  │
│ + Jupyter Lab                      │
│ + Data science packages            │
│ + Your requirements                │
└────────────────────────────────────┘
```

## Building Images

**Interactive (recommended):**
```bash
image-create my-project
```

**Manual (Dockerfile):**
```dockerfile
FROM henrycgbaker/aime-pytorch:2.8.0-cuda12.4-ubuntu22.04
WORKDIR /workspace
RUN pip install transformers datasets
```

## Image Layers

Images are built in layers:
```
Layer 5: Your packages      (50 MB)
Layer 4: Data science pkgs  (500 MB)
Layer 3: Jupyter Lab        (200 MB)
Layer 2: PyTorch            (2 GB)
Layer 1: Base OS            (1 GB)
────────────────────────────────────
Total: 3.75 GB
```

**Benefits:**
- Caching (rebuild only changed layers)
- Sharing (layers shared between images)

## Managing Images

```bash
# List images
image-list

# Rebuild image
image-update my-project

# Remove image
image-delete my-project

# Docker commands
docker images
docker rmi <image>
```

## Next Steps

→ [Building Custom Images](../workflows/custom-images.md)
→ [Dockerfile Guide](../advanced/dockerfile-guide.md)
