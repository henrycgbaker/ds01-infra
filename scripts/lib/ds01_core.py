#!/usr/bin/env python3
"""
/opt/ds01-infra/scripts/lib/ds01_core.py
Core DS01 utilities for centralized, deduplicated infrastructure logic.

This module provides:
- Duration parsing (parse_duration, format_duration)
- Container utilities (get_user_containers, get_container_owner, get_container_gpu)
- ANSI color constants (Colors class)

Usage:
    from ds01_core import parse_duration, format_duration, Colors

    # Parse duration strings to seconds
    seconds = parse_duration("2h")  # -> 7200
    seconds = parse_duration("0.5h")  # -> 1800

    # Format seconds to human-readable
    text = format_duration(7200)  # -> "2h"

    # Colors for terminal output
    print(f"{Colors.GREEN}Success{Colors.NC}")
"""

import re
import subprocess
import json
from typing import Optional, List, Dict, Any


class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    NC = '\033[0m'  # No Color / Reset


def parse_duration(duration: str) -> int:
    """
    Parse a duration string to seconds.

    Supports:
    - Hours: "2h", "0.5h", "48h"
    - Days: "1d", "7d"
    - Weeks: "1w", "2w"
    - Minutes: "30m", "90m"
    - Seconds: "3600s", "60s"
    - Special values: "null", "None", "never", "indefinite" -> -1

    Args:
        duration: Duration string like "2h", "0.5d", "null"

    Returns:
        Duration in seconds, or -1 for no-limit values, or 0 if invalid

    Examples:
        >>> parse_duration("2h")
        7200
        >>> parse_duration("0.5h")
        1800
        >>> parse_duration("1d")
        86400
        >>> parse_duration("null")
        -1
    """
    if not duration:
        return -1  # Empty string = no limit

    duration = str(duration).strip().lower()

    # Special no-limit values
    if duration in ('null', 'none', 'never', 'indefinite', ''):
        return -1

    # Extract numeric value and unit
    match = re.match(r'^([0-9.]+)\s*([a-z]*)$', duration)
    if not match:
        return 0

    try:
        value = float(match.group(1))
    except ValueError:
        return 0

    unit = match.group(2) or 's'  # Default to seconds if no unit

    # Convert to seconds
    multipliers = {
        's': 1,
        'm': 60,
        'h': 3600,
        'd': 86400,
        'w': 604800,
    }

    multiplier = multipliers.get(unit, 0)
    if multiplier == 0:
        return 0

    return int(value * multiplier)


def format_duration(seconds: int) -> str:
    """
    Format seconds as human-readable duration.

    Args:
        seconds: Duration in seconds

    Returns:
        Human-readable string like "2h", "1d 3h", "45m"

    Examples:
        >>> format_duration(7200)
        '2h'
        >>> format_duration(90000)
        '1d 1h'
        >>> format_duration(1800)
        '30m'
    """
    if seconds < 0:
        return "unlimited"
    if seconds == 0:
        return "0s"

    parts = []

    days = seconds // 86400
    if days > 0:
        parts.append(f"{days}d")
        seconds %= 86400

    hours = seconds // 3600
    if hours > 0:
        parts.append(f"{hours}h")
        seconds %= 3600

    minutes = seconds // 60
    if minutes > 0 and not parts:  # Only show minutes if no larger units
        parts.append(f"{minutes}m")
        seconds %= 60

    if seconds > 0 and not parts:  # Only show seconds if nothing else
        parts.append(f"{seconds}s")

    return ' '.join(parts) if parts else '0s'


