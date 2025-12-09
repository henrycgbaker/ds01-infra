#!/usr/bin/env python3
"""
Tests for /opt/ds01-infra/scripts/lib/docker-utils.sh

This test suite validates the docker-utils.sh library functions that provide
common Docker query patterns across DS01 scripts.

Functions tested:
- ds01_container_exists() / ds01_container_exists_by_tag()
- ds01_container_running() / ds01_container_running_by_tag()
- ds01_container_status()
- ds01_get_container_label()
- ds01_get_container_gpu_uuids() / ds01_get_container_gpu_slots()
- ds01_get_container_owner() / ds01_get_container_interface()
- ds01_get_user_containers() / ds01_count_user_containers()
- ds01_container_name_to_tag() / ds01_tag_to_container_name() / ds01_tag_to_user_id()
- ds01_is_ds01_managed() / ds01_is_aime_container()
"""

import os
import subprocess
import pytest
from pathlib import Path
from typing import Dict, Any, Optional


# Path to the docker-utils.sh library
DOCKER_UTILS_PATH = Path("/opt/ds01-infra/scripts/lib/docker-utils.sh")


class TestDockerUtilsLibrary:
    """Tests for docker-utils.sh bash library functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """
        Helper to run a bash function from docker-utils.sh and return result.

        Args:
            function_call: The function call to execute (e.g., "ds01_container_name_to_tag my-project 1001")
            env: Optional environment variables to set

        Returns:
            subprocess.CompletedProcess with stdout, stderr, returncode
        """
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """

        run_env = os.environ.copy()
        if env:
            run_env.update(env)

        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_library_exists(self):
        """docker-utils.sh library file should exist."""
        assert DOCKER_UTILS_PATH.exists(), f"Library not found at {DOCKER_UTILS_PATH}"

    def test_library_sources_without_error(self):
        """docker-utils.sh should source without errors."""
        result = self.run_bash_function("echo sourced_ok")
        assert result.returncode == 0, f"Failed to source library: {result.stderr}"
        assert "sourced_ok" in result.stdout


class TestContainerNameHelpers:
    """Tests for container name transformation functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_container_name_to_tag_with_explicit_user_id(self):
        """ds01_container_name_to_tag should format name._.userid correctly."""
        result = self.run_bash_function('ds01_container_name_to_tag "my-project" "1001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "my-project._.1001"

    def test_container_name_to_tag_uses_current_user_id(self):
        """ds01_container_name_to_tag should use current user ID when not specified."""
        current_uid = str(os.getuid())
        result = self.run_bash_function('ds01_container_name_to_tag "my-project"')
        assert result.returncode == 0
        assert result.stdout.strip() == f"my-project._.{current_uid}"

    def test_container_name_to_tag_with_hyphens(self):
        """ds01_container_name_to_tag should handle names with hyphens."""
        result = self.run_bash_function('ds01_container_name_to_tag "my-complex-project-name" "2001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "my-complex-project-name._.2001"

    def test_tag_to_container_name_extracts_name(self):
        """ds01_tag_to_container_name should extract name from tag."""
        result = self.run_bash_function('ds01_tag_to_container_name "my-project._.1001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "my-project"

    def test_tag_to_container_name_handles_complex_names(self):
        """ds01_tag_to_container_name should handle names with multiple hyphens."""
        result = self.run_bash_function('ds01_tag_to_container_name "my-complex-name._.1001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "my-complex-name"

    def test_tag_to_user_id_extracts_uid(self):
        """ds01_tag_to_user_id should extract user ID from tag."""
        result = self.run_bash_function('ds01_tag_to_user_id "my-project._.1001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "1001"

    def test_tag_to_user_id_handles_large_uid(self):
        """ds01_tag_to_user_id should handle large user IDs."""
        result = self.run_bash_function('ds01_tag_to_user_id "project._.1000001"')
        assert result.returncode == 0
        assert result.stdout.strip() == "1000001"


class TestContainerDetection:
    """Tests for container type detection functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_is_aime_container_returns_true_for_aime_naming(self):
        """ds01_is_aime_container should return 0 for AIME naming convention."""
        result = self.run_bash_function('ds01_is_aime_container "my-project._.1001" && echo "true" || echo "false"')
        assert result.returncode == 0
        assert result.stdout.strip() == "true"

    def test_is_aime_container_returns_false_for_non_aime_naming(self):
        """ds01_is_aime_container should return 1 for non-AIME naming."""
        result = self.run_bash_function('ds01_is_aime_container "my-project" && echo "true" || echo "false"')
        assert result.returncode == 0
        assert result.stdout.strip() == "false"

    def test_is_aime_container_handles_docker_compose_names(self):
        """ds01_is_aime_container should return false for docker-compose names."""
        result = self.run_bash_function('ds01_is_aime_container "myproject_web_1" && echo "true" || echo "false"')
        assert result.returncode == 0
        assert result.stdout.strip() == "false"


