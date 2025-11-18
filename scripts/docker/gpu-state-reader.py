#!/usr/bin/env python3
"""
GPU State Reader - Docker-First GPU Allocation State
Reads GPU allocation state directly from Docker containers (HostConfig + Labels)
This is the SINGLE SOURCE OF TRUTH for GPU allocations.
"""

import subprocess
import json
import re
import sys
from typing import Dict, List, Optional
from collections import defaultdict

class GPUStateReader:
    def __init__(self):
        self._mig_uuid_to_slot_cache = None

    def _get_mig_uuid_to_slot_mapping(self) -> Dict[str, str]:
        """
        Get mapping of MIG UUIDs to slot IDs (e.g., "1.0", "1.2")
        Caches result for performance.
        """
        if self._mig_uuid_to_slot_cache is not None:
            return self._mig_uuid_to_slot_cache

        mapping = {}

        try:
            # Run nvidia-smi to get MIG instances
            result = subprocess.run(
                ["nvidia-smi", "-L"],
                capture_output=True,
                text=True,
                check=True
            )

            # Parse output like:
            # GPU 1: NVIDIA A100-PCIE-40GB (UUID: GPU-xxx)
            #   MIG 1g.10gb Device 0: (UUID: MIG-abc-123)
            #   MIG 1g.10gb Device 1: (UUID: MIG-def-456)

            current_gpu = None
            for line in result.stdout.split('\n'):
                # Match GPU line: "GPU 1: ..."
                gpu_match = re.match(r'GPU (\d+):', line)
                if gpu_match:
                    current_gpu = gpu_match.group(1)
                    continue

                # Match MIG line: "  MIG 1g.10gb Device 0: (UUID: MIG-xxx)"
                mig_match = re.match(r'\s+MIG\s+\S+\s+Device\s+(\d+):\s+\(UUID:\s+(MIG-[a-f0-9-]+)\)', line)
                if mig_match and current_gpu is not None:
                    device_id = mig_match.group(1)
                    uuid = mig_match.group(2)
                    slot_id = f"{current_gpu}.{device_id}"
                    mapping[uuid] = slot_id

        except (subprocess.CalledProcessError, FileNotFoundError):
            # MIG not available or nvidia-smi not found
            pass

        self._mig_uuid_to_slot_cache = mapping
        return mapping

    def _get_container_inspect(self, container_name: str) -> Optional[Dict]:
        """Get docker inspect output for a container."""
        try:
            result = subprocess.run(
                ["docker", "inspect", container_name],
                capture_output=True,
                text=True,
                check=True
            )
            data = json.loads(result.stdout)
            return data[0] if data else None
        except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
            return None

    def _extract_gpu_from_container(self, container_data: Dict) -> Optional[Dict]:
        """
        Extract GPU assignment from Docker container inspect data.
        Returns dict with gpu_uuid, gpu_slot, etc. or None if no GPU.
        """
        try:
            # Get HostConfig.DeviceRequests
            device_requests = container_data.get('HostConfig', {}).get('DeviceRequests', [])

            if not device_requests:
                return None

            # Look for GPU device IDs in first DeviceRequest
            first_request = device_requests[0]
            device_ids = first_request.get('DeviceIDs', [])

            if not device_ids:
                # Might be using 'all' GPUs - not supported in DS01
                return None

            # Get the first (and usually only) GPU UUID
            gpu_uuid = device_ids[0]

            # Map UUID to slot ID (e.g., MIG-xxx -> "1.2")
            uuid_to_slot = self._get_mig_uuid_to_slot_mapping()
            gpu_slot = uuid_to_slot.get(gpu_uuid, gpu_uuid)  # Fallback to UUID if not found

            # Extract from Docker labels if available
            labels = container_data.get('Config', {}).get('Labels', {}) or {}
            allocated_at = labels.get('ds01.gpu.allocated_at', '')
            priority = labels.get('ds01.gpu.priority', '')
            user = labels.get('ds01.user') or labels.get('aime.mlc.USER', '')
            container_name = container_data.get('Name', '').lstrip('/')

            return {
                'container_name': container_name,
                'gpu_uuid': gpu_uuid,
                'gpu_slot': gpu_slot,
                'allocated_at': allocated_at,
                'priority': priority,
                'user': user
            }

        except Exception:
            return None

    def get_all_allocations(self) -> Dict:
        """
        Get all GPU allocations by reading Docker containers.
        Returns dict structured like old gpu-state.json for compatibility.
        """
        allocations = defaultdict(lambda: {
            'type': 'mig_instance',
            'containers': [],
            'users': defaultdict(int),
            'uuid': '',
            'profile': '',
            'docker_id': ''
        })

        # Get all DS01 containers (naming pattern: .*\._\.*)
        try:
            result = subprocess.run(
                ["docker", "ps", "-a", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                check=True
            )
            container_names = [line.strip() for line in result.stdout.split('\n') if '._.' in line]
        except subprocess.CalledProcessError:
            return dict(allocations)

        for container_name in container_names:
            if not container_name:
                continue

            container_data = self._get_container_inspect(container_name)
            if not container_data:
                continue

            gpu_info = self._extract_gpu_from_container(container_data)

            if not gpu_info:
                continue  # Container has no GPU

            gpu_slot = gpu_info['gpu_slot']
            user = gpu_info['user']

            # Add to allocations
            allocations[gpu_slot]['containers'].append(container_name)
            allocations[gpu_slot]['users'][user] += 1
            allocations[gpu_slot]['uuid'] = gpu_info['gpu_uuid']
            allocations[gpu_slot]['docker_id'] = gpu_info['gpu_uuid']

            # Try to determine profile from UUID or slot
            if 'MIG' in gpu_info['gpu_uuid']:
                allocations[gpu_slot]['profile'] = '1g.10gb'  # Default, could parse from nvidia-smi

        # Convert defaultdict to regular dict
        result = {}
        for k, v in allocations.items():
            v['users'] = dict(v['users'])
            result[k] = v

        return result

    def get_container_gpu(self, container_name: str) -> Optional[Dict]:
        """Get GPU assignment for a specific container."""
        container_data = self._get_container_inspect(container_name)
        if not container_data:
            return None
        return self._extract_gpu_from_container(container_data)

    def get_user_allocations(self, username: str) -> List[Dict]:
        """Get all GPU allocations for a specific user."""
        user_allocations = []

        # Get all DS01 containers
        try:
            result = subprocess.run(
                ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Status}}"],
                capture_output=True,
                text=True,
                check=True
            )
        except subprocess.CalledProcessError:
            return user_allocations

        for line in result.stdout.split('\n'):
            if not line or '._.' not in line:
                continue

            parts = line.split('\t')
            if len(parts) < 2:
                continue

            container_name = parts[0].strip()
            status = parts[1].strip()

            container_data = self._get_container_inspect(container_name)
            if not container_data:
                continue

            gpu_info = self._extract_gpu_from_container(container_data)

            if not gpu_info or gpu_info['user'] != username:
                continue

            user_allocations.append({
                'container': container_name,
                'gpu_slot': gpu_info['gpu_slot'],
                'gpu_uuid': gpu_info['gpu_uuid'],
                'status': status,
                'running': 'Up' in status
            })

        return user_allocations


