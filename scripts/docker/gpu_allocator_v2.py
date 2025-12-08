#!/usr/bin/env python3
"""
GPU Allocator Smart - Stateless GPU Allocation Manager
Uses Docker labels as single source of truth. No state files maintained.
Reads current state from Docker via gpu-state-reader.py.

Updated for DS01 Layered Architecture:
- Interface-specific state handling:
  - Orchestration: Binary state model (running/removed only)
  - Atomic/Docker/Other: Full state model (created/running/stopped/removed)
- GPU hold behavior varies by interface
"""

import sys
import json
import yaml
import subprocess
import importlib.util
import fcntl
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Tuple

# Interface constants (from gpu-state-reader.py)
INTERFACE_ORCHESTRATION = "orchestration"
INTERFACE_ATOMIC = "atomic"
INTERFACE_DOCKER = "docker"
INTERFACE_OTHER = "other"

# Import our helper modules (handle hyphenated filenames)
SCRIPT_DIR = Path(__file__).parent
LIB_DIR = SCRIPT_DIR.parent / "lib"

# Import username sanitization utility
sys.path.insert(0, str(LIB_DIR))
try:
    from username_utils import sanitize_username_for_slice
except ImportError:
    # Fallback if library not available
    import re as _re
    def sanitize_username_for_slice(username: str) -> str:
        if not username:
            return username
        sanitized = username.replace('@', '-at-').replace('.', '-')
        sanitized = _re.sub(r'[^a-zA-Z0-9_:-]', '-', sanitized)
        sanitized = _re.sub(r'-+', '-', sanitized).strip('-')
        return sanitized

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

        # Lock file for preventing race conditions
        self.lock_file = self.log_dir / "gpu-allocator.lock"

    def _acquire_lock(self):
        """Acquire exclusive lock for GPU allocation operations"""
        self._lock_fd = open(self.lock_file, 'w')
        fcntl.flock(self._lock_fd, fcntl.LOCK_EX)

    def _release_lock(self):
        """Release the exclusive lock"""
        if hasattr(self, '_lock_fd') and self._lock_fd:
            fcntl.flock(self._lock_fd, fcntl.LOCK_UN)
            self._lock_fd.close()
            self._lock_fd = None

    def _load_config(self) -> dict:
        """Load YAML configuration"""
        if not self.config_path.exists():
            return {}

        with open(self.config_path) as f:
            return yaml.safe_load(f)

    def _get_user_limits(self, username: str) -> Dict:
        """Get user's resource limits from config (merges defaults + group/override).

        Supports both original and sanitized usernames in config lookups.
        Tries original username first, then sanitized form.
        """
        defaults = self.config.get('defaults', {}) or {}
        groups = self.config.get('groups', {}) or {}
        sanitized = sanitize_username_for_slice(username)

        # Check user_overrides first (highest priority) - try original, then sanitized
        user_overrides = self.config.get('user_overrides', {}) or {}
        override_key = None
        if username in user_overrides:
            override_key = username
        elif sanitized != username and sanitized in user_overrides:
            override_key = sanitized

        if override_key:
            base_limits = defaults.copy()
            base_limits.update(user_overrides[override_key])
            base_limits['_group'] = 'override'
            return base_limits

        # Check groups - try original, then sanitized
        for group_name, group_config in groups.items():
            if group_config:
                members = group_config.get('members', [])
                if username in members or (sanitized != username and sanitized in members):
                    base_limits = defaults.copy()
                    group_limits = {k: v for k, v in group_config.items() if k != 'members'}
                    base_limits.update(group_limits)
                    base_limits['_group'] = group_name
                    return base_limits

        # Default group
        default_group = self.config.get('default_group', 'student')
        if default_group in groups:
            base_limits = defaults.copy()
            group_config = groups[default_group]
            group_limits = {k: v for k, v in group_config.items() if k != 'members'}
            base_limits.update(group_limits)
            base_limits['_group'] = default_group
            return base_limits

        # Fallback to defaults only
        base_limits = defaults.copy()
        base_limits['_group'] = 'default'
        return base_limits

    def _can_use_full_gpu(self, username: str) -> bool:
        """Check if user is allowed to use full (non-MIG) GPUs"""
        limits = self._get_user_limits(username)
        # Default to False - students and default users cannot use full GPUs
        return limits.get('allow_full_gpu', False)

    def _is_full_gpu(self, gpu_slot: str) -> bool:
        """Check if a GPU slot is a full GPU (not MIG instance)"""
        # Full GPU slots don't have a decimal (e.g., "0", "1")
        # MIG slots have decimal (e.g., "1.0", "1.2")
        return '.' not in str(gpu_slot)

    def _get_user_priority(self, username: str) -> int:
        """Get user's allocation priority"""
        limits = self._get_user_limits(username)
        return limits.get('priority', 10)

    def _log_event(self, event_type: str, user: str, container: str,
                   gpu_id: Optional[str] = None, reason: str = ""):
        """Log event to centralized event logger (events.jsonl)"""
        # Map legacy event types to new event types
        event_map = {
            "ALLOCATED": "gpu.allocated",
            "REJECTED": "gpu.rejected",
            "RELEASED": "gpu.released",
        }
        mapped_type = event_map.get(event_type, f"gpu.{event_type.lower()}")

        # Build event-logger.py command
        event_logger = str(SCRIPT_DIR / 'event-logger.py')
        args = ['python3', event_logger, 'log', mapped_type,
                f'user={user}', f'container={container}']

        if gpu_id:
            args.append(f'gpu={gpu_id}')
        if reason:
            args.append(f'reason={reason}')

        # Log to centralized event system (fail silently)
        try:
            subprocess.run(args, capture_output=True, check=False)
        except Exception:
            pass

        # Also write to legacy log file for backwards compatibility
        timestamp = datetime.now().isoformat()
        log_entry = f"{timestamp}|{event_type}|{user}|{container}|{gpu_id or 'N/A'}|{reason}\n"
        try:
            with open(self.log_file, 'a') as f:
                f.write(log_entry)
        except Exception:
            pass

    def _get_container_interface(self, container: str) -> str:
        """
        Get the interface a container was created with.
        Returns: INTERFACE_ORCHESTRATION, INTERFACE_ATOMIC, INTERFACE_DOCKER, or INTERFACE_OTHER
        """
        try:
            result = subprocess.run(
                ['docker', 'inspect', '--format',
                 '{{index .Config.Labels "ds01.interface"}}|||'
                 '{{index .Config.Labels "ds01.managed"}}|||'
                 '{{.Name}}'],
                capture_output=True, text=True, check=True
            )
            output = result.stdout.strip()
            parts = output.split('|||')
            interface_label = parts[0] if len(parts) > 0 else ''
            managed_label = parts[1] if len(parts) > 1 else ''
            name = parts[2].lstrip('/') if len(parts) > 2 else ''

            # Explicit interface label
            if interface_label and interface_label != '<no value>':
                return interface_label

            # DS01 managed but no explicit interface -> atomic (backward compat)
            if managed_label == 'true':
                return INTERFACE_ATOMIC

            # AIME naming convention
            if '._.' in name:
                return INTERFACE_ATOMIC

            # Default: docker direct
            return INTERFACE_DOCKER

        except subprocess.CalledProcessError:
            return INTERFACE_DOCKER

    def allocate_gpu(self, username: str, container: str,
                     max_gpus: Optional[int] = None,
                     require_full_gpu: bool = False) -> Tuple[Optional[str], str]:
        """
        Allocate GPU for a container (stateless - reads from Docker).
        Uses file lock to prevent race conditions.

        Args:
            username: User requesting GPU
            container: Container name (full tag: name._.userid)
            max_gpus: User's max GPU limit (from resource-limits.yaml)
            require_full_gpu: If True, only allocate full GPU (not MIG)

        Returns:
            Tuple of (gpu_id, status_message)
            gpu_id: Slot ID (e.g., "1.2") if successful, None if failed
            status_message: "SUCCESS", "ALREADY_ALLOCATED", or error reason
        """
        try:
            # Acquire exclusive lock to prevent race conditions
            self._acquire_lock()

            # Check if container already has GPU (read from Docker)
            container_gpu = self.state_reader.get_container_gpu(container)
            if container_gpu:
                gpu_slot = container_gpu['gpu_slot']
                return gpu_slot, "ALREADY_ALLOCATED"

            # Get user's limits
            limits = self._get_user_limits(username)

            if max_gpus is None:
                max_gpus = limits.get('max_mig_instances', 1)
                # Handle unlimited
                if max_gpus is None or max_gpus == "unlimited":
                    max_gpus = 999

            # Check full GPU permission if requesting full GPU
            if require_full_gpu and not self._can_use_full_gpu(username):
                group = limits.get('_group', 'default')
                reason = f"FULL_GPU_NOT_ALLOWED (group={group}, allow_full_gpu=false)"
                self._log_event("REJECTED", username, container, reason=reason)
                return None, reason

            # Check user's current GPU count
            user_allocs = self.state_reader.get_user_allocations(username)
            current_count = len(user_allocs)

            if current_count >= max_gpus:
                reason = f"USER_AT_LIMIT ({current_count}/{max_gpus})"
                self._log_event("REJECTED", username, container, reason=reason)
                return None, reason

            # Find available GPU
            # Pass allow_full_gpu to availability checker so it can filter appropriately
            allow_full = self._can_use_full_gpu(username)
            suggestion = self.availability_checker.suggest_gpu_for_user(
                username, max_gpus, self._get_user_priority(username),
                require_full_gpu=require_full_gpu, allow_full_gpu=allow_full
            )

            if not suggestion['success']:
                reason = suggestion['error']
                self._log_event("REJECTED", username, container, reason=reason)
                return None, reason

            gpu_slot = suggestion['gpu_slot']

            # Double-check full GPU permission (belt and suspenders)
            if self._is_full_gpu(gpu_slot) and not allow_full:
                reason = f"FULL_GPU_NOT_ALLOWED (got slot {gpu_slot}, user cannot use full GPUs)"
                self._log_event("REJECTED", username, container, reason=reason)
                return None, reason

            # Log allocation
            reason = f"ALLOCATED (user has {current_count + 1}/{max_gpus} GPUs)"
            self._log_event("ALLOCATED", username, container, gpu_slot, reason)

            return gpu_slot, "SUCCESS"

        finally:
            # Always release the lock
            self._release_lock()

    def allocate_multi_gpu(self, username: str, container: str,
                           num_migs: int = 1,
                           prefer_full_gpu: bool = False) -> Tuple[list, int, str]:
        """
        Allocate multiple MIG instances or full GPUs for a container.
        Supports distributed containers across multiple GPU slots.

        Args:
            username: User requesting GPUs
            container: Container name (full tag: name._.userid)
            num_migs: Number of MIG-equivalents to allocate (1 full GPU = mig_instances_per_gpu)
            prefer_full_gpu: If True and user has allow_full_gpu, prefer full GPUs over MIGs

        Returns:
            Tuple of (gpu_slots, actual_mig_equiv, status_message)
            gpu_slots: List of GPU slot IDs (e.g., ["1.2", "1.3"] or ["0"])
            actual_mig_equiv: Total MIG-equivalents allocated (full GPU = mig_instances_per_gpu)
            status_message: "SUCCESS", "ALREADY_ALLOCATED", or error reason
        """
        try:
            # Acquire exclusive lock
            self._acquire_lock()

            # Check if container already has GPU(s)
            container_gpu = self.state_reader.get_container_gpu(container)
            if container_gpu:
                gpu_slot = container_gpu['gpu_slot']
                return [gpu_slot], 1, "ALREADY_ALLOCATED"

            # Get user's limits
            limits = self._get_user_limits(username)

            # Get mig_instances_per_gpu from config
            gpu_config = self.config.get('gpu_allocation', {})
            mig_per_gpu = gpu_config.get('mig_instances_per_gpu', 4)

            # Get max MIG instances total and per container
            max_mig_total = limits.get('max_mig_instances', 2)
            # Handle None (unlimited) - check key presence, not truthiness
            if 'max_mig_per_container' in limits:
                max_mig_per_container = limits['max_mig_per_container']
            elif 'max_gpus_per_container' in limits:
                max_mig_per_container = limits['max_gpus_per_container']
            else:
                max_mig_per_container = 1

            # Handle unlimited (None or "unlimited" string)
            if max_mig_total is None or max_mig_total == "unlimited":
                max_mig_total = 999
            if max_mig_per_container is None or max_mig_per_container == "unlimited":
                max_mig_per_container = 999

            # Check per-container limit
            if num_migs > max_mig_per_container:
                reason = f"EXCEEDS_CONTAINER_LIMIT ({num_migs}>{max_mig_per_container})"
                self._log_event("REJECTED", username, container, reason=reason)
                return [], 0, reason

            # Check user's current usage
            user_allocs = self.state_reader.get_user_allocations(username)
            current_mig_equiv = self._calculate_mig_equivalents(user_allocs, mig_per_gpu)
            remaining_migs = max_mig_total - current_mig_equiv

            if num_migs > remaining_migs:
                reason = f"EXCEEDS_TOTAL_LIMIT ({num_migs}+{current_mig_equiv}>{max_mig_total})"
                self._log_event("REJECTED", username, container, reason=reason)
                return [], 0, reason

            # Check full GPU permission
            can_use_full = self._can_use_full_gpu(username)

            # Determine allocation strategy
            allocated_slots = []
            total_mig_equiv = 0

            if prefer_full_gpu and can_use_full and num_migs >= mig_per_gpu:
                # Try to allocate full GPUs first
                num_full_gpus = num_migs // mig_per_gpu
                remaining_migs_needed = num_migs % mig_per_gpu

                for _ in range(num_full_gpus):
                    suggestion = self.availability_checker.suggest_gpu_for_user(
                        username, max_mig_total, self._get_user_priority(username),
                        require_full_gpu=True, allow_full_gpu=True
                    )
                    if suggestion['success']:
                        allocated_slots.append(suggestion['gpu_slot'])
                        total_mig_equiv += mig_per_gpu
                    else:
                        # No more full GPUs available, try MIGs
                        remaining_migs_needed += mig_per_gpu
                        break

                # Allocate remaining MIGs
                for _ in range(remaining_migs_needed):
                    suggestion = self.availability_checker.suggest_gpu_for_user(
                        username, max_mig_total, self._get_user_priority(username),
                        require_full_gpu=False, allow_full_gpu=can_use_full
                    )
                    if suggestion['success']:
                        allocated_slots.append(suggestion['gpu_slot'])
                        total_mig_equiv += 1
                    else:
                        # Can't allocate remaining, release what we got and fail
                        reason = suggestion.get('error', 'NO_GPU_AVAILABLE')
                        self._log_event("REJECTED", username, container, reason=reason)
                        return [], 0, reason
            else:
                # Allocate MIGs first (default behavior)
                for _ in range(num_migs):
                    suggestion = self.availability_checker.suggest_gpu_for_user(
                        username, max_mig_total, self._get_user_priority(username),
                        require_full_gpu=False, allow_full_gpu=can_use_full
                    )
                    if suggestion['success']:
                        slot = suggestion['gpu_slot']
                        allocated_slots.append(slot)
                        # Full GPU counts as mig_per_gpu equivalents
                        if self._is_full_gpu(slot):
                            total_mig_equiv += mig_per_gpu
                        else:
                            total_mig_equiv += 1
                    else:
                        reason = suggestion.get('error', 'NO_GPU_AVAILABLE')
                        self._log_event("REJECTED", username, container, reason=reason)
                        return [], 0, reason

            if not allocated_slots:
                reason = "NO_GPU_AVAILABLE"
                self._log_event("REJECTED", username, container, reason=reason)
                return [], 0, reason

            # Log allocation
            slots_str = ','.join(allocated_slots)
            reason = f"ALLOCATED ({total_mig_equiv} MIG-equiv, slots: {slots_str})"
            self._log_event("ALLOCATED", username, container, slots_str, reason)

            return allocated_slots, total_mig_equiv, "SUCCESS"

        finally:
            self._release_lock()

    def _calculate_mig_equivalents(self, allocations: list, mig_per_gpu: int) -> int:
        """Calculate total MIG-equivalents from a list of allocations."""
        total = 0
        for alloc in allocations:
            gpu_slot = alloc.get('gpu_slot', '')
            if self._is_full_gpu(gpu_slot):
                total += mig_per_gpu
            else:
                total += 1
        return total

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

    def release_stale_allocations(self, username: str = None) -> list:
        """
        Remove stopped containers that exceeded GPU hold timeout.
        Container removal automatically releases GPU (Docker labels gone = GPU freed).

        Interface-specific behavior:
        - Orchestration: No hold timeout, stopped containers removed immediately
        - Atomic/Docker/Other: Respect gpu_hold_after_stop timeout

        Args:
            username: Optional - only check this user's containers (None = all users)

        Returns:
            List of (container, reason) tuples for removed containers
        """
        from datetime import timedelta
        import re

        def parse_duration(duration_str: str) -> Optional[timedelta]:
            """Parse duration string like '24h', '0.5h', '1d' to timedelta"""
            if not duration_str or duration_str == "null" or duration_str == "indefinite":
                return None

            duration_str = str(duration_str).strip().lower()

            # Extract numeric value (supporting decimals)
            match = re.search(r'([\d.]+)', duration_str)
            if not match:
                return None
            value = float(match.group(1))

            if 'h' in duration_str:
                return timedelta(hours=value)
            elif 'd' in duration_str:
                return timedelta(days=value)
            elif 'm' in duration_str:
                return timedelta(minutes=value)
            else:
                # Default to hours
                return timedelta(hours=value)

        removed = []
        now = datetime.now()

        # Get all containers with GPU allocations (from Docker labels)
        all_allocations = self.state_reader.get_all_allocations()

        for gpu_slot, gpu_info in all_allocations.items():
            for container in gpu_info['containers']:
                # Get username from Docker label (not UID from container name)
                try:
                    result = subprocess.run(
                        ['docker', 'inspect', '--format', '{{index .Config.Labels "ds01.user"}}', container],
                        capture_output=True, text=True, check=True
                    )
                    user = result.stdout.strip()
                    if not user or user == '<no value>':
                        user = None
                except subprocess.CalledProcessError:
                    user = None

                # Filter by username if specified
                if username and user != username:
                    continue

                # Get container interface
                interface = self._get_container_interface(container)

                # Check if container is stopped
                try:
                    result = subprocess.run(
                        ['docker', 'inspect', '--format', '{{.State.Running}}', container],
                        capture_output=True, text=True, check=True
                    )
                    is_running = result.stdout.strip() == 'true'

                    if is_running:
                        continue  # Skip running containers

                    # Container is stopped - get FinishedAt timestamp from Docker state (automatic)
                    result = subprocess.run(
                        ['docker', 'inspect', '--format', '{{.State.FinishedAt}}', container],
                        capture_output=True, text=True, check=True
                    )
                    finished_at_str = result.stdout.strip()

                    if not finished_at_str or finished_at_str == '0001-01-01T00:00:00Z':
                        # Container never ran or invalid state - remove immediately (stale allocation)
                        subprocess.run(['docker', 'rm', '-f', container], check=True)
                        removed.append((container, "Invalid FinishedAt - stale allocation"))
                        self._log_event("REMOVED_STALE", user or "unknown", container, gpu_slot,
                                       reason="Invalid FinishedAt")
                        continue

                    # Parse stopped timestamp (remove Z suffix and parse)
                    stopped_at = datetime.fromisoformat(finished_at_str.replace('Z', '+00:00')).replace(tzinfo=None)
                    elapsed = now - stopped_at

                    # INTERFACE-SPECIFIC STATE HANDLING
                    if interface == INTERFACE_ORCHESTRATION:
                        # Orchestration Interface: Binary state model
                        # Stopped containers should be removed immediately (no limbo state)
                        subprocess.run(['docker', 'rm', '-f', container], check=True)
                        removed.append((container, f"Orchestration interface - binary state (stopped→removed)"))
                        self._log_event("REMOVED_STALE", user or "unknown", container, gpu_slot,
                                       reason=f"Orchestration binary state: stopped→removed")
                        continue

                    # Atomic/Docker/Other: Full state model with hold timeout
                    if user:
                        limits = self._get_user_limits(user)
                        hold_timeout_str = limits.get('gpu_hold_after_stop')
                        hold_timeout = parse_duration(hold_timeout_str)

                        if hold_timeout is None:
                            # Indefinite hold - don't remove
                            continue

                        # Check if timeout exceeded
                        if elapsed > hold_timeout:
                            # Remove container (automatically releases GPU)
                            subprocess.run(['docker', 'rm', '-f', container], check=True)
                            removed.append((container, f"Timeout exceeded ({elapsed.total_seconds():.0f}s > {hold_timeout.total_seconds():.0f}s)"))
                            self._log_event("REMOVED_STALE", user, container, gpu_slot,
                                           reason=f"Timeout exceeded: {elapsed.total_seconds():.0f}s")

                except subprocess.CalledProcessError:
                    # Container doesn't exist anymore - already removed
                    removed.append((container, "Container no longer exists"))
                except Exception as e:
                    # Log error but continue
                    print(f"Warning: Error checking container {container}: {e}", file=sys.stderr)
                    continue

        return removed


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

    # release-stale command
    parser_stale = subparsers.add_parser('release-stale', help='Release stale GPU allocations from stopped containers')
    parser_stale.add_argument('user', nargs='?', help='Optional: username to filter (default: all users)')

    # allocate-multi command (NEW: multi-GPU allocation for distributed containers)
    parser_multi = subparsers.add_parser('allocate-multi', help='Allocate multiple MIG instances or GPUs to container')
    parser_multi.add_argument('user', help='Username')
    parser_multi.add_argument('container', help='Container name (full tag)')
    parser_multi.add_argument('num_migs', type=int, help='Number of MIG-equivalents to allocate')
    parser_multi.add_argument('--prefer-full', action='store_true', help='Prefer full GPUs over MIGs')

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

    elif args.command == 'release-stale':
        username = args.user if hasattr(args, 'user') and args.user else None
        removed = allocator.release_stale_allocations(username)

        if removed:
            for container, reason in removed:
                print(f"✓ Removed {container}: {reason}")
            print(f"\n✓ Removed {len(removed)} stale container(s) (GPUs freed automatically)")
        else:
            print("✓ No stale containers found")

    elif args.command == 'allocate-multi':
        gpu_slots, mig_equiv, reason = allocator.allocate_multi_gpu(
            args.user, args.container, args.num_migs,
            prefer_full_gpu=args.prefer_full
        )

        if gpu_slots and reason == "SUCCESS":
            # Get Docker IDs for all slots
            docker_ids = [allocator.get_docker_id(slot) for slot in gpu_slots]
            slots_str = ','.join(gpu_slots)
            docker_ids_str = ','.join(docker_ids)
            print(f"✓ Allocated {len(gpu_slots)} GPU/MIG ({mig_equiv} MIG-equiv) to {args.container}")
            print(f"GPU_SLOTS={slots_str}")
            print(f"DOCKER_IDS={docker_ids_str}")  # For mlc-create-wrapper parsing
            print(f"MIG_EQUIV={mig_equiv}")
        elif reason == "ALREADY_ALLOCATED":
            slots_str = ','.join(gpu_slots)
            docker_ids = [allocator.get_docker_id(slot) for slot in gpu_slots]
            docker_ids_str = ','.join(docker_ids)
            print(f"⚠ Container {args.container} already has GPU(s) {slots_str} allocated")
            print(f"GPU_SLOTS={slots_str}")
            print(f"DOCKER_IDS={docker_ids_str}")
        else:
            print(f"✗ Allocation failed: {reason}")
            sys.exit(1)


if __name__ == '__main__':
    main()
