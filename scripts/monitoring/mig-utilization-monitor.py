#!/usr/bin/env python3
"""
DS01 MIG Utilization Monitor
/opt/ds01-infra/scripts/monitoring/mig-utilization-monitor.py

Tracks actual MIG instance utilization (not just allocation) and shows per-instance usage.

Usage:
    mig-utilization-monitor.py                 # Current MIG utilization snapshot
    mig-utilization-monitor.py --json          # JSON output
    mig-utilization-monitor.py --record        # Record to history log (admin only)
    mig-utilization-monitor.py --check-waste   # Check for wasted MIG allocations
"""

import subprocess
import json
import os
import sys
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Configuration
INFRA_ROOT = Path("/opt/ds01-infra")
STATE_DIR = Path("/var/lib/ds01")
LOG_DIR = Path("/var/log/ds01")
UTILIZATION_LOG = LOG_DIR / "mig-utilization.jsonl"
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


def get_mig_instances():
    """Get list of MIG instances with their GPU parent and index."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "-L"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            return None

        instances = []
        current_gpu = None
        current_gpu_name = None

        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue

            # Match GPU line: "GPU 0: NVIDIA A100-PCIE-40GB (UUID: GPU-xxx)"
            gpu_match = re.match(r'GPU\s+(\d+):\s+(.+?)\s+\(UUID:\s+(GPU-[a-f0-9-]+)\)', line)
            if gpu_match:
                current_gpu = int(gpu_match.group(1))
                current_gpu_name = gpu_match.group(2)
                continue

            # Match MIG line: "  MIG 1g.10gb Device 0: (UUID: MIG-xxx)"
            mig_match = re.match(r'\s+MIG\s+(\S+)\s+Device\s+(\d+):\s+\(UUID:\s+(MIG-[a-f0-9-]+)\)', line)
            if mig_match and current_gpu is not None:
                profile = mig_match.group(1)
                device_id = int(mig_match.group(2))
                uuid = mig_match.group(3)

                instances.append({
                    "gpu": current_gpu,
                    "gpu_name": current_gpu_name,
                    "device_id": device_id,
                    "slot": f"{current_gpu}.{device_id}",
                    "uuid": uuid,
                    "profile": profile
                })

        return instances
    except Exception as e:
        print(f"Error getting MIG instances: {e}", file=sys.stderr)
        return None


def get_mig_utilization(mig_instances):
    """Get utilization for each MIG instance."""
    if not mig_instances:
        return []

    try:
        # Query nvidia-smi for MIG-specific utilization
        # Format: GPU index, MIG UUID, utilization, memory used, memory total
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-compute-apps=gpu_uuid,used_gpu_memory",
                "--format=csv,noheader,nounits"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        # Map running processes to MIG instances
        process_memory = {}
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if not line.strip():
                    continue
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 2:
                    uuid = parts[0]
                    mem = int(parts[1]) if parts[1] != '[N/A]' else 0
                    process_memory[uuid] = process_memory.get(uuid, 0) + mem

        # Get detailed utilization per GPU (MIG instances share parent GPU stats)
        result2 = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu",
                "--format=csv,noheader,nounits"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        gpu_stats = {}
        if result2.returncode == 0:
            for line in result2.stdout.strip().split('\n'):
                if not line.strip():
                    continue
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 4:
                    gpu_idx = int(parts[0])
                    gpu_stats[gpu_idx] = {
                        "gpu_util_percent": int(parts[1]) if parts[1] != '[N/A]' else 0,
                        "mem_util_percent": int(parts[2]) if parts[2] != '[N/A]' else 0,
                        "temperature_c": int(parts[3]) if parts[3] != '[N/A]' else 0
                    }

        # Enrich MIG instances with utilization data
        for instance in mig_instances:
            gpu_idx = instance["gpu"]
            uuid = instance["uuid"]

            # Get parent GPU stats
            if gpu_idx in gpu_stats:
                instance["gpu_util_percent"] = gpu_stats[gpu_idx]["gpu_util_percent"]
                instance["mem_util_percent"] = gpu_stats[gpu_idx]["mem_util_percent"]
                instance["temperature_c"] = gpu_stats[gpu_idx]["temperature_c"]
            else:
                instance["gpu_util_percent"] = 0
                instance["mem_util_percent"] = 0
                instance["temperature_c"] = 0

            # Add process memory if any
            instance["process_mem_mb"] = process_memory.get(uuid, 0)

        return mig_instances
    except Exception as e:
        print(f"Error getting MIG utilization: {e}", file=sys.stderr)
        return mig_instances


# Cache the gpu-state-reader module for performance
_gpu_state_module = None

def _get_gpu_state_module():
    """Get cached gpu-state-reader module (imported once, reused)."""
    global _gpu_state_module
    if _gpu_state_module is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            'gpu_state_reader',
            '/opt/ds01-infra/scripts/docker/gpu-state-reader.py'
        )
        _gpu_state_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_gpu_state_module)
    return _gpu_state_module


def get_container_mig_allocations():
    """Get which containers have MIG instances allocated.

    Uses gpu-state-reader.py as the SINGLE SOURCE OF TRUTH for allocations.
    Falls back to direct Docker query if gpu-state-reader fails.
    """
    try:
        # Primary: Use gpu-state-reader (single source of truth)
        gpu_state = _get_gpu_state_module()
        return gpu_state.get_mig_allocations()

    except Exception as e:
        # Fallback: Direct Docker query (for resilience)
        try:
            result = subprocess.run(
                [
                    DOCKER_BIN, "ps",
                    "--filter", "label=ds01.gpu.slots",
                    "--format", "{{.Names}}|{{.Label \"ds01.user\"}}|{{.Label \"ds01.gpu.slots\"}}|{{.Label \"ds01.gpu.uuids\"}}"
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
                    container = parts[0]
                    user = parts[1] if len(parts) > 1 else "unknown"
                    gpu_slots = [s.strip() for s in parts[2].split(',') if s.strip()]
                    gpu_uuids = [u.strip() for u in (parts[3] if len(parts) > 3 else "").split(',') if u.strip()]

                    for i, slot in enumerate(gpu_slots):
                        if '.' in slot:
                            allocations.append({
                                "container": container,
                                "user": user,
                                "mig_slot": slot,
                                "mig_uuid": gpu_uuids[i] if i < len(gpu_uuids) else ""
                            })
            return allocations
        except Exception as fallback_error:
            print(f"Error getting allocations (both methods failed): {e}, {fallback_error}", file=sys.stderr)
            return []


def can_write_log():
    """Check if we can write to the log file."""
    try:
        if UTILIZATION_LOG.exists():
            return os.access(UTILIZATION_LOG, os.W_OK)
        else:
            return os.access(LOG_DIR, os.W_OK)
    except Exception:
        return False


def record_utilization(mig_instances, allocations):
    """Record current utilization to log file."""
    if not can_write_log():
        print("Error: Cannot write to log file. Run with sudo for --record.", file=sys.stderr)
        print(f"  Log file: {UTILIZATION_LOG}", file=sys.stderr)
        sys.exit(1)

    LOG_DIR.mkdir(parents=True, exist_ok=True)

    entry = {
        "timestamp": now_utc_iso(),
        "mig_instances": [
            {
                "slot": m["slot"],
                "profile": m["profile"],
                "gpu_util_percent": m.get("gpu_util_percent", 0),
                "process_mem_mb": m.get("process_mem_mb", 0)
            }
            for m in mig_instances
        ],
        "allocations": [
            {"container": a["container"], "user": a["user"], "mig_slot": a["mig_slot"]}
            for a in allocations
        ]
    }

    with open(UTILIZATION_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")

    print(f"Recorded MIG utilization snapshot to {UTILIZATION_LOG}")


def check_wasted_allocations():
    """Check for MIG instances that have been underutilized for too long."""
    if not UTILIZATION_LOG.exists():
        print("No MIG utilization history available yet.")
        print(f"Run 'sudo mig-utilization-monitor.py --record' periodically to collect data.")
        return []

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

    if len(history) < 3:
        print(f"Not enough data points yet ({len(history)} found, need 3+).")
        print(f"Run 'sudo mig-utilization-monitor.py --record' every 5 minutes to collect data.")
        return []

    # Analyze each container's MIG usage
    container_usage = {}
    for entry in history:
        for alloc in entry.get("allocations", []):
            container = alloc.get("container", "")
            if not container:
                continue
            if container not in container_usage:
                container_usage[container] = {
                    "user": alloc.get("user", "unknown"),
                    "mig_slot": alloc.get("mig_slot", ""),
                    "samples": 0,
                    "low_util_samples": 0
                }

            # Check MIG utilization for this container's instance
            mig_slot = alloc.get("mig_slot", "")
            for mig in entry.get("mig_instances", []):
                if mig.get("slot") == mig_slot:
                    container_usage[container]["samples"] += 1
                    if mig.get("gpu_util_percent", 0) < WASTE_THRESHOLD:
                        container_usage[container]["low_util_samples"] += 1
                    break

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
                "mig_slot": usage["mig_slot"],
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


def format_utilization_display(mig_instances, allocations):
    """Format MIG utilization for terminal display."""
    lines = []
    lines.append("DS01 MIG Utilization Monitor")
    lines.append("=" * 70)
    lines.append(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    if not mig_instances:
        lines.append("No MIG instances found.")
        lines.append("")
        lines.append("MIG may not be enabled on this system, or no instances are configured.")
        lines.append("Check MIG status: nvidia-smi mig -lgi")
        return "\n".join(lines)

    # Group by parent GPU
    gpus = {}
    for instance in mig_instances:
        gpu = instance["gpu"]
        if gpu not in gpus:
            gpus[gpu] = {
                "name": instance["gpu_name"],
                "instances": []
            }
        gpus[gpu]["instances"].append(instance)

    # Create allocation lookup
    alloc_map = {a["mig_slot"]: a for a in allocations}

    # Display each GPU's MIG instances
    for gpu_idx in sorted(gpus.keys()):
        gpu_info = gpus[gpu_idx]
        lines.append(f"GPU {gpu_idx}: {gpu_info['name']}")
        lines.append("-" * 50)

        for instance in gpu_info["instances"]:
            slot = instance["slot"]
            profile = instance["profile"]
            util = instance.get("gpu_util_percent", 0)
            process_mem = instance.get("process_mem_mb", 0)

            # Color coding (ANSI)
            if util >= 80:
                color = "\033[0;31m"  # Red
            elif util >= 50:
                color = "\033[1;33m"  # Yellow
            elif util > 0:
                color = "\033[0;32m"  # Green
            else:
                color = "\033[0;90m"  # Gray (idle)
            reset = "\033[0m"

            # Find container using this MIG instance
            alloc = alloc_map.get(slot)
            if alloc:
                container_info = f" -> {alloc['user']}:{alloc['container']}"
                status = "ALLOCATED"
            else:
                container_info = ""
                status = "FREE"

            lines.append(f"  MIG {slot} [{profile}]: {color}{util:3d}%{reset} | Mem: {process_mem:5d}MB | {status}{container_info}")

            # Simple bar
            bar_width = 30
            filled = int(util * bar_width / 100)
            bar = "\u2588" * filled + "\u2591" * (bar_width - filled)
            lines.append(f"    [{color}{bar}{reset}]")

        lines.append("")

    # Summary
    total_instances = len(mig_instances)
    allocated = len(allocations)
    free = total_instances - allocated

    active_util = [m.get("gpu_util_percent", 0) for m in mig_instances if alloc_map.get(m["slot"])]
    avg_util = sum(active_util) / len(active_util) if active_util else 0

    lines.append("-" * 70)
    lines.append(f"Total MIG Instances: {total_instances} | Allocated: {allocated} | Free: {free} | Avg Util (allocated): {avg_util:.1f}%")

    return "\n".join(lines)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="DS01 MIG Utilization Monitor")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--record", action="store_true", help="Record to history log (requires sudo)")
    parser.add_argument("--check-waste", action="store_true", help="Check for wasted MIG allocations")
    args = parser.parse_args()

    # Get MIG instances
    mig_instances = get_mig_instances()
    if mig_instances is None:
        print("Error: Could not query MIG instances", file=sys.stderr)
        print("Tip: MIG may not be enabled. Check with: nvidia-smi mig -lgi", file=sys.stderr)
        sys.exit(1)

    # Get utilization data
    mig_instances = get_mig_utilization(mig_instances)

    # Get allocations
    allocations = get_container_mig_allocations()

    # Record if requested
    if args.record:
        record_utilization(mig_instances, allocations)
        return

    # Check for waste
    if args.check_waste:
        wasted = check_wasted_allocations()
        if wasted:
            print(f"Found {len(wasted)} potentially wasted MIG allocation(s):")
            for w in wasted:
                print(f"  - {w['container']} ({w['user']}): MIG {w['mig_slot']} - {w['waste_ratio']*100:.0f}% idle")
                log_event("alert.mig_waste", w["user"], f"MIG {w['mig_slot']} underutilized in {w['container']}")
        else:
            print("No wasted MIG allocations detected.")
        return

    # Output
    if args.json:
        output = {
            "timestamp": now_utc_iso(),
            "mig_instances": mig_instances,
            "allocations": allocations
        }
        print(json.dumps(output, indent=2))
    else:
        print(format_utilization_display(mig_instances, allocations))


if __name__ == "__main__":
    main()
