#!/usr/bin/env python3
"""
GPU State Reader - Docker-First GPU Allocation State
Reads GPU allocation state directly from Docker containers (HostConfig + Labels)
This is the SINGLE SOURCE OF TRUTH for GPU allocations.

Updated for DS01 Layered Architecture:
- Tracks ALL containers in ds01.slice (not just AIME naming convention)
- Supports 4 interfaces: Orchestration, Atomic, Docker, Other
- Interface detection via ds01.interface label and naming patterns
"""

import subprocess
import json
import re
import sys
from typing import Dict, List, Optional
from collections import defaultdict

# Real Docker binary - bypasses the wrapper at /usr/local/bin/docker
# The wrapper filters 'docker ps' for non-admin users, which would cause
# the GPU state reader to miss allocations from other users, leading to
# incorrect "available" GPU status and double-allocations.
DOCKER_BIN = "/usr/bin/docker"


# Interface detection constants
INTERFACE_ORCHESTRATION = "orchestration"
INTERFACE_ATOMIC = "atomic"
INTERFACE_DOCKER = "docker"
INTERFACE_OTHER = "other"


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
                [DOCKER_BIN, "inspect", container_name],
                capture_output=True,
                text=True,
                check=True
            )
            data = json.loads(result.stdout)
            return data[0] if data else None
        except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
            return None

    def _detect_interface(self, container_data: Dict) -> str:
        """
        Detect which interface created this container.

        Detection order:
        1. ds01.interface label (explicit)
        2. AIME naming convention (name._.uid) -> Atomic or Orchestration
        3. Tool-specific labels/naming -> Other
        4. Default -> Docker

        Returns: INTERFACE_ORCHESTRATION, INTERFACE_ATOMIC, INTERFACE_DOCKER, or INTERFACE_OTHER
        """
        labels = container_data.get('Config', {}).get('Labels', {}) or {}
        name = container_data.get('Name', '').lstrip('/')

        # 1. Explicit ds01.interface label
        interface_label = labels.get('ds01.interface', '')
        if interface_label:
            if interface_label == 'orchestration':
                return INTERFACE_ORCHESTRATION
            elif interface_label == 'atomic':
                return INTERFACE_ATOMIC
            # Other explicit values fall through

        # 2. DS01 managed label (from mlc-create-wrapper)
        if labels.get('ds01.managed') == 'true':
            # Has DS01 label but no explicit interface -> atomic (backward compat)
            return INTERFACE_ATOMIC

        # 3. AIME naming convention (name._.uid)
        if '._.' in name:
            return INTERFACE_ATOMIC

        # 4. Tool-specific detection for "Other" interface
        # VS Code Dev Containers
        if (name.startswith('vscode-') or
            'devcontainer' in labels or
            labels.get('devcontainer.metadata')):
            return INTERFACE_OTHER

        # Docker Compose
        if (labels.get('com.docker.compose.project') or
            labels.get('com.docker.compose.service') or
            '_' in name and name.endswith(('_1', '_2', '_3'))):
            return INTERFACE_OTHER

        # JupyterHub
        if (name.startswith('jupyterhub-') or
            name.startswith('jupyter-') or
            labels.get('hub.jupyter.org/username')):
            return INTERFACE_OTHER

        # 5. Default: Docker direct
        return INTERFACE_DOCKER

    def _extract_user_from_cgroup(self, cgroup_parent: str) -> Optional[str]:
        """
        Extract (sanitized) username from cgroup path.
        Example: ds01-student-alice.slice -> alice
        Example: ds01-student-h-baker-at-hertie-school-lan.slice -> h-baker-at-hertie-school-lan

        Note: Returns the sanitized form of the username. For original username,
        use Docker labels (ds01.user or aime.mlc.USER) which preserve the original.
        """
        if not cgroup_parent:
            return None

        # Pattern: ds01-{group}-{sanitized_username}.slice
        # Sanitized usernames can contain hyphens, so use .+ for the username part
        match = re.match(r'ds01-(\w+)-(.+)\.slice', cgroup_parent)
        if match:
            return match.group(2)  # Return sanitized username
        return None

    def _extract_gpu_from_container(self, container_data: Dict) -> Optional[Dict]:
        """
        Extract GPU assignment from Docker container inspect data.
        Returns dict with gpu_uuid, gpu_slot, interface, etc. or None if no GPU.
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

            # Detect interface
            interface = self._detect_interface(container_data)

            # Fall back to cgroup-based user detection if label not set
            if not user:
                cgroup_parent = container_data.get('HostConfig', {}).get('CgroupParent', '')
                user = self._extract_user_from_cgroup(cgroup_parent) or ''

            return {
                'container_name': container_name,
                'gpu_uuid': gpu_uuid,
                'gpu_slot': gpu_slot,
                'allocated_at': allocated_at,
                'priority': priority,
                'user': user,
                'interface': interface
            }

        except Exception:
            return None

    def get_all_allocations(self) -> Dict:
        """
        Get all GPU allocations by reading Docker containers.
        Now tracks ALL containers in ds01.slice (all interfaces).
        Returns dict structured like old gpu-state.json for compatibility.
        """
        allocations = defaultdict(lambda: {
            'type': 'mig_instance',
            'containers': [],
            'users': defaultdict(int),
            'uuid': '',
            'profile': '',
            'docker_id': '',
            'interfaces': defaultdict(int)  # Track containers by interface
        })

        # Get ALL containers (not just AIME naming convention)
        container_names = self._get_all_ds01_containers()

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
            interface = gpu_info.get('interface', INTERFACE_DOCKER)

            # Add to allocations
            allocations[gpu_slot]['containers'].append(container_name)
            allocations[gpu_slot]['users'][user] += 1
            allocations[gpu_slot]['uuid'] = gpu_info['gpu_uuid']
            allocations[gpu_slot]['docker_id'] = gpu_info['gpu_uuid']
            allocations[gpu_slot]['interfaces'][interface] += 1

            # Try to determine profile from UUID or slot
            if 'MIG' in gpu_info['gpu_uuid']:
                allocations[gpu_slot]['profile'] = '1g.10gb'  # Default, could parse from nvidia-smi

        # Convert defaultdict to regular dict
        result = {}
        for k, v in allocations.items():
            v['users'] = dict(v['users'])
            v['interfaces'] = dict(v['interfaces'])
            result[k] = v

        return result

    def _get_all_ds01_containers(self) -> List[str]:
        """
        Get ALL containers that should be tracked by DS01.
        Includes containers from all interfaces:
        - DS01 Orchestration (ds01.interface=orchestration)
        - DS01 Atomic (ds01.interface=atomic or name._.uid pattern)
        - Docker (direct docker run, in ds01.slice)
        - Other (VS Code, Compose, etc., in ds01.slice)
        """
        container_names = []

        try:
            # Get all containers (using real docker binary to see all users' containers)
            result = subprocess.run(
                [DOCKER_BIN, "ps", "-a", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                check=True
            )

            for name in result.stdout.split('\n'):
                name = name.strip()
                if not name:
                    continue

                # Check if container is in ds01 slice hierarchy
                container_data = self._get_container_inspect(name)
                if container_data:
                    cgroup_parent = container_data.get('HostConfig', {}).get('CgroupParent', '')

                    # Include if:
                    # 1. In ds01.slice hierarchy
                    # 2. Has ds01.* labels
                    # 3. Has AIME naming convention (legacy support)
                    labels = container_data.get('Config', {}).get('Labels', {}) or {}

                    in_ds01_slice = cgroup_parent.startswith('ds01')
                    has_ds01_labels = any(k.startswith('ds01.') for k in labels.keys())
                    has_aime_naming = '._.' in name

                    if in_ds01_slice or has_ds01_labels or has_aime_naming:
                        container_names.append(name)

        except subprocess.CalledProcessError:
            pass

        return container_names

    def get_all_containers_by_interface(self) -> Dict[str, List[Dict]]:
        """
        Get all containers grouped by interface.
        Returns dict with interface names as keys and container info lists as values.
        """
        by_interface = {
            INTERFACE_ORCHESTRATION: [],
            INTERFACE_ATOMIC: [],
            INTERFACE_DOCKER: [],
            INTERFACE_OTHER: []
        }

        container_names = self._get_all_ds01_containers()

        for container_name in container_names:
            if not container_name:
                continue

            container_data = self._get_container_inspect(container_name)
            if not container_data:
                continue

            interface = self._detect_interface(container_data)
            gpu_info = self._extract_gpu_from_container(container_data)

            # Get container state
            state = container_data.get('State', {})
            is_running = state.get('Running', False)
            status = state.get('Status', 'unknown')

            # Get user
            labels = container_data.get('Config', {}).get('Labels', {}) or {}
            user = labels.get('ds01.user') or labels.get('aime.mlc.USER', '')
            if not user:
                cgroup_parent = container_data.get('HostConfig', {}).get('CgroupParent', '')
                user = self._extract_user_from_cgroup(cgroup_parent) or 'unknown'

            container_info = {
                'name': container_name,
                'user': user,
                'status': status,
                'running': is_running,
                'gpu': gpu_info['gpu_slot'] if gpu_info else None,
                'gpu_uuid': gpu_info['gpu_uuid'] if gpu_info else None,
                'interface': interface
            }

            by_interface[interface].append(container_info)

        return by_interface

    def get_container_gpu(self, container_name: str) -> Optional[Dict]:
        """Get GPU assignment for a specific container."""
        container_data = self._get_container_inspect(container_name)
        if not container_data:
            return None
        return self._extract_gpu_from_container(container_data)

    def get_user_allocations(self, username: str) -> List[Dict]:
        """
        Get all GPU allocations for a specific user.
        Now tracks all containers from all interfaces.
        """
        user_allocations = []

        # Get all DS01 containers (all interfaces)
        container_names = self._get_all_ds01_containers()

        for container_name in container_names:
            if not container_name:
                continue

            container_data = self._get_container_inspect(container_name)
            if not container_data:
                continue

            gpu_info = self._extract_gpu_from_container(container_data)

            if not gpu_info:
                continue

            # Get user from labels or cgroup
            container_user = gpu_info['user']
            if not container_user:
                continue

            if container_user != username:
                continue

            # Get status
            state = container_data.get('State', {})
            is_running = state.get('Running', False)
            status = state.get('Status', 'unknown')
            interface = gpu_info.get('interface', INTERFACE_DOCKER)

            user_allocations.append({
                'container': container_name,
                'gpu_slot': gpu_info['gpu_slot'],
                'gpu_uuid': gpu_info['gpu_uuid'],
                'status': status,
                'running': is_running,
                'interface': interface
            })

        return user_allocations


def main():
    """CLI interface"""
    reader = GPUStateReader()

    if len(sys.argv) < 2:
        print("Usage: gpu-state-reader.py <command> [args]")
        print("\nCommands:")
        print("  all                    - Show all GPU allocations")
        print("  by-interface           - Show containers grouped by interface")
        print("  container <name>       - Show GPU for specific container")
        print("  user <username>        - Show user's GPU allocations")
        print("  json                   - Output all allocations as JSON")
        print("  json-by-interface      - Output containers by interface as JSON")
        sys.exit(1)

    command = sys.argv[1]

    if command == "all":
        allocations = reader.get_all_allocations()
        for gpu_slot, data in sorted(allocations.items()):
            print(f"\nGPU/MIG {gpu_slot}:")
            print(f"  UUID: {data['uuid']}")
            print(f"  Containers: {', '.join(data['containers']) if data['containers'] else 'none'}")
            print(f"  Users: {dict(data['users'])}")
            if data.get('interfaces'):
                print(f"  Interfaces: {dict(data['interfaces'])}")

    elif command == "by-interface":
        by_interface = reader.get_all_containers_by_interface()

        interface_names = {
            INTERFACE_ORCHESTRATION: "DS01 ORCHESTRATION",
            INTERFACE_ATOMIC: "DS01 ATOMIC",
            INTERFACE_DOCKER: "DOCKER DIRECT",
            INTERFACE_OTHER: "OTHER (VS Code, Compose, etc.)"
        }

        for interface, containers in by_interface.items():
            print(f"\n{interface_names.get(interface, interface)} ({len(containers)}):")
            if not containers:
                print("  (none)")
            for c in containers:
                status = "🟢" if c['running'] else "○"
                gpu = f"GPU:{c['gpu']}" if c['gpu'] else "no GPU"
                print(f"  {status} {c['name']} [{c['user']}] {gpu}")

    elif command == "json":
        allocations = reader.get_all_allocations()
        print(json.dumps(allocations, indent=2, default=str))

    elif command == "json-by-interface":
        by_interface = reader.get_all_containers_by_interface()
        print(json.dumps(by_interface, indent=2, default=str))

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
            interface = f"[{alloc.get('interface', '?')}]"
            print(f"  {status} {alloc['container']}: GPU {alloc['gpu_slot']} {interface}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
