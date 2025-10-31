#!/usr/bin/env python3
"""
Resource limits configuration parser for DS01 GPU server
Reads resource-limits.yaml and returns appropriate limits for a given user
"""

import yaml
import sys
import os
from pathlib import Path

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
        """Get the group name for a user"""
        user_overrides = self.config.get('user_overrides') or {}
        if username in user_overrides:
            return 'override'
        
        groups = self.config.get('groups') or {}
        for group_name, group_config in groups.items():
            if username in group_config.get('members', []):
                return group_name
        
        return self.config.get('default_group', 'student')
    
    def get_user_limits(self, username):
        """Get resource limits for a specific user"""
        if not self.config:
            raise ValueError("Configuration is empty or invalid")
        
        defaults = self.config.get('defaults', {})
        
        # Check for user-specific override first
        user_overrides = self.config.get('user_overrides') or {}
        if username in user_overrides:
            base_limits = defaults.copy()
            base_limits.update(user_overrides[username])
            base_limits['_group'] = 'override'
            return base_limits
        
        # Check which group the user belongs to
        groups = self.config.get('groups') or {}
        for group_name, group_config in groups.items():
            if username in group_config.get('members', []):
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
        
        # CPU limits
        args.append(f'--cpus={limits["cpus"]}')
        
        # Memory limits
        args.append(f'--memory={limits["memory"]}')
        args.append(f'--memory-swap={limits.get("memory_swap", limits["memory"])}')
        args.append(f'--shm-size={limits["shm_size"]}')
        
        # Process limits
        args.append(f'--pids-limit={limits["pids_limit"]}')
        
        # Storage limits (for tmpfs inside container)
        if "storage_tmp" in limits:
            args.append(f'--tmpfs=/tmp:size={limits["storage_tmp"]}')
        
        # Cgroup parent (for systemd slices)
        group = limits.get('_group', 'student')
        args.append(f'--cgroup-parent=ds01-{group}.slice')
        
        return args
    
    def format_for_display(self, username):
        """Format limits for human-readable display"""
        limits = self.get_user_limits(username)
        group = limits.get('_group', 'unknown')
        
        max_gpus = limits.get('max_gpus_per_user', 1)
        if max_gpus is None:
            max_gpus_str = "unlimited"
        else:
            max_gpus_str = str(max_gpus)
        
        output = f"\nResource limits for user '{username}' (group: {group}):\n"
        output += f"\n  GPU Limits:\n"
        output += f"    Max GPUs (simultaneous):  {max_gpus_str}\n"
        output += f"    Priority level:           {limits.get('priority', 10)}\n"
        output += f"    Max containers:           {limits.get('max_containers_per_user', 3)}\n"
        output += f"\n  Compute (per container):\n"
        output += f"    CPU cores:                {limits['cpus']}\n"
        output += f"    RAM:                      {limits['memory']}\n"
        output += f"    Shared memory:            {limits['shm_size']}\n"
        output += f"    Max processes:            {limits['pids_limit']}\n"
        output += f"\n  Storage:\n"
        output += f"    Workspace (/workspace):   {limits.get('storage_workspace', 'N/A')}\n"
        output += f"    Data (/data):             {limits.get('storage_data', 'N/A')}\n"
        output += f"    Tmp (/tmp in container):  {limits.get('storage_tmp', 'N/A')}\n"
        output += f"\n  Lifecycle:\n"
        output += f"    Idle timeout:             {limits.get('idle_timeout', 'N/A')}\n"
        output += f"    Max runtime:              {limits.get('max_runtime', 'unlimited')}\n"
        output += f"\n  Enforcement:\n"
        output += f"    Systemd slice:            ds01-{group}.slice\n"
        
        return output


def main():
    """CLI interface for testing"""
    if len(sys.argv) < 2:
        print("Usage: get_resource_limits.py <username> [--docker-args|--group|--max-gpus|--priority]")
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
        max_gpus = limits.get('max_gpus_per_user', 1)
        print(max_gpus if max_gpus is not None else "unlimited")
    elif '--priority' in sys.argv:
        limits = parser.get_user_limits(username)
        print(limits.get('priority', 10))
    else:
        print(parser.format_for_display(username))


if __name__ == '__main__':
    main()
