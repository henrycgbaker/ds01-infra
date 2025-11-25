#!/usr/bin/env python3
"""
DS01 Bare Metal Process Detector

Detects processes running directly on the host (not in containers).
This helps identify users bypassing containerization.

What we detect:
- User processes (UID >= 1000) running outside containers
- Specifically GPU-using processes outside containers
- Long-running compute processes outside containers

What we exclude:
- System processes (UID < 1000)
- Kernel threads
- Short-lived processes (< 1 minute)
- Whitelisted processes (shells, editors, etc.)

Usage:
    detect-bare-metal.py [--json] [--warn-only] [--exclude-user USER]
"""

import os
import sys
import json
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Set, Optional

# Configuration
MIN_UID = 1000  # Minimum UID to consider (skip system users)
MIN_RUNTIME_SECONDS = 60  # Minimum runtime to report

# Whitelisted process names (common user utilities, not compute workloads)
WHITELIST = {
    # Shells and terminals
    'bash', 'sh', 'zsh', 'fish', 'tcsh', 'csh',
    'tmux', 'screen', 'sshd', 'ssh', 'ssh-agent',

    # Editors
    'vim', 'nvim', 'nano', 'emacs', 'code', 'code-server',

    # System utilities
    'systemd', 'dbus-daemon', 'pulseaudio', 'pipewire',
    'gnome-shell', 'gdm', 'lightdm', 'Xorg', 'Xwayland',

    # Development tools (short-lived)
    'git', 'docker', 'kubectl', 'make', 'cmake', 'gcc', 'g++',

    # DS01 tools
    'ds01-dashboard', 'container-list', 'container-stats',
    'mlc-list', 'mlc-open', 'mlc-create',
}

# Process names that indicate compute workloads
COMPUTE_INDICATORS = {
    'python', 'python3', 'python3.8', 'python3.9', 'python3.10', 'python3.11', 'python3.12',
    'jupyter', 'jupyter-lab', 'jupyter-notebook',
    'train', 'training', 'inference',
    'torch', 'tensorflow', 'keras',
    'ray', 'celery', 'dask',
    'spark-submit', 'pyspark',
}


