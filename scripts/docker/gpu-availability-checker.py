#!/usr/bin/env python3
"""
GPU Availability Checker
Calculates available GPUs by comparing nvidia-smi output with Docker allocations.
Uses gpu-state-reader.py as single source of truth for current allocations.
"""

import subprocess
import json
import re
import sys
import importlib.util
from typing import Dict, List, Set
from pathlib import Path

# Dynamic import for gpu-state-reader.py (hyphenated filename)
SCRIPT_DIR = Path(__file__).parent
spec = importlib.util.spec_from_file_location('gpu_state_reader', str(SCRIPT_DIR / 'gpu-state-reader.py'))
gpu_state_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_state_module)
GPUStateReader = gpu_state_module.GPUStateReader


class GPUAvailabilityChecker:
    def __init__(self):
        self.state_reader = GPUStateReader()

    def _get_all_mig_instances(self) -> Dict[str, Dict]:
        """
        Get all available MIG instances from nvidia-smi.
        Returns dict: {"1.0": {...}, "1.2": {...}, etc.}
        """
        mig_instances = {}

        try:
            result = subprocess.run(
                ["nvidia-smi", "-L"],
                capture_output=True,
                text=True,
                check=True
            )

            current_gpu = None
            for line in result.stdout.split('\n'):
                # Match GPU line
                gpu_match = re.match(r'GPU (\d+):', line)
                if gpu_match:
                    current_gpu = gpu_match.group(1)
                    continue

                # Match MIG line: "  MIG 1g.10gb Device 0: (UUID: MIG-xxx)"
                mig_match = re.match(r'\s+MIG\s+(\S+)\s+Device\s+(\d+):\s+\(UUID:\s+(MIG-[a-f0-9-]+)\)', line)
                if mig_match and current_gpu is not None:
                    profile = mig_match.group(1)
                    device_id = mig_match.group(2)
                    uuid = mig_match.group(3)
                    slot_id = f"{current_gpu}.{device_id}"

                    mig_instances[slot_id] = {
                        'profile': profile,
                        'uuid': uuid,
                        'physical_gpu': current_gpu,
                        'device_id': device_id
                    }

        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

        return mig_instances

    def _get_physical_gpus(self) -> Dict[str, Dict]:
        """
        Get all physical GPUs from nvidia-smi.
        Returns dict: {"0": {"uuid": "GPU-xxx", ...}, "1": {...}, etc.}
        """
        physical_gpus = {}

        try:
            result = subprocess.run(
                ["nvidia-smi", "-L"],
                capture_output=True,
                text=True,
                check=True
            )

            for line in result.stdout.split('\n'):
                # Match GPU line: "GPU 0: NVIDIA A100 (UUID: GPU-xxx)"
                gpu_match = re.match(r'GPU (\d+):\s+([^(]+)\s+\(UUID:\s+(GPU-[a-f0-9-]+)\)', line)
                if gpu_match:
                    gpu_id = gpu_match.group(1)
                    gpu_name = gpu_match.group(2).strip()
                    gpu_uuid = gpu_match.group(3)
                    physical_gpus[gpu_id] = {
                        'id': gpu_id,
                        'name': gpu_name,
                        'uuid': gpu_uuid
                    }

        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

        return physical_gpus

    def _get_full_gpus_available(self) -> Dict[str, Dict]:
        """
        Get available full GPUs in priority order:
        1. Real unpartitioned GPUs (no MIG instances defined on them)
        2. Virtual full GPUs (all MIG slots free on a physical GPU)
        """
        all_migs = self._get_all_mig_instances()
        allocations = self.state_reader.get_all_allocations()
        all_physical_gpus = self._get_physical_gpus()

        full_available = {}

        for gpu_id, gpu_info in all_physical_gpus.items():
            mig_slots_on_gpu = [s for s in all_migs if all_migs[s]['physical_gpu'] == gpu_id]

            if not mig_slots_on_gpu:
                # Real full GPU - no MIG partitions exist on this GPU
                if gpu_id not in allocations:
                    full_available[gpu_id] = {
                        'slot': gpu_id,
                        'uuid': gpu_info['uuid'],
                        'type': 'full',
                        'mig_slots': [],
                        'profile': 'full-gpu',
                        'physical_gpu': gpu_id,
                        'status': 'available'
                    }
            else:
                # Check if ALL MIG slots on this GPU are free
                all_free = all(slot not in allocations for slot in mig_slots_on_gpu)
                if all_free:
                    full_available[gpu_id] = {
                        'slot': gpu_id,
                        'uuid': gpu_info['uuid'],
                        'type': 'virtual_full',
                        'mig_slots': mig_slots_on_gpu,
                        'profile': 'virtual-full-gpu',
                        'physical_gpu': gpu_id,
                        'status': 'available'
                    }

        return full_available

    def get_available_gpus(self) -> Dict[str, Dict]:
        """
        Get all available (unallocated) GPUs.
        Returns dict of GPU slots that are free.
        """
        # Get all MIG instances from hardware
        all_migs = self._get_all_mig_instances()

        # Get current allocations from Docker
        allocations = self.state_reader.get_all_allocations()

        # Find available = all - allocated
        available = {}
        for slot_id, mig_info in all_migs.items():
            if slot_id not in allocations:
                available[slot_id] = {
                    'slot': slot_id,
                    'uuid': mig_info['uuid'],
                    'profile': mig_info['profile'],
                    'physical_gpu': mig_info['physical_gpu'],
                    'status': 'available'
                }

        return available

    def get_user_available_gpus(self, username: str, max_gpus: int = None) -> Dict:
        """
        Get available GPUs for a specific user, considering their current allocations and limits.

        Args:
            username: Username to check
            max_gpus: Maximum GPUs user can have (from resource limits)

        Returns:
            Dict with 'available' GPUs and 'user_current' count
        """
        # Get user's current allocations
        user_allocs = self.state_reader.get_user_allocations(username)
        user_current_count = len(user_allocs)

        # Get globally available GPUs
        available_gpus = self.get_available_gpus()

        # Check if user can allocate more
        can_allocate = True
        reason = ""

        if max_gpus is not None and user_current_count >= max_gpus:
            can_allocate = False
            reason = f"User already has {user_current_count}/{max_gpus} GPUs allocated"

        return {
            'available_gpus': available_gpus,
            'user_current_count': user_current_count,
            'user_max_gpus': max_gpus,
            'can_allocate': can_allocate,
            'reason': reason if not can_allocate else 'OK',
            'user_allocations': user_allocs
        }

    def _is_full_gpu(self, gpu_slot: str) -> bool:
        """Check if a GPU slot is a full GPU (not MIG instance)"""
        # Full GPU slots don't have a decimal (e.g., "0", "1")
        # MIG slots have decimal (e.g., "1.0", "1.2")
        return '.' not in str(gpu_slot)

    def suggest_gpu_for_user(self, username: str, max_gpus: int = None, priority: int = 10,
                             require_full_gpu: bool = False, allow_full_gpu: bool = False,
                             exclude_slots: list = None) -> Dict:
        """
        Suggest which GPU to allocate for a user.
        Uses least-allocated strategy with full GPU access control.

        Args:
            username: User requesting GPU
            max_gpus: User's max GPU limit
            priority: User's allocation priority (not currently used)
            require_full_gpu: If True, only suggest full GPUs (not MIG)
            allow_full_gpu: If False, filter out full GPUs from suggestions
            exclude_slots: List of slot IDs to exclude (for multi-GPU allocation)

        Returns:
            Dict with 'gpu_slot', 'gpu_uuid', or error if none available
            For full GPUs, also includes 'mig_slots' list if it's a virtual full GPU
        """
        if exclude_slots is None:
            exclude_slots = []

        availability = self.get_user_available_gpus(username, max_gpus)

        if not availability['can_allocate']:
            return {
                'success': False,
                'error': availability['reason'],
                'user_current': availability['user_current_count'],
                'user_max': max_gpus
            }

        # If requiring full GPU, check full GPU availability first
        if require_full_gpu:
            full_gpus = self._get_full_gpus_available()

            # Exclude already-reserved slots
            for slot in exclude_slots:
                full_gpus.pop(slot, None)
                # Also exclude virtual full GPUs whose MIG slots overlap
                for gpu_id, gpu_info in list(full_gpus.items()):
                    if slot in gpu_info.get('mig_slots', []):
                        full_gpus.pop(gpu_id, None)

            if full_gpus:
                # Prefer real full GPUs over virtual full GPUs
                sorted_gpus = sorted(
                    full_gpus.items(),
                    key=lambda x: (0 if x[1]['type'] == 'full' else 1, x[0])
                )
                gpu_id, gpu_info = sorted_gpus[0]
                return {
                    'success': True,
                    'gpu_slot': gpu_id,
                    'gpu_uuid': gpu_info['uuid'],
                    'profile': gpu_info['profile'],
                    'physical_gpu': gpu_info['physical_gpu'],
                    'type': gpu_info['type'],
                    'mig_slots': gpu_info.get('mig_slots', [])
                }
            else:
                return {
                    'success': False,
                    'error': 'No full GPUs available (all GPUs have allocated MIG instances)',
                    'user_current': availability['user_current_count']
                }

        available = availability['available_gpus']

        # Exclude already-reserved slots (for multi-GPU allocation)
        for slot in exclude_slots:
            available.pop(slot, None)

        if not available:
            return {
                'success': False,
                'error': 'No GPUs available (all allocated)',
                'user_current': availability['user_current_count']
            }

        # Filter GPUs based on full GPU permissions
        filtered_available = {}
        for slot, info in available.items():
            is_full = self._is_full_gpu(slot)

            # If user is not allowed full GPUs, exclude them
            if not allow_full_gpu and is_full:
                continue

            filtered_available[slot] = info

        if not filtered_available:
            if not allow_full_gpu:
                return {
                    'success': False,
                    'error': 'No MIG instances available (only full GPUs free, user not permitted)',
                    'user_current': availability['user_current_count']
                }
            else:
                return {
                    'success': False,
                    'error': 'No GPUs available matching criteria',
                    'user_current': availability['user_current_count']
                }

        # Use least-allocated strategy - prefer MIG instances if available and allowed
        # Sort: MIG instances first (they have '.'), then by slot ID
        def sort_key(slot):
            is_mig = '.' in slot
            # MIG instances get priority (sort first) unless require_full_gpu
            if require_full_gpu:
                return (is_mig, slot)  # Full GPUs first
            else:
                return (not is_mig, slot)  # MIG instances first

        sorted_slots = sorted(filtered_available.keys(), key=sort_key)
        gpu_slot = sorted_slots[0]
        gpu_info = filtered_available[gpu_slot]

        return {
            'success': True,
            'gpu_slot': gpu_slot,
            'gpu_uuid': gpu_info['uuid'],
            'profile': gpu_info['profile'],
            'physical_gpu': gpu_info['physical_gpu']
        }

    def get_allocation_summary(self) -> Dict:
        """Get summary of GPU allocation status."""
        all_migs = self._get_all_mig_instances()
        allocations = self.state_reader.get_all_allocations()

        total = len(all_migs)
        allocated = len(allocations)
        available = total - allocated

        return {
            'total_gpus': total,
            'allocated': allocated,
            'available': available,
            'utilization_percent': (allocated / total * 100) if total > 0 else 0,
            'all_slots': list(all_migs.keys()),
            'allocated_slots': list(allocations.keys()),
            'available_slots': list(self.get_available_gpus().keys())
        }