def get_container_owner(container_name: str) -> Optional[str]:
    """
    Extract owner username from container name.

    AIME naming convention: {project_name}._.{uid}

    Args:
        container_name: Container name like "my-project._.12345"

    Returns:
        Username resolved from UID, or None if not found

    Examples:
        >>> get_container_owner("thesis._.1000")  # Returns username for UID 1000
        'alice'
    """
    # Extract UID from AIME naming convention
    if '._.' not in container_name:
        return None

    try:
        uid = container_name.split('._.')[-1]
        result = subprocess.run(
            ['getent', 'passwd', uid],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0 and result.stdout:
            return result.stdout.split(':')[0]
    except (subprocess.TimeoutExpired, Exception):
        pass

    return None


def get_container_gpu(container_name: str) -> Optional[str]:
    """
    Get GPU allocation for a container from Docker labels.

    Args:
        container_name: Container name

    Returns:
        GPU device string (e.g., "0", "0:1" for MIG), or None if not allocated

    Examples:
        >>> get_container_gpu("thesis._.1000")
        '0:1'
    """
    try:
        result = subprocess.run(
            ['docker', 'inspect', '--format',
             '{{index .Config.Labels "ds01.gpu.allocated"}}', container_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            gpu = result.stdout.strip()
            if gpu and gpu != '<no value>':
                return gpu
    except (subprocess.TimeoutExpired, Exception):
        pass

    return None


def get_user_containers(username: str = None) -> List[Dict[str, Any]]:
    """
    List containers, optionally filtered by username.

    Args:
        username: Filter by this username (None for all)

    Returns:
        List of container dicts with keys: name, status, owner, gpu

    Examples:
        >>> get_user_containers("alice")
        [{'name': 'thesis._.1000', 'status': 'running', 'owner': 'alice', 'gpu': '0:1'}]
    """
    containers = []

    try:
        # Get all containers with AIME naming convention
        result = subprocess.run(
            ['docker', 'ps', '-a', '--format', '{{.Names}}\t{{.Status}}'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            return containers

        for line in result.stdout.strip().split('\n'):
            if not line or '._.' not in line:
                continue

            parts = line.split('\t')
            if len(parts) < 2:
                continue

            name, status = parts[0], parts[1]
            owner = get_container_owner(name)

            # Filter by username if specified
            if username and owner != username:
                continue

            containers.append({
                'name': name,
                'status': 'running' if status.startswith('Up') else 'stopped',
                'owner': owner,
                'gpu': get_container_gpu(name)
            })

    except (subprocess.TimeoutExpired, Exception):
        pass

    return containers


def run_docker_command(args: List[str], timeout: int = 30) -> subprocess.CompletedProcess:
    """
    Run a docker command with consistent error handling.

    Args:
        args: Command arguments (without 'docker' prefix)
        timeout: Timeout in seconds

    Returns:
        CompletedProcess result

    Raises:
        subprocess.TimeoutExpired: If command times out
        subprocess.CalledProcessError: If command fails
    """
    return subprocess.run(
        ['docker'] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True
    )


if __name__ == '__main__':
    # Self-test when run directly
    import sys

    print("DS01 Core Library - Self Test")
    print("=" * 50)

    # Test parse_duration
    print("\nparse_duration() tests:")
    test_cases = [
        ("2h", 7200),
        ("0.5h", 1800),
        ("1d", 86400),
        ("30m", 1800),
        ("1w", 604800),
        ("null", -1),
        ("never", -1),
        ("", -1),
    ]
    all_passed = True
    for input_val, expected in test_cases:
        result = parse_duration(input_val)
        status = "PASS" if result == expected else "FAIL"
        if result != expected:
            all_passed = False
        print(f"  parse_duration('{input_val}') = {result} (expected {expected}) [{status}]")

    # Test format_duration
    print("\nformat_duration() tests:")
    format_tests = [
        (7200, "2h"),
        (90000, "1d 1h"),
        (1800, "30m"),
        (0, "0s"),
        (-1, "unlimited"),
    ]
    for input_val, expected in format_tests:
        result = format_duration(input_val)
        status = "PASS" if result == expected else "FAIL"
        if result != expected:
            all_passed = False
        print(f"  format_duration({input_val}) = '{result}' (expected '{expected}') [{status}]")

    # Test Colors
    print("\nColors test:")
    print(f"  {Colors.RED}RED{Colors.NC} {Colors.GREEN}GREEN{Colors.NC} {Colors.YELLOW}YELLOW{Colors.NC} {Colors.BLUE}BLUE{Colors.NC}")

    print("\n" + "=" * 50)
    if all_passed:
        print("All tests passed!")
        sys.exit(0)
    else:
        print("Some tests failed!")
        sys.exit(1)
