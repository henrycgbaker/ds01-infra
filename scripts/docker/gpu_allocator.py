#!/usr/bin/env python3
"""
GPU Allocation Manager for DS01 Server (MIG-aware, Priority-based)
Handles dynamic GPU/MIG allocation with priority and reservations
"""

import json
import subprocess
import yaml
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Tuple

class GPUAllocationManager:
    def __init__(self, state_dir="/var/lib/ds01", log_dir="/var/logs/ds01", config_path="/opt/ds01-infra/config/resource-limits.yaml"):
        self.state_dir = Path(state_dir)
        self.log_dir = Path(log_dir)
        self.config_path = Path(config_path)
        self.state_file = self.state_dir / "gpu-state.json"
        self.log_file = self.log_dir / "gpu-allocations.log"
        self.metadata_dir = self.state_dir / "container-metadata"
        
        # Load config
        self.config = self._load_config()
        self.mig_enabled = self.config.get('gpu_allocation', {}).get('enable_mig', False)
        
        # Ensure directories exist
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.metadata_dir.mkdir(exist_ok=True)
        
        # Initialize state if doesn't exist
        if not self.state_file.exists():
            self._initialize_state()
    
    def _load_config(self) -> dict:
        """Load YAML configuration"""
        if not self.config_path.exists():
            return {}
        
        with open(self.config_path) as f:
            return yaml.safe_load(f)
    
    def _get_mig_instances(self) -> List[Dict]:
        """Detect MIG instances if MIG is enabled"""
        if not self.mig_enabled:
            return []
        
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=index,mig.mode.current', '--format=csv,noheader'],
                capture_output=True, text=True, check=True
            )
            
            # Check if any GPU has MIG enabled
            mig_gpus = []
            for line in result.stdout.strip().split('\n'):
                parts = line.split(',')
                gpu_id = parts[0].strip()
                mig_mode = parts[1].strip() if len(parts) > 1 else 'N/A'
                
                if mig_mode == 'Enabled':
                    # Get MIG instances for this GPU
                    result2 = subprocess.run(
                        ['nvidia-smi', 'mig', '-lgi', '-i', gpu_id],
                        capture_output=True, text=True
                    )
                    # Parse MIG instance IDs (simplified, would need proper parsing)
                    # For now, assume 3 instances per GPU (2g.20gb profile)
                    for instance in range(3):
                        mig_gpus.append({
                            'physical_gpu': gpu_id,
                            'mig_instance': instance,
                            'id': f"{gpu_id}:{instance}"  # e.g., "0:0", "0:1", "0:2"
                        })
            
            return mig_gpus
        except:
            return []
    
    def _initialize_state(self):
        """Initialize GPU state file with detected GPUs/MIG instances"""
        # Detect physical GPUs
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=index', '--format=csv,noheader'],
                capture_output=True, text=True, check=True
            )
            gpu_count = len(result.stdout.strip().split('\n'))
        except:
            gpu_count = 4  # Default to 4 GPUs
        
        # Check for MIG instances
        mig_instances = self._get_mig_instances()
        
        if mig_instances:
            # MIG mode: track MIG instances
            gpus = {
                mig['id']: {
                    "type": "mig_instance",
                    "physical_gpu": mig['physical_gpu'],
                    "mig_instance": mig['mig_instance'],
                    "containers": [],
                    "users": {},
                    "reserved_until": None,
                    "reserved_for": None
                }
                for mig in mig_instances
            }
        else:
            # Standard mode: track physical GPUs
            gpus = {
                str(i): {
                    "type": "physical_gpu",
                    "containers": [],
                    "users": {},
                    "reserved_until": None,
                    "reserved_for": None
                }
                for i in range(gpu_count)
            }
        
        state = {
            "gpus": gpus,
            "mig_enabled": self.mig_enabled,
            "allocation_strategy": self.config.get('gpu_allocation', {}).get('strategy', 'least_allocated')
        }
        
        with open(self.state_file, 'w') as f:
            json.dump(state, f, indent=2)
    
    def _load_state(self) -> dict:
        """Load current GPU state"""
        with open(self.state_file, 'r') as f:
            return json.load(f)
    
    def _save_state(self, state: dict):
        """Save GPU state"""
        with open(self.state_file, 'w') as f:
            json.dump(state, f, indent=2)
    
    def _log_event(self, event_type: str, user: str, container: str, gpu_id: Optional[str] = None, reason: str = "", priority: int = 0):
        """Append event to log file"""
        timestamp = datetime.now().isoformat()
        log_entry = f"{timestamp}|{event_type}|{user}|{container}|{gpu_id or 'N/A'}|priority={priority}|{reason}\n"
        
        with open(self.log_file, 'a') as f:
            f.write(log_entry)
    
    def _save_container_metadata(self, container: str, user: str, gpu_id: str, priority: int):
        """Save container metadata"""
        metadata = {
            "container": container,
            "user": user,
            "gpu_id": gpu_id,
            "priority": priority,
            "allocated_at": datetime.now().isoformat(),
        }
        
        metadata_file = self.metadata_dir / f"{container}.json"
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f, indent=2)
    
    def _check_reservations(self, username: str) -> List[str]:
        """Check for active reservations and return reserved GPU IDs for this user"""
        user_overrides = self.config.get('user_overrides', {})
        now = datetime.now()
        
        reserved_gpus = []
        
        if username in user_overrides:
            override = user_overrides[username]
            
            # Check if reservation is active
            start = override.get('reservation_start')
            end = override.get('reservation_end')
            
            if start and end:
                start_dt = datetime.fromisoformat(start)
                end_dt = datetime.fromisoformat(end)
                
                if start_dt <= now <= end_dt:
                    # Reservation is active
                    reserved_gpus = override.get('reserved_gpus', [])
        
        return [str(gpu) for gpu in reserved_gpus]
    
    def _check_gpu_reservation(self, gpu_id: str) -> Optional[Dict]:
        """Check if a GPU is reserved by someone else"""
        state = self._load_state()
        gpu_info = state["gpus"].get(str(gpu_id), {})
        
        reserved_until = gpu_info.get('reserved_until')
        reserved_for = gpu_info.get('reserved_for')
        
        if reserved_until and reserved_for:
            end_dt = datetime.fromisoformat(reserved_until)
            if datetime.now() <= end_dt:
                return {
                    'reserved_for': reserved_for,
                    'reserved_until': reserved_until
                }
        
        return None
    
    def _get_user_priority(self, username: str) -> int:
        """Get user's priority level"""
        # Check for override (highest priority)
        user_overrides = self.config.get('user_overrides', {})
        if username in user_overrides:
            return user_overrides[username].get('priority', 100)
        
        # Check group
        groups = self.config.get('groups', {})
        for group_name, group_config in groups.items():
            if username in group_config.get('members', []):
                return group_config.get('priority', 10)
        
        # Default group
        default_group = self.config.get('default_group', 'student')
        if default_group in groups:
            return groups[default_group].get('priority', 10)
        
        return 10  # Lowest priority
    
    def get_user_gpu_count(self, username: str) -> int:
        """Count how many GPUs/MIG instances a user currently has allocated"""
        state = self._load_state()
        
        total_gpus = 0
        for gpu_id, gpu_info in state["gpus"].items():
            if username in gpu_info.get("users", {}):
                total_gpus += gpu_info["users"][username]
        
        return total_gpus
    
    def get_user_containers(self, username: str) -> List[Dict]:
        """Get all containers with GPUs for a specific user"""
        state = self._load_state()
        containers = []
        
        for gpu_id, gpu_info in state["gpus"].items():
            for container in gpu_info.get("containers", []):
                metadata_file = self.metadata_dir / f"{container}.json"
                if metadata_file.exists():
                    with open(metadata_file, 'r') as f:
                        metadata = json.load(f)
                        if metadata.get("user") == username:
                            containers.append({
                                "container": container,
                                "gpu_id": gpu_id,
                                "priority": metadata.get("priority", 0),
                                "allocated_at": metadata.get("allocated_at")
                            })
        
        return containers
    
    def _get_gpu_load(self) -> Dict[str, Dict]:
        """Get current GPU utilization and memory usage"""
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=index,utilization.gpu,memory.used,memory.total',
                 '--format=csv,noheader,nounits'],
                capture_output=True, text=True, check=True
            )
            
            gpu_load = {}
            for line in result.stdout.strip().split('\n'):
                parts = [p.strip() for p in line.split(',')]
                gpu_id = parts[0]
                gpu_load[gpu_id] = {
                    "utilization": int(parts[1]),
                    "memory_used": int(parts[2]),
                    "memory_total": int(parts[3]),
                    "memory_percent": (int(parts[2]) / int(parts[3])) * 100
                }
            
            return gpu_load
        except:
            return {}
    
    def get_least_allocated_gpu(self, username: str, priority: int) -> Optional[str]:
        """
        Find best GPU/MIG instance using priority-aware least-allocated strategy
        
        Priority order:
        1. User's reserved GPUs (if any)
        2. GPUs with lowest priority containers
        3. Fewest containers
        4. Lowest memory usage
        """
        state = self._load_state()
        gpu_load = self._get_gpu_load()
        
        # Check for user's reservations first
        reserved_gpus = self._check_reservations(username)
        if reserved_gpus:
            # User has reserved GPUs, use those first
            for gpu_id in reserved_gpus:
                if gpu_id in state["gpus"]:
                    return gpu_id
        
        # Calculate score for each GPU
        gpu_scores = []
        for gpu_id, gpu_info in state["gpus"].items():
            # Check if GPU is reserved by someone else
            reservation = self._check_gpu_reservation(gpu_id)
            if reservation and reservation['reserved_for'] != username:
                continue  # Skip reserved GPUs
            
            container_count = len(gpu_info.get("containers", []))
            
            # Get max priority of containers on this GPU
            max_priority_on_gpu = 0
            for container in gpu_info.get("containers", []):
                metadata_file = self.metadata_dir / f"{container}.json"
                if metadata_file.exists():
                    with open(metadata_file, 'r') as f:
                        metadata = json.load(f)
                        max_priority_on_gpu = max(max_priority_on_gpu, metadata.get("priority", 0))
            
            # Get physical GPU for memory stats
            physical_gpu = gpu_info.get('physical_gpu', gpu_id)
            memory_percent = gpu_load.get(physical_gpu, {}).get("memory_percent", 0)
            
            # Score: (priority_difference, container_count, memory_percent)
            # Higher priority users get lower-priority GPUs first
            priority_diff = max_priority_on_gpu - priority
            score = (priority_diff, container_count, memory_percent)
            gpu_scores.append((gpu_id, score))
        
        # Sort by score (ascending - lower is better)
        gpu_scores.sort(key=lambda x: x[1])
        
        # Return best GPU
        if gpu_scores:
            return gpu_scores[0][0]
        
        return None
    
    def allocate_gpu(self, username: str, container: str, max_gpus: int, 
                     priority: int, strategy: str = "least_allocated") -> Tuple[Optional[str], str]:
        """
        Allocate GPU/MIG instance to a container (dynamic, priority-aware)
        """
        # Check if container already has GPU
        state = self._load_state()
        for gpu_id, gpu_info in state["gpus"].items():
            if container in gpu_info.get("containers", []):
                return gpu_id, "ALREADY_ALLOCATED"
        
        # Check user's current GPU count against limit
        current_count = self.get_user_gpu_count(username)
        if current_count >= max_gpus:
            reason = f"USER_AT_LIMIT ({current_count}/{max_gpus})"
            self._log_event("REJECTED", username, container, reason=reason, priority=priority)
            return None, reason
        
        # Find best GPU using priority-aware least-allocated strategy
        gpu_id = self.get_least_allocated_gpu(username, priority)
        
        if gpu_id is None:
            reason = "NO_GPU_AVAILABLE"
            self._log_event("REJECTED", username, container, reason=reason, priority=priority)
            return None, reason
        
        # Allocate GPU
        state["gpus"][gpu_id]["containers"].append(container)
        
        # Update user count
        if username not in state["gpus"][gpu_id]["users"]:
            state["gpus"][gpu_id]["users"][username] = 0
        state["gpus"][gpu_id]["users"][username] += 1
        
        self._save_state(state)
        
        # Save container metadata
        self._save_container_metadata(container, username, gpu_id, priority)
        
        # Log allocation
        container_count = len(state["gpus"][gpu_id]["containers"])
        gpu_type = state["gpus"][gpu_id].get("type", "physical_gpu")
        reason = f"ALLOCATED {gpu_type} (now has {container_count} containers)"
        self._log_event("ALLOCATED", username, container, gpu_id, reason, priority)
        
        return gpu_id, "SUCCESS"
    
    def release_gpu(self, container: str) -> Tuple[Optional[str], str]:
        """Release GPU/MIG instance from container"""
        state = self._load_state()
        
        for gpu_id, gpu_info in state["gpus"].items():
            if container in gpu_info.get("containers", []):
                # Load metadata
                metadata_file = self.metadata_dir / f"{container}.json"
                username = None
                priority = 0
                if metadata_file.exists():
                    with open(metadata_file, 'r') as f:
                        metadata = json.load(f)
                        username = metadata.get("user")
                        priority = metadata.get("priority", 0)
                
                # Remove container
                state["gpus"][gpu_id]["containers"].remove(container)
                
                # Update user count
                if username and username in state["gpus"][gpu_id]["users"]:
                    state["gpus"][gpu_id]["users"][username] -= 1
                    if state["gpus"][gpu_id]["users"][username] <= 0:
                        del state["gpus"][gpu_id]["users"][username]
                
                self._save_state(state)
                
                # Log release
                container_count = len(state["gpus"][gpu_id]["containers"])
                reason = f"RELEASED (now has {container_count} containers)"
                self._log_event("RELEASED", username or "unknown", container, gpu_id, reason, priority)
                
                # Remove metadata
                if metadata_file.exists():
                    metadata_file.unlink()
                
                return gpu_id, "SUCCESS"
        
        return None, "NOT_ALLOCATED"
    
    def get_status(self) -> Dict:
        """Get current GPU allocation status"""
        state = self._load_state()
        gpu_load = self._get_gpu_load()
        
        status = {
            "total_gpus": len(state["gpus"]),
            "total_allocated_containers": 0,
            "mig_enabled": state.get("mig_enabled", False),
            "gpus": []
        }
        
        for gpu_id in sorted(state["gpus"].keys()):
            gpu_info = state["gpus"][gpu_id]
            containers = gpu_info.get("containers", [])
            container_count = len(containers)
            status["total_allocated_containers"] += container_count
            
            # Get physical GPU for stats
            physical_gpu = gpu_info.get('physical_gpu', gpu_id)
            load = gpu_load.get(str(physical_gpu), {})
            
            # Check reservation
            reservation = self._check_gpu_reservation(gpu_id)
            
            status["gpus"].append({
                "id": gpu_id,
                "type": gpu_info.get("type", "physical_gpu"),
                "physical_gpu": physical_gpu if "physical_gpu" in gpu_info else gpu_id,
                "container_count": container_count,
                "containers": containers,
                "users": gpu_info.get("users", {}),
                "utilization": load.get("utilization", 0),
                "memory_used": load.get("memory_used", 0),
                "memory_total": load.get("memory_total", 0),
                "memory_percent": load.get("memory_percent", 0),
                "reserved": reservation is not None,
                "reserved_for": reservation['reserved_for'] if reservation else None,
                "reserved_until": reservation['reserved_until'] if reservation else None,
            })
        
        return status


