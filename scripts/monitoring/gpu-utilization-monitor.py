#!/usr/bin/env python3
"""
DS01 GPU Utilization Monitor
/opt/ds01-infra/scripts/monitoring/gpu-utilization-monitor.py

Tracks actual GPU usage (not just allocation) and identifies underutilized GPUs.

Usage:
    gpu-utilization-monitor.py                 # Current utilization snapshot
    gpu-utilization-monitor.py --json          # JSON output
    gpu-utilization-monitor.py --record        # Record to history log (admin only)
    gpu-utilization-monitor.py --check-waste   # Check for wasted allocations
"""

import subprocess
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Configuration
INFRA_ROOT = Path("/opt/ds01-infra")
STATE_DIR = Path("/var/lib/ds01")
LOG_DIR = Path("/var/log/ds01")
UTILIZATION_LOG = LOG_DIR / "gpu-utilization.jsonl"
EVENT_LOGGER = INFRA_ROOT / "scripts/docker/event-logger.py"
# Use real docker binary directly (bypass wrapper filtering)
DOCKER_BIN = "/usr/bin/docker"

# Thresholds
WASTE_THRESHOLD = 5  # GPU utilization below this % is considered "wasted"
WASTE_DURATION_MINUTES = 30  # Must be wasted for this long to alert


def now_utc():
    """Get current UTC time (timezone-aware)."""
    return datetime.now(timezone.utc)


def now_utc_iso():
    """Get current UTC time as ISO string."""
    return now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")


