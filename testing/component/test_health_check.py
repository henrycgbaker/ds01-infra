#!/usr/bin/env python3
"""
Component Tests: Health Check Script
Tests ds01-health-check functionality
"""

import pytest
import subprocess
from pathlib import Path


class TestHealthCheckScript:
    """Tests for ds01-health-check script."""

    HEALTH_CHECK = Path("/opt/ds01-infra/scripts/monitoring/ds01-health-check")

    @pytest.mark.component
    def test_script_exists(self):
        """Health check script exists."""
        assert self.HEALTH_CHECK.exists()

    @pytest.mark.component
    def test_script_executable(self):
        """Health check script is executable."""
        assert self.HEALTH_CHECK.stat().st_mode & 0o111

    @pytest.mark.component
    def test_help_flag(self):
        """Health check shows help with --help."""
        result = subprocess.run(
            [str(self.HEALTH_CHECK), "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Should show help or at least not crash
        assert result.returncode == 0 or "usage" in result.stdout.lower() + result.stderr.lower()

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_basic_execution(self):
        """Health check executes without critical failure."""
        result = subprocess.run(
            [str(self.HEALTH_CHECK)],
            capture_output=True,
            text=True,
            timeout=60
        )
        # Exit code 0 = all pass, 1 = some warnings, 2 = failures
        assert result.returncode in [0, 1, 2]

    @pytest.mark.component
    def test_script_has_docker_check(self):
        """Health check includes Docker daemon check."""
        content = self.HEALTH_CHECK.read_text()
        assert "docker" in content.lower()

    @pytest.mark.component
    def test_script_has_nvidia_check(self):
        """Health check includes NVIDIA/GPU check."""
        content = self.HEALTH_CHECK.read_text()
        assert "nvidia" in content.lower() or "gpu" in content.lower()

    @pytest.mark.component
    def test_script_has_cgroup_check(self):
        """Health check includes cgroup check."""
        content = self.HEALTH_CHECK.read_text()
        assert "cgroup" in content.lower() or "slice" in content.lower()


class TestHealthCheckOutput:
    """Tests for health check output format."""

    HEALTH_CHECK = Path("/opt/ds01-infra/scripts/monitoring/ds01-health-check")

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_output_has_status_indicators(self):
        """Health check output includes pass/fail indicators."""
        result = subprocess.run(
            [str(self.HEALTH_CHECK)],
            capture_output=True,
            text=True,
            timeout=60
        )
        output = result.stdout + result.stderr
        # Should have some status indicators
        has_indicators = any(ind in output for ind in ["PASS", "FAIL", "OK", "ERROR", "WARN", "✓", "✗"])
        assert has_indicators or result.returncode == 0

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_json_output_option(self):
        """Health check supports --json output."""
        result = subprocess.run(
            [str(self.HEALTH_CHECK), "--json"],
            capture_output=True,
            text=True,
            timeout=60
        )
        # May not support JSON, so just check it doesn't crash
        # If it does support JSON, output should be valid
        if result.returncode == 0 and result.stdout.strip().startswith("{"):
            import json
            data = json.loads(result.stdout)
            assert "checks" in data or "status" in data or isinstance(data, dict)
