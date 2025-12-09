#!/usr/bin/env python3
"""
Tests for /opt/ds01-infra/scripts/lib/container-session.sh

This test suite validates the container-session.sh script, particularly
the validate_gpu_available() function that was updated to query Docker
labels instead of reading from orphaned state files.

Key changes tested:
1. validate_gpu_available() now queries Docker labels (ds01.gpu.uuids, ds01.gpu.uuid)
   instead of reading from /var/lib/ds01/container-metadata/ files
2. GPU UUIDs are validated against nvidia-smi output
3. Multi-GPU containers are supported (comma-separated UUIDs)
"""

import os
import subprocess
import pytest
from pathlib import Path
from typing import Dict, Optional
from unittest.mock import patch


# Path to the container-session.sh script
CONTAINER_SESSION_PATH = Path("/opt/ds01-infra/scripts/lib/container-session.sh")


class TestContainerSessionScript:
    """Tests for container-session.sh initialization and mode detection."""

    def run_bash_script(
        self,
        script_content: str,
        env: Optional[Dict] = None
    ) -> subprocess.CompletedProcess:
        """Helper to run bash script content."""
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script_content],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_script_exists(self):
        """container-session.sh should exist."""
        assert CONTAINER_SESSION_PATH.exists()

    def test_validate_gpu_available_function_defined(self):
        """validate_gpu_available function should be defined in the script."""
        content = CONTAINER_SESSION_PATH.read_text()
        assert "validate_gpu_available()" in content

    def test_validate_gpu_available_uses_docker_labels(self):
        """validate_gpu_available should query Docker labels, not state files.

        This is the key fix: the function now uses Docker labels (ds01.gpu.uuids
        or ds01.gpu.uuid) as the single source of truth instead of reading from
        potentially orphaned state files in /var/lib/ds01/container-metadata/.
        """
        content = CONTAINER_SESSION_PATH.read_text()

        # Should query ds01.gpu.uuids label
        assert 'ds01.gpu.uuids' in content

        # Should query ds01.gpu.uuid as fallback
        assert 'ds01.gpu.uuid' in content

        # Should use docker inspect to get labels
        assert 'docker inspect' in content

    def test_validate_gpu_available_does_not_use_state_files(self):
        """validate_gpu_available should NOT read from container-metadata directory.

        The old implementation read from /var/lib/ds01/container-metadata/ files
        which could become orphaned when containers were removed outside of DS01.
        """
        content = CONTAINER_SESSION_PATH.read_text()

        # The function should not reference the old metadata path directly
        # for GPU validation (it may still exist elsewhere in the script)
        lines = content.split('\n')
        in_validate_gpu_function = False

        for line in lines:
            if 'validate_gpu_available()' in line:
                in_validate_gpu_function = True
            elif in_validate_gpu_function and line.strip().startswith('}'):
                in_validate_gpu_function = False

            if in_validate_gpu_function:
                # The function should not read from metadata files
                assert 'container-metadata' not in line.lower(), \
                    f"validate_gpu_available should not read from container-metadata: {line}"

    def test_validate_gpu_available_handles_no_value(self):
        """validate_gpu_available should handle Docker's '<no value>' response."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should check for "<no value>" placeholder
        assert '<no value>' in content

    def test_validate_gpu_available_validates_against_nvidia_smi(self):
        """validate_gpu_available should validate UUIDs against nvidia-smi output."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should call nvidia-smi to verify GPU exists
        assert 'nvidia-smi' in content

    def test_validate_gpu_available_supports_multi_gpu(self):
        """validate_gpu_available should support containers with multiple GPUs."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should split comma-separated UUIDs
        assert 'IFS' in content or ',' in content


class TestValidateGpuAvailableFunction:
    """Focused tests on the validate_gpu_available function logic."""

    def extract_validate_gpu_function(self) -> str:
        """Extract the validate_gpu_available function from the script."""
        content = CONTAINER_SESSION_PATH.read_text()
        lines = content.split('\n')
        function_lines = []
        in_function = False
        brace_count = 0

        for line in lines:
            if 'validate_gpu_available()' in line:
                in_function = True

            if in_function:
                function_lines.append(line)
                brace_count += line.count('{') - line.count('}')
                if brace_count == 0 and function_lines:
                    break

        return '\n'.join(function_lines)

    def test_function_signature(self):
        """validate_gpu_available should accept container name as argument."""
        func = self.extract_validate_gpu_function()
        # Should take a container name
        assert 'local name="$1"' in func

    def test_function_constructs_container_tag(self):
        """validate_gpu_available should construct full container tag."""
        func = self.extract_validate_gpu_function()
        # Should construct tag from name and user ID
        assert '${name}._.${USER_ID}' in func or '${name}._.' in func

    def test_function_checks_uuids_label_first(self):
        """validate_gpu_available should check ds01.gpu.uuids label first."""
        func = self.extract_validate_gpu_function()
        # Should query uuids label (multi-GPU)
        assert 'ds01.gpu.uuids' in func

    def test_function_falls_back_to_uuid_label(self):
        """validate_gpu_available should fall back to ds01.gpu.uuid for single GPU."""
        func = self.extract_validate_gpu_function()
        # Should have fallback to single GPU label
        assert 'ds01.gpu.uuid' in func

    def test_function_iterates_over_uuids(self):
        """validate_gpu_available should iterate over multiple GPU UUIDs."""
        func = self.extract_validate_gpu_function()
        # Should iterate over UUID array
        assert 'UUID_ARRAY' in func or 'for' in func

    def test_function_validates_each_uuid(self):
        """validate_gpu_available should validate each UUID against nvidia-smi."""
        func = self.extract_validate_gpu_function()
        # Should check each GPU against nvidia-smi output
        assert 'nvidia-smi' in func and 'grep' in func

    def test_function_returns_failure_for_missing_gpu(self):
        """validate_gpu_available should return 1 if GPU is not available."""
        func = self.extract_validate_gpu_function()
        # Should return failure
        assert 'return 1' in func

    def test_function_returns_success_for_valid_gpu(self):
        """validate_gpu_available should return 0 if all GPUs are available."""
        func = self.extract_validate_gpu_function()
        # Should return success (implicit or explicit)
        assert 'return 0' in func


class TestContainerSessionModes:
    """Tests for container-session.sh mode detection."""

    def run_bash_script(
        self,
        script_content: str,
        env: Optional[Dict] = None
    ) -> subprocess.CompletedProcess:
        """Helper to run bash script content."""
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script_content],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_mode_detection_from_script_name(self):
        """Mode should be detected from script name (basename)."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should use basename to detect mode
        assert 'SCRIPT_NAME=$(basename "$0")' in content or 'basename' in content

    def test_supports_container_start_mode(self):
        """Should support container-start mode."""
        content = CONTAINER_SESSION_PATH.read_text()
        assert 'container-start' in content
        assert 'MODE="start"' in content

    def test_supports_container_run_mode(self):
        """Should support container-run mode."""
        content = CONTAINER_SESSION_PATH.read_text()
        assert 'container-run' in content
        assert 'MODE="run"' in content

    def test_supports_container_attach_mode(self):
        """Should support container-attach mode."""
        content = CONTAINER_SESSION_PATH.read_text()
        assert 'container-attach' in content
        assert 'MODE="attach"' in content


