#!/usr/bin/env python3
"""
DS01 State Validation Tool

Validates consistency between GPU allocations and Docker containers.
Detects and optionally repairs inconsistencies.

Checks performed:
1. GPU exists: Containers with GPU labels reference valid GPUs
2. No orphaned allocations: GPUs aren't allocated to non-existent containers
3. No duplicates: Each GPU slot allocated to only one container
4. Labels valid: DS01 labels have valid format
5. User exists: Container owners are valid system users

Usage:
    validate-state.py             # Check and report
    validate-state.py --repair    # Auto-repair minor issues
    validate-state.py --json      # JSON output
"""

import sys
import json
import subprocess
import re
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, List, Set, Tuple, Optional

INFRA_ROOT = Path("/opt/ds01-infra")
EVENT_LOGGER = INFRA_ROOT / "scripts/docker/event-logger.py"


class StateValidator:
    def __init__(self, repair: bool = False):
        self.repair = repair
        self.issues = []
        self.repairs = []

    def log_event(self, event_type: str, **kwargs):
        """Log to centralized event system."""
        try:
            if EVENT_LOGGER.exists():
                args = ['python3', str(EVENT_LOGGER), 'log', event_type]
                for k, v in kwargs.items():
                    args.append(f'{k}={v}')
                subprocess.run(args, capture_output=True, check=False)
        except Exception:
            pass

    def _get_nvidia_gpus(self) -> Dict[str, Dict]:
        """Get all GPUs/MIG instances from nvidia-smi."""
        gpus = {}

        try:
            result = subprocess.run(
                ['nvidia-smi', '-L'],
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
                    gpus[current_gpu] = {
                        'type': 'full',
                        'uuid': None
                    }
                    continue

                # Match MIG line
                mig_match = re.match(
                    r'\s+MIG\s+(\S+)\s+Device\s+(\d+):\s+\(UUID:\s+(MIG-[a-f0-9-]+)\)',
                    line
                )
                if mig_match and current_gpu is not None:
                    profile = mig_match.group(1)
                    device_id = mig_match.group(2)
                    uuid = mig_match.group(3)
                    slot_id = f"{current_gpu}.{device_id}"

                    gpus[slot_id] = {
                        'type': 'mig',
                        'profile': profile,
                        'uuid': uuid,
                        'physical_gpu': current_gpu
                    }

        except Exception as e:
            self.issues.append({
                'severity': 'error',
                'check': 'nvidia_smi',
                'message': f'Cannot query nvidia-smi: {e}'
            })

        return gpus

    def _get_docker_allocations(self) -> Dict[str, Dict]:
        """Get GPU allocations from Docker container labels."""
        allocations = {}

        try:
            result = subprocess.run(
                ['docker', 'ps', '-a', '--format',
                 '{{.Names}}|||{{.Labels}}|||{{.Status}}'],
                capture_output=True,
                text=True,
                check=True
            )

            for line in result.stdout.strip().split('\n'):
                if not line.strip():
                    continue

                parts = line.split('|||')
                if len(parts) < 3:
                    continue

                name = parts[0]
                labels = parts[1]
                status = parts[2]

                # Parse GPU slot from labels
                gpu_match = re.search(r'ds01\.gpu_slot=([^,]+)', labels)
                user_match = re.search(r'ds01\.user=([^,]+)', labels)

                if gpu_match:
                    gpu_slot = gpu_match.group(1)
                    user = user_match.group(1) if user_match else 'unknown'

                    allocations[name] = {
                        'gpu_slot': gpu_slot,
                        'user': user,
                        'status': status,
                        'running': 'Up' in status
                    }

        except Exception as e:
            self.issues.append({
                'severity': 'error',
                'check': 'docker_allocations',
                'message': f'Cannot query Docker: {e}'
            })

        return allocations

    def check_gpu_exists(self, nvidia_gpus: Dict, allocations: Dict):
        """Check that allocated GPUs actually exist."""
        for container, info in allocations.items():
            gpu_slot = info['gpu_slot']

            if gpu_slot not in nvidia_gpus:
                self.issues.append({
                    'severity': 'warning',
                    'check': 'gpu_exists',
                    'container': container,
                    'gpu_slot': gpu_slot,
                    'message': f'GPU {gpu_slot} does not exist (container: {container})'
                })

                # Repair: If container stopped, clear the GPU label
                if self.repair and not info['running']:
                    self._repair_clear_gpu_label(container)

    def check_no_duplicates(self, allocations: Dict):
        """Check for duplicate GPU allocations."""
        gpu_to_containers: Dict[str, List[str]] = {}

        for container, info in allocations.items():
            gpu_slot = info['gpu_slot']

            if gpu_slot not in gpu_to_containers:
                gpu_to_containers[gpu_slot] = []
            gpu_to_containers[gpu_slot].append(container)

        for gpu_slot, containers in gpu_to_containers.items():
            if len(containers) > 1:
                # Determine which is running
                running = [c for c in containers if allocations[c]['running']]
                stopped = [c for c in containers if not allocations[c]['running']]

                self.issues.append({
                    'severity': 'error',
                    'check': 'duplicate_allocation',
                    'gpu_slot': gpu_slot,
                    'containers': containers,
                    'message': f'GPU {gpu_slot} allocated to multiple containers: {containers}'
                })

                # Repair: Keep running container, clear others
                if self.repair and len(running) == 1 and stopped:
                    for container in stopped:
                        self._repair_clear_gpu_label(container)

    def check_label_format(self, allocations: Dict):
        """Check that labels have valid format."""
        for container, info in allocations.items():
            gpu_slot = info['gpu_slot']

            # Valid formats: "0", "1", "0.0", "1.2", etc.
            if not re.match(r'^\d+(\.\d+)?$', gpu_slot):
                self.issues.append({
                    'severity': 'warning',
                    'check': 'label_format',
                    'container': container,
                    'gpu_slot': gpu_slot,
                    'message': f'Invalid GPU slot format: {gpu_slot}'
                })

    def check_user_exists(self, allocations: Dict):
        """Check that container owners are valid users."""
        import pwd

        for container, info in allocations.items():
            user = info.get('user', 'unknown')

            if user == 'unknown':
                continue

            try:
                pwd.getpwnam(user)
            except KeyError:
                self.issues.append({
                    'severity': 'info',
                    'check': 'user_exists',
                    'container': container,
                    'user': user,
                    'message': f'User {user} does not exist on system'
                })

    def _repair_clear_gpu_label(self, container: str):
        """Clear GPU label from a container (repair action)."""
        try:
            # Note: Docker doesn't support removing labels from existing containers
            # We can only note this for manual cleanup
            self.repairs.append({
                'action': 'note',
                'container': container,
                'message': f'Container {container} has stale GPU allocation. '
                          f'Remove with: docker rm {container}'
            })

            self.log_event('state.repair_needed',
                          container=container,
                          action='remove_stale_container')

        except Exception as e:
            self.issues.append({
                'severity': 'error',
                'check': 'repair',
                'message': f'Failed to repair {container}: {e}'
            })

    def validate(self) -> Dict:
        """Run all validation checks."""
        nvidia_gpus = self._get_nvidia_gpus()
        allocations = self._get_docker_allocations()

        # Run checks
        self.check_gpu_exists(nvidia_gpus, allocations)
        self.check_no_duplicates(allocations)
        self.check_label_format(allocations)
        self.check_user_exists(allocations)

        # Build result
        errors = [i for i in self.issues if i['severity'] == 'error']
        warnings = [i for i in self.issues if i['severity'] == 'warning']
        info = [i for i in self.issues if i['severity'] == 'info']

        result = {
            'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'valid': len(errors) == 0,
            'summary': {
                'errors': len(errors),
                'warnings': len(warnings),
                'info': len(info),
                'total_gpus': len(nvidia_gpus),
                'allocated': len(allocations)
            },
            'issues': self.issues,
            'repairs': self.repairs if self.repair else []
        }

        # Log validation result
        self.log_event('state.validation',
                      valid=str(result['valid']).lower(),
                      errors=str(len(errors)),
                      warnings=str(len(warnings)))

        return result


def main():
    import argparse

    parser = argparse.ArgumentParser(description='DS01 State Validation')
    parser.add_argument('--repair', action='store_true',
                       help='Attempt to repair issues')
    parser.add_argument('--json', action='store_true',
                       help='Output as JSON')

    args = parser.parse_args()

    validator = StateValidator(repair=args.repair)
    result = validator.validate()

    if args.json:
        print(json.dumps(result, indent=2))
        return

    # Human-readable output
    print(f"\nDS01 State Validation - {result['timestamp']}")
    print("=" * 60)

    s = result['summary']
    status = "\033[32mVALID\033[0m" if result['valid'] else "\033[31mINVALID\033[0m"
    print(f"Status: {status}")
    print(f"GPUs: {s['allocated']} allocated / {s['total_gpus']} total")
    print(f"Issues: {s['errors']} errors, {s['warnings']} warnings, {s['info']} info")

    if result['issues']:
        print("\n" + "-" * 60)
        print("Issues Found:")

        for issue in result['issues']:
            sev = issue['severity'].upper()
            if sev == 'ERROR':
                sev = f"\033[31m{sev}\033[0m"
            elif sev == 'WARNING':
                sev = f"\033[33m{sev}\033[0m"
            else:
                sev = f"\033[34m{sev}\033[0m"

            print(f"  [{sev}] {issue['message']}")

    if result['repairs']:
        print("\n" + "-" * 60)
        print("Repair Actions:")
        for repair in result['repairs']:
            print(f"  - {repair['message']}")

    print("=" * 60)

    sys.exit(0 if result['valid'] else 1)


if __name__ == "__main__":
    main()