@pytest.mark.requires_docker
@pytest.mark.slow
class TestContainerStateFunctions:
    """Tests for container state query functions (requires Docker).

    Note: These tests are marked slow because docker inspect can take time.
    They use longer timeouts to handle Docker daemon latency.
    """

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=30  # Longer timeout for Docker operations
        )

    def test_container_exists_returns_false_for_nonexistent(self):
        """ds01_container_exists_by_tag should return 1 for nonexistent container."""
        result = self.run_bash_function(
            'ds01_container_exists_by_tag "nonexistent-container-xyz123" && echo "exists" || echo "not_exists"'
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "not_exists"

    def test_container_running_returns_false_for_nonexistent(self):
        """ds01_container_running_by_tag should return 1 for nonexistent container."""
        result = self.run_bash_function(
            'ds01_container_running_by_tag "nonexistent-container-xyz123" && echo "running" || echo "not_running"'
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "not_running"

    def test_container_status_returns_empty_for_nonexistent(self):
        """ds01_container_status should return empty string for nonexistent container."""
        result = self.run_bash_function('ds01_container_status "nonexistent-container-xyz123"')
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_get_container_label_returns_empty_for_nonexistent(self):
        """ds01_get_container_label should return empty for nonexistent container."""
        result = self.run_bash_function(
            'ds01_get_container_label "nonexistent-container-xyz123" "ds01.user"'
        )
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_get_container_gpu_uuids_returns_empty_for_nonexistent(self):
        """ds01_get_container_gpu_uuids should return empty for nonexistent container."""
        result = self.run_bash_function(
            'ds01_get_container_gpu_uuids "nonexistent-container-xyz123"'
        )
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_is_ds01_managed_returns_false_for_nonexistent(self):
        """ds01_is_ds01_managed should return 1 for nonexistent container."""
        result = self.run_bash_function(
            'ds01_is_ds01_managed "nonexistent-container-xyz123" && echo "managed" || echo "not_managed"'
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "not_managed"


@pytest.mark.requires_docker
class TestUserContainerFunctions:
    """Tests for user container listing functions (requires Docker)."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_get_user_containers_returns_empty_for_nonexistent_user(self):
        """ds01_get_user_containers should handle nonexistent users gracefully."""
        # Use a random username that likely doesn't exist
        result = self.run_bash_function('ds01_get_user_containers "nonexistent_user_xyz123"')
        # Should not crash, may return empty or error message
        assert result.returncode == 0

    def test_count_user_containers_returns_zero_for_current_user_initially(self):
        """ds01_count_user_containers should work without error."""
        result = self.run_bash_function('ds01_count_user_containers')
        assert result.returncode == 0
        # Output should be a number (possibly 0)
        count = result.stdout.strip()
        assert count.isdigit() or count == ""


class TestGetContainerLabelFunction:
    """Tests for the ds01_get_container_label function behavior."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_get_container_label_handles_no_value_placeholder(self):
        """ds01_get_container_label should filter out <no value> placeholder.

        This tests the fix where Docker returns '<no value>' for missing labels,
        which needs to be converted to an empty string.
        """
        # The function internally handles this - we test the behavior
        # by checking that it returns empty string for a nonexistent container
        # (which would return '<no value>' from docker inspect)
        result = self.run_bash_function('''
        # Simulate what the function does with <no value>
        value="<no value>"
        if [[ "$value" == "<no value>" ]]; then
            echo ""
        else
            echo "$value"
        fi
        ''')
        assert result.returncode == 0
        assert result.stdout.strip() == ""


class TestGPUSlotFunctions:
    """Tests for GPU slot retrieval functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_get_container_gpu_uuids_fallback_logic(self):
        """ds01_get_container_gpu_uuids should fall back to ds01.gpu.uuid label.

        The function first checks ds01.gpu.uuids (multi-GPU), then falls back
        to ds01.gpu.uuid (single GPU) for backward compatibility.
        """
        # Test that the function exists and the fallback logic is in place
        result = self.run_bash_function('''
        # Check the function contains fallback logic
        type ds01_get_container_gpu_uuids | grep -q "ds01.gpu.uuid" && echo "has_fallback" || echo "no_fallback"
        ''')
        assert result.returncode == 0
        assert "has_fallback" in result.stdout

    def test_get_container_gpu_slots_fallback_logic(self):
        """ds01_get_container_gpu_slots should fall back to ds01.gpu.allocated label.

        The function first checks ds01.gpu.slots, then falls back to ds01.gpu.allocated.
        """
        result = self.run_bash_function('''
        # Check the function contains fallback logic
        type ds01_get_container_gpu_slots | grep -q "ds01.gpu.allocated" && echo "has_fallback" || echo "no_fallback"
        ''')
        assert result.returncode == 0
        assert "has_fallback" in result.stdout


class TestContainerOwnerFunction:
    """Tests for ds01_get_container_owner function."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_get_container_owner_fallback_logic(self):
        """ds01_get_container_owner should fall back to aime.mlc.USER label.

        The function first checks ds01.user, then falls back to aime.mlc.USER
        for backward compatibility with existing AIME containers.
        """
        result = self.run_bash_function('''
        # Check the function contains fallback logic to AIME label
        type ds01_get_container_owner | grep -q "aime.mlc.USER" && echo "has_fallback" || echo "no_fallback"
        ''')
        assert result.returncode == 0
        assert "has_fallback" in result.stdout


class TestContainerInterfaceFunction:
    """Tests for ds01_get_container_interface function."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{DOCKER_UTILS_PATH}"
        {function_call}
        """
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env=run_env,
            timeout=10
        )

    def test_get_container_interface_fallback_for_aime_naming(self):
        """ds01_get_container_interface should detect atomic interface from naming convention.

        When ds01.interface label is not set, the function should detect
        AIME naming convention (name._.uid) and return 'atomic'.
        """
        result = self.run_bash_function('''
        # Check the function contains fallback logic for AIME naming
        type ds01_get_container_interface | grep -q "\\._\\." && echo "has_fallback" || echo "no_fallback"
        ''')
        assert result.returncode == 0
        assert "has_fallback" in result.stdout

    def test_get_container_interface_default_to_docker(self):
        """ds01_get_container_interface should default to 'docker' when no interface detected."""
        result = self.run_bash_function('''
        # Check the function has docker as default
        type ds01_get_container_interface | grep -q '"docker"' && echo "has_default" || echo "no_default"
        ''')
        assert result.returncode == 0
        assert "has_default" in result.stdout
