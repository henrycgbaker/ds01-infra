#!/usr/bin/env python3
"""
DS01 Resource Query - Unified Query Layer
Central service for querying containers and GPU allocations.
Single source of truth: Docker itself (via gpu-state-reader and gpu-availability-checker).
"""

import sys
import json
import subprocess
import argparse
from pathlib import Path
from typing import Dict, List, Optional

# Import our helper modules
sys.path.insert(0, str(Path(__file__).parent))
from gpu_state_reader import GPUStateReader
from gpu_availability_checker import GPUAvailabilityChecker


class DS01ResourceQuery:
    def __init__(self):
        self.state_reader = GPUStateReader()
        self.availability_checker = GPUAvailabilityChecker()

    def query_containers(self, user: Optional[str] = None, status: str = 'all') -> List[Dict]:
        """
        Query containers with optional user and status filtering.

        Args:
            user: Filter by username (None = all users)
            status: 'running', 'stopped', 'all' (default: 'all')

        Returns:
            List of container dicts with GPU info
        """
        containers = []

        # Build docker ps filter
        docker_cmd = ['docker', 'ps']

        if status == 'all':
            docker_cmd.append('-a')
        elif status == 'stopped':
            docker_cmd.extend(['-a', '--filter', 'status=exited'])
        # else: running (default docker ps)

        docker_cmd.extend(['--format', '{{.Names}}\t{{.Status}}\t{{.CreatedAt}}'])

        try:
            result = subprocess.run(docker_cmd, capture_output=True, text=True, check=True)
        except subprocess.CalledProcessError:
            return containers

        for line in result.stdout.strip().split('\n'):
            if not line or '._.' not in line:  # DS01 naming convention
                continue

            parts = line.split('\t')
            if len(parts) < 2:
                continue

            container_name = parts[0].strip()
            container_status = parts[1].strip()
            created_at = parts[2].strip() if len(parts) > 2 else ''

            # Get container details
            inspect_result = subprocess.run(
                ['docker', 'inspect', container_name],
                capture_output=True, text=True
            )

            if inspect_result.returncode != 0:
                continue

            try:
                container_info = json.loads(inspect_result.stdout)[0]
            except (json.JSONDecodeError, IndexError):
                continue

            # Get labels
            labels = container_info.get('Config', {}).get('Labels', {}) or {}

            # Filter by user if specified
            container_user = labels.get('ds01.user') or labels.get('aime.mlc.USER', '')
            if user and container_user != user:
                continue

            # Get GPU info
            gpu_info = self.state_reader._extract_gpu_from_container(container_info)

            # Build container dict
            container_dict = {
                'name': container_name,
                'user': container_user,
                'status': container_status,
                'running': 'Up' in container_status,
                'created': created_at,
                'ds01_managed': labels.get('ds01.managed') == 'true',
                'created_at': labels.get('ds01.created_at', ''),
            }

            if gpu_info:
                container_dict.update({
                    'gpu_allocated': gpu_info['gpu_slot'],
                    'gpu_uuid': gpu_info['gpu_uuid'],
                    'gpu_allocated_at': labels.get('ds01.gpu.allocated_at', ''),
                    'gpu_priority': labels.get('ds01.gpu.priority', ''),
                })
            else:
                container_dict.update({
                    'gpu_allocated': None,
                    'gpu_uuid': None,
                })

            containers.append(container_dict)

        return containers

    def query_gpus_status(self) -> Dict:
        """
        Query GPU allocation status.

        Returns:
            Dict with GPU allocation information
        """
        return self.state_reader.get_all_allocations()

    def query_available_gpus(self, user: Optional[str] = None, max_gpus: Optional[int] = None) -> Dict:
        """
        Query available GPUs for allocation.

        Args:
            user: Check availability for specific user
            max_gpus: User's max GPU limit

        Returns:
            Dict with available GPU information
        """
        if user and max_gpus is not None:
            return self.availability_checker.get_user_available_gpus(user, max_gpus)
        else:
            available = self.availability_checker.get_available_gpus()
            return {
                'available_gpus': available,
                'count': len(available)
            }

    def query_container(self, container_name: str) -> Optional[Dict]:
        """
        Get detailed information about a specific container.

        Args:
            container_name: Name of the container

        Returns:
            Dict with full container metadata or None
        """
        try:
            result = subprocess.run(
                ['docker', 'inspect', container_name],
                capture_output=True, text=True, check=True
            )
            container_info = json.loads(result.stdout)[0]
        except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
            return None

        labels = container_info.get('Config', {}).get('Labels', {}) or {}
        state = container_info.get('State', {})
        gpu_info = self.state_reader._extract_gpu_from_container(container_info)

        metadata = {
            'name': container_info.get('Name', '').lstrip('/'),
            'id': container_info.get('Id', ''),
            'created': container_info.get('Created', ''),
            'status': state.get('Status', ''),
            'running': state.get('Running', False),
            'user': labels.get('ds01.user') or labels.get('aime.mlc.USER', ''),
            'ds01_managed': labels.get('ds01.managed') == 'true',
            'created_at': labels.get('ds01.created_at', ''),
            'labels': {k: v for k, v in labels.items() if k.startswith('ds01.')},
        }

        if gpu_info:
            metadata['gpu'] = {
                'allocated': gpu_info['gpu_slot'],
                'uuid': gpu_info['gpu_uuid'],
                'allocated_at': labels.get('ds01.gpu.allocated_at', ''),
                'priority': labels.get('ds01.gpu.priority', ''),
            }
        else:
            metadata['gpu'] = None

        return metadata

    def query_user_summary(self, user: str) -> Dict:
        """
        Get summary of user's resource usage.

        Args:
            user: Username

        Returns:
            Dict with user's container and GPU usage summary
        """
        containers = self.query_containers(user=user)
        gpu_allocs = self.state_reader.get_user_allocations(user)

        running_containers = [c for c in containers if c['running']]
        stopped_containers = [c for c in containers if not c['running']]

        with_gpu = [c for c in containers if c.get('gpu_allocated')]
        without_gpu = [c for c in containers if not c.get('gpu_allocated')]

        return {
            'user': user,
            'total_containers': len(containers),
            'running_containers': len(running_containers),
            'stopped_containers': len(stopped_containers),
            'containers_with_gpu': len(with_gpu),
            'containers_without_gpu': len(without_gpu),
            'gpu_count': len(gpu_allocs),
            'gpu_allocations': gpu_allocs,
            'containers': containers,
        }


