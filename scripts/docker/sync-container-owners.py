#!/usr/bin/env python3
"""
/opt/ds01-infra/scripts/docker/sync-container-owners.py
DS01 Container Ownership Sync

Maintains a JSON file mapping container IDs to their owners for OPA authorization.
This script runs periodically (via cron or systemd timer) to keep the mapping current.

Output file: /var/lib/ds01/opa/container-owners.json

Usage:
    sudo python3 sync-container-owners.py           # Update ownership mapping
    sudo python3 sync-container-owners.py --once    # Single update (for cron)
    sudo python3 sync-container-owners.py --watch   # Continuous updates (for systemd)
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Any, Optional

# Configuration
OUTPUT_DIR = Path("/var/lib/ds01/opa")
OUTPUT_FILE = OUTPUT_DIR / "container-owners.json"
ADMIN_CACHE_FILE = OUTPUT_DIR / "admin-users.json"
RESOURCE_LIMITS = Path("/opt/ds01-infra/config/resource-limits.yaml")
WATCH_INTERVAL = 5  # seconds between updates in watch mode


def get_container_owner(labels: Dict[str, str]) -> Optional[str]:
    """
    Extract owner from container labels.

    Checks multiple label sources in priority order:
    1. ds01.user - Explicit DS01 owner label
    2. aime.mlc.USER - AIME MLC user label
    3. devcontainer.local_folder - Extract from path for dev containers

    Returns None if owner cannot be determined.
    """
    # Priority 1: Explicit DS01 label
    if "ds01.user" in labels:
        return labels["ds01.user"]

    # Priority 2: AIME MLC label
    if "aime.mlc.USER" in labels:
        return labels["aime.mlc.USER"]

    # Priority 3: Dev container - extract user from local_folder path
    # Format: /home/<username>/...
    if "devcontainer.local_folder" in labels:
        folder = labels["devcontainer.local_folder"]
        if folder.startswith("/home/"):
            parts = folder.split("/")
            if len(parts) >= 3:
                return parts[2]  # /home/<username>/...

    return None


def get_admin_users() -> list:
    """
    Get list of admin users from:
    1. resource-limits.yaml (groups.admin.members)
    2. Linux group 'ds01-admin'

    Returns combined list of admin usernames.
    """
    admins = set()

    # Source 1: resource-limits.yaml
    if RESOURCE_LIMITS.exists():
        try:
            import yaml
            with open(RESOURCE_LIMITS) as f:
                config = yaml.safe_load(f)

            admin_group = config.get("groups", {}).get("admin", {})
            members = admin_group.get("members", [])
            if members:
                admins.update(members)
        except Exception as e:
            print(f"Warning: Could not read resource-limits.yaml: {e}", file=sys.stderr)

    # Source 2: Linux group ds01-admin
    try:
        result = subprocess.run(
            ["getent", "group", "ds01-admin"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            # Format: ds01-admin:x:1234:user1,user2,user3
            parts = result.stdout.strip().split(":")
            if len(parts) >= 4 and parts[3]:
                admins.update(parts[3].split(","))
    except Exception:
        pass  # Group may not exist yet

    return sorted(list(admins))


def get_all_containers() -> list:
    """
    Get all containers with their labels using docker inspect.
    Returns list of container info dicts.
    """
    try:
        # Get all container IDs
        result = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.ID}}"],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Error listing containers: {result.stderr}", file=sys.stderr)
            return []

        container_ids = result.stdout.strip().split("\n")
        container_ids = [c for c in container_ids if c]  # Filter empty

        if not container_ids:
            return []

        # Inspect all containers at once
        result = subprocess.run(
            ["docker", "inspect"] + container_ids,
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Error inspecting containers: {result.stderr}", file=sys.stderr)
            return []

        return json.loads(result.stdout)

    except Exception as e:
        print(f"Error getting containers: {e}", file=sys.stderr)
        return []


def build_ownership_data() -> Dict[str, Any]:
    """
    Build the complete ownership data structure for OPA.

    Returns:
        {
            "containers": {
                "<container_id>": {
                    "owner": "<username>",
                    "name": "<container_name>",
                    "ds01_managed": true/false
                },
                ...
            },
            "admins": ["user1", "user2"],
            "service_users": ["ds01-dashboard"],
            "updated_at": "<timestamp>"
        }
    """
    containers = {}

    for container in get_all_containers():
        container_id = container.get("Id", "")[:12]  # Short ID
        full_id = container.get("Id", "")
        name = container.get("Name", "").lstrip("/")
        labels = container.get("Config", {}).get("Labels", {}) or {}

        owner = get_container_owner(labels)
        ds01_managed = labels.get("ds01.managed") == "true" or \
                       labels.get("aime.mlc.DS01_MANAGED") == "true"

        # Store both short and full ID for lookup
        entry = {
            "owner": owner,
            "name": name,
            "ds01_managed": ds01_managed
        }
        containers[container_id] = entry
        containers[full_id] = entry
        # Also store by name for convenience
        if name:
            containers[name] = entry

    return {
        "containers": containers,
        "admins": get_admin_users(),
        "service_users": ["ds01-dashboard"],  # Service accounts with full access
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }


def write_ownership_data(data: Dict[str, Any]) -> bool:
    """
    Atomically write ownership data to file.
    Uses write-to-temp-then-rename for atomicity.
    """
    try:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        # Write to temp file first
        temp_file = OUTPUT_FILE.with_suffix(".tmp")
        with open(temp_file, "w") as f:
            json.dump(data, f, indent=2)

        # Atomic rename
        temp_file.rename(OUTPUT_FILE)

        # Set permissions (readable by OPA process)
        os.chmod(OUTPUT_FILE, 0o644)

        return True
    except Exception as e:
        print(f"Error writing ownership data: {e}", file=sys.stderr)
        return False


def sync_once() -> bool:
    """Perform a single sync operation."""
    data = build_ownership_data()
    success = write_ownership_data(data)

    if success:
        container_count = len([k for k in data["containers"] if len(k) == 12])  # Count short IDs only
        admin_count = len(data["admins"])
        print(f"Synced {container_count} containers, {admin_count} admins")

    return success


def watch_mode(interval: int = None):
    """Continuously sync ownership data."""
    if interval is None:
        interval = WATCH_INTERVAL
    print(f"Starting watch mode (interval: {interval}s)")
    print(f"Output: {OUTPUT_FILE}")

    while True:
        sync_once()
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(
        description="Sync container ownership data for OPA authorization"
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Single sync (for cron jobs)"
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Continuous sync (for systemd service)"
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=WATCH_INTERVAL,
        help=f"Watch interval in seconds (default: {WATCH_INTERVAL})"
    )

    args = parser.parse_args()

    if args.watch:
        watch_mode(args.interval)
    else:
        success = sync_once()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
