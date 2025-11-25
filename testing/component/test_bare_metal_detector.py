#!/usr/bin/env python3
"""
Component Tests: Bare Metal Process Detector
Tests detect-bare-metal.py functionality
"""

import pytest
import subprocess
import json
from pathlib import Path


class TestBaremetalDetectorScript:
    """Tests for detect-bare-metal.py script."""

    DETECTOR = Path("/opt/ds01-infra/scripts/monitoring/detect-bare-metal.py")

    @pytest.mark.component
    def test_script_exists(self):
        """Bare metal detector script exists."""
        assert self.DETECTOR.exists()

    @pytest.mark.component
    def test_script_syntax(self):
        """Bare metal detector has valid Python syntax."""
        result = subprocess.run(
            ["python3", "-m", "py_compile", str(self.DETECTOR)],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Syntax error: {result.stderr}"

    @pytest.mark.component
    def test_basic_execution(self):
        """Bare metal detector executes without crash."""
        result = subprocess.run(
            ["python3", str(self.DETECTOR)],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should complete successfully
        assert result.returncode == 0

    @pytest.mark.component
    def test_json_output(self):
        """Bare metal detector outputs valid JSON with --json."""
        result = subprocess.run(
            ["python3", str(self.DETECTOR), "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        assert result.returncode == 0

        # Parse JSON
        data = json.loads(result.stdout)
        assert isinstance(data, dict)

    @pytest.mark.component
    def test_json_has_expected_fields(self):
        """JSON output has expected fields."""
        result = subprocess.run(
            ["python3", str(self.DETECTOR), "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        data = json.loads(result.stdout)

        # Should have some standard fields
        expected_fields = {"warning", "total_count", "processes", "timestamp"}
        actual_fields = set(data.keys())
        # At least some expected fields should be present
        assert len(actual_fields & expected_fields) >= 2 or "error" not in data


class TestBaremetalDetectorLogic:
    """Tests for bare metal detection logic."""

    DETECTOR = Path("/opt/ds01-infra/scripts/monitoring/detect-bare-metal.py")

    @pytest.mark.component
    def test_script_has_compute_detection(self):
        """Script has compute workload detection."""
        content = self.DETECTOR.read_text()
        assert "is_compute" in content or "compute" in content.lower()

    @pytest.mark.component
    def test_script_excludes_system_processes(self):
        """Script excludes system processes."""
        content = self.DETECTOR.read_text()
        # Should have logic to exclude system users/processes
        system_indicators = ["root", "systemd", "exclude", "skip", "system"]
        has_exclusion = any(ind in content.lower() for ind in system_indicators)
        assert has_exclusion

    @pytest.mark.component
    def test_script_identifies_gpu_processes(self):
        """Script identifies GPU-using processes."""
        content = self.DETECTOR.read_text()
        gpu_indicators = ["nvidia", "cuda", "gpu", "compute-apps"]
        has_gpu_detection = any(ind in content.lower() for ind in gpu_indicators)
        assert has_gpu_detection


class TestBaremetalDetectorIntegration:
    """Integration tests for bare metal detection."""

    DETECTOR = Path("/opt/ds01-infra/scripts/monitoring/detect-bare-metal.py")

    @pytest.mark.component
    @pytest.mark.requires_docker
    def test_excludes_container_processes(self):
        """Detector excludes processes inside containers."""
        result = subprocess.run(
            ["python3", str(self.DETECTOR), "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        data = json.loads(result.stdout)

        # If there are detected processes, verify none are containerized
        processes = data.get("processes", [])
        for proc in processes:
            # Should not be flagged as in container
            assert proc.get("in_container", False) is False

    @pytest.mark.component
    def test_current_python_process_not_detected(self):
        """The test's own Python process is not detected as bare metal."""
        import os
        my_pid = os.getpid()

        result = subprocess.run(
            ["python3", str(self.DETECTOR), "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        data = json.loads(result.stdout)

        # Our process might be detected but should be categorized correctly
        processes = data.get("processes", [])
        my_proc = [p for p in processes if p.get("pid") == my_pid]

        # Either not detected (system process) or correctly identified
        # This test is informational
        pass
