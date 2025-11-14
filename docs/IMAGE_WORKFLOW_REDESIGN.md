# Image Workflow Redesign Strategy

## AIME Base Image Analysis

### What's IN the AIME Base (aimehub/pytorch-2.7.1-cuda12.6.3)
**Framework & Compute (13 packages):**
- torch, torchaudio, torchvision, triton
- nvidia-cuda-*, nvidia-cudnn-*, nvidia-nccl-* (CUDA stack)

**Core Python Utilities (8 packages):**
- conda (package management)
- numpy 2.2.6 (arrays/numerical)
- pillow 11.0.0 (image processing)
- tqdm 4.67.1 (progress bars)
- ipython 9.3.0 (interactive shell)
- psutil 7.0.0 (system monitoring)
- requests 2.32.3 (HTTP)
- pyyaml 6.0.2 (config parsing)

**Total:** 133 packages (mostly CUDA/conda dependencies)

### What's MISSING (commonly needed for data science)
**Core Data Science:**
- pandas, scipy, scikit-learn (NOT included)

**Jupyter/Interactive:**
- jupyter, jupyterlab, notebook, ipykernel, ipywidgets (NOT included, only ipython)

**Visualization:**
- matplotlib, seaborn, plotly (NOT included)

**Domain-Specific:**
- opencv-python (computer vision)
- transformers, datasets (NLP)
- tensorboard, wandb (experiment tracking)

**Conclusion:** AIME bases are framework-focused (PyTorch/TensorFlow + CUDA), NOT comprehensive data science stacks. DS01's package installation workflow is ESSENTIAL.

---

## mlc-create vs Dedicated Build Logic

**Q: Can we use mlc-create for dockerfile→image building?**

**A: NO** - Different responsibilities:
- `mlc-create` (mlc-patched.py) = Creates CONTAINERS from existing images
- `docker build` = Builds IMAGES from Dockerfiles

**Correct workflow:**
```
1. image-create: Generate Dockerfile + Run `docker build`
2. container-create: Call mlc-create-wrapper → mlc-patched.py
```

---

## Proposed Phased Workflow for image-create

### Option A: Detailed Taxonomy (RECOMMENDED)

**Phase 1: Base Framework Selection**
```
Select base framework:
  1) PyTorch 2.8.0 + CUDA 12.6.3 (CUDA_ADA) [recommended]
  2) TensorFlow 2.16.1 + CUDA 12.3 (CUDA_ADA)
  3) JAX + CUDA (if available)
  4) PyTorch CPU-only
  5) Custom - Specify Docker image (e.g., ubuntu:22.04, python:3.11)
  6) Custom - Build from scratch (no base image)
```

After selection, display:
```
━━━ Selected Base Image ━━━
Image: aimehub/pytorch-2.8.0-aime-cuda12.6.3
Architecture: CUDA_ADA (optimized for A100/A6000)

Key Pre-installed Packages:
  • PyTorch 2.8.0 (torch, torchvision, torchaudio)
  • CUDA 12.6.3 + cuDNN
  • numpy 2.2.6, pillow, tqdm
  • conda, ipython, psutil

📋 View full package list? [y/N]:
```

**Phase 2: Core Python & Interactive (Jupyter)**
```
Install Jupyter Lab & interactive tools?

These enable notebook-based development:
  • jupyter, jupyterlab - Web-based IDE
  • ipykernel - Python kernel for notebooks
  • ipywidgets - Interactive widgets
  • notebook - Classic Jupyter interface

Default packages: jupyter jupyterlab ipykernel ipywidgets notebook

Options:
  1) Yes - Install defaults (recommended for data science)
  2) No - Skip (use terminal/IDE only)
  3) Custom - Specify packages manually

Choice [1-3, default: 1]:
```

**Phase 3: Core Data Science**
```
Install core data science packages?

Essential libraries for data analysis:
  • pandas - DataFrames & data manipulation
  • scipy - Scientific computing
  • scikit-learn - Traditional ML algorithms
  • matplotlib, seaborn - Visualization

⚠️  Note: These are NOT in AIME base (only numpy included)

Default packages: pandas scipy scikit-learn matplotlib seaborn

Options:
  1) Yes - Install defaults (recommended)
  2) No - Skip (framework-only setup)
  3) Custom - Specify packages manually

Choice [1-3, default: 1]:
```

**Phase 4: Use-Case Specific**
```
Select use case (domain-specific packages):

  1) General ML (default)
     xgboost, lightgbm, catboost, optuna
     → Boosting algorithms, hyperparameter tuning

  2) Computer Vision
     opencv-python, timm, albumentations
     → Image processing, pre-trained models (torchvision already in base)

  3) Natural Language Processing
     transformers, datasets, tokenizers, accelerate, sentencepiece
     → Hugging Face ecosystem for LLMs/NLP

  4) Reinforcement Learning
     gymnasium, stable-baselines3
     → RL environments and algorithms

  5) None/Custom
     Skip or specify packages manually

Choice [1-5, default: 1]:
```

**Phase 5: Additional Packages**
```
Additional Python packages? (space-separated, or Enter to skip)
Examples: wandb tensorboard pytorch-lightning optuna

> _

System packages (apt)? (or Enter to skip)
Examples: htop tmux vim git-lfs ffmpeg

> _
```

**Phase 6: Dockerfile Generation**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Phase 1/3: Dockerfile Created
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Location: ~/dockerfiles/my-project-username.Dockerfile

Structure:
  FROM aimehub/pytorch-2.8.0-aime-cuda12.6.3
  • System packages (git, curl, vim, htop)
  • Core Python & Jupyter (4 packages)
  • Core Data Science (5 packages)
  • Use case: General ML (4 packages)
  • Additional: wandb tensorboard