def main():
    """CLI interface"""
    parser = argparse.ArgumentParser(
        description='DS01 Resource Query - Unified query layer for containers and GPUs'
    )
    subparsers = parser.add_subparsers(dest='command', help='Query command')

    # containers command
    parser_containers = subparsers.add_parser('containers', help='Query containers')
    parser_containers.add_argument('--user', help='Filter by user')
    parser_containers.add_argument('--status', choices=['all', 'running', 'stopped'],
                                   default='all', help='Filter by status')
    parser_containers.add_argument('--json', action='store_true', help='Output as JSON')

    # gpus command
    parser_gpus = subparsers.add_parser('gpus', help='Query GPU allocations')
    parser_gpus.add_argument('--json', action='store_true', help='Output as JSON')

    # available command
    parser_available = subparsers.add_parser('available', help='Query available GPUs')
    parser_available.add_argument('--user', help='Check for specific user')
    parser_available.add_argument('--max-gpus', type=int, help='User max GPU limit')
    parser_available.add_argument('--json', action='store_true', help='Output as JSON')

    # container command (singular)
    parser_container = subparsers.add_parser('container', help='Query specific container')
    parser_container.add_argument('name', help='Container name')
    parser_container.add_argument('--json', action='store_true', help='Output as JSON')

    # user-summary command
    parser_user = subparsers.add_parser('user-summary', help='Get user resource summary')
    parser_user.add_argument('user', help='Username')
    parser_user.add_argument('--json', action='store_true', help='Output as JSON')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    query = DS01ResourceQuery()

    # Execute command
    if args.command == 'containers':
        containers = query.query_containers(user=args.user, status=args.status)

        if args.json:
            print(json.dumps(containers, indent=2))
        else:
            print(f"\nContainers ({len(containers)}):\n")
            for c in containers:
                status_icon = "🟢" if c['running'] else "○"
                gpu_info = f" | GPU {c['gpu_allocated']}" if c.get('gpu_allocated') else " | No GPU"
                print(f"  {status_icon} {c['name']} ({c['user']}){gpu_info}")

    elif args.command == 'gpus':
        gpus = query.query_gpus_status()

        if args.json:
            print(json.dumps(gpus, indent=2))
        else:
            print(f"\nGPU Allocations:\n")
            for gpu_slot, info in sorted(gpus.items()):
                containers = ', '.join(info['containers']) if info['containers'] else 'none'
                print(f"  GPU/MIG {gpu_slot}:")
                print(f"    UUID: {info['uuid']}")
                print(f"    Containers: {containers}")

    elif args.command == 'available':
        available = query.query_available_gpus(user=args.user, max_gpus=args.max_gpus)

        if args.json:
            print(json.dumps(available, indent=2))
        else:
            if args.user:
                print(f"\nGPU Availability for {args.user}:")
                print(f"  Current: {available['user_current_count']}/{available.get('user_max_gpus', '∞')}")
                print(f"  Can allocate: {'Yes' if available['can_allocate'] else 'No'}")
                if not available['can_allocate']:
                    print(f"  Reason: {available['reason']}")
                print(f"  Available GPUs: {len(available['available_gpus'])}")
            else:
                print(f"\nAvailable GPUs: {available['count']}")
                for slot, info in sorted(available['available_gpus'].items()):
                    print(f"  MIG {slot}: {info['profile']} ({info['uuid']})")

    elif args.command == 'container':
        container = query.query_container(args.name)

        if not container:
            print(f"Container '{args.name}' not found", file=sys.stderr)
            sys.exit(1)

        if args.json:
            print(json.dumps(container, indent=2))
        else:
            print(f"\nContainer: {container['name']}")
            print(f"  User: {container['user']}")
            print(f"  Status: {container['status']}")
            print(f"  Created: {container['created']}")
            if container['gpu']:
                print(f"  GPU: {container['gpu']['allocated']} ({container['gpu']['uuid']})")
                print(f"    Allocated at: {container['gpu']['allocated_at']}")
                print(f"    Priority: {container['gpu']['priority']}")
            else:
                print(f"  GPU: None")

    elif args.command == 'user-summary':
        summary = query.query_user_summary(args.user)

        if args.json:
            print(json.dumps(summary, indent=2))
        else:
            print(f"\nResource Summary for {summary['user']}:")
            print(f"  Total containers: {summary['total_containers']}")
            print(f"  Running: {summary['running_containers']}")
            print(f"  Stopped: {summary['stopped_containers']}")
            print(f"  With GPU: {summary['containers_with_gpu']}")
            print(f"  GPU allocations: {summary['gpu_count']}")

            if summary['gpu_allocations']:
                print(f"\n  GPU Details:")
                for alloc in summary['gpu_allocations']:
                    status = "🟢" if alloc['running'] else "○"
                    print(f"    {status} {alloc['container']}: GPU {alloc['gpu_slot']}")


if __name__ == '__main__':
    main()