def main():
    """CLI interface"""
    reader = GPUStateReader()

    if len(sys.argv) < 2:
        print("Usage: gpu-state-reader.py <command> [args]")
        print("\nCommands:")
        print("  all                    - Show all GPU allocations")
        print("  container <name>       - Show GPU for specific container")
        print("  user <username>        - Show user's GPU allocations")
        print("  json                   - Output as JSON")
        sys.exit(1)

    command = sys.argv[1]

    if command == "all":
        allocations = reader.get_all_allocations()
        for gpu_slot, data in sorted(allocations.items()):
            print(f"\nGPU/MIG {gpu_slot}:")
            print(f"  UUID: {data['uuid']}")
            print(f"  Containers: {', '.join(data['containers']) if data['containers'] else 'none'}")
            print(f"  Users: {dict(data['users'])}")

    elif command == "json":
        allocations = reader.get_all_allocations()
        print(json.dumps(allocations, indent=2, default=str))

    elif command == "container" and len(sys.argv) > 2:
        container_name = sys.argv[2]
        gpu_info = reader.get_container_gpu(container_name)
        if gpu_info:
            print(json.dumps(gpu_info, indent=2))
        else:
            print(f"Container {container_name} has no GPU or not found")
            sys.exit(1)

    elif command == "user" and len(sys.argv) > 2:
        username = sys.argv[2]
        allocations = reader.get_user_allocations(username)
        print(f"GPU allocations for {username}:")
        for alloc in allocations:
            status = "🟢" if alloc['running'] else "○"
            print(f"  {status} {alloc['container']}: GPU {alloc['gpu_slot']}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