Total packages to install: 15
Estimated build time: 3-5 minutes
```

**Phase 7: Build Image**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 2/3: Build Docker Image?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This will:
  • Pull base image: aimehub/pytorch-2.8.0-aime-cuda12.6.3 (~3 GB)
  • Install 15 packages
  • Configure Jupyter Lab
  • Save final image: my-project-username (~5 GB)

Estimated time: 3-5 minutes

Build image now? [Y/n]:
```

**Phase 8: Create Container**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 3/3: Create Container?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

A container is a running instance where you'll do your work.

This will:
  • Create container: my-project
  • Allocate GPU resources
  • Mount workspace: ~/workspace/my-project
  • Apply resource limits

Create container now? [Y/n]:
```

---

### Option B: Simplified Taxonomy (Alternative)

Collapse Phases 2-4 into single "Package Selection":

**Phase 2: Package Selection**
```
Select package bundles to install:

  [x] Essential (recommended)
      jupyter, pandas, numpy, matplotlib, scikit-learn
      → Interactive notebooks + core data science

  [ ] Use Case: General ML
      xgboost, lightgbm, catboost, optuna

  [ ] Use Case: Computer Vision
      opencv, timm, albumentations

  [ ] Use Case: NLP
      transformers, datasets, tokenizers

  [ ] Use Case: Reinforcement Learning
      gymnasium, stable-baselines3

Select bundles (space to toggle, Enter to continue):
```

**Comparison:**

| Aspect | Option A (Detailed) | Option B (Simplified) |
|--------|--------------------|-----------------------|
| Phases | 8 total | 6 total |
| Clarity | Very explicit about what's included | More concise |
| Flexibility | High - each tier customizable | Medium - bundle-based |
| Educational | Better for --guided mode | Faster for experienced users |
| Complexity | Higher | Lower |

**RECOMMENDATION: Option A** - Better aligns with educational goals, clearer package categorization, and easier to explain in --guided mode.

---

## Key Design Principles

1. **Show AIME base contents BEFORE asking what to install**
   - Prevents duplicate installations
   - Sets expectations correctly

2. **Consistent key packages display**
   - Always show: conda, numpy, pillow, tqdm, torch, torchvision, torchaudio
   - These are consistent across AIME PyTorch images (may vary for TensorFlow)

3. **Default to installing data science packages**
   - AIME bases are framework-only, most users need more

4. **Custom image workflows:**
   - "Custom (specify image)": Skip base package prompts, just add extras
   - "Custom (no base)": Full control, start from scratch (e.g., FROM python:3.11)

5. **Dockerfile location:**
   - Default: `~/dockerfiles/` (centralized)
   - Optional: `--project-dockerfile` for per-project Dockerfiles

6. **--guided mode:**
   - Explain each phase in detail
   - Show examples and recommendations

---

## Implementation Checklist

### image-create
- [ ] Update framework selection menu (lines 267-293)
  - Latest versions from AIME v2 catalog
  - Add "Custom (no base)" option
- [ ] Add function: `show_base_image_packages()`
  - Extract key packages: `docker run --rm <image> pip list 2>/dev/null`
  - Parse and display formatted list
- [ ] Refactor package selection phases
  - Phase 2: Core Python & Jupyter (new)
  - Phase 3: Core Data Science (expanded from current "base packages")
  - Phase 4: Use-case specific (existing, expand package lists)
- [ ] Update --guided explanations
  - Explain AIME base vs DS01 additions
  - Clarify each package category

### image-update
- [ ] Apply same package display logic
- [ ] Show current Dockerfile contents categorized by phase:
  ```
  AIME Base: aimehub/pytorch-2.8.0-aime-cuda12.6.3
  Key Pre-installed: conda, numpy, pillow, tqdm, torch, torchvision, torchaudio

  System Packages: git, curl, vim, htop
  Core Python: jupyter, jupyterlab, ipykernel, ipywidgets
  Core Data Science: pandas, scipy, scikit-learn, matplotlib, seaborn
  Use Case (General ML): xgboost, lightgbm, catboost, optuna
  Custom: wandb, tensorboard
  ```
- [ ] Offer same phased update workflow

### container-create
- [ ] REMOVE all image creation functionality (lines 140-150)
- [ ] Simplify to: "Select existing image from list"
- [ ] Add interactive image selection GUI (if no args provided)
- [ ] --guided: Explain container vs image, give command to run image-create

### Tier 2 Modularization
- [ ] Audit all Tier 2 commands for entanglement
- [ ] Remove cross-calls between Tier 2 commands
- [ ] Use --guided to suggest next steps (don't auto-call)

### Tier 3 Orchestrators
- [ ] Review `project-init`: Does it still orchestrate cleanly?
- [ ] Review `user-setup`: Does it still orchestrate cleanly?
- [ ] Ensure they call Tier 2 commands sequentially (no duplication)

---

## Questions for Review

1. **Taxonomy:** Option A (detailed 8-phase) or Option B (simplified 6-phase)?
2. **Key packages:** Is the list correct? (conda, numpy, pillow, tqdm, torch, torchvision, torchaudio, ipython, psutil)
3. **Use-case packages:** Should we expand the lists? Add more options?
4. **Framework selection:** Include JAX? Other frameworks from AIME catalog?
5. **Architecture selection:** Should users choose CUDA_ADA vs CUDA_AMPERE vs ROCM?

## Next Steps

Once approved:
1. Implement `show_base_image_packages()` function
2. Refactor `image-create` phases 1-5
3. Update `image-update` to match
4. Simplify `container-create` (remove image creation)
5. Test E2E workflow
6. Update documentation
