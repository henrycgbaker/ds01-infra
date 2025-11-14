#!/usr/bin/env python3
"""
Unit Test: GPU Allocator MIG Detection
Tests that MIG detection works correctly with and without actual MIG partitions
"""

import subprocess
import sys
sys.path.insert(0, '/opt/ds01-infra/scripts/docker')


def test_mig_detection_no_partitions():
    """Test MIG detection when mode is enabled but no partitions configured"""
    print("━━━ Test: MIG Detection (No Partitions) ━━━\n")

    # Check hardware state
    result = subprocess.run(
        ['nvidia-smi', '--query-gpu=index,mig.mode.current', '--format=csv,noheader'],
        capture_output=True, text=True
    )

    print("Hardware state:")
    for line in result.stdout.strip().split('\n'):
        gpu_id, mig_mode = line.split(',')
        print(f"  GPU {gpu_id.strip()}: MIG {mig_mode.strip()}")

    # Import allocator with test paths
    import os
    exec(open('/opt/ds01-infra/scripts/docker/gpu_allocator.py').read().split('def main()')[0])

    test_dir = os.path.expanduser('~/test-gpu-allocator-unit')
    os.makedirs(f"{test_dir}/state", exist_ok=True)
    os.makedirs(f"{test_dir}/logs", exist_ok=True)

    manager = GPUAllocationManager(
        state_dir=f"{test_dir}/state",
        log_dir=f"{test_dir}/logs"
    )

    # Load initialized state
    import json
    with open(manager.state_file) as f:
        state = json.load(f)

    print(f"\nAllocator state:")
    print(f"  MIG enabled in config: {state.get('mig_enabled')}")
    print(f"  Detected GPUs: {len(state.get('gpus', {}))}")
    print(f"  GPU type: {list(state['gpus'].values())[0]['type']}")

    # Verify correct behavior
    assert len(state['gpus']) == 4, f"Expected 4 GPUs, got {len(state['gpus'])}"
    assert all(gpu['type'] == 'physical_gpu' for gpu in state['gpus'].values()), \
        "Expected all GPUs to be physical_gpu type"

    print("\n✓ Test passed: Allocator correctly uses physical GPU mode when no MIG partitions exist")

    # Cleanup
    import shutil
    shutil.rmtree(test_dir, ignore_errors=True)


if __name__ == '__main__':
    test_mig_detection_no_partitions()
