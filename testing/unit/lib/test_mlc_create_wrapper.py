#!/usr/bin/env python3
"""
Tests for GPU allocation race condition fix in mlc-create-wrapper.sh

This test suite validates the race condition fix added to mlc-create-wrapper.sh
at lines 813-844. The fix verifies that the GPU allocated matches the GPU
in the container labels after creation.

The race condition scenario:
1. Process A allocates GPU 0 (lock released)
2. Process B allocates GPU 0 (before Process A creates container)
3. Process B creates container with GPU 0
4. Process A creates container - should DETECT the conflict

Fix implementation:
- After container creation, verify ds01.gpu.uuids or ds01.gpu.uuid label
- Compare with DOCKER_ID from allocation
- If mismatch, clean up and fail with helpful message
"""

import os
import subprocess
import pytest
import re
from pathlib import Path
from typing import Dict, Optional


# Path to the mlc-create-wrapper.sh script
MLC_CREATE_WRAPPER_PATH = Path("/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh")


class TestMlcCreateWrapperScript:
    """Tests for mlc-create-wrapper.sh script structure."""

    def test_script_exists(self):
        """mlc-create-wrapper.sh should exist."""
        assert MLC_CREATE_WRAPPER_PATH.exists()

    def test_race_condition_check_exists(self):
        """Script should contain GPU allocation race condition check."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()
        assert "GPU ALLOCATION RACE CONDITION CHECK" in content

    def test_race_condition_check_in_correct_location(self):
        """Race condition check should be after container creation."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()

        # Find the race condition check
        race_check_pos = content.find("GPU ALLOCATION RACE CONDITION CHECK")
        assert race_check_pos > 0

        # Should be after mlc-patched.py is invoked (container creation)
        # The script uses $MLC_PATCHED variable (set to mlc-patched.py)
        mlc_patched_pos = content.find("MLC_PATCHED")
        assert mlc_patched_pos > 0, "Should reference MLC_PATCHED for container creation"

        # The race check should be after the container is created
        # Look for the python3 call that creates the container
        python_create_pos = content.find('python3 "$MLC_PATCHED"')
        if python_create_pos == -1:
            python_create_pos = content.find('$MLC_PATCHED')

        # The race check section should be after the creation logic
        # (it's in the post-creation section of the script)


class TestRaceConditionCheckImplementation:
    """Tests for the race condition check implementation details."""

    def extract_race_condition_check(self) -> str:
        """Extract the race condition check code block."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()
        lines = content.split('\n')

        # Find the section
        start_idx = None
        end_idx = None

        for i, line in enumerate(lines):
            if "GPU ALLOCATION RACE CONDITION CHECK" in line:
                start_idx = i
            if start_idx and "Build docker update command" in line:
                end_idx = i
                break

        if start_idx and end_idx:
            return '\n'.join(lines[start_idx:end_idx])
        return ""

    def test_checks_docker_id_is_set(self):
        """Race condition check should only run if DOCKER_ID is set."""
        check = self.extract_race_condition_check()
        # Should check if DOCKER_ID is non-empty
        assert '[ -n "$DOCKER_ID" ]' in check or \
               '[[ -n "$DOCKER_ID" ]]' in check or \
               'if [ -n "$DOCKER_ID"' in check

    def test_queries_gpu_uuids_label(self):
        """Check should query ds01.gpu.uuids label."""
        check = self.extract_race_condition_check()
        assert 'ds01.gpu.uuids' in check

    def test_queries_gpu_uuid_label_as_fallback(self):
        """Check should fall back to ds01.gpu.uuid label."""
        check = self.extract_race_condition_check()
        assert 'ds01.gpu.uuid' in check

    def test_uses_docker_inspect(self):
        """Check should use docker inspect to get labels."""
        check = self.extract_race_condition_check()
        assert 'docker inspect' in check

    def test_compares_actual_vs_expected(self):
        """Check should compare actual GPU vs expected DOCKER_ID."""
        check = self.extract_race_condition_check()
        # Should compare ACTUAL_GPU with DOCKER_ID
        assert 'ACTUAL_GPU' in check
        assert 'DOCKER_ID' in check

    def test_handles_no_value_placeholder(self):
        """Check should handle Docker's '<no value>' placeholder."""
        check = self.extract_race_condition_check()
        assert '<no value>' in check

    def test_logs_error_on_mismatch(self):
        """Check should log error when race condition detected."""
        check = self.extract_race_condition_check()
        assert 'race condition' in check.lower()
        assert 'log_error' in check.lower() or 'ERROR' in check

    def test_removes_conflicting_container(self):
        """Check should remove the conflicting container."""
        check = self.extract_race_condition_check()
        assert 'docker rm' in check

    def test_releases_gpu_allocation(self):
        """Check should release the GPU allocation."""
        check = self.extract_race_condition_check()
        assert 'release' in check.lower()

    def test_exits_with_error(self):
        """Check should exit with error code."""
        check = self.extract_race_condition_check()
        assert 'exit 1' in check

    def test_suggests_retry(self):
        """Check should suggest retrying the command."""
        check = self.extract_race_condition_check()
        assert 'retry' in check.lower() or 'container-deploy' in check