def main():
    """CLI interface"""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: gpu_allocator.py <command> [args]")
        print("\nCommands:")
        print("  status                                    - Show GPU allocations")
        print("  allocate <user> <container> <max_gpus> <priority> - Allocate GPU")
        print("  release <container>                       - Release GPU")
        print("  user-status <user>                        - Show user's allocations")
        print("  user-count <user>                         - Show GPU count for user")
        sys.exit(1)
    
    manager = GPUAllocationManager()
    command = sys.argv[1]
    
    if command == "status":
        status = manager.get_status()
        mig_status = "MIG ENABLED" if status['mig_enabled'] else "Standard GPUs"
        print(f"\nGPU Status ({mig_status}): {status['total_allocated_containers']} containers across {status['total_gpus']} GPU{'s' if not status['mig_enabled'] else ' instances'}\n")
        
        for gpu in status["gpus"]:
            gpu_type = "MIG" if gpu["type"] == "mig_instance" else "GPU"
            reserved_str = f" [RESERVED for {gpu['reserved_for']}]" if gpu['reserved'] else ""
            print(f"{gpu_type} {gpu['id']}: {gpu['container_count']} containers{reserved_str}")
            print(f"  Util: {gpu['utilization']}% | Mem: {gpu['memory_used']}/{gpu['memory_total']} MB")
            if gpu['containers']:
                for container in gpu['containers']:
                    print(f"    - {container}")
            print()
    
    elif command == "allocate" and len(sys.argv) == 6:
        user = sys.argv[2]
        container = sys.argv[3]
        max_gpus = int(sys.argv[4])
        priority = int(sys.argv[5])
        
        gpu_id, reason = manager.allocate_gpu(user, container, max_gpus, priority)
        if gpu_id:
            print(f"✓ Allocated GPU/MIG {gpu_id} to {container}")
        else:
            print(f"✗ Allocation failed: {reason}")
    
    elif command == "release" and len(sys.argv) == 3:
        container = sys.argv[2]
        gpu_id, reason = manager.release_gpu(container)
        if gpu_id:
            print(f"✓ Released GPU/MIG {gpu_id} from {container}")
        else:
            print(f"✗ No GPU allocated to {container}")
    
    elif command == "user-status" and len(sys.argv) == 3:
        user = sys.argv[2]
        containers = manager.get_user_containers(user)
        gpu_count = manager.get_user_gpu_count(user)
        print(f"\n{user}: {gpu_count} GPU/MIG instances across {len(containers)} containers\n")
        for c in containers:
            print(f"  GPU {c['gpu_id']}: {c['container']} (priority {c['priority']})")
    
    elif command == "user-count" and len(sys.argv) == 3:
        user = sys.argv[2]
        print(manager.get_user_gpu_count(user))
    
    else:
        print("Invalid command")
        sys.exit(1)


if __name__ == '__main__':
    main()
