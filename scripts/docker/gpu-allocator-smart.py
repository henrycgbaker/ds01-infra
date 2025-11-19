#!/usr/bin/env python3
"""
GPU Allocator Smart - Stateless GPU Allocation Manager
Uses Docker labels as single source of truth. No state files maintained.
Reads current state from Docker via gpu-state-reader.py.
"""

import sys
import json
import yaml
import subprocess
import importlib.util
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Tuple

# Import our helper modules (handle hyphenated filenames)
SCRIPT_DIR = Path(__file__).parent

# Dynamic import for gpu-state-reader.py
spec = importlib.util.spec_from_file_location('gpu_state_reader', str(SCRIPT_DIR / 'gpu-state-reader.py'))
gpu_state_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_state_module)
GPUStateReader = gpu_state_module.GPUStateReader

# Dynamic import for gpu-availability-checker.py
spec = importlib.util.spec_from_file_location('gpu_availability_checker', str(SCRIPT_DIR / 'gpu-availability-checker.py'))
gpu_avail_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_avail_module)
GPUAvailabilityChecker = gpu_avail_module.GPUAvailabilityChecker


class GPUAllocatorSmart:
    def __init__(self, config_path="/opt/ds01-infra/config/resource-limits.yaml"):
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.state_reader = GPUStateReader()
        self.availability_checker = GPUAvailabilityChecker()

        # Logging
        self.log_dir = Path("/var/log/ds01")
        self.log_file = self.log_dir / "gpu-allocations.log"
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def _load_config(self) -> dict:
        """Load YAML configuration"""
        if not self.config_path.exists():
            return {}

        with open(self.config_path) as f:
            return yaml.safe_load(f)

    def _get_user_limits(self, username: str) -> Dict:
        """Get user's resource limits from config"""
        # Check user_overrides first
        user_overrides = self.config.get('user_overrides', {}) or {}
        if username in user_overrides:
            return user_overrides[username]

        # Check groups
        groups = self.config.get('groups', {}) or {}
        for group_name, group_config in groups.items():
            if group_config and username in group_config.get('members', []):
                return group_config

        # Default group
        default_group = self.config.get('default_group', 'student')
        if default_group in groups:
            return groups[default_group]

        # Fallback defaults
        return self.config.get('defaults', {}) or {}

    def _get_user_priority(self, username: str) -> int:
        """Get user's allocation priority"""
        limits = self._get_user_limits(username)
        return limits.get('priority', 10)

    def _log_event(self, event_type: str, user: str, container: str,
                   gpu_id: Optional[str] = None, reason: str = "", priority: int = 0):
        """Append event to log file"""
        timestamp = datetime.now().isoformat()
        log_entry = f"{timestamp}|{event_type}|{user}|{container}|{gpu_id or 'N/A'}|priority={priority}|{reason}\n"

        with open(self.log_file, 'a') as f:
            f.write(log_entry)

    def allocate_gpu(self, username: str, container: str,
                     max_gpus: Optional[int] = None) -> Tuple[Optional[str], str]:
        """
        Allocate GPU for a container (stateless - reads from Docker).

        Args:
            username: User requesting GPU
            container: Container name (full tag: name._.userid)
            max_gpus: User's max GPU limit (from resource-limits.yaml)

        Returns:
            Tuple of (gpu_id, status_message)
            gpu_id: Slot ID (e.g., "1.2") if successful, None if failed
            status_message: "SUCCESS", "ALREADY_ALLOCATED", or error reason
        """
        # Check if container already has GPU (read from Docker)
        container_gpu = self.state_reader.get_container_gpu(container)
        if container_gpu:
            gpu_slot = container_gpu['gpu_slot']
            return gpu_slot, "ALREADY_ALLOCATED"

        # Get user's limits if not provided
        if max_gpus is None:
            limits = self._get_user_limits(username)
            max_gpus = limits.get('max_mig_instances', 1)

            # Handle unlimited
            if max_gpus is None or max_gpus == "unlimited":
                max_gpus = 999

        # Check user's current GPU count
        user_allocs = self.state_reader.get_user_allocations(username)
        current_count = len(user_allocs)

        if current_count >= max_gpus:
            reason = f"USER_AT_LIMIT ({current_count}/{max_gpus})"
            priority = self._get_user_priority(username)
            self._log_event("REJECTED", username, container, reason=reason, priority=priority)
            return None, reason

        # Get priority for allocation
        priority = self._get_user_priority(username)

        # Find available GPU
        suggestion = self.availability_checker.suggest_gpu_for_user(username, max_gpus, priority)

        if not suggestion['success']:
            reason = suggestion['error']
            self._log_event("REJECTED", username, container, reason=reason, priority=priority)
            return None, reason

        gpu_slot = suggestion['gpu_slot']
        gpu_uuid = suggestion['gpu_uuid']

        # Log allocation
        reason = f"ALLOCATED (user has {current_count + 1}/{max_gpus} GPUs)"
        self._log_event("ALLOCATED", username, container, gpu_slot, reason, priority)

        return gpu_slot, "SUCCESS"

    def get_docker_id(self, gpu_slot: str) -> str:
        """
        Get Docker-compatible device ID for a GPU slot.
        For MIG instances, returns UUID. For physical GPUs, returns slot ID.
        """
        # Query nvidia-smi for the UUID
        try:
            result = subprocess.run(
                ['nvidia-smi', '-L'],
                capture_output=True,
                text=True,
                check=True
            )

            # Parse output to find UUID for this slot
            import re
            current_gpu = None
            for line in result.stdout.split('\n'):
                gpu_match = re.match(r'GPU (\d+):', line)
                if gpu_match:
                    current_gpu = gpu_match.group(1)
                    continue

                mig_match = re.match(r'\s+MIG\s+\S+\s+Device\s+(\d+):\s+\(UUID:\s+(MIG-[a-f0-9-]+)\)', line)
                if mig_match and current_gpu is not None:
                    device_id = mig_match.group(1)
                    uuid = mig_match.group(2)
                    slot_id = f"{current_gpu}.{device_id}"

                    if slot_id == gpu_slot:
                        return uuid

        except (subprocess.CalledProcessError, Exception):
            pass

        # Fallback: return slot ID
        return gpu_slot

    def release_gpu(self, container: str) -> Tuple[Optional[str], str]:
        """
        Release GPU from container (stateless - just logs event).
        Actual release happens when container is removed from Docker.

        Args:
            container: Container name

        Returns:
            Tuple of (gpu_id, status_message)
        """
        # Read GPU assignment from Docker
        container_gpu = self.state_reader.get_container_gpu(container)

        if not container_gpu:
            return None, "NOT_ALLOCATED"

        gpu_slot = container_gpu['gpu_slot']
        username = container_gpu['user']

        # Log release
        reason = f"RELEASED (container removed/stopped)"
        self._log_event("RELEASED", username, container, gpu_slot, reason)

        return gpu_slot, "SUCCESS"

    def get_status(self) -> Dict:
        """
        Get current GPU allocation status (reads from Docker).

        Returns:
            Dict with GPU allocation information
        """
        allocations = self.state_reader.get_all_allocations()
        summary = self.availability_checker.get_allocation_summary()

        return {
            'total_gpus': summary['total_gpus'],
            'allocated': summary['allocated'],
            'available': summary['available'],
            'utilization_percent': summary['utilization_percent'],
            'allocations': allocations,
        }

    def get_user_gpu_count(self, username: str) -> int:
        """Count how many GPUs a user currently has allocated (reads from Docker)"""
        user_allocs = self.state_reader.get_user_allocations(username)
        return len(user_allocs)