def get_gpu_utilization():
    """Get current GPU utilization from nvidia-smi."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu",
                "--format=csv,noheader,nounits"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            return None

        gpus = []
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 7:
                gpus.append({
                    "index": int(parts[0]),
                    "name": parts[1],
                    "gpu_util_percent": int(parts[2]) if parts[2] != '[N/A]' else 0,
                    "mem_util_percent": int(parts[3]) if parts[3] != '[N/A]' else 0,
                    "mem_used_mb": int(parts[4]) if parts[4] != '[N/A]' else 0,
                    "mem_total_mb": int(parts[5]) if parts[5] != '[N/A]' else 0,
                    "temperature_c": int(parts[6]) if parts[6] != '[N/A]' else 0
                })
        return gpus
    except Exception as e:
        print(f"Error getting GPU utilization: {e}", file=sys.stderr)
        return None


def get_container_gpu_allocations():
    """Get which containers have GPUs allocated."""
    try:
        result = subprocess.run(
            [
                DOCKER_BIN, "ps",
                "--filter", "label=ds01.gpu.allocated",
                "--format", "{{.Names}}|{{.Label \"ds01.user\"}}|{{.Label \"ds01.gpu.allocated\"}}|{{.Label \"ds01.gpu.uuid\"}}"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        allocations = []
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = line.split('|')
            if len(parts) >= 3:
                allocations.append({
                    "container": parts[0],
                    "user": parts[1] if len(parts) > 1 else "unknown",
                    "gpu_slot": parts[2] if len(parts) > 2 else "",
                    "gpu_uuid": parts[3] if len(parts) > 3 else ""
                })
        return allocations
    except Exception as e:
        print(f"Error getting container allocations: {e}", file=sys.stderr)
        return []


def can_write_log():
    """Check if we can write to the log file."""
    try:
        # Check if log file exists and is writable, or if directory is writable
        if UTILIZATION_LOG.exists():
            return os.access(UTILIZATION_LOG, os.W_OK)
        else:
            return os.access(LOG_DIR, os.W_OK)
    except Exception:
        return False


def record_utilization(gpus, allocations):
    """Record current utilization to log file."""
    if not can_write_log():
        print("Error: Cannot write to log file. Run with sudo for --record.", file=sys.stderr)
        print(f"  Log file: {UTILIZATION_LOG}", file=sys.stderr)
        sys.exit(1)

    LOG_DIR.mkdir(parents=True, exist_ok=True)

    entry = {
        "timestamp": now_utc_iso(),
        "gpus": gpus,
        "allocations": [
            {"container": a["container"], "user": a["user"], "gpu_slot": a["gpu_slot"]}
            for a in allocations
        ]
    }

    with open(UTILIZATION_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")

    print(f"Recorded utilization snapshot to {UTILIZATION_LOG}")


def check_wasted_allocations():
    """Check for GPUs that have been underutilized for too long."""
    if not UTILIZATION_LOG.exists():
        print("No utilization history available yet.")
        print(f"Run 'sudo gpu-utilization-monitor.py --record' periodically to collect data.")
        return []

    # Check read permission
    if not os.access(UTILIZATION_LOG, os.R_OK):
        print(f"Error: Cannot read {UTILIZATION_LOG}", file=sys.stderr)
        print("  This file is only readable by admins.", file=sys.stderr)
        sys.exit(1)

    # Read recent history
    cutoff = now_utc() - timedelta(minutes=WASTE_DURATION_MINUTES)
    history = []

    with open(UTILIZATION_LOG, "r") as f:
        for line in f:
            try:
                entry = json.loads(line.strip())
                ts_str = entry["timestamp"].replace("Z", "+00:00")
                ts = datetime.fromisoformat(ts_str)
                if ts > cutoff:
                    history.append(entry)
            except (json.JSONDecodeError, KeyError, ValueError):
                continue

    if len(history) < 3:  # Need at least a few data points
        print(f"Not enough data points yet ({len(history)} found, need 3+).")
        print(f"Run 'sudo gpu-utilization-monitor.py --record' every 5 minutes to collect data.")
        return []

    # Analyze each container's GPU usage
    container_usage = {}
    for entry in history:
        for alloc in entry.get("allocations", []):
            container = alloc.get("container", "")
            if not container:
                continue
            if container not in container_usage:
                container_usage[container] = {
                    "user": alloc.get("user", "unknown"),
                    "gpu_slot": alloc.get("gpu_slot", ""),
                    "samples": 0,
                    "low_util_samples": 0
                }

            # Check GPU utilization for this container's GPU
            gpu_slot = alloc.get("gpu_slot", "")
            if "." in gpu_slot:
                gpu_idx = int(gpu_slot.split(".")[0])
            else:
                try:
                    gpu_idx = int(gpu_slot) if gpu_slot else -1
                except ValueError:
                    gpu_idx = -1

            if gpu_idx >= 0 and gpu_idx < len(entry.get("gpus", [])):
                gpu_util = entry["gpus"][gpu_idx].get("gpu_util_percent", 0)
                container_usage[container]["samples"] += 1
                if gpu_util < WASTE_THRESHOLD:
                    container_usage[container]["low_util_samples"] += 1

    # Find wasted allocations
    wasted = []
    for container, usage in container_usage.items():
        if usage["samples"] < 3:
            continue
        waste_ratio = usage["low_util_samples"] / usage["samples"]
        if waste_ratio > 0.8:  # 80%+ of samples show low utilization
            wasted.append({
                "container": container,
                "user": usage["user"],
                "gpu_slot": usage["gpu_slot"],
                "waste_ratio": waste_ratio,
                "samples": usage["samples"]
            })

    return wasted


def log_event(event_type, user, message):
    """Log event to centralized event logger."""
    if EVENT_LOGGER.exists():
        try:
            subprocess.run(
                ["python3", str(EVENT_LOGGER), event_type, "--user", user, "--message", message],
                capture_output=True,
                timeout=5
            )
        except Exception:
            pass


def format_utilization_display(gpus, allocations):
    """Format utilization for terminal display."""
    lines = []
    lines.append("DS01 GPU Utilization Monitor")
    lines.append("=" * 70)
    lines.append(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    # Display each GPU
    for gpu in gpus:
        idx = gpu["index"]
        util = gpu["gpu_util_percent"]
        mem_util = gpu["mem_util_percent"]
        temp = gpu["temperature_c"]

        # Color coding (ANSI)
        if util >= 80:
            color = "\033[0;31m"  # Red
        elif util >= 50:
            color = "\033[1;33m"  # Yellow
        else:
            color = "\033[0;32m"  # Green
        reset = "\033[0m"

        # Find container using this GPU
        container_info = ""
        for alloc in allocations:
            slot = alloc.get("gpu_slot", "")
            if slot.startswith(f"{idx}.") or slot == str(idx):
                container_info = f" -> {alloc['user']}:{alloc['container']}"
                break

        lines.append(f"GPU {idx}: {gpu['name']}")
        lines.append(f"  Utilization: {color}{util:3d}%{reset} | Memory: {mem_util:3d}% | Temp: {temp}C{container_info}")

        # Simple bar
        bar_width = 40
        filled = int(util * bar_width / 100)
        bar = "█" * filled + "░" * (bar_width - filled)
        lines.append(f"  [{color}{bar}{reset}]")
        lines.append("")

    # Summary
    total_gpus = len(gpus)
    allocated = len(allocations)
    avg_util = sum(g["gpu_util_percent"] for g in gpus) / total_gpus if total_gpus > 0 else 0

    lines.append("-" * 70)
    lines.append(f"Total GPUs: {total_gpus} | Allocated: {allocated} | Avg Utilization: {avg_util:.1f}%")

    return "\n".join(lines)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="DS01 GPU Utilization Monitor")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--record", action="store_true", help="Record to history log (requires sudo)")
    parser.add_argument("--check-waste", action="store_true", help="Check for wasted allocations")
    args = parser.parse_args()

    # Get current data
    gpus = get_gpu_utilization()
    if gpus is None:
        print("Error: Could not get GPU utilization", file=sys.stderr)
        sys.exit(1)

    allocations = get_container_gpu_allocations()

    # Record if requested
    if args.record:
        record_utilization(gpus, allocations)
        return

    # Check for waste
    if args.check_waste:
        wasted = check_wasted_allocations()
        if wasted:
            print(f"Found {len(wasted)} potentially wasted GPU allocation(s):")
            for w in wasted:
                print(f"  - {w['container']} ({w['user']}): GPU {w['gpu_slot']} - {w['waste_ratio']*100:.0f}% idle")
                log_event("alert.gpu_waste", w["user"], f"GPU {w['gpu_slot']} underutilized in {w['container']}")
        else:
            print("No wasted GPU allocations detected.")
        return

    # Output
    if args.json:
        output = {
            "timestamp": now_utc_iso(),
            "gpus": gpus,
            "allocations": allocations
        }
        print(json.dumps(output, indent=2))
    else:
        print(format_utilization_display(gpus, allocations))


if __name__ == "__main__":
    main()
