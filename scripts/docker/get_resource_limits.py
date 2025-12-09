#!/usr/bin/env python3
"""
Resource limits configuration parser for DS01 GPU server
Reads resource-limits.yaml and returns appropriate limits for a given user
"""

import yaml
import sys
import os
from pathlib import Path

# Import username sanitization utility
script_dir = Path(__file__).resolve().parent
lib_dir = script_dir.parent / "lib"
sys.path.insert(0, str(lib_dir))

try:
    from username_utils import sanitize_username_for_slice
except ImportError:
    # Fallback if library not available
    # Uses underscores (not hyphens) to avoid systemd hierarchy interpretation
    import re
    def sanitize_username_for_slice(username: str) -> str:
        if not username:
            return username
        # Strip domain part
        if '@' in username:
            username = username.split('@')[0]
        # Replace dots and invalid chars with underscores (NOT hyphens)
        sanitized = username.replace('.', '_')
        sanitized = re.sub(r'[^a-zA-Z0-9_:]', '_', sanitized)
        sanitized = re.sub(r'_+', '_', sanitized).strip('_')
        return sanitized

class ResourceLimitParser:
    def __init__(self, config_path=None):
        if config_path is None:
            # Try multiple default locations
            script_dir = Path(__file__).resolve().parent
            possible_paths = [
                script_dir.parent.parent / "config" / "resource-limits.yaml",
                Path("/opt/ds01-infra/config/resource-limits.yaml"),
                script_dir / "../../config/resource-limits.yaml",
            ]
            
            for path in possible_paths:
                if path.exists():
                    config_path = path
                    break
            else:
                config_path = possible_paths[0]
        
        self.config_path = Path(config_path).resolve()
        self.config = self._load_config()
    
    def _load_config(self):
        """Load and parse the YAML config file"""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def get_user_group(self, username):
        """Get the group name for a user.

        Supports both original and sanitized usernames in config lookups.
        Tries original username first, then sanitized form.
        """
        user_overrides = self.config.get('user_overrides') or {}
        sanitized = sanitize_username_for_slice(username)

        # Check user_overrides with original username first
        if username in user_overrides:
            return 'override'
        # Fallback to sanitized form
        if sanitized != username and sanitized in user_overrides:
            return 'override'

        groups = self.config.get('groups') or {}
        for group_name, group_config in groups.items():
            members = group_config.get('members', [])
            # Check original username first
            if username in members:
                return group_name
            # Fallback to sanitized form
            if sanitized != username and sanitized in members:
                return group_name

        return self.config.get('default_group', 'student')
    
    def get_user_limits(self, username):
        """Get resource limits for a specific user.

        Supports both original and sanitized usernames in config lookups.
        Tries original username first, then sanitized form.
        """
        if not self.config:
            raise ValueError("Configuration is empty or invalid")

        defaults = self.config.get('defaults', {})
        sanitized = sanitize_username_for_slice(username)

        # Check for user-specific override first (try original, then sanitized)
        user_overrides = self.config.get('user_overrides') or {}
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

        # Check which group the user belongs to (try original, then sanitized)
        groups = self.config.get('groups') or {}
        for group_name, group_config in groups.items():
            members = group_config.get('members', [])
            if username in members or (sanitized != username and sanitized in members):
                base_limits = defaults.copy()
                group_limits = {k: v for k, v in group_config.items() if k != 'members'}
                base_limits.update(group_limits)
                base_limits['_group'] = group_name
                return base_limits

        # Default limits if user not in any group
        default_group = self.config.get('default_group', 'student')
        group_config = groups.get(default_group, {})

        base_limits = defaults.copy()
        group_limits = {k: v for k, v in group_config.items() if k != 'members'}
        base_limits.update(group_limits)
        base_limits['_group'] = default_group

        return base_limits
    
    def get_docker_args(self, username):
        """Generate Docker run arguments for resource limits"""
        limits = self.get_user_limits(username)

        args = []

        # CPU limits (check both 'max_cpus' and 'cpus' for backwards compatibility)
        cpus = limits.get("max_cpus") or limits.get("cpus", 16)
        args.append(f'--cpus={cpus}')

        # Memory limits
        memory = limits.get("memory", "32g")
        args.append(f'--memory={memory}')
        args.append(f'--memory-swap={limits.get("memory_swap", memory)}')
        args.append(f'--shm-size={limits.get("shm_size", "16g")}')

        # Process limits
        args.append(f'--pids-limit={limits.get("pids_limit", 4096)}')

        # Storage limits (for tmpfs inside container)
        if "storage_tmp" in limits:
            args.append(f'--tmpfs=/tmp:size={limits["storage_tmp"]}')

        # Cgroup parent (per-user slice for granular monitoring)
        # Hierarchy: ds01.slice → ds01-{group}.slice → ds01-{group}-{sanitized_username}.slice
        # Username is sanitized for systemd compatibility (LDAP users may have @ and . chars)
        group = limits.get('_group', 'student')
        sanitized = sanitize_username_for_slice(username)
        args.append(f'--cgroup-parent=ds01-{group}-{sanitized}.slice')

        return args
    
    def format_for_display(self, username):
        """Format limits for human-readable display"""
        limits = self.get_user_limits(username)
        group = limits.get('_group', 'unknown')

        max_gpus = limits.get('max_gpus_per_user') or limits.get('max_mig_instances', 1)
        if max_gpus is None:
            max_gpus_str = "unlimited"
        else:
            max_gpus_str = str(max_gpus)

        cpus = limits.get('max_cpus') or limits.get('cpus', 16)

        # Get max_gpus_per_container (support both old and new config names)
        # Note: None means unlimited, so check explicitly (don't use 'or' which treats None as falsy)
        max_gpus_container = limits.get('max_mig_per_container')
        if max_gpus_container is None:
            max_gpus_container = limits.get('max_gpus_per_container')
        if max_gpus_container is None:
            max_gpus_container_str = "unlimited"
        else:
            max_gpus_container_str = str(max_gpus_container)

        # Get allow_full_gpu setting
        allow_full = limits.get('allow_full_gpu', False)

        output = f"\nResource limits for user '{username}' (group: {group}):\n"
        output += f"\n  GPU Limits:\n"
        output += f"    Max GPUs (simultaneous):  {max_gpus_str}\n"
        output += f"    Max GPUs per container:   {max_gpus_container_str}\n"
        output += f"    Allow full GPU:           {'Yes' if allow_full else 'No'}\n"
        output += f"    Priority level:           {limits.get('priority', 10)}\n"
        output += f"    Max containers:           {limits.get('max_containers_per_user', 3)}\n"
        output += f"\n  Compute (per container):\n"
        output += f"    CPU cores:                {cpus}\n"
        output += f"    RAM:                      {limits.get('memory', '32g')}\n"
        output += f"    Shared memory:            {limits.get('shm_size', '16g')}\n"
        output += f"    Max processes:            {limits.get('pids_limit', 4096)}\n"
        output += f"\n  Storage:\n"
        output += f"    Workspace (/workspace):   {limits.get('storage_workspace', 'N/A')}\n"
        output += f"    Data (/data):             {limits.get('storage_data', 'N/A')}\n"
        output += f"    Tmp (/tmp in container):  {limits.get('storage_tmp', 'N/A')}\n"
        output += f"\n  Lifecycle:\n"
        output += f"    Idle timeout:             {limits.get('idle_timeout', 'N/A')}\n"
        output += f"    GPU hold after stop:      {limits.get('gpu_hold_after_stop', 'N/A')}\n"
        output += f"    Container hold (stopped): {limits.get('container_hold_after_stop', 'N/A')}\n"
        output += f"    Max runtime:              {limits.get('max_runtime', 'unlimited')}\n"
        output += f"\n  Enforcement:\n"
        sanitized = sanitize_username_for_slice(username)
        output += f"    Systemd slice:            ds01-{group}-{sanitized}.slice\n"
        if sanitized != username:
            output += f"    (sanitized from: {username})\n"

        return output


    def get_gpu_allocation_config(self):
        """Get gpu_allocation section from config"""
        return self.config.get('gpu_allocation', {})


