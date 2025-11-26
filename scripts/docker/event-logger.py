#!/usr/bin/env python3
"""
DS01 Event Logger - Append-Only Audit Trail

This is an APPEND-ONLY audit log for historical events and debugging.
It is NOT a source of truth - Docker labels are the single source of truth.

Design principle:
- If events.jsonl is lost, NO IMPACT on system operation
- System reconstructs current state from Docker labels only
- Events are for: audit, debugging, dashboards, alerts
- Events are NOT used for: state recovery, allocation decisions

Usage:
    event-logger.py log <event_type> [key=value ...]
    event-logger.py tail [N]
    event-logger.py search <pattern>
"""

import sys
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional, List

# Configuration
LOG_DIR = Path("/var/log/ds01")
EVENTS_FILE = LOG_DIR / "events.jsonl"
MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB before rotation


class EventLogger:
    def __init__(self, log_file: Path = EVENTS_FILE):
        self.log_file = log_file
        self.log_file.parent.mkdir(parents=True, exist_ok=True)

    def log(self, event_type: str, **kwargs) -> bool:
        """
        Log an event to the append-only log.

        Args:
            event_type: Type of event (e.g., container.created, gpu.allocated)
            **kwargs: Additional key-value pairs for the event

        Returns:
            True if logged successfully, False otherwise
        """
        event = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "event": event_type,
            **kwargs
        }

        try:
            # Check for rotation
            self._maybe_rotate()

            # Append to file
            with open(self.log_file, 'a') as f:
                f.write(json.dumps(event) + '\n')
            return True

        except Exception as e:
            # Event logging should NEVER break the system
            # Log to stderr and continue
            print(f"Warning: Event logging failed: {e}", file=sys.stderr)
            return False

    def _maybe_rotate(self):
        """Rotate log file if it exceeds max size."""
        if not self.log_file.exists():
            return

        try:
            if self.log_file.stat().st_size > MAX_FILE_SIZE:
                # Rotate to timestamped backup
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup = self.log_file.with_suffix(f".{timestamp}.jsonl")
                self.log_file.rename(backup)
        except Exception:
            pass  # Rotation is best-effort

    def tail(self, n: int = 20) -> List[Dict]:
        """Get last N events."""
        if not self.log_file.exists():
            return []

        events = []
        try:
            with open(self.log_file, 'r') as f:
                # Read all lines (could optimize for large files)
                lines = f.readlines()
                for line in lines[-n:]:
                    try:
                        events.append(json.loads(line.strip()))
                    except json.JSONDecodeError:
                        continue
        except Exception:
            pass

        return events

    def search(self, pattern: str, limit: int = 100) -> List[Dict]:
        """Search events matching regex pattern."""
        if not self.log_file.exists():
            return []

        events = []
        regex = re.compile(pattern, re.IGNORECASE)

        try:
            with open(self.log_file, 'r') as f:
                for line in f:
                    if regex.search(line):
                        try:
                            events.append(json.loads(line.strip()))
                            if len(events) >= limit:
                                break
                        except json.JSONDecodeError:
                            continue
        except Exception:
            pass

        return events

    def get_events_for_container(self, container: str) -> List[Dict]:
        """Get all events for a specific container."""
        return self.search(f'"container":\\s*"{re.escape(container)}"')

    def get_events_for_user(self, user: str) -> List[Dict]:
        """Get all events for a specific user."""
        return self.search(f'"user":\\s*"{re.escape(user)}"')


# Predefined event types
EVENT_TYPES = {
    # Container lifecycle
    "container.created": ["user", "container", "interface", "gpu"],
    "container.started": ["user", "container"],
    "container.stopped": ["user", "container", "reason"],
    "container.removed": ["user", "container", "gpu_released"],

    # GPU allocation
    "gpu.allocated": ["user", "container", "gpu", "priority"],
    "gpu.released": ["user", "container", "gpu", "reason"],
    "gpu.rejected": ["user", "container", "reason"],

    # System events
    "health.check": ["status", "checks_passed", "checks_failed"],
    "health.failed": ["check", "message"],
    "opa.bypass_attempt": ["user", "cgroup_requested"],

    # Bare metal detection
    "bare_metal.warning": ["user", "pids", "message"],

    # Admin actions
    "admin.cleanup": ["containers_removed", "gpus_freed"],
    "admin.config_change": ["field", "old_value", "new_value"],
}


def main():
    """CLI interface"""
    logger = EventLogger()

    if len(sys.argv) < 2:
        print("Usage: event-logger.py <command> [args]")
        print("\nCommands:")
        print("  log <event_type> [key=value ...]  - Log an event")
        print("  tail [N]                          - Show last N events (default: 20)")
        print("  search <pattern>                  - Search events by regex")
        print("  user <username>                   - Show events for user")
        print("  container <name>                  - Show events for container")
        print("  types                             - List predefined event types")
        print("\nExample:")
        print("  event-logger.py log container.created user=alice container=proj gpu=1.2")
        sys.exit(1)

    command = sys.argv[1]

    if command == "log":
        if len(sys.argv) < 3:
            print("Error: Event type required")
            sys.exit(1)

        event_type = sys.argv[2]
        kwargs = {}

        # Parse key=value arguments
        for arg in sys.argv[3:]:
            if '=' in arg:
                key, value = arg.split('=', 1)
                # Try to parse as JSON for complex values
                try:
                    kwargs[key] = json.loads(value)
                except json.JSONDecodeError:
                    kwargs[key] = value

        if logger.log(event_type, **kwargs):
            print(f"Logged: {event_type}")
        else:
            print("Warning: Event logging may have failed")
            sys.exit(1)

    elif command == "tail":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        events = logger.tail(n)

        if not events:
            print("No events found")
        else:
            for event in events:
                ts = event.get('ts', '?')
                evt = event.get('event', '?')
                # Remove ts and event for display
                details = {k: v for k, v in event.items() if k not in ('ts', 'event')}
                details_str = ' '.join(f"{k}={v}" for k, v in details.items())
                print(f"{ts} {evt} {details_str}")

    elif command == "search":
        if len(sys.argv) < 3:
            print("Error: Search pattern required")
            sys.exit(1)

        pattern = sys.argv[2]
        events = logger.search(pattern)

        if not events:
            print(f"No events matching '{pattern}'")
        else:
            for event in events:
                print(json.dumps(event))

    elif command == "user":
        if len(sys.argv) < 3:
            print("Error: Username required")
            sys.exit(1)

        user = sys.argv[2]
        events = logger.get_events_for_user(user)

        print(f"Events for user '{user}':")
        for event in events[-50:]:  # Last 50
            ts = event.get('ts', '?')
            evt = event.get('event', '?')
            container = event.get('container', '')
            print(f"  {ts} {evt} {container}")

    elif command == "container":
        if len(sys.argv) < 3:
            print("Error: Container name required")
            sys.exit(1)

        container = sys.argv[2]
        events = logger.get_events_for_container(container)

        print(f"Events for container '{container}':")
        for event in events:
            ts = event.get('ts', '?')
            evt = event.get('event', '?')
            details = {k: v for k, v in event.items() if k not in ('ts', 'event', 'container')}
            details_str = ' '.join(f"{k}={v}" for k, v in details.items())
            print(f"  {ts} {evt} {details_str}")

    elif command == "types":
        print("Predefined event types:\n")
        for event_type, fields in EVENT_TYPES.items():
            print(f"  {event_type}")
            print(f"    Fields: {', '.join(fields)}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