def main():
    """CLI interface"""
    checker = GPUAvailabilityChecker()

    if len(sys.argv) < 2:
        print("Usage: gpu-availability-checker.py <command> [args]")
        print("\nCommands:")
        print("  available                          - Show available GPUs")
        print("  summary                            - Show allocation summary")
        print("  user-available <user> [max_gpus]  - Check what's available for user")
        print("  suggest <user> [max_gpus]          - Suggest GPU for user")
        sys.exit(1)

    command = sys.argv[1]

    if command == "available":
        available = checker.get_available_gpus()
        print(f"\n{len(available)} GPU(s) available:\n")
        for slot, info in sorted(available.items()):
            print(f"  MIG {slot}: {info['profile']} (UUID: {info['uuid']})")

    elif command == "summary":
        summary = checker.get_allocation_summary()
        print(f"\nGPU Allocation Summary:")
        print(f"  Total GPUs:     {summary['total_gpus']}")
        print(f"  Allocated:      {summary['allocated']}")
        print(f"  Available:      {summary['available']}")
        print(f"  Utilization:    {summary['utilization_percent']:.1f}%")

    elif command == "user-available" and len(sys.argv) > 2:
        username = sys.argv[2]
        max_gpus = int(sys.argv[3]) if len(sys.argv) > 3 else None

        result = checker.get_user_available_gpus(username, max_gpus)

        print(f"\nAvailability for {username}:")
        print(f"  Current allocations: {result['user_current_count']}")
        if result['user_max_gpus']:
            print(f"  Maximum allowed:     {result['user_max_gpus']}")
        print(f"  Can allocate more:   {'Yes' if result['can_allocate'] else 'No'}")
        if not result['can_allocate']:
            print(f"  Reason: {result['reason']}")
        print(f"\n  Available GPUs: {len(result['available_gpus'])}")

    elif command == "check-user" and len(sys.argv) > 2:
        # Simple check for container-start script
        username = sys.argv[2]
        max_gpus = int(sys.argv[3]) if len(sys.argv) > 3 else None

        result = checker.get_user_available_gpus(username, max_gpus)

        if result['can_allocate']:
            print("CAN_ALLOCATE")
        else:
            print(f"CANNOT_ALLOCATE: {result['reason']}")

    elif command == "suggest" and len(sys.argv) > 2:
        username = sys.argv[2]
        max_gpus = int(sys.argv[3]) if len(sys.argv) > 3 else None

        result = checker.suggest_gpu_for_user(username, max_gpus)

        if result['success']:
            print(f"\n✓ Suggest GPU {result['gpu_slot']} for {username}")
            print(f"  UUID: {result['gpu_uuid']}")
            print(f"  Profile: {result['profile']}")
        else:
            print(f"\n✗ Cannot allocate GPU for {username}")
            print(f"  Reason: {result['error']}")
            if 'user_current' in result:
                print(f"  Current: {result['user_current']}", end="")
                if 'user_max' in result and result['user_max']:
                    print(f"/{result['user_max']}")
                else:
                    print()

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
