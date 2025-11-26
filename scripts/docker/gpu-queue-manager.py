#!/usr/bin/env python3
"""
DS01 GPU Queue Manager
/opt/ds01-infra/scripts/docker/gpu-queue-manager.py

Manages a queue for users waiting for GPU availability.
When GPU allocation fails, users can join the queue to be notified when GPUs become available.

Usage:
    gpu-queue-manager.py add <user> <container> <max_gpus>    # Add to queue
    gpu-queue-manager.py remove <user> [container]           # Remove from queue
    gpu-queue-manager.py list                                # Show queue
    gpu-queue-manager.py position <user>                     # Show user's position
    gpu-queue-manager.py process                             # Check queue and notify
    gpu-queue-manager.py clean                               # Remove old entries
"""

import json
import os
import sys
import fcntl
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
STATE_DIR = Path("/var/lib/ds01")
QUEUE_FILE = STATE_DIR / "gpu-queue.json"
ALERTS_DIR = STATE_DIR / "alerts"
INFRA_ROOT = Path("/opt/ds01-infra")
EVENT_LOGGER = INFRA_ROOT / "scripts/docker/event-logger.py"
GPU_AVAILABILITY_CHECKER = INFRA_ROOT / "scripts/docker/gpu-availability-checker.py"
RESOURCE_PARSER = INFRA_ROOT / "scripts/docker/get_resource_limits.py"

# Queue entry retention (hours)
QUEUE_RETENTION_HOURS = 24


def load_queue():
    """Load the queue file with locking."""
    try:
        if not QUEUE_FILE.exists():
            return []

        with open(QUEUE_FILE, 'r') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            data = json.load(f)
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            return data
    except PermissionError:
        print(f"Note: Cannot read queue file (permission denied)", file=sys.stderr)
        print(f"  The queue may be empty or requires admin access.", file=sys.stderr)
        return []
    except (json.JSONDecodeError, IOError):
        return []


def save_queue(queue):
    """Save the queue file with locking."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    with open(QUEUE_FILE, 'w') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        json.dump(queue, f, indent=2)
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)


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


def add_to_queue(user, container, max_gpus):
    """Add a user to the GPU queue."""
    queue = load_queue()

    # Check if user already in queue for this container
    for entry in queue:
        if entry["user"] == user and entry["container"] == container:
            print(f"Already in queue for container '{container}'")
            return False

    # Add new entry
    entry = {
        "user": user,
        "container": container,
        "max_gpus": max_gpus,
        "requested_at": datetime.now(tz=None).isoformat() + "Z",
        "notified": False,
        "notification_sent_at": None
    }

    queue.append(entry)
    save_queue(queue)

    position = len(queue)
    log_event("queue.joined", user, f"Joined GPU queue at position {position}")

    print(f"Added to GPU queue at position {position}")
    print(f"You'll be notified when a GPU becomes available.")
    print(f"Check your position: gpu-queue-manager.py position {user}")

    return True


def remove_from_queue(user, container=None):
    """Remove a user from the queue."""
    queue = load_queue()
    original_len = len(queue)

    if container:
        queue = [e for e in queue if not (e["user"] == user and e["container"] == container)]
    else:
        queue = [e for e in queue if e["user"] != user]

    removed = original_len - len(queue)

    if removed > 0:
        save_queue(queue)
        log_event("queue.left", user, f"Left GPU queue ({removed} entries removed)")
        print(f"Removed {removed} queue entry/entries for {user}")
    else:
        print(f"No queue entries found for {user}")

    return removed > 0


def list_queue():
    """List all queue entries."""
    queue = load_queue()

    if not queue:
        print("GPU queue is empty.")
        return

    print("GPU Request Queue")
    print("=" * 70)
    print(f"{'Pos':<4} {'User':<15} {'Container':<20} {'GPUs':<5} {'Waiting Since':<20}")
    print("-" * 70)

    for i, entry in enumerate(queue, 1):
        requested = entry.get("requested_at", "unknown")
        if requested != "unknown":
            try:
                dt = datetime.fromisoformat(requested.replace("Z", "+00:00").replace("+00:00", ""))
                wait_time = datetime.now(tz=None) - dt.replace(tzinfo=None)
                hours = int(wait_time.total_seconds() / 3600)
                mins = int((wait_time.total_seconds() % 3600) / 60)
                waiting = f"{hours}h {mins}m ago"
            except Exception:
                waiting = requested[:19]
        else:
            waiting = "unknown"

        notified = " (notified)" if entry.get("notified") else ""

        print(f"{i:<4} {entry['user']:<15} {entry['container']:<20} {entry.get('max_gpus', 1):<5} {waiting}{notified}")

    print("-" * 70)
    print(f"Total: {len(queue)} user(s) waiting")


def get_position(user):
    """Get user's position in queue."""
    queue = load_queue()

    positions = []
    for i, entry in enumerate(queue, 1):
        if entry["user"] == user:
            positions.append({
                "position": i,
                "container": entry["container"],
                "max_gpus": entry.get("max_gpus", 1),
                "notified": entry.get("notified", False)
            })

    if not positions:
        print(f"You are not in the GPU queue.")
        return None

    print(f"Queue positions for {user}:")
    for p in positions:
        status = " (notified - GPU available!)" if p["notified"] else ""
        print(f"  Position {p['position']}: {p['container']} ({p['max_gpus']} GPU(s)){status}")

    return positions