class BareMetalDetector:
    def __init__(self):
        self.container_pids: Set[int] = set()
        self._load_container_pids()

    def _load_container_pids(self):
        """Get all PIDs running inside containers."""
        self.container_pids = set()

        try:
            # Get all container IDs
            result = subprocess.run(
                ['docker', 'ps', '-q'],
                capture_output=True,
                text=True,
                timeout=10
            )

            container_ids = [cid.strip() for cid in result.stdout.split('\n') if cid.strip()]

            # Get PIDs for each container
            for cid in container_ids:
                result = subprocess.run(
                    ['docker', 'top', cid, '-o', 'pid'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                for line in result.stdout.split('\n')[1:]:  # Skip header
                    pid_str = line.strip()
                    if pid_str.isdigit():
                        self.container_pids.add(int(pid_str))

        except Exception as e:
            print(f"Warning: Could not get container PIDs: {e}", file=sys.stderr)

    def _get_process_info(self, pid: int) -> Optional[Dict]:
        """Get information about a process."""
        try:
            # Read /proc/[pid]/stat
            stat_path = Path(f"/proc/{pid}/stat")
            if not stat_path.exists():
                return None

            with open(stat_path) as f:
                stat = f.read()

            # Parse stat - format: pid (comm) state ppid ...
            match = re.match(r'(\d+) \((.+)\) (\S) (\d+)', stat)
            if not match:
                return None

            # Read /proc/[pid]/status for UID
            status_path = Path(f"/proc/{pid}/status")
            uid = None
            with open(status_path) as f:
                for line in f:
                    if line.startswith('Uid:'):
                        uid = int(line.split()[1])
                        break

            if uid is None or uid < MIN_UID:
                return None

            # Get command line
            cmdline_path = Path(f"/proc/{pid}/cmdline")
            cmdline = ""
            with open(cmdline_path) as f:
                cmdline = f.read().replace('\x00', ' ').strip()

            # Get username
            try:
                import pwd
                username = pwd.getpwuid(uid).pw_name
            except (KeyError, ImportError):
                username = str(uid)

            # Get start time and calculate runtime
            # /proc/[pid]/stat field 22 is starttime in clock ticks
            stat_parts = stat.split()
            if len(stat_parts) >= 22:
                starttime_ticks = int(stat_parts[21])
                # Get system boot time and clock ticks per second
                with open('/proc/uptime') as f:
                    uptime_seconds = float(f.read().split()[0])
                clock_ticks = os.sysconf('SC_CLK_TCK')

                # Calculate runtime
                process_age = uptime_seconds - (starttime_ticks / clock_ticks)
            else:
                process_age = 0

            # Get CPU and memory usage
            cpu_percent = 0
            mem_mb = 0
            try:
                # Use ps for accurate CPU/memory
                result = subprocess.run(
                    ['ps', '-p', str(pid), '-o', '%cpu,%mem,rss', '--no-headers'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    parts = result.stdout.strip().split()
                    if len(parts) >= 3:
                        cpu_percent = float(parts[0])
                        mem_mb = int(parts[2]) / 1024  # RSS in KB to MB
            except Exception:
                pass

            return {
                'pid': pid,
                'name': match.group(2),
                'state': match.group(3),
                'ppid': int(match.group(4)),
                'uid': uid,
                'username': username,
                'cmdline': cmdline[:200],  # Truncate long command lines
                'runtime_seconds': int(process_age),
                'cpu_percent': cpu_percent,
                'mem_mb': round(mem_mb, 1)
            }

        except Exception:
            return None

    def _is_whitelisted(self, proc: Dict) -> bool:
        """Check if process is whitelisted."""
        name = proc['name'].lower()
        return name in WHITELIST

    def _is_compute_workload(self, proc: Dict) -> bool:
        """Check if process looks like a compute workload."""
        name = proc['name'].lower()
        cmdline = proc.get('cmdline', '').lower()

        # Check name
        for indicator in COMPUTE_INDICATORS:
            if indicator in name or indicator in cmdline:
                return True

        # High CPU or memory is suspicious
        if proc.get('cpu_percent', 0) > 50 or proc.get('mem_mb', 0) > 1000:
            return True

        return False

    def detect(self, exclude_users: List[str] = None) -> Dict:
        """
        Detect bare metal processes.

        Returns:
            Dict with 'warning', 'processes', 'summary'
        """
        exclude_users = exclude_users or []
        bare_metal_processes = []

        # Scan /proc for user processes
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit():
                continue

            pid = int(entry.name)

            # Skip container processes
            if pid in self.container_pids:
                continue

            proc = self._get_process_info(pid)
            if proc is None:
                continue

            # Skip excluded users
            if proc['username'] in exclude_users:
                continue

            # Skip whitelisted processes
            if self._is_whitelisted(proc):
                continue

            # Skip short-lived processes
            if proc['runtime_seconds'] < MIN_RUNTIME_SECONDS:
                continue

            # Flag compute workloads
            proc['is_compute'] = self._is_compute_workload(proc)

            bare_metal_processes.append(proc)

        # Group by user
        by_user = {}
        for proc in bare_metal_processes:
            user = proc['username']
            if user not in by_user:
                by_user[user] = []
            by_user[user].append(proc)

        # Build result
        result = {
            'warning': len(bare_metal_processes) > 0,
            'total_count': len(bare_metal_processes),
            'compute_count': sum(1 for p in bare_metal_processes if p.get('is_compute')),
            'users_affected': list(by_user.keys()),
            'by_user': by_user,
            'processes': bare_metal_processes,
            'checked_at': datetime.utcnow().isoformat() + "Z"
        }

        return result


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Detect bare metal processes')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--warn-only', action='store_true',
                        help='Only show warnings, not process list')
    parser.add_argument('--exclude-user', action='append', dest='exclude_users',
                        default=[], help='Exclude user from detection')

    args = parser.parse_args()

    detector = BareMetalDetector()
    result = detector.detect(exclude_users=args.exclude_users)

    if args.json:
        print(json.dumps(result, indent=2))
        return

    if not result['warning']:
        print("No bare metal processes detected")
        return

    print(f"\n{'='*70}")
    print(f"BARE METAL PROCESS WARNING")
    print(f"{'='*70}")
    print(f"\nFound {result['total_count']} process(es) running outside containers")
    print(f"Compute workloads: {result['compute_count']}")
    print(f"Users affected: {', '.join(result['users_affected'])}")

    if not args.warn_only:
        print(f"\n{'─'*70}")
        print(f"{'PID':>8}  {'USER':<12}  {'CPU%':>5}  {'MEM':>8}  {'RUNTIME':>10}  COMMAND")
        print(f"{'─'*70}")

        for proc in sorted(result['processes'],
                          key=lambda p: p.get('cpu_percent', 0),
                          reverse=True)[:20]:

            # Format runtime
            runtime = proc['runtime_seconds']
            if runtime > 3600:
                runtime_str = f"{runtime // 3600}h {(runtime % 3600) // 60}m"
            else:
                runtime_str = f"{runtime // 60}m"

            # Truncate command
            cmd = proc.get('cmdline', proc['name'])[:40]

            # Flag compute workloads
            flag = "*" if proc.get('is_compute') else " "

            print(f"{proc['pid']:>8}  {proc['username']:<12}  "
                  f"{proc.get('cpu_percent', 0):>5.1f}  "
                  f"{proc.get('mem_mb', 0):>6.1f}MB  "
                  f"{runtime_str:>10}  {flag}{cmd}")

        if result['total_count'] > 20:
            print(f"\n... and {result['total_count'] - 20} more")

    print(f"\n{'─'*70}")
    print("Please run compute workloads inside containers for proper resource isolation.")
    print("Use 'container deploy <name>' to create a container.")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    main()