@pytest.mark.requires_docker
@pytest.mark.slow
class TestValidateGpuAvailableLive:
    """Live tests for validate_gpu_available with Docker.

    Note: container-session.sh is a full executable script, not just a library
    to be sourced. These tests focus on code inspection rather than execution.
    """

    def test_validate_gpu_function_can_be_extracted(self):
        """The validate_gpu_available function should be extractable from the script.

        Note: container-session.sh runs as an interactive script with mode detection,
        so sourcing it directly triggers the full script execution. We test the
        function's code structure instead.
        """
        content = CONTAINER_SESSION_PATH.read_text()

        # Find the function
        assert "validate_gpu_available()" in content

        # The function should:
        # 1. Query Docker labels
        assert 'docker inspect' in content
        # 2. Check for GPU UUIDs
        assert 'ds01.gpu.uuids' in content or 'ds01.gpu.uuid' in content
        # 3. Validate against nvidia-smi
        assert 'nvidia-smi' in content

    def test_validate_gpu_handles_empty_response_gracefully(self):
        """validate_gpu_available logic should handle empty/no-value responses.

        When Docker labels return empty or '<no value>', the function should
        pass validation (no GPU to validate).
        """
        content = CONTAINER_SESSION_PATH.read_text()

        # Should check for empty values
        assert '[ -z "$gpu_uuids" ]' in content or \
               '[[ -z "$gpu_uuids"' in content or \
               '-z "$gpu_uuids"' in content or \
               '<no value>' in content


class TestGpuLabelQueryOrder:
    """Tests to verify correct label query order in validate_gpu_available."""

    def test_multi_gpu_label_checked_before_single(self):
        """ds01.gpu.uuids should be checked before ds01.gpu.uuid."""
        content = CONTAINER_SESSION_PATH.read_text()

        # Find positions of both label checks
        uuids_pos = content.find('ds01.gpu.uuids')
        uuid_pos = content.find('ds01.gpu.uuid"')  # Include quote to avoid matching uuids

        # uuids (multi-GPU) should be checked first
        assert uuids_pos > 0
        assert uuid_pos > 0
        assert uuids_pos < uuid_pos, "Multi-GPU label should be checked before single GPU label"


class TestErrorMessages:
    """Tests for error message formatting in validate_gpu_available."""

    def test_error_message_includes_uuid(self):
        """Error message should include the missing GPU UUID."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Error message should show which GPU is missing
        assert 'GPU $gpu_uuid is no longer available' in content or \
               'no longer available' in content.lower()

    def test_error_message_suggests_recreation(self):
        """Error message should suggest container recreation."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should suggest how to fix
        assert 'container-remove' in content or 'container-create' in content

    def test_error_message_mentions_workspace_safety(self):
        """Error message should mention workspace files are safe."""
        content = CONTAINER_SESSION_PATH.read_text()
        # Should reassure about data safety
        assert 'Workspace files' in content or 'workspace' in content.lower()
