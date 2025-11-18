#!/usr/bin/env python3
"""
Unit tests for gpu-state-reader.py
Tests reading GPU allocations from Docker containers
"""

import sys
import unittest
import subprocess
import json
from pathlib import Path

# Add scripts to path and import using dynamic loader (files use hyphens)
import importlib.util

SCRIPT_DIR = Path(__file__).parent.parent.parent / 'scripts' / 'docker'
spec = importlib.util.spec_from_file_location('gpu_state_reader', str(SCRIPT_DIR / 'gpu-state-reader.py'))
gpu_state_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_state_module)

GPUStateReader = gpu_state_module.GPUStateReader


class TestGPUStateReader(unittest.TestCase):
    """Test GPUStateReader functionality"""

    def setUp(self):
        """Initialize reader for each test"""
        self.reader = GPUStateReader()

    def test_reader_initialization(self):
        """Test that reader initializes without errors"""
        self.assertIsNotNone(self.reader)

    def test_get_all_allocations(self):
        """Test getting all GPU allocations"""
        allocations = self.reader.get_all_allocations()
        self.assertIsInstance(allocations, dict)

        # Each allocation should have required fields
        for gpu_slot, info in allocations.items():
            self.assertIn('uuid', info)
            self.assertIn('containers', info)
            self.assertIsInstance(info['containers'], list)

    def test_get_user_allocations(self):
        """Test getting allocations for specific user"""
        # Get current user
        username = subprocess.check_output(['whoami']).decode().strip()

        user_allocs = self.reader.get_user_allocations(username)
        self.assertIsInstance(user_allocs, list)

        # Each allocation should have required fields
        for alloc in user_allocs:
            self.assertIn('gpu_slot', alloc)
            self.assertIn('container', alloc)
            self.assertIn('running', alloc)

    def test_extract_gpu_from_container(self):
        """Test GPU extraction from container info"""
        # Get a container to test with
        try:
            result = subprocess.run(
                ['docker', 'ps', '-a', '--format', '{{.Names}}', '--filter', 'label=ds01.managed=true'],
                capture_output=True,
                text=True,
                check=True
            )

            containers = [c for c in result.stdout.strip().split('\n') if c]

            if containers:
                container_name = containers[0]

                # Get container info
                inspect_result = subprocess.run(
                    ['docker', 'inspect', container_name],
                    capture_output=True,
                    text=True,
                    check=True
                )

                container_info = json.loads(inspect_result.stdout)[0]
                gpu_info = self.reader._extract_gpu_from_container(container_info)

                # If container has GPU, validate structure
                if gpu_info:
                    self.assertIn('gpu_slot', gpu_info)
                    self.assertIn('gpu_uuid', gpu_info)
            else:
                self.skipTest("No DS01-managed containers found")

        except subprocess.CalledProcessError:
            self.skipTest("Docker not available or no containers")

    def test_get_container_gpu(self):
        """Test getting GPU for specific container"""
        # Get a container
        try:
            result = subprocess.run(
                ['docker', 'ps', '-a', '--format', '{{.Names}}', '--filter', 'label=ds01.managed=true'],
                capture_output=True,
                text=True,
                check=True
            )

            containers = [c for c in result.stdout.strip().split('\n') if c]

            if containers:
                container_name = containers[0]
                gpu_info = self.reader.get_container_gpu(container_name)

                # Container may or may not have GPU
                if gpu_info:
                    self.assertIn('gpu_slot', gpu_info)
                    self.assertIn('user', gpu_info)
            else:
                self.skipTest("No DS01-managed containers found")

        except subprocess.CalledProcessError:
            self.skipTest("Docker not available")


class TestGPUStateReaderEdgeCases(unittest.TestCase):
    """Test edge cases and error handling"""

    def setUp(self):
        self.reader = GPUStateReader()

    def test_nonexistent_container(self):
        """Test querying non-existent container"""
        result = self.reader.get_container_gpu('nonexistent-container-xyz')
        self.assertIsNone(result)

    def test_empty_user_allocations(self):
        """Test user with no allocations"""
        allocs = self.reader.get_user_allocations('nonexistent-user-xyz')
        self.assertIsInstance(allocs, list)
        self.assertEqual(len(allocs), 0)


if __name__ == '__main__':
    # Run tests with verbose output
    unittest.main(verbosity=2)
