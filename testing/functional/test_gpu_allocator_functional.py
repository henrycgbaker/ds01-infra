#!/usr/bin/env python3
"""
E2E Test: GPU Allocator
Tests full allocation workflow: allocate, check counts, release
"""

import sys
import os
import json
sys.path.insert(0, '/opt/ds01-infra/scripts/docker')

# Load GPU allocator class
exec(open('/opt/ds01-infra/scripts/docker/gpu_allocator.py').read().split('def main()')[0])

def test_gpu_allocation_workflow():
    """Test complete GPU allocation workflow"""

    # Setup test environment
    test_dir = os.path.expanduser('~/test-gpu-allocator-e2e')
    os.makedirs(f"{test_dir}/state", exist_ok=True)
    os.makedirs(f"{test_dir}/logs", exist_ok=True)

    manager = GPUAllocationManager(
        state_dir=f"{test_dir}/state",
        log_dir=f"{test_dir}/logs"
    )

    print("━━━ E2E GPU Allocator Test ━━━\n")

    # Test 1: Allocate single GPU for student (low priority)
    print("Test 1: Allocate GPU for student (priority=10)")
    gpu1, status1 = manager.allocate_gpu("student1", "student-container._.1001", max_gpus=1, priority=10)
    assert status1 == "SUCCESS", f"Expected SUCCESS, got {status1}"
    print(f"  ✓ GPU {gpu1}: {status1}\n")

    # Test 2: Allocate multiple GPUs for admin (high priority)
    print("Test 2: Allocate 2 GPUs for admin (priority=90)")
    gpu2, status2 = manager.allocate_gpu("admin", "admin-container._.2001", max_gpus=2, priority=90)
    assert status2 == "SUCCESS", f"Expected SUCCESS, got {status2}"
    print(f"  ✓ GPU {gpu2}: {status2}\n")

    # Test 3: Verify GPU counts
    print("Test 3: Check GPU counts")
    student_count = manager.get_user_gpu_count('student1')
    admin_count = manager.get_user_gpu_count('admin')
    assert student_count == 1, f"Expected student1 to have 1 GPU, got {student_count}"
    assert admin_count == 1, f"Expected admin to have 1 GPU, got {admin_count}"
    print(f"  ✓ student1: {student_count} GPU")
    print(f"  ✓ admin: {admin_count} GPU\n")

    # Test 4: Release GPU
    print("Test 4: Release student container")
    manager.release_gpu("student-container._.1001")
    student_count_after = manager.get_user_gpu_count('student1')
    assert student_count_after == 0, f"Expected student1 to have 0 GPUs after release, got {student_count_after}"
    print(f"  ✓ Released (student1 now has {student_count_after} GPUs)\n")

    # Test 5: Verify final state
    print("Test 5: Verify final state")
    with open(manager.state_file) as f:
        state = json.load(f)

    total_allocated = sum(len(gpu['containers']) for gpu in state['gpus'].values())
    assert total_allocated == 1, f"Expected 1 allocated GPU, got {total_allocated}"
    print(f"  ✓ Total allocated GPUs: {total_allocated}")
    print(f"  ✓ GPU type: {list(state['gpus'].values())[0]['type']}\n")

    # Cleanup
    import shutil
    shutil.rmtree(test_dir, ignore_errors=True)

    print("━━━ All Tests Passed ━━━")


if __name__ == '__main__':
    test_gpu_allocation_workflow()
