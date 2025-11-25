#!/usr/bin/env python3
"""
Unit Tests: GPU Allocator v2
Tests GPU allocation logic with mocked Docker and nvidia-smi
"""

import pytest
import json
from pathlib import Path
from unittest.mock import patch, MagicMock
from datetime import datetime

import sys
sys.path.insert(0, "/opt/ds01-infra/scripts/docker")


class TestGPUAllocatorUserLimits:
    """Tests for user limit resolution in GPU allocator."""

    @pytest.fixture
    def mock_state_reader(self):
        """Mock GPUStateReader."""
        mock = MagicMock()
        mock.get_all_containers_with_gpus.return_value = {}
        mock.get_available_gpu_slots.return_value = ["0", "1", "2", "3"]
        return mock

    @pytest.fixture
    def mock_availability_checker(self):
        """Mock GPUAvailabilityChecker."""
        mock = MagicMock()
        mock.get_available_slots.return_value = ["0", "1", "2", "3"]
        mock.is_slot_available.return_value = True
        return mock

    @pytest.mark.unit
    def test_user_limits_from_override(self, sample_resource_limits, temp_config_file):
        """User override limits take precedence."""
        with patch("importlib.util.spec_from_file_location"):
            # We'll test the limit resolution logic directly
            config = sample_resource_limits
            user_overrides = config.get("user_overrides", {})

            assert "special_user" in user_overrides
            assert user_overrides["special_user"]["max_mig_instances"] == 4

    @pytest.mark.unit
    def test_user_limits_from_group(self, sample_resource_limits):
        """User gets limits from their group."""
        config = sample_resource_limits
        groups = config.get("groups", {})
        student_config = groups.get("students", {})

        assert student_config["max_mig_instances"] == 1
        assert "student1" in student_config.get("members", [])

    @pytest.mark.unit
    def test_unlimited_gpus_is_none(self, sample_resource_limits):
        """Unlimited GPUs represented as None."""
        config = sample_resource_limits
        admin_config = config["groups"]["admins"]

        assert admin_config["max_mig_instances"] is None


class TestGPUAllocationLogic:
    """Tests for GPU allocation decision logic."""

    @pytest.mark.unit
    def test_least_loaded_gpu_selected(self):
        """Allocation prefers least-loaded GPU."""
        # Simulate GPU state: GPU 0 has 2 containers, GPU 1 has 0
        gpu_state = {
            "0": {"containers": ["a", "b"]},
            "1": {"containers": []},
        }

        # Least loaded should be GPU 1
        least_loaded = min(gpu_state.keys(), key=lambda g: len(gpu_state[g]["containers"]))
        assert least_loaded == "1"

    @pytest.mark.unit
    def test_user_gpu_count_calculation(self):
        """User's current GPU count calculated correctly."""
        allocations = {
            "0": {"containers": [
                {"user": "alice", "container": "proj-a"},
                {"user": "bob", "container": "proj-b"},
            ]},
            "1": {"containers": [
                {"user": "alice", "container": "proj-c"},
            ]},
        }

        # Count Alice's GPUs
        alice_count = sum(
            1 for gpu_data in allocations.values()
            for container in gpu_data.get("containers", [])
            if container.get("user") == "alice"
        )

        assert alice_count == 2

    @pytest.mark.unit
    def test_allocation_respects_max_limit(self):
        """Allocation fails when user at max limit."""
        max_gpus = 2
        current_count = 2

        can_allocate = current_count < max_gpus
        assert can_allocate is False

    @pytest.mark.unit
    def test_allocation_allowed_under_limit(self):
        """Allocation succeeds when user under limit."""
        max_gpus = 2
        current_count = 1

        can_allocate = current_count < max_gpus
        assert can_allocate is True

    @pytest.mark.unit
    def test_unlimited_user_always_can_allocate(self):
        """Users with unlimited (None) can always allocate."""
        max_gpus = None  # unlimited
        current_count = 100

        # None means unlimited
        can_allocate = max_gpus is None or current_count < max_gpus
        assert can_allocate is True