def main():
    """CLI interface for testing"""
    if len(sys.argv) < 2:
        print("Usage: get_resource_limits.py <username> [--docker-args|--group|--max-gpus|--max-containers|--max-mig-per-container|--mig-instances-per-gpu|--allow-full-gpu|--priority|--gpu-hold-time|--container-hold-time|--idle-timeout|--max-runtime]")
        sys.exit(1)

    username = sys.argv[1]
    parser = ResourceLimitParser()

    if '--docker-args' in sys.argv:
        args = parser.get_docker_args(username)
        print(' '.join(args))
    elif '--group' in sys.argv:
        print(parser.get_user_group(username))
    elif '--max-gpus' in sys.argv:
        limits = parser.get_user_limits(username)
        max_gpus = limits.get('max_gpus_per_user') or limits.get('max_mig_instances', 1)
        print(max_gpus if max_gpus is not None else "unlimited")
    elif '--max-containers' in sys.argv:
        limits = parser.get_user_limits(username)
        max_containers = limits.get('max_containers_per_user', 3)
        print(max_containers if max_containers is not None else "unlimited")
    elif '--max-mig-per-container' in sys.argv:
        limits = parser.get_user_limits(username)
        # Support both old name (max_gpus_per_container) and new name (max_mig_per_container)
        # Note: None means unlimited, so we must check for key presence, not truthiness
        if 'max_mig_per_container' in limits:
            max_mig = limits['max_mig_per_container']
        elif 'max_gpus_per_container' in limits:
            max_mig = limits['max_gpus_per_container']
        else:
            max_mig = 1  # Default
        print(max_mig if max_mig is not None else "unlimited")
    elif '--mig-instances-per-gpu' in sys.argv:
        gpu_config = parser.get_gpu_allocation_config()
        mig_per_gpu = gpu_config.get('mig_instances_per_gpu', 4)
        print(mig_per_gpu)
    elif '--allow-full-gpu' in sys.argv:
        limits = parser.get_user_limits(username)
        allow_full = limits.get('allow_full_gpu', False)
        print("true" if allow_full else "false")
    elif '--priority' in sys.argv:
        limits = parser.get_user_limits(username)
        print(limits.get('priority', 10))
    elif '--gpu-hold-time' in sys.argv:
        limits = parser.get_user_limits(username)
        hold_time = limits.get('gpu_hold_after_stop')
        print(hold_time if hold_time is not None else "indefinite")
    elif '--container-hold-time' in sys.argv:
        limits = parser.get_user_limits(username)
        hold_time = limits.get('container_hold_after_stop')
        print(hold_time if hold_time is not None else "never")
    elif '--idle-timeout' in sys.argv:
        limits = parser.get_user_limits(username)
        idle_timeout = limits.get('idle_timeout')
        print(idle_timeout if idle_timeout is not None else "None")
    elif '--max-runtime' in sys.argv:
        limits = parser.get_user_limits(username)
        max_runtime = limits.get('max_runtime')
        print(max_runtime if max_runtime is not None else "None")
    else:
        print(parser.format_for_display(username))


if __name__ == '__main__':
    main()
