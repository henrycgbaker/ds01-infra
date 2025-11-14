#!/usr/bin/env python3
"""
DS01 GPU Status Dashboard
Generates a markdown report of current GPU allocations (dynamic, per-container)
"""

import json
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List

class GPUStatusDashboard:
    def __init__(self, state_dir="/var/lib/ds01", log_dir="/var/log/ds01", output_dir="/tmp"):
        self.state_dir = Path(state_dir)
        self.log_dir = Path(log_dir)
        self.state_file = self.state_dir / "gpu-state.json"
        self.log_file = self.log_dir / "gpu-allocations.log"
        self.output_dir = Path(output_dir)
    
    def _load_state(self) -> dict:
        """Load GPU state"""
        if not self.state_file.exists():
            return {"gpus": {}, "allocation_strategy": "least_allocated"}
        
        with open(self.state_file, 'r') as f:
            return json.load(f)
    
    def _get_nvidia_info(self) -> List[Dict]:
        """Get GPU info from nvidia-smi"""
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=index,name,utilization.gpu,memory.used,memory.total',
                 '--format=csv,noheader,nounits'],
                capture_output=True, text=True, check=True
            )
            
            gpus = []
            for line in result.stdout.strip().split('\n'):
                parts = [p.strip() for p in line.split(',')]
                gpus.append({
                    "index": parts[0],
                    "name": parts[1],
                    "utilization": parts[2],
                    "memory_used": parts[3],
                    "memory_total": parts[4]
                })
            return gpus
        except:
            return []
    
    def _get_recent_log_entries(self, n=15) -> List[str]:
        """Get last N log entries"""
        if not self.log_file.exists():
            return []
        
        with open(self.log_file, 'r') as f:
            lines = f.readlines()
        
        return lines[-n:]
    
    def _format_timestamp(self, iso_timestamp: str) -> str:
        """Format ISO timestamp to readable format"""
        if not iso_timestamp:
            return "N/A"
        
        try:
            dt = datetime.fromisoformat(iso_timestamp)
            return dt.strftime("%Y-%m-%d %H:%M:%S")
        except:
            return iso_timestamp
    
    def _calculate_duration(self, start_time: str) -> str:
        """Calculate duration from start time"""
        if not start_time:
            return "N/A"
        
        try:
            start = datetime.fromisoformat(start_time)
            now = datetime.now()
            delta = now - start
            
            hours = delta.seconds // 3600
            minutes = (delta.seconds % 3600) // 60
            
            if delta.days > 0:
                return f"{delta.days}d {hours}h"
            elif hours > 0:
                return f"{hours}h {minutes}m"
            else:
                return f"{minutes}m"
        except:
            return "N/A"
    
    def _get_container_metadata(self, container: str) -> Dict:
        """Get container metadata"""
        metadata_file = self.state_dir / "container-metadata" / f"{container}.json"
        if metadata_file.exists():
            with open(metadata_file, 'r') as f:
                return json.load(f)
        return {}
    
    def generate_markdown(self) -> str:
        """Generate markdown status report"""
        state = self._load_state()
        nvidia_info = self._get_nvidia_info()
        recent_logs = self._get_recent_log_entries(15)
        
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        md = f"# DS01 GPU Server Status\n\n"
        md += f"**Generated:** {now}\n"
        md += f"**Allocation Strategy:** {state.get('allocation_strategy', 'least_allocated')} (dynamic per-container)\n\n"
        
        # Summary
        total_containers = sum(len(g.get("containers", [])) for g in state["gpus"].values())
        total_gpus = len(state["gpus"])
        gpus_in_use = sum(1 for g in state["gpus"].values() if len(g.get("containers", [])) > 0)
        
        md += f"## Summary\n\n"
        md += f"- **Total GPUs:** {total_gpus}\n"
        md += f"- **GPUs in use:** {gpus_in_use}\n"
        md += f"- **Available GPUs:** {total_gpus - gpus_in_use}\n"
        md += f"- **Total containers with GPUs:** {total_containers}\n\n"
        
        # GPU Details
        md += f"## GPU Details\n\n"
        md += "| GPU | Model | Containers | Util | Memory | Status |\n"
        md += "|-----|-------|------------|------|--------|--------|\n"
        
        for gpu_id in sorted(state["gpus"].keys(), key=int):
            gpu_state = state["gpus"][gpu_id]
            
            # Get nvidia-smi info
            gpu_hw = next((g for g in nvidia_info if g["index"] == gpu_id), {})
            model = gpu_hw.get("name", "Unknown")[:25]
            util = gpu_hw.get("utilization", "?") + "%"
            memory = f"{gpu_hw.get('memory_used', '?')}/{gpu_hw.get('memory_total', '?')} MB"
            
            # Get allocation info
            containers = gpu_state.get("containers", [])
            container_count = len(containers)
            
            if container_count > 0:
                status = f"🔴 Active ({container_count})"
            else:
                status = "🟢 Available"
            
            md += f"| {gpu_id} | {model} | {container_count} | {util} | {memory} | {status} |\n"
        
        md += "\n"
        
        # Per-GPU container details
        md += "## Container Allocations\n\n"
        
        any_allocations = False
        for gpu_id in sorted(state["gpus"].keys(), key=int):
            gpu_state = state["gpus"][gpu_id]
            containers = gpu_state.get("containers", [])
            
            if containers:
                any_allocations = True
                md += f"### GPU {gpu_id}\n\n"
                md += "| Container | User | Allocated At | Duration |\n"
                md += "|-----------|------|--------------|----------|\n"
                
                for container in containers:
                    metadata = self._get_container_metadata(container)
                    user = metadata.get("user", "unknown")
                    allocated_at = self._format_timestamp(metadata.get("allocated_at", ""))
                    duration = self._calculate_duration(metadata.get("allocated_at", ""))
                    
                    md += f"| {container[:20]} | {user} | {allocated_at} | {duration} |\n"
                
                md += "\n"
        
        if not any_allocations:
            md += "*No containers currently allocated to GPUs*\n\n"
        
        # Per-user summary
        md += "## Allocations by User\n\n"
        
        user_gpus = {}
        for gpu_state in state["gpus"].values():
            for user, count in gpu_state.get("users", {}).items():
                user_gpus[user] = user_gpus.get(user, 0) + count
        
        if user_gpus:
            md += "| User | GPU Count | Containers |\n"
            md += "|------|-----------|------------|\n"
            
            for user in sorted(user_gpus.keys()):
                count = user_gpus[user]
                
                # Get containers for this user
                user_containers = []
                for gpu_state in state["gpus"].values():
                    for container in gpu_state.get("containers", []):
                        metadata = self._get_container_metadata(container)
                        if metadata.get("user") == user:
                            user_containers.append(container)
                
                container_list = ", ".join(c[:15] for c in user_containers)
                md += f"| {user} | {count} | {container_list} |\n"
        else:
            md += "*No GPUs currently allocated*\n"
        
        md += "\n"
        
        # Recent activity
        md += "## Recent Activity (Last 15 Events)\n\n"
        
        if recent_logs:
            md += "| Timestamp | Event | User | Container | GPU | Reason |\n"
            md += "|-----------|-------|------|-----------|-----|--------|\n"
            
            for line in recent_logs:
                parts = line.strip().split('|')
                if len(parts) >= 5:
                    timestamp = parts[0][-8:]  # Just time
                    event = parts[1]
                    user = parts[2][:15]
                    container = parts[3][:15]
                    gpu = parts[4]
                    reason = parts[5] if len(parts) > 5 else ""
                    md += f"| {timestamp} | {event} | {user} | {container} | {gpu} | {reason} |\n"
        else:
            md += "*No recent activity logged*\n"
        
        md += "\n"
        
        # Footer
        md += "---\n"
        md += f"*Auto-generated by DS01 GPU Status Dashboard*\n"
        md += f"*Allocation is dynamic: GPUs assigned on container start, released on stop*\n"
        
        return md
    
    def save_to_file(self, filename="gpu-status.md"):
        """Generate and save markdown to file"""
        md = self.generate_markdown()
        output_file = self.output_dir / filename
        
        with open(output_file, 'w') as f:
            f.write(md)
        
        return output_file
    
    def print_terminal(self):
        """Print simplified status to terminal"""
        state = self._load_state()
        nvidia_info = self._get_nvidia_info()
        
        print("\n" + "="*70)
        print("DS01 GPU SERVER STATUS (Dynamic Allocation)".center(70))
        print("="*70 + "\n")
        
        for gpu_id in sorted(state["gpus"].keys(), key=int):
            gpu_state = state["gpus"][gpu_id]
            gpu_hw = next((g for g in nvidia_info if g["index"] == gpu_id), {})
            
            containers = gpu_state.get("containers", [])
            container_count = len(containers)
            
            print(f"GPU {gpu_id}: {gpu_hw.get('name', 'Unknown')}")
            print(f"  Utilization: {gpu_hw.get('utilization', '?')}%")
            print(f"  Memory: {gpu_hw.get('memory_used', '?')}/{gpu_hw.get('memory_total', '?')} MB")
            
            if container_count > 0:
                print(f"  🔴 ACTIVE ({container_count} containers)")
                for container in containers:
                    metadata = self._get_container_metadata(container)
                    user = metadata.get("user", "unknown")
                    duration = self._calculate_duration(metadata.get("allocated_at", ""))
                    print(f"    - {container[:30]} ({user}, {duration})")
            else:
                print(f"  🟢 AVAILABLE")
            
            print()
        
        print("="*70)
        print("Allocation is dynamic: assigned on container start, released on stop")
        print("="*70 + "\n")


def main():
    import sys
    
    dashboard = GPUStatusDashboard()
    
    if len(sys.argv) > 1 and sys.argv[1] == "--markdown":
        # Generate markdown file
        output_file = dashboard.save_to_file()
        print(f"Generated: {output_file}")
    else:
        # Print to terminal
        dashboard.print_terminal()


if __name__ == '__main__':
    main()
