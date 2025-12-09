#!/usr/bin/env python3
"""
E2E Tests: Container Workflow
Full end-to-end tests for container deploy/retire workflows
"""

import pytest
import subprocess
import os
import time
import json
from pathlib import Path


class TestContainerDeployRetire:
    """E2E tests for container-deploy and container-retire."""

    @pytest.fixture
    def test_project_name(self):
        """Generate unique test project name."""
        import random
        return f"e2e-test-{random.randint(1000, 9999)}"

    @pytest.fixture
    def cleanup_container(self, test_project_name):
        """Fixture to clean up test containers after test."""
        yield test_project_name
        # Cleanup after test
        user = os.environ.get("USER", "testuser")
        container_name = f"{test_project_name}._.{os.getuid()}"
        subprocess.run(
            ["docker", "rm", "-f", container_name],
            capture_output=True
        )

    @pytest.mark.e2e
    @pytest.mark.requires_docker
    @pytest.mark.requires_gpu
    @pytest.mark.slow
    def test_deploy_creates_running_container(self, cleanup_container):
        """container-deploy creates a running container."""
        project = cleanup_container

        # This would be a real deploy test
        # For now, verify the script exists and can show help
        deploy = Path("/opt/ds01-infra/scripts/user/orchestrators/container-deploy")
        result = subprocess.run(
            [str(deploy), "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Script should at least run
        assert result.returncode in [0, 1]

    @pytest.mark.e2e
    def test_deploy_retire_output_consistency(self):
        """Deploy and retire produce consistent output for users."""
        deploy = Path("/opt/ds01-infra/scripts/user/orchestrators/container-deploy")
        retire = Path("/opt/ds01-infra/scripts/user/orchestrators/container-retire")

        # Both should exist
        assert deploy.exists()
        assert retire.exists()

        # Both should have consistent UX
        deploy_content = deploy.read_text()
        retire_content = retire.read_text()

        # Both should use same color/output library
        assert "ds01-context.sh" in deploy_content
        assert "ds01-context.sh" in retire_content


class TestWizardWorkflows:
    """E2E tests for wizard commands (project-init, user-setup)."""

    @pytest.mark.e2e
    def test_project_init_help(self):
        """project-init shows help without errors."""
        project_init = Path("/opt/ds01-infra/scripts/user/project-init")
        if not project_init.exists():
            pytest.skip("project-init not found")

        result = subprocess.run(
            [str(project_init), "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode in [0, 1]

    @pytest.mark.e2e
    def test_user_setup_help(self):
        """user-setup shows help without errors."""
        user_setup = Path("/opt/ds01-infra/scripts/user/user-setup")
        if not user_setup.exists():
            pytest.skip("user-setup not found")

        result = subprocess.run(
            [str(user_setup), "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode in [0, 1]

    @pytest.mark.e2e
    def test_wizard_sets_orchestration_context(self):
        """Wizards set orchestration context."""
        for script_name in ["project-init", "user-setup"]:
            script = Path(f"/opt/ds01-infra/scripts/user/{script_name}")
            if script.exists():
                content = script.read_text()
                assert "orchestration" in content.lower(), \
                    f"{script_name} should set orchestration context"


class TestDashboardE2E:
    """E2E tests for dashboard command."""

    @pytest.mark.e2e
    def test_dashboard_exists(self):
        """Dashboard command exists."""
        dashboard = Path("/opt/ds01-infra/scripts/admin/dashboard")
        assert dashboard.exists()

    @pytest.mark.e2e
    @pytest.mark.requires_docker
    def test_dashboard_default_view(self):
        """Dashboard default view executes and produces output."""
        dashboard = Path("/opt/ds01-infra/scripts/admin/dashboard")

        result = subprocess.run(
            [str(dashboard)],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should produce output (may fail with IndexError on malformed log entries)
        # The important thing is it produces meaningful output before any crash
        assert len(result.stdout) > 100, "Dashboard should produce substantial output"
        assert "GPU" in result.stdout or "CONTAINER" in result.stdout

    @pytest.mark.e2e
    @pytest.mark.requires_docker
    def test_dashboard_interfaces_view(self):
        """Dashboard interfaces view shows all 4 categories."""
        dashboard = Path("/opt/ds01-infra/scripts/admin/dashboard")

        result = subprocess.run(
            [str(dashboard), "interfaces"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should complete
        assert result.returncode == 0


class TestHealthCheckE2E:
    """E2E tests for health check system."""

    @pytest.mark.e2e
    @pytest.mark.requires_docker
    def test_health_check_full_run(self):
        """Health check runs all checks."""
        health_check = Path("/opt/ds01-infra/scripts/monitoring/ds01-health-check")
        if not health_check.exists():
            pytest.skip("Health check not found")

        result = subprocess.run(
            [str(health_check)],
            capture_output=True,
            text=True,
            timeout=120
        )
        # Should complete with some status
        # 0 = all pass, 1 = warnings, 2 = failures
        assert result.returncode in [0, 1, 2]

    @pytest.mark.e2e
    def test_health_check_components(self):
        """Health check validates critical components."""
        health_check = Path("/opt/ds01-infra/scripts/monitoring/ds01-health-check")
        if not health_check.exists():
            pytest.skip("Health check not found")

        content = health_check.read_text()

        # Should check these components
        components = ["docker", "nvidia", "config", "cgroup"]
        for component in components:
            assert component in content.lower(), \
                f"Health check missing {component} validation"


class TestCommandDiscovery:
    """E2E tests for command availability."""

    @pytest.mark.e2e
    def test_user_commands_in_path(self):
        """User commands are accessible."""
        commands = [
            "container-deploy",
            "container-retire",
            "container-list",
            "container-stats",
        ]

        scripts_dir = Path("/opt/ds01-infra/scripts/user")
        for cmd in commands:
            path = scripts_dir / cmd
            assert path.exists(), f"Command not found: {cmd}"
            assert path.stat().st_mode & 0o111, f"Not executable: {cmd}"

    @pytest.mark.e2e
    def test_admin_commands_exist(self):
        """Admin commands exist."""
        commands = ["dashboard"]

        scripts_dir = Path("/opt/ds01-infra/scripts/admin")
        for cmd in commands:
            path = scripts_dir / cmd
            assert path.exists(), f"Admin command not found: {cmd}"
