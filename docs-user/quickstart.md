# 5-Minute Quickstart

Get from zero to working in 5 minutes.

---

## Step 1: Connect via SSH

From your laptop terminal:

```bash
ssh your-username@ds01-server-address
```

If you don't have SSH keys set up, you'll be prompted for a password.

---

## Step 2: Run First-Time Setup

Once connected, run:

```bash
user-setup
```

This wizard will:
- Set up SSH keys (for GitHub)
- Create your first project workspace
- Build a custom Docker image
- Deploy your first container

**Time:** 15-20 minutes (includes image build)

**Interactive:** Just answer the prompts - it walks you through everything.

**Stuck?** Add `--guided` for more explanations:
```bash
user-setup --guided
```

---

## Step 3: Start Working

After setup completes, you'll be inside a container. Check that GPU is available:

```bash
nvidia-smi
```

You should see GPU information. Now you can:

```bash
# Check Python
python --version

# Check PyTorch (or TensorFlow)
python -c "import torch; print(torch.cuda.is_available())"

# Navigate to your workspace
cd /workspace

# Start coding!
```

---

## Step 4: Exit and Retire (End of Day)

When done working:

```bash
# Exit the container
exit

# Free the GPU for others
container retire my-project
```

**Your files in `~/workspace/` are always saved** - the container is just the temporary environment.

---

## Tomorrow and Beyond

Your daily routine:

```bash
# Morning
project launch my-project --open

# Work...

# Evening
exit
container retire my-project
```

That's it!

---

## Next Steps

→ [Understand the daily workflow](getting-started/daily-workflow.md)

→ [Create additional projects](guides/creating-projects.md)

→ [Set up Jupyter notebooks](guides/jupyter-notebooks.md)

→ [Connect VS Code](guides/vscode-remote.md)

---

## Getting Help

Every command has built-in help:

```bash
<command> --help        # Quick reference
<command> --guided      # Step-by-step mode
<command> --concepts    # Learn before running
```

**Show all available commands:**
```bash
commands
```

**Check system status:**
```bash
dashboard
```

**See your resource limits:**
```bash
check-limits
```
