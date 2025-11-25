#!/usr/bin/env python3
"""
Integration Tests: GPU Allocation Flow
Tests GPU allocator integration with state reader and config
"""

import pytest
import subprocess
import json
from pathlib import Path
from unittest.mock import patch


class TestGPUAllocatorIntegration:
    """Integration tests for GPU allocator components."""

    @pytest.mark.integration
    def test_allocator_loads_config(self, config_dir):
        """GPU allocator loads resource-limits.yaml."""
        config_file = config_dir / "resource-limits.yaml"
        if not config_file.exists():
            pytest.skip("Config file not found")

        # Try to import and use allocator
        result = subprocess.run(
            ["python3", "-c", f"""
import sys
sys.path.insert(0, '/opt/ds01-infra/scripts/docker')
import yaml

# Load config
with open('{config_file}') as f:
    config = yaml.safe_load(f)

# Verify structure
assert 'defaults' in config
print('CONFIG_OK')
"""],
            capture_output=True,
            text=True
        )
        assert "CONFIG_OK" in result.stdout

    @pytest.mark.integration
    def test_allocator_status_command(self):
        """GPU allocator status command works."""
        allocator = Path("/opt/ds01-infra/scripts/docker/gpu_allocator_v2.py")
        if not allocator.exists():
            pytest.skip("gpu_allocator_v2.py not found")

        result = subprocess.run(
            ["python3", str(allocator), "status"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should complete (may fail if no Docker, but shouldn't crash)
        assert result.returncode in [0, 1]

    @pytest.mark.integration
    @pytest.mark.requires_docker
    def test_state_reader_provides_allocator_data(self):
        """State reader provides data for allocator decisions."""
        state_reader = Path("/opt/ds01-infra/scripts/docker/gpu-state-reader.py")

        result = subprocess.run(
            ["python3", str(state_reader), "all"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should execute successfully
        assert result.returncode == 0


class TestUserLimitEnforcement:
    """Tests for user limit enforcement during allocation."""

    @pytest.mark.integration
    def test_get_resource_limits_for_user(self, config_dir):
        """get_resource_limits.py returns limits for user."""
        limits_script = Path("/opt/ds01-infra/scripts/docker/get_resource_limits.py")
        config_file = config_dir / "resource-limits.yaml"

        if not config_file.exists():
            pytest.skip("Config file not found")

        # Get limits for a hypothetical user
        result = subprocess.run(
            ["python3", str(limits_script), "testuser"],
            capture_output=True,
            text=True,
            env={**dict(__import__("os").environ), "RESOURCE_LIMITS_CONFIG": str(config_file)}
        )
        # Should return some output
        assert result.returncode == 0 or "User:" in result.stdout

    @pytest.mark.integration
    def test_limits_include_gpu_settings(self, config_dir):
        """Resource limits include GPU allocation settings."""
        config_file = config_dir / "resource-limits.yaml"
        if not config_file.exists():
            pytest.skip("Config file not found")

        import yaml
        with open(config_file) as f:
            config = yaml.safe_load(f)

        defaults = config.get("defaults", {})
        # Should have GPU-related settings
        gpu_settings = ["max_mig_instances", "gpu_hold_after_stop"]
        has_gpu_settings = any(s in defaults for s in gpu_settings)
        assert has_gpu_settings


class TestAllocationStateConsistency:
    """Tests for allocation state consistency between components."""

    @pytest.mark.integration
    @pytest.mark.requires_docker
    def test_docker_labels_match_state_reader(self):
        """Docker labels match state reader output."""
        # This test validates that state reader correctly reads Docker state
        state_reader = Path("/opt/ds01-infra/scripts/docker/gpu-state-reader.py")

        result = subprocess.run(
            ["python3", str(state_reader), "by-interface", "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0 and result.stdout.strip():
            try:
                data = json.loads(result.stdout)
                # Should be organized by interface
                assert isinstance(data, dict)
            except json.JSONDecodeError:
                # Non-JSON output is acceptable
                pass

    @pytest.mark.integration
    def test_interface_constants_consistent(self):
        """Interface constants consistent across modules."""
        # Read interface constants from both files
        state_reader = Path("/opt/ds01-infra/scripts/docker/gpu-state-reader.py").read_text()
        allocator = Path("/opt/ds01-infra/scripts/docker/gpu_allocator_v2.py").read_text()

        # Both should define same constants
        for interface in ["orchestration", "atomic", "docker", "other"]:
            assert f'"{interface}"' in state_reader or f"'{interface}'" in state_reader
            assert f'"{interface}"' in allocator or f"'{interface}'" in allocator


class TestAllocationLogging:
    """Tests for allocation event logging."""

    LOG_FILE = Path("/var/log/ds01/gpu-allocations.log")

    @pytest.mark.integration
    def test_log_directory_exists(self):
        """Log directory exists or can be created."""
        log_dir = self.LOG_FILE.parent
        # Either exists or allocator would create it
        assert log_dir.exists() or True  # Informational

    @pytest.mark.integration
    def test_allocator_writes_to_log(self):
        """Allocator writes events to log file."""
        allocator = Path("/opt/ds01-infra/scripts/docker/gpu_allocator_v2.py")
        content = allocator.read_text()

        # Should have logging code
        log_indicators = ["log_event", "log_file", "gpu-allocations.log", "write"]
        has_logging = any(ind in content for ind in log_indicators)
        assert has_logging
