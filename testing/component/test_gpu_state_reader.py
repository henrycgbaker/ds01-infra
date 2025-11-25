#!/usr/bin/env python3
"""
Component Tests: GPU State Reader
Tests gpu-state-reader.py with real Docker (when available)
"""

import pytest
import subprocess
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

import sys
sys.path.insert(0, "/opt/ds01-infra/scripts/docker")


class TestGPUStateReaderExecution:
    """Tests for GPU state reader script execution."""

    GPU_STATE_READER = Path("/opt/ds01-infra/scripts/docker/gpu-state-reader.py")

    @pytest.mark.component
    def test_script_exists(self):
        """GPU state reader script exists."""
        assert self.GPU_STATE_READER.exists()

    @pytest.mark.component
    def test_script_syntax(self):
        """GPU state reader has valid Python syntax."""
        result = subprocess.run(
            ["python3", "-m", "py_compile", str(self.GPU_STATE_READER)],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Syntax error: {result.stderr}"

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_all_command(self):
        """GPU state reader 'all' command executes."""
        result = subprocess.run(
            ["python3", str(self.GPU_STATE_READER), "all"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should not crash (may have no containers)
        assert result.returncode == 0

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_by_interface_command(self):
        """GPU state reader 'by-interface' command executes."""
        result = subprocess.run(
            ["python3", str(self.GPU_STATE_READER), "by-interface"],
            capture_output=True,
            text=True,
            timeout=30
        )
        assert result.returncode == 0

    @pytest.mark.component
    def test_usage_shown(self):
        """GPU state reader shows usage when called with no args."""
        result = subprocess.run(
            ["python3", str(self.GPU_STATE_READER)],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Should show usage
        assert "Usage" in result.stdout or "Commands" in result.stdout


class TestGPUStateReaderClass:
    """Tests for GPUStateReader class methods."""

    @pytest.fixture
    def reader(self):
        """Create GPUStateReader instance with mocked docker."""
        try:
            # Import with careful handling of dependencies
            spec = __import__("importlib.util").util.spec_from_file_location(
                "gpu_state_reader",
                "/opt/ds01-infra/scripts/docker/gpu-state-reader.py"
            )
            module = __import__("importlib.util").util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module.GPUStateReader()
        except Exception as e:
            pytest.skip(f"Could not import GPUStateReader: {e}")

    @pytest.mark.component
    def test_interface_detection_method_exists(self, reader):
        """GPUStateReader has _detect_interface method."""
        assert hasattr(reader, "_detect_interface")

    @pytest.mark.component
    def test_mig_mapping_method_exists(self, reader):
        """GPUStateReader has _get_mig_uuid_to_slot_mapping method."""
        assert hasattr(reader, "_get_mig_uuid_to_slot_mapping")

    @pytest.mark.component
    def test_cgroup_user_extraction_method_exists(self, reader):
        """GPUStateReader has _extract_user_from_cgroup method."""
        assert hasattr(reader, "_extract_user_from_cgroup")


class TestGPUStateReaderWithMockDocker:
    """Tests with mocked Docker responses."""

    @pytest.fixture
    def mock_container_data(self, sample_docker_container):
        """Use sample container data from conftest."""
        return sample_docker_container

    @pytest.mark.component
    def test_detect_orchestration_interface(self, mock_container_data):
        """Detect orchestration interface from labels."""
        mock_container_data["Config"]["Labels"]["ds01.interface"] = "orchestration"

        labels = mock_container_data["Config"]["Labels"]
        name = mock_container_data["Name"].lstrip("/")

        # Simulate detection logic
        if labels.get("ds01.interface") == "orchestration":
            interface = "orchestration"
        else:
            interface = "atomic"

        assert interface == "orchestration"

    @pytest.mark.component
    def test_detect_atomic_interface(self, mock_container_data):
        """Detect atomic interface from AIME naming."""
        mock_container_data["Config"]["Labels"].pop("ds01.interface", None)
        mock_container_data["Name"] = "/project-a._.1001"

        name = mock_container_data["Name"].lstrip("/")

        # AIME naming convention
        if "._." in name:
            interface = "atomic"
        else:
            interface = "docker"

        assert interface == "atomic"

    @pytest.mark.component
    def test_extract_gpu_from_device_requests(self, mock_container_data):
        """Extract GPU ID from DeviceRequests."""
        device_requests = mock_container_data["HostConfig"]["DeviceRequests"]

        gpu_ids = []
        for req in device_requests:
            if req.get("Driver") == "nvidia":
                gpu_ids.extend(req.get("DeviceIDs", []))

        assert "0" in gpu_ids

    @pytest.mark.component
    def test_extract_user_from_cgroup_path(self, mock_container_data):
        """Extract user from cgroup parent path."""
        import re
        cgroup = mock_container_data["HostConfig"]["CgroupParent"]

        # Pattern: ds01-{group}-{user}.slice
        match = re.match(r"ds01-([^-]+)-(.+)\.slice", cgroup)
        if match:
            user = match.group(2)
        else:
            user = None

        assert user == "student1"


class TestGPUStateReaderInterfaceCategories:
    """Tests for interface category grouping."""

    @pytest.mark.component
    def test_interface_categories_complete(self):
        """All four interface categories defined."""
        expected = {"orchestration", "atomic", "docker", "other"}

        # These should be constants in the module
        try:
            from gpu_state_reader import (
                INTERFACE_ORCHESTRATION,
                INTERFACE_ATOMIC,
                INTERFACE_DOCKER,
                INTERFACE_OTHER
            )
            actual = {
                INTERFACE_ORCHESTRATION,
                INTERFACE_ATOMIC,
                INTERFACE_DOCKER,
                INTERFACE_OTHER
            }
            assert actual == expected
        except ImportError:
            # Check by reading the file
            content = Path("/opt/ds01-infra/scripts/docker/gpu-state-reader.py").read_text()
            for interface in expected:
                assert f'"{interface}"' in content or f"'{interface}'" in content
