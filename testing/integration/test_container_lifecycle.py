#!/usr/bin/env python3
"""
Integration Tests: Container Lifecycle
Tests container create -> start -> stop -> remove workflow
"""

import pytest
import subprocess
import os
import time
from pathlib import Path


class TestContainerLifecycleScripts:
    """Tests that container lifecycle scripts exist and have correct structure."""

    SCRIPTS_DIR = Path("/opt/ds01-infra/scripts/user")

    LIFECYCLE_SCRIPTS = [
        "container-create",
        "container-start",
        "container-stop",
        "container-remove",
        "container-deploy",
        "container-retire",
    ]

    @pytest.mark.integration
    def test_all_lifecycle_scripts_exist(self):
        """All container lifecycle scripts exist."""
        for script in self.LIFECYCLE_SCRIPTS:
            path = self.SCRIPTS_DIR / script
            assert path.exists(), f"Missing script: {script}"

    @pytest.mark.integration
    def test_all_scripts_executable(self):
        """All container lifecycle scripts are executable."""
        for script in self.LIFECYCLE_SCRIPTS:
            path = self.SCRIPTS_DIR / script
            if path.exists():
                assert path.stat().st_mode & 0o111, f"Not executable: {script}"

    @pytest.mark.integration
    def test_atomic_scripts_source_context_lib(self):
        """Atomic scripts source the context library."""
        atomic_scripts = ["container-create", "container-start", "container-stop", "container-remove"]
        for script in atomic_scripts:
            path = self.SCRIPTS_DIR / script
            if path.exists():
                content = path.read_text()
                assert "ds01-context.sh" in content, f"{script} missing context lib"

    @pytest.mark.integration
    def test_orchestrator_scripts_set_context(self):
        """Orchestrator scripts set DS01_CONTEXT."""
        orchestrator_scripts = ["container-deploy", "container-retire"]
        for script in orchestrator_scripts:
            path = self.SCRIPTS_DIR / script
            if path.exists():
                content = path.read_text()
                assert "DS01_CONTEXT" in content or "set_orchestration_context" in content, \
                    f"{script} doesn't set context"


class TestContainerCreateStop:
    """Integration tests for container-create and container-stop."""

    @pytest.mark.integration
    @pytest.mark.requires_docker
    @pytest.mark.slow
    def test_create_stop_sequence(self, temp_dir):
        """Test create followed by stop (without actual container)."""
        # This is a structural test - verify scripts can be called
        create_script = Path("/opt/ds01-infra/scripts/user/atomic/container-create")
        stop_script = Path("/opt/ds01-infra/scripts/user/atomic/container-stop")

        # Test --help works for both
        for script in [create_script, stop_script]:
            result = subprocess.run(
                [str(script), "--help"],
                capture_output=True,
                text=True,
                timeout=10
            )
            # Should show usage or help text
            assert result.returncode in [0, 1]  # 0 = success, 1 = usage shown


class TestDeployRetireWorkflow:
    """Integration tests for deploy/retire orchestration."""

    @pytest.mark.integration
    def test_deploy_calls_create_and_start(self):
        """container-deploy should call create and start."""
        deploy_script = Path("/opt/ds01-infra/scripts/user/orchestrators/container-deploy")
        content = deploy_script.read_text()

        # Should reference both create and start
        has_create = "container-create" in content or "create" in content.lower()
        has_start = "container-start" in content or "mlc-open" in content or "start" in content.lower()

        assert has_create and has_start

    @pytest.mark.integration
    def test_retire_calls_stop_and_remove(self):
        """container-retire should call stop and remove."""
        retire_script = Path("/opt/ds01-infra/scripts/user/orchestrators/container-retire")
        content = retire_script.read_text()

        # Should reference both stop and remove
        has_stop = "container-stop" in content or "mlc-stop" in content or "stop" in content.lower()
        has_remove = "container-remove" in content or "mlc-remove" in content or "remove" in content.lower()

        assert has_stop and has_remove

    @pytest.mark.integration
    def test_deploy_sets_orchestration_context(self):
        """container-deploy sets orchestration context for child commands."""
        deploy_script = Path("/opt/ds01-infra/scripts/user/orchestrators/container-deploy")
        content = deploy_script.read_text()

        assert "orchestration" in content.lower()

    @pytest.mark.integration
    def test_retire_sets_orchestration_context(self):
        """container-retire sets orchestration context for child commands."""
        retire_script = Path("/opt/ds01-infra/scripts/user/orchestrators/container-retire")
        content = retire_script.read_text()

        assert "orchestration" in content.lower()


class TestGPUAllocationIntegration:
    """Integration tests for GPU allocation during lifecycle."""

    @pytest.mark.integration
    def test_create_uses_gpu_allocator(self):
        """container-create uses GPU allocator."""
        # Check mlc-create-wrapper.sh uses allocator
        wrapper = Path("/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh")
        if wrapper.exists():
            content = wrapper.read_text()
            assert "gpu_allocator" in content.lower()

    @pytest.mark.integration
    def test_lifecycle_scripts_handle_gpu_labels(self):
        """Scripts handle GPU-related Docker labels."""
        # Check create wrapper sets labels
        wrapper = Path("/opt/ds01-infra/scripts/docker/mlc-create-wrapper.sh")
        if wrapper.exists():
            content = wrapper.read_text()
            gpu_label_indicators = ["ds01.gpu", "gpu.allocated", "--label"]
            has_gpu_labels = any(ind in content for ind in gpu_label_indicators)
            assert has_gpu_labels


class TestContextPropagation:
    """Tests for context propagation through lifecycle."""

    @pytest.mark.integration
    def test_context_propagates_in_deploy(self):
        """Context set by deploy propagates to atomic commands."""
        # Test via shell
        result = subprocess.run(
            ["bash", "-c", """
            source /opt/ds01-infra/scripts/lib/ds01-context.sh
            set_orchestration_context
            # Verify in subshell
            bash -c 'echo $DS01_CONTEXT'
            """],
            capture_output=True,
            text=True,
            env={**os.environ, "DS01_CONTEXT": ""}
        )
        assert result.stdout.strip() == "orchestration"

    @pytest.mark.integration
    def test_atomic_command_shows_next_steps_when_direct(self):
        """Atomic commands show next steps when called directly."""
        # Call with atomic context
        result = subprocess.run(
            ["bash", "-c", """
            source /opt/ds01-infra/scripts/lib/ds01-context.sh
            unset DS01_CONTEXT
            # Check if next steps would be shown
            if is_atomic_context; then
                echo "WOULD_SHOW_NEXT_STEPS"
            fi
            """],
            capture_output=True,
            text=True
        )
        assert "WOULD_SHOW_NEXT_STEPS" in result.stdout

    @pytest.mark.integration
    def test_atomic_command_suppresses_next_steps_when_orchestrated(self):
        """Atomic commands suppress next steps when called from orchestrator."""
        result = subprocess.run(
            ["bash", "-c", """
            source /opt/ds01-infra/scripts/lib/ds01-context.sh
            export DS01_CONTEXT=orchestration
            # Check if next steps would be shown
            if is_atomic_context; then
                echo "WOULD_SHOW_NEXT_STEPS"
            else
                echo "SUPPRESSED"
            fi
            """],
            capture_output=True,
            text=True
        )
        assert "SUPPRESSED" in result.stdout