def main():
    """CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(description='GPU Allocator Smart - Stateless GPU allocation')
    subparsers = parser.add_subparsers(dest='command', help='Command')

    # allocate command
    parser_allocate = subparsers.add_parser('allocate', help='Allocate GPU to container')
    parser_allocate.add_argument('user', help='Username')
    parser_allocate.add_argument('container', help='Container name (full tag)')
    parser_allocate.add_argument('max_gpus', type=int, help='Max GPUs for user')
    parser_allocate.add_argument('priority', type=int, help='User priority')

    # release command
    parser_release = subparsers.add_parser('release', help='Release GPU from container')
    parser_release.add_argument('container', help='Container name')

    # status command
    parser_status = subparsers.add_parser('status', help='Show GPU allocation status')

    # user-count command
    parser_count = subparsers.add_parser('user-count', help='Show GPU count for user')
    parser_count.add_argument('user', help='Username')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    allocator = GPUAllocatorSmart()

    if args.command == 'allocate':
        gpu_id, reason = allocator.allocate_gpu(args.user, args.container, args.max_gpus)

        if gpu_id and reason not in ["ALREADY_ALLOCATED"]:
            docker_id = allocator.get_docker_id(gpu_id)
            print(f"✓ Allocated GPU/MIG {gpu_id} to {args.container}")
            print(f"DOCKER_ID={docker_id}")  # For mlc-create-wrapper parsing
        elif reason == "ALREADY_ALLOCATED":
            docker_id = allocator.get_docker_id(gpu_id)
            print(f"⚠ Container {args.container} already has GPU/MIG {gpu_id} allocated")
            print(f"DOCKER_ID={docker_id}")
        else:
            print(f"✗ Allocation failed: {reason}")
            sys.exit(1)

    elif args.command == 'release':
        gpu_id, reason = allocator.release_gpu(args.container)
        if gpu_id:
            print(f"✓ Released GPU/MIG {gpu_id} from {args.container}")
        else:
            print(f"✗ No GPU allocated to {args.container}")

    elif args.command == 'status':
        status = allocator.get_status()
        print(f"\nGPU Status: {status['allocated']}/{status['total_gpus']} allocated ({status['utilization_percent']:.1f}% utilization)\n")

        for gpu_slot, info in sorted(status['allocations'].items()):
            containers = ', '.join(info['containers']) if info['containers'] else 'none'
            print(f"GPU/MIG {gpu_slot}:")
            print(f"  UUID: {info['uuid']}")
            print(f"  Containers: {containers}")
            print()

    elif args.command == 'user-count':
        count = allocator.get_user_gpu_count(args.user)
        print(count)


if __name__ == '__main__':
    main()
