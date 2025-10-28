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
            # Default location
            config_path = Path(__file__).parent.parent / "config" / "resource-limits.yaml"
        
        self.config_path = Path(config_path)
        self.config = self._load_config()
    
    def _load_config(self):
        """Load and parse the YAML config file"""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def get_user_limits(self, username):
        """Get resource limits for a specific user"""
        # Check for user-specific override first
        if username in self.config.get('user_overrides', {}):
            base_limits = self.config['defaults'].copy()
            base_limits.update(self.config['user_overrides'][username])
            return base_limits
        
        # Check which group the user belongs to
        for group_name, group_config in self.config.get('groups', {}).items():
            if username in group_config.get('members', []):
                base_limits = self.config['defaults'].copy()
                # Update with group settings (exclude 'members' key)
                group_limits = {k: v for k, v in group_config.items() if k != 'members'}
                base_limits.update(group_limits)
                return base_limits
        
        # Default limits if user not in any group
        return self.config['defaults'].copy()
    
    def get_docker_args(self, username):
        """Generate Docker run arguments for resource limits"""
        limits = self.get_user_limits(username)
        
        args = []
        
        # GPU settings
        if limits['gpus'] == 'all':
            args.append('--gpus=all')
        else:
            # Will be set by GPU allocation system
            args.append(f'--gpus={limits["gpus"]}')
        
        # CPU limits
        args.append(f'--cpus={limits["cpus"]}')
        
        # Memory limits
        args.append(f'--memory={limits["memory"]}')
        args.append(f'--memory-swap={limits["memory_swap"]}')
        args.append(f'--shm-size={limits["shm_size"]}')
        
        # Process limits
        args.append(f'--pids-limit={limits["pids_limit"]}')
        
        return args
    
    def format_for_display(self, username):
        """Format limits for human-readable display"""
        limits = self.get_user_limits(username)
        
        output = f"\nResource limits for user '{username}':\n"
        output += f"  GPUs:        {limits['gpus']}\n"
        output += f"  CPU cores:   {limits['cpus']}\n"
        output += f"  RAM:         {limits['memory']}\n"
        output += f"  Shared mem:  {limits['shm_size']}\n"
        output += f"  Max PIDs:    {limits['pids_limit']}\n"
        output += f"  Idle timeout: {limits['idle_timeout']}\n"
        
        return output


def main():
    """CLI interface for testing"""
    if len(sys.argv) < 2:
        print("Usage: get_resource_limits.py <username> [--docker-args]")
        sys.exit(1)
    
    username = sys.argv[1]
    parser = ResourceLimitParser()
    
    if '--docker-args' in sys.argv:
        # Output Docker arguments (for use in scripts)
        args = parser.get_docker_args(username)
        print(' '.join(args))
    else:
        # Human-readable output
        print(parser.format_for_display(username))


if __name__ == '__main__':
    main()