def check_gpu_available(user, max_gpus):
    """Check if a GPU is available for this user."""
    if not GPU_AVAILABILITY_CHECKER.exists():
        return False

    try:
        result = subprocess.run(
            ["python3", str(GPU_AVAILABILITY_CHECKER), user, "--count"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            available = int(result.stdout.strip())
            return available >= max_gpus
    except Exception:
        pass

    return False


def create_notification(user, container, position):
    """Create a notification for the user."""
    ALERTS_DIR.mkdir(parents=True, exist_ok=True)
    alerts_file = ALERTS_DIR / f"{user}.json"

    alert = {
        "type": "gpu_available",
        "message": f"GPU now available! You were #{position} in queue for '{container}'. Run: container-deploy {container}",
        "created_at": datetime.now(tz=None).isoformat() + "Z",
        "updated_at": datetime.now(tz=None).isoformat() + "Z"
    }

    # Load existing alerts
    alerts = []
    if alerts_file.exists():
        try:
            with open(alerts_file, 'r') as f:
                alerts = json.load(f)
        except (json.JSONDecodeError, IOError):
            alerts = []

    # Check if similar alert already exists
    for a in alerts:
        if a["type"] == "gpu_available" and container in a.get("message", ""):
            # Update existing alert
            a["updated_at"] = datetime.now(tz=None).isoformat() + "Z"
            break
    else:
        # Add new alert
        alerts.append(alert)

    with open(alerts_file, 'w') as f:
        json.dump(alerts, f, indent=2)

    alerts_file.chmod(0o644)


def process_queue():
    """Process the queue and notify users when GPUs become available."""
    queue = load_queue()

    if not queue:
        print("Queue is empty.")
        return

    modified = False
    notified_count = 0

    for i, entry in enumerate(queue):
        if entry.get("notified"):
            continue

        user = entry["user"]
        container = entry["container"]
        max_gpus = entry.get("max_gpus", 1)

        # Check if GPU is available for this user
        if check_gpu_available(user, max_gpus):
            entry["notified"] = True
            entry["notification_sent_at"] = datetime.now(tz=None).isoformat() + "Z"
            modified = True
            notified_count += 1

            # Create notification for user
            create_notification(user, container, i + 1)
            log_event("queue.notified", user, f"GPU available for {container}")

            print(f"Notified {user} - GPU available for '{container}'")

    if modified:
        save_queue(queue)

    print(f"Processed queue: {notified_count} user(s) notified")


def clean_queue():
    """Remove old queue entries."""
    queue = load_queue()
    original_len = len(queue)
    cutoff = datetime.now(tz=None) - timedelta(hours=QUEUE_RETENTION_HOURS)

    new_queue = []
    for entry in queue:
        # Keep if not notified OR notified recently
        if not entry.get("notified"):
            new_queue.append(entry)
        else:
            notified_at = entry.get("notification_sent_at", "")
            if notified_at:
                try:
                    dt = datetime.fromisoformat(notified_at.replace("Z", "+00:00").replace("+00:00", ""))
                    if dt.replace(tzinfo=None) > cutoff:
                        new_queue.append(entry)
                except Exception:
                    pass

    removed = original_len - len(new_queue)
    if removed > 0:
        save_queue(new_queue)
        print(f"Cleaned {removed} old queue entries")
    else:
        print("No old entries to clean")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "add":
        if len(sys.argv) < 5:
            print("Usage: gpu-queue-manager.py add <user> <container> <max_gpus>")
            sys.exit(1)
        add_to_queue(sys.argv[2], sys.argv[3], int(sys.argv[4]))

    elif command == "remove":
        if len(sys.argv) < 3:
            print("Usage: gpu-queue-manager.py remove <user> [container]")
            sys.exit(1)
        container = sys.argv[3] if len(sys.argv) > 3 else None
        remove_from_queue(sys.argv[2], container)

    elif command == "list":
        list_queue()

    elif command == "position":
        if len(sys.argv) < 3:
            print("Usage: gpu-queue-manager.py position <user>")
            sys.exit(1)
        get_position(sys.argv[2])

    elif command == "process":
        process_queue()

    elif command == "clean":
        clean_queue()

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