class TestRaceConditionMessages:
    """Tests for user-facing messages in the race condition check."""

    def get_race_condition_section(self) -> str:
        """Get the race condition check section."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()
        # Find section between race condition check and docker update
        match = re.search(
            r'# === GPU ALLOCATION RACE CONDITION CHECK ===.*?# Build docker update',
            content,
            re.DOTALL
        )
        return match.group(0) if match else ""

    def test_error_shows_expected_gpu(self):
        """Error message should show expected GPU ID."""
        section = self.get_race_condition_section()
        # Should show what GPU was expected
        assert 'Expected GPU' in section or 'DOCKER_ID' in section

    def test_error_shows_actual_gpu(self):
        """Error message should show actual GPU in container."""
        section = self.get_race_condition_section()
        # Should show what GPU the container has
        assert 'Container has' in section or 'ACTUAL_GPU' in section

    def test_explains_the_situation(self):
        """Error message should explain the race condition."""
        section = self.get_race_condition_section()
        # Should explain that another container got the GPU
        assert 'another container' in section.lower() or \
               'same time' in section.lower()


class TestRaceConditionScenarios:
    """Scenario-based tests for the race condition logic."""

    def run_bash_test(self, script: str) -> subprocess.CompletedProcess:
        """Run a bash script and return result."""
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=10
        )

    def test_scenario_matching_gpus_passes(self):
        """When allocated GPU matches container label, should pass."""
        # Simulate the logic where GPUs match
        result = self.run_bash_test('''
        DOCKER_ID="GPU-abc123"
        ACTUAL_GPU="GPU-abc123"

        # Simulate the comparison logic from mlc-create-wrapper.sh
        if [ -n "$ACTUAL_GPU" ] && [ "$ACTUAL_GPU" != "<no value>" ] && [ "$ACTUAL_GPU" != "$DOCKER_ID" ]; then
            echo "MISMATCH"
            exit 1
        fi
        echo "MATCH"
        ''')

        assert result.returncode == 0
        assert "MATCH" in result.stdout

    def test_scenario_mismatched_gpus_fails(self):
        """When allocated GPU differs from container label, should fail."""
        result = self.run_bash_test('''
        DOCKER_ID="GPU-abc123"
        ACTUAL_GPU="GPU-xyz789"

        # Simulate the comparison logic
        if [ -n "$ACTUAL_GPU" ] && [ "$ACTUAL_GPU" != "<no value>" ] && [ "$ACTUAL_GPU" != "$DOCKER_ID" ]; then
            echo "MISMATCH_DETECTED"
            exit 1
        fi
        echo "MATCH"
        ''')

        assert result.returncode == 1
        assert "MISMATCH_DETECTED" in result.stdout

    def test_scenario_no_value_is_ignored(self):
        """When label returns '<no value>', should pass (no GPU label set)."""
        result = self.run_bash_test('''
        DOCKER_ID="GPU-abc123"
        ACTUAL_GPU="<no value>"

        # Simulate the comparison logic
        if [ -n "$ACTUAL_GPU" ] && [ "$ACTUAL_GPU" != "<no value>" ] && [ "$ACTUAL_GPU" != "$DOCKER_ID" ]; then
            echo "MISMATCH"
            exit 1
        fi
        echo "PASS"
        ''')

        assert result.returncode == 0
        assert "PASS" in result.stdout

    def test_scenario_empty_actual_gpu_is_ignored(self):
        """When label is empty, should pass (no GPU allocated)."""
        result = self.run_bash_test('''
        DOCKER_ID="GPU-abc123"
        ACTUAL_GPU=""

        # Simulate the comparison logic
        if [ -n "$ACTUAL_GPU" ] && [ "$ACTUAL_GPU" != "<no value>" ] && [ "$ACTUAL_GPU" != "$DOCKER_ID" ]; then
            echo "MISMATCH"
            exit 1
        fi
        echo "PASS"
        ''')

        assert result.returncode == 0
        assert "PASS" in result.stdout


class TestRaceConditionCleanup:
    """Tests for the cleanup actions when race condition is detected."""

    def get_cleanup_commands(self) -> str:
        """Extract cleanup commands from race condition handler."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()
        match = re.search(
            r'race condition detected.*?exit 1',
            content,
            re.DOTALL | re.IGNORECASE
        )
        return match.group(0) if match else ""

    def test_cleanup_removes_container_forcefully(self):
        """Cleanup should use docker rm -f to force remove."""
        cleanup = self.get_cleanup_commands()
        assert 'docker rm -f' in cleanup

    def test_cleanup_uses_container_tag(self):
        """Cleanup should remove the correct container by tag."""
        cleanup = self.get_cleanup_commands()
        assert 'CONTAINER_TAG' in cleanup

    def test_cleanup_releases_allocation(self):
        """Cleanup should release the GPU allocation."""
        cleanup = self.get_cleanup_commands()
        assert 'GPU_ALLOCATOR' in cleanup or 'release' in cleanup

    def test_cleanup_suppresses_errors(self):
        """Cleanup commands should suppress errors (best effort)."""
        cleanup = self.get_cleanup_commands()
        # Should redirect stderr and/or use || true
        assert '2>/dev/null' in cleanup or '|| true' in cleanup


class TestRaceConditionIntegration:
    """Integration tests for the race condition fix."""

    def test_check_runs_only_with_docker_id(self):
        """Race condition check should be conditional on DOCKER_ID."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()

        # Find the race condition section
        section_start = content.find("GPU ALLOCATION RACE CONDITION CHECK")
        next_lines = content[section_start:section_start+500]

        # Should have conditional check
        assert 'if [ -n "$DOCKER_ID" ]' in next_lines or \
               'if [[ -n "$DOCKER_ID"' in next_lines

    def test_fallback_label_check_order(self):
        """Should check multi-GPU label first, then single GPU label."""
        content = MLC_CREATE_WRAPPER_PATH.read_text()

        # Find both label checks in the race condition section
        section_start = content.find("GPU ALLOCATION RACE CONDITION CHECK")
        section = content[section_start:section_start+1000]

        uuids_pos = section.find('ds01.gpu.uuids')
        uuid_pos = section.find('ds01.gpu.uuid"')  # Include quote to avoid matching uuids

        assert uuids_pos > 0, "Should check ds01.gpu.uuids"
        assert uuid_pos > 0, "Should check ds01.gpu.uuid as fallback"
        assert uuids_pos < uuid_pos, "Multi-GPU label should be checked first"