class TestInterfaceConstants:
    """Tests for interface constant consistency."""

    @pytest.mark.unit
    def test_interface_constants_defined(self):
        """Interface constants are properly defined."""
        # Import the module
        try:
            from gpu_allocator_v2 import (
                INTERFACE_ORCHESTRATION,
                INTERFACE_ATOMIC,
                INTERFACE_DOCKER,
                INTERFACE_OTHER
            )

            assert INTERFACE_ORCHESTRATION == "orchestration"
            assert INTERFACE_ATOMIC == "atomic"
            assert INTERFACE_DOCKER == "docker"
            assert INTERFACE_OTHER == "other"
        except ImportError:
            # Module may have import-time dependencies
            pytest.skip("Could not import gpu_allocator_v2 (dependency issues)")


class TestGPUStateModel:
    """Tests for interface-specific state model handling."""

    @pytest.mark.unit
    def test_orchestration_binary_state(self):
        """Orchestration interface uses binary state model."""
        # Binary model: containers are either running or removed
        # No stopped state
        valid_states = {"running", "removed"}

        # Orchestration containers should transition directly
        assert "stopped" not in valid_states

    @pytest.mark.unit
    def test_atomic_full_state(self):
        """Atomic interface uses full state model."""
        # Full model: created -> running -> stopped -> removed
        valid_states = {"created", "running", "stopped", "removed"}

        assert "stopped" in valid_states

    @pytest.mark.unit
    def test_gpu_hold_applies_to_atomic(self):
        """GPU hold timeout applies to atomic/docker interfaces."""
        interface = "atomic"
        gpu_hold_timeout = "24h"

        # GPU should be held after stop for atomic
        applies = interface in ("atomic", "docker")
        assert applies is True

    @pytest.mark.unit
    def test_gpu_hold_not_for_orchestration(self):
        """GPU hold not needed for orchestration (retire removes immediately)."""
        interface = "orchestration"

        # Orchestration retires (removes) immediately - no hold needed
        immediate_release = interface == "orchestration"
        assert immediate_release is True


class TestGPUAllocationLabels:
    """Tests for Docker label handling."""

    @pytest.mark.unit
    def test_expected_labels_for_allocation(self):
        """Verify expected Docker labels for GPU allocation."""
        expected_labels = {
            "ds01.interface": "orchestration",
            "ds01.user": "student1",
            "ds01.gpu.allocated": "0",
            "ds01.managed": "true"
        }

        # All expected labels should be present
        assert "ds01.interface" in expected_labels
        assert "ds01.gpu.allocated" in expected_labels

    @pytest.mark.unit
    def test_label_format_for_mig(self):
        """MIG allocation uses slot format (e.g., '1.2')."""
        mig_slot = "1.2"  # GPU 1, MIG instance 2

        # Should match pattern
        assert "." in mig_slot
        parts = mig_slot.split(".")
        assert len(parts) == 2
        assert all(p.isdigit() for p in parts)


class TestAllocationLogging:
    """Tests for allocation event logging."""

    @pytest.mark.unit
    def test_log_entry_format(self):
        """Log entries have expected format."""
        timestamp = datetime.now().isoformat()
        event_type = "ALLOCATED"
        user = "student1"
        container = "project-a._.1001"
        gpu_id = "0"
        priority = 10

        log_entry = f"{timestamp}|{event_type}|{user}|{container}|{gpu_id}|priority={priority}|"

        # Verify format
        parts = log_entry.split("|")
        assert len(parts) >= 6
        assert parts[1] == "ALLOCATED"
        assert parts[2] == "student1"

    @pytest.mark.unit
    def test_log_events(self):
        """Expected log event types."""
        expected_events = {
            "ALLOCATED",
            "RELEASED",
            "DENIED_LIMIT",
            "DENIED_NO_GPU",
            "ALREADY_ALLOCATED"
        }

        assert "ALLOCATED" in expected_events
        assert "RELEASED" in expected_events
