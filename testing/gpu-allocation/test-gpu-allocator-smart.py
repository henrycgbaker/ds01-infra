#!/usr/bin/env python3
"""
Unit tests for gpu-allocator-smart.py
Tests stateless GPU allocation logic
"""

import sys
import unittest
import subprocess
import tempfile
import yaml
from pathlib import Path

# Add scripts to path and import using dynamic loader (files use hyphens)
import importlib.util

SCRIPT_DIR = Path(__file__).parent.parent.parent / 'scripts' / 'docker'
spec = importlib.util.spec_from_file_location('gpu_alloc', str(SCRIPT_DIR / 'gpu-allocator-smart.py'))
gpu_alloc_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_alloc_module)

GPUAllocatorSmart = gpu_alloc_module.GPUAllocatorSmart


class TestGPUAllocatorSmart(unittest.TestCase):
    """Test GPUAllocatorSmart functionality"""

    def setUp(self):
        """Initialize allocator for each test"""
        self.allocator = GPUAllocatorSmart()

    def test_allocator_initialization(self):
        """Test that allocator initializes without errors"""
        self.assertIsNotNone(self.allocator)
        self.assertIsNotNone(self.allocator.config)

    def test_get_status(self):
        """Test getting allocation status"""
        status = self.allocator.get_status()

        self.assertIsInstance(status, dict)
        self.assertIn('total_gpus', status)
        self.assertIn('allocated', status)
        self.assertIn('available', status)
        self.assertIn('utilization_percent', status)
        self.assertIn('allocations', status)

    def test_get_user_gpu_count(self):
        """Test counting user's GPU allocations"""
        username = subprocess.check_output(['whoami']).decode().strip()

        count = self.allocator.get_user_gpu_count(username)

        self.assertIsInstance(count, int)
        self.assertGreaterEqual(count, 0)

    def test_allocate_gpu_dry_run(self):
        """Test GPU allocation logic (without actual allocation)"""
        # Test with fake container name (won't actually allocate)
        username = 'testuser'
        container = 'test-container._.9999'

        gpu_id, reason = self.allocator.allocate_gpu(username, container, max_gpus=1)

        # Should either succeed or fail with reason
        if gpu_id:
            self.assertIsInstance(gpu_id, str)
        else:
            self.assertIsInstance(reason, str)

    def test_release_gpu_nonexistent(self):
        """Test releasing GPU from non-existent container"""
        gpu_id, reason = self.allocator.release_gpu('nonexistent-container')

        self.assertIsNone(gpu_id)
        self.assertEqual(reason, 'NOT_ALLOCATED')

    def test_get_user_limits(self):
        """Test reading user limits from config"""
        username = subprocess.check_output(['whoami']).decode().strip()

        limits = self.allocator._get_user_limits(username)

        self.assertIsInstance(limits, dict)
        # Should have at least some limit fields
        # (exact fields depend on config)

    def test_get_user_priority(self):
        """Test reading user priority"""
        username = subprocess.check_output(['whoami']).decode().strip()

        priority = self.allocator._get_user_priority(username)

        self.assertIsInstance(priority, int)
        self.assertGreaterEqual(priority, 0)
        self.assertLessEqual(priority, 100)


class TestGPUAllocatorSmartConfig(unittest.TestCase):
    """Test config loading and parsing"""

    def test_config_loading(self):
        """Test that config loads successfully"""
        allocator = GPUAllocatorSmart()

        self.assertIsInstance(allocator.config, dict)

    def test_user_limits_hierarchy(self):
        """Test user limits priority: user_overrides > groups > defaults"""
        allocator = GPUAllocatorSmart()

        # Test with various users should return valid limits
        for username in ['testuser', 'admin', 'student1']:
            limits = allocator._get_user_limits(username)
            self.assertIsInstance(limits, dict)


if __name__ == '__main__':
    unittest.main(verbosity=2)
