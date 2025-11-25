#!/usr/bin/env python3
"""
Unit tests for gpu-availability-checker.py
Tests GPU availability calculation and allocation suggestions
"""

import sys
import unittest
import subprocess
from pathlib import Path

# Add scripts to path and import using dynamic loader (files use hyphens)
import importlib.util

SCRIPT_DIR = Path(__file__).parent.parent.parent / 'scripts' / 'docker'
spec = importlib.util.spec_from_file_location('gpu_avail', str(SCRIPT_DIR / 'gpu-availability-checker.py'))
gpu_avail_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_avail_module)

GPUAvailabilityChecker = gpu_avail_module.GPUAvailabilityChecker


class TestGPUAvailabilityChecker(unittest.TestCase):
    """Test GPUAvailabilityChecker functionality"""

    def setUp(self):
        """Initialize checker for each test"""
        self.checker = GPUAvailabilityChecker()

    def test_checker_initialization(self):
        """Test that checker initializes without errors"""
        self.assertIsNotNone(self.checker)

    def test_get_available_gpus(self):
        """Test getting available GPUs"""
        available = self.checker.get_available_gpus()
        self.assertIsInstance(available, dict)

        # Each available GPU should have required fields
        for gpu_slot, info in available.items():
            self.assertIn('uuid', info)
            self.assertIn('profile', info)

    def test_get_allocation_summary(self):
        """Test getting allocation summary"""
        summary = self.checker.get_allocation_summary()

        self.assertIsInstance(summary, dict)
        self.assertIn('total_gpus', summary)
        self.assertIn('allocated', summary)
        self.assertIn('available', summary)
        self.assertIn('utilization_percent', summary)

        # Validate numbers make sense
        self.assertGreaterEqual(summary['total_gpus'], 0)
        self.assertGreaterEqual(summary['allocated'], 0)
        self.assertGreaterEqual(summary['available'], 0)
        self.assertGreaterEqual(summary['utilization_percent'], 0)
        self.assertLessEqual(summary['utilization_percent'], 100)

        # Total should equal allocated + available
        self.assertEqual(
            summary['total_gpus'],
            summary['allocated'] + summary['available']
        )

    def test_get_user_available_gpus(self):
        """Test checking availability for specific user"""
        # Get current user
        username = subprocess.check_output(['whoami']).decode().strip()

        result = self.checker.get_user_available_gpus(username, max_gpus=2)

        self.assertIsInstance(result, dict)
        self.assertIn('can_allocate', result)
        self.assertIn('user_current_count', result)
        self.assertIn('available_gpus', result)

        if not result['can_allocate']:
            self.assertIn('reason', result)

    def test_suggest_gpu_for_user(self):
        """Test GPU suggestion for allocation"""
        username = subprocess.check_output(['whoami']).decode().strip()

        result = self.checker.suggest_gpu_for_user(username, max_gpus=2, priority=50)

        self.assertIsInstance(result, dict)
        self.assertIn('success', result)

        if result['success']:
            self.assertIn('gpu_slot', result)
            self.assertIn('gpu_uuid', result)
            self.assertIn('profile', result)
        else:
            self.assertIn('error', result)


class TestGPUAvailabilityCheckerEdgeCases(unittest.TestCase):
    """Test edge cases"""

    def setUp(self):
        self.checker = GPUAvailabilityChecker()

    def test_user_at_limit(self):
        """Test when user is at GPU limit"""
        # Test with max_gpus=0 (should never be able to allocate)
        result = self.checker.get_user_available_gpus('testuser', max_gpus=0)

        self.assertFalse(result['can_allocate'])
        # Reason should mention either 'limit' or '0/0'
        self.assertTrue(
            'limit' in result['reason'].lower() or '0/0' in result['reason'],
            f"Expected reason to mention limit, got: {result['reason']}"
        )

    def test_unlimited_gpus(self):
        """Test with unlimited GPU allocation (None)"""
        result = self.checker.get_user_available_gpus('testuser', max_gpus=None)

        # Should be able to allocate if any GPUs available
        self.assertIsInstance(result['can_allocate'], bool)


if __name__ == '__main__':
    unittest.main(verbosity=2)
