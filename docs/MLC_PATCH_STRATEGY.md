# mlc-patched.py - Custom Image Support Strategy

**Date:** 2025-11-12
**Purpose:** Document the minimal patch to AIME v2's mlc.py to support DS01 custom images

---

## Problem Statement

**AIME v2's mlc.py CANNOT accept custom images:**
- Lines 1534-1612: Framework/version MUST exist in ml_images.repo catalog
- No mechanism to bypass catalog lookup
- Custom images (built with DS01's `image-create`) cannot be used

**DS01 Requirement:**
- Users build custom images: `FROM aimehub/pytorch... + RUN pip install packages`
- Container creation needs to use these custom images, not catalog images
- Must preserve AIME's container setup (UID/GID matching, labels, etc.)

---

## Solution: mlc-patched.py

**Approach:** Create a MINIMALLY modified version of mlc.py that:
1. Accepts a new `--image` flag for custom images
2. Bypasses catalog lookup when custom image provided
3. Preserves ALL other AIME v2 logic (95%+ unchanged)
4. Maintains compatibility with AIME's ecosystem

**Why Patch vs Wrapper:**
- mlc.py is 2,400 lines of sophisticated Python logic
- Includes: user creation, volume management, GPU detection, interactive mode
- Rewriting this in a wrapper = 2000+ lines of duplicated code
- Patching ~50 lines = 2% change, 98% AIME reuse

---

## Patch Specification

### Change 1: Add --image Argument

**File:** mlc-patched.py
**Line:** ~100 (in parser_create section)

```python
# EXISTING:
parser_create.add_argument('framework', nargs='?', type=str, help='Name of the framework (Pytorch, Tensorflow).')
parser_create.add_argument('version', nargs='?', type=str, help='Version of the framework.')

# ADD:
parser_create.add_argument(
    '--image',
    type=str,
    default=None,
    help='Custom Docker image to use (bypasses catalog lookup). Image must exist locally.'
)
```

### Change 2: Modify Image Resolution Logic

**File:** mlc-patched.py
**Lines:** ~1534-1612 (framework/version validation section)

```python
# ADD at line ~1533 (before "Extract framework, version and docker image from the ml_images.repo file"):

# ========== DS01 PATCH: Custom Image Support ==========
if args.image:
    # Custom image provided - bypass catalog lookup
    selected_docker_image = args.image

    # Validate image exists locally
    try:
        result = subprocess.run(
            ['docker', 'image', 'inspect', selected_docker_image],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"\n{ERROR}Custom image not found:{RESET} {INPUT}{selected_docker_image}{RESET}")
            print(f"{HINT}Build it first with: image-create{RESET}\n")
            exit(1)
    except Exception as e:
        print(f"\n{ERROR}Error checking custom image:{RESET} {e}\n")
        exit(1)

    # For custom images, framework/version are optional (labels only)
    selected_framework = args.framework or "custom"
    selected_version = args.version or "latest"

    print(f"\n{INFO}Using custom image:{RESET} {INPUT}{selected_docker_image}{RESET}")
    print(f"{NEUTRAL}Framework: {selected_framework}, Version: {selected_version}{RESET}\n")

    # Skip catalog lookup - jump directly to container name validation
    validated_container_name, validated_container_tag = get_container_name(args.container_name, user_name, args.command, args.script)

    # Skip to workspace selection (line ~1618)
    # ... (rest of script continues normally)

else:
    # ORIGINAL AIME LOGIC: Use catalog
    # Extract framework, version and docker image from the ml_images.repo file
    framework_version_docker = extract_from_ml_images(repo_file, architecture)
    # ... (existing code continues)
# ========== END DS01 PATCH ==========
```

### Change 3: Update build_docker_create_command Call

**File:** mlc-patched.py
**Line:** ~1850 (where docker create command is built)

**No changes needed** - function already accepts `selected_docker_image` parameter!

### Change 4: Add DS01 Label

**File:** mlc-patched.py
**Line:** ~1425 (in build_docker_create_command)

```python
# EXISTING labels:
'--label', f'{container_label}.FRAMEWORK={selected_framework}-{selected_version}',
'--label', f'{container_label}.GPUS={num_gpus}',

# ADD:
'--label', f'{container_label}.DS01_MANAGED=true',
'--label', f'{container_label}.CUSTOM_IMAGE={selected_docker_image if "--image" in sys.argv else ""}',
```

---

## Patch Summary

**Total Changes:**
- ~15 lines for --image argument
- ~35 lines for custom image logic
- ~2 lines for DS01 labels
- **Total: ~52 lines** added to 2,400-line script = **2.2% change**

**Preserved:**
- 100% of AIME's user creation logic
- 100% of volume mounting logic
- 100% of GPU detection logic
- 100% of interactive mode
- 100% of label system
- 100% of container lifecycle

---

## Usage Examples

### AIME Catalog Workflow (unchanged)
```bash
mlc-patched create my-project pytorch 2.7.1
# Works exactly like mlc create
```

### DS01 Custom Image Workflow (NEW)
```bash
# 1. Build custom image (DS01's image-create)
image-create my-cv-project -f pytorch -t cv
# Result: my-cv-project-john (FROM aimehub/pytorch + custom packages)

# 2. Create container from custom image
mlc-patched create my-cv-project pytorch --image=my-cv-project-john
# Uses custom image, bypasses catalog, applies all AIME setup
```

### DS01 Wrapper Integration
```bash
# mlc-create-wrapper.sh detects custom image
if [ -n "$CUSTOM_IMAGE" ]; then
    mlc-patched create $NAME $FRAMEWORK --image=$CUSTOM_IMAGE \
        $RESOURCE_LIMITS $GPU_ARGS
else
    mlc-patched create $NAME $FRAMEWORK $VERSION \
        $RESOURCE_LIMITS $GPU_ARGS
fi
```

---

## Testing Plan

### Test 1: AIME Catalog (Compatibility)
```bash
mlc-patched create test1 pytorch 2.7.1
# Expected: Identical to mlc create
# Verify: docker inspect shows aimehub/pytorch image
```

### Test 2: Custom Image
```bash
image-create test-img -f pytorch
mlc-patched create test2 pytorch --image=test-img-john
# Expected: Container created from custom image
# Verify: docker inspect shows test-img-john
```

### Test 3: Custom Image Not Found
```bash
mlc-patched create test3 pytorch --image=nonexistent
# Expected: Error message + exit
```

### Test 4: Labels Preserved
```bash
docker inspect test2._.1001 --format '{{json .Config.Labels}}' | jq
# Expected: All aime.mlc.* labels + DS01_MANAGED=true
```

### Test 5: mlc open Compatibility
```bash
mlc open test2
# Expected: Works with patched containers
```

---

## File Structure

```
/opt/ds01-infra/
├── aime-ml-containers/          # Untouched AIME v2 submodule
│   ├── mlc.py                   # Original AIME v2 (2,400 lines)
│   └── ml_images.repo           # Framework catalog
├── scripts/
│   └── docker/
│       ├── mlc-patched.py       # NEW: Patched version (~2,450 lines)
│       ├── mlc-create-wrapper.sh # Updated to call mlc-patched.py
│       ├── get_resource_limits.py
│       └── gpu_allocator.py
```

---

## Maintenance Strategy

**Updating AIME v2:**
1. Pull latest AIME v2 submodule: `git submodule update --remote`
2. Diff check: `diff aime-ml-containers/mlc.py scripts/docker/mlc-patched.py`
3. If AIME changed significantly, re-apply 50-line patch to new version
4. Test all 5 test cases above

**Upstreaming to AIME:**
- Custom image support could be contributed back to AIME
- Add `--image` flag as optional feature
- Maintain backward compatibility (flag is optional)
- Would benefit other AIME users wanting custom packages

---

## Decision: Proceed with mlc-patched.py

**Rationale:**
- ✅ Minimal change (2.2% of codebase)
- ✅ Maximum AIME reuse (97.8%)
- ✅ Maintainable (50 lines to sync on updates)
- ✅ Clean separation (AIME submodule untouched)
- ✅ Backward compatible (catalog workflow unchanged)
- ✅ No duplication (vs 2000+ line wrapper)

**Next Steps:**
1. Create mlc-patched.py
2. Test compatibility with AIME catalog
3. Test custom image workflow
4. Update mlc-create-wrapper.sh
5. Document in INTEGRATION_STRATEGY_v2.md
