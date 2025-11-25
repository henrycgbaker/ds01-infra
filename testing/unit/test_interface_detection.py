#!/usr/bin/env python3
"""
Unit Tests: Interface Detection
Tests container interface detection logic from gpu-state-reader.py
"""

import pytest
from unittest.mock import patch, MagicMock


class TestInterfaceDetection:
    """Tests for _detect_interface method logic."""

    @pytest.fixture
    def detector(self):
        """Create a detector function that mimics gpu-state-reader logic."""
        def detect_interface(name: str, labels: dict) -> str:
            INTERFACE_ORCHESTRATION = "orchestration"
            INTERFACE_ATOMIC = "atomic"
            INTERFACE_DOCKER = "docker"
            INTERFACE_OTHER = "other"

            # 1. Explicit ds01.interface label
            interface_label = labels.get("ds01.interface", "")
            if interface_label:
                if interface_label == "orchestration":
                    return INTERFACE_ORCHESTRATION
                elif interface_label == "atomic":
                    return INTERFACE_ATOMIC

            # 2. DS01 managed label
            if labels.get("ds01.managed") == "true":
                return INTERFACE_ATOMIC

            # 3. AIME naming convention (name._.uid)
            if "._." in name:
                return INTERFACE_ATOMIC

            # 4. Tool-specific detection for "Other"
            # VS Code Dev Containers
            if (name.startswith("vscode-") or
                "devcontainer" in labels or
                labels.get("devcontainer.metadata")):
                return INTERFACE_OTHER

            # Docker Compose
            if (labels.get("com.docker.compose.project") or
                labels.get("com.docker.compose.service") or
                ("_" in name and name.endswith(("_1", "_2", "_3")))):
                return INTERFACE_OTHER

            # JupyterHub
            if (name.startswith("jupyterhub-") or
                name.startswith("jupyter-") or
                labels.get("hub.jupyter.org/username")):
                return INTERFACE_OTHER

            # 5. Default: Docker direct
            return INTERFACE_DOCKER

        return detect_interface

    # =========================================================================
    # Explicit Label Tests
    # =========================================================================

    @pytest.mark.unit
    def test_explicit_orchestration_label(self, detector):
        """Container with ds01.interface=orchestration detected correctly."""
        result = detector(
            name="my-project._.1001",
            labels={"ds01.interface": "orchestration"}
        )
        assert result == "orchestration"

    @pytest.mark.unit
    def test_explicit_atomic_label(self, detector):
        """Container with ds01.interface=atomic detected correctly."""
        result = detector(
            name="test-container",
            labels={"ds01.interface": "atomic"}
        )
        assert result == "atomic"

    # =========================================================================
    # DS01 Managed Label Tests
    # =========================================================================

    @pytest.mark.unit
    def test_ds01_managed_label(self, detector):
        """Container with ds01.managed=true defaults to atomic."""
        result = detector(
            name="custom-container",
            labels={"ds01.managed": "true"}
        )
        assert result == "atomic"

    # =========================================================================
    # AIME Naming Convention Tests
    # =========================================================================

    @pytest.mark.unit
    def test_aime_naming_pattern(self, detector):
        """Container with AIME naming (name._.uid) detected as atomic."""
        result = detector(
            name="project-a._.1001",
            labels={}
        )
        assert result == "atomic"

    @pytest.mark.unit
    def test_aime_naming_with_complex_name(self, detector):
        """Complex AIME names detected correctly."""
        result = detector(
            name="my-awesome-project._.65534",
            labels={}
        )
        assert result == "atomic"

    # =========================================================================
    # VS Code Dev Container Tests
    # =========================================================================

    @pytest.mark.unit
    def test_vscode_prefix(self, detector):
        """Container starting with vscode- detected as Other."""
        result = detector(
            name="vscode-my-project-abc123",
            labels={}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_devcontainer_label(self, detector):
        """Container with devcontainer label detected as Other."""
        result = detector(
            name="random-name",
            labels={"devcontainer": "true"}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_devcontainer_metadata_label(self, detector):
        """Container with devcontainer.metadata detected as Other."""
        result = detector(
            name="random-name",
            labels={"devcontainer.metadata": '{"some": "config"}'}
        )
        assert result == "other"

    # =========================================================================
    # Docker Compose Tests
    # =========================================================================

    @pytest.mark.unit
    def test_compose_project_label(self, detector):
        """Container with compose project label detected as Other."""
        result = detector(
            name="myapp_web_1",
            labels={"com.docker.compose.project": "myapp"}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_compose_service_label(self, detector):
        """Container with compose service label detected as Other."""
        result = detector(
            name="myapp_web_1",
            labels={"com.docker.compose.service": "web"}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_compose_naming_pattern(self, detector):
        """Container with compose naming pattern (service_1) detected as Other."""
        result = detector(
            name="myproject_jupyter_1",
            labels={}
        )
        assert result == "other"

    # =========================================================================
    # JupyterHub Tests
    # =========================================================================

    @pytest.mark.unit
    def test_jupyterhub_prefix(self, detector):
        """Container starting with jupyterhub- detected as Other."""
        result = detector(
            name="jupyterhub-alice",
            labels={}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_jupyter_prefix(self, detector):
        """Container starting with jupyter- detected as Other."""
        result = detector(
            name="jupyter-alice",
            labels={}
        )
        assert result == "other"

    @pytest.mark.unit
    def test_jupyterhub_label(self, detector):
        """Container with JupyterHub label detected as Other."""
        result = detector(
            name="user-notebook",
            labels={"hub.jupyter.org/username": "alice"}
        )
        assert result == "other"

    # =========================================================================
    # Docker Direct Tests
    # =========================================================================

    @pytest.mark.unit
    def test_plain_docker_container(self, detector):
        """Plain Docker container with no special labels detected as Docker."""
        result = detector(
            name="my-container",
            labels={}
        )
        assert result == "docker"

    @pytest.mark.unit
    def test_docker_with_random_labels(self, detector):
        """Docker container with random labels detected as Docker."""
        result = detector(
            name="custom-app",
            labels={
                "maintainer": "someone@example.com",
                "version": "1.0"
            }
        )
        assert result == "docker"

    # =========================================================================
    # Priority Tests
    # =========================================================================

    @pytest.mark.unit
    def test_explicit_label_overrides_naming(self, detector):
        """Explicit label takes precedence over naming convention."""
        # Has AIME naming but explicit orchestration label
        result = detector(
            name="project._.1001",
            labels={"ds01.interface": "orchestration"}
        )
        assert result == "orchestration"

    @pytest.mark.unit
    def test_ds01_managed_overrides_tool_detection(self, detector):
        """ds01.managed label takes precedence over tool detection."""
        # Has jupyterhub prefix but ds01.managed
        result = detector(
            name="jupyterhub-something",
            labels={"ds01.managed": "true"}
        )
        assert result == "atomic"

    @pytest.mark.unit
    def test_explicit_label_overrides_everything(self, detector):
        """Explicit ds01.interface overrides all other detection."""
        # Has compose labels but explicit interface
        result = detector(
            name="myproject_web_1",
            labels={
                "ds01.interface": "orchestration",
                "com.docker.compose.project": "myproject"
            }
        )
        assert result == "orchestration"


class TestCgroupUserExtraction:
    """Tests for user extraction from cgroup path."""

    @pytest.fixture
    def extractor(self):
        """Create a user extraction function."""
        def extract_user_from_cgroup(cgroup_parent: str) -> str:
            # Pattern: ds01-{group}-{user}.slice
            import re
            match = re.match(r"ds01-([^-]+)-(.+)\.slice", cgroup_parent)
            if match:
                return match.group(2)

            # Pattern: ds01-{user}.slice (no group)
            match = re.match(r"ds01-(.+)\.slice", cgroup_parent)
            if match:
                return match.group(1)

            return None

        return extract_user_from_cgroup

    @pytest.mark.unit
    def test_extract_from_group_slice(self, extractor):
        """Extract user from ds01-{group}-{user}.slice format."""
        result = extractor("ds01-students-alice.slice")
        assert result == "alice"

    @pytest.mark.unit
    def test_extract_from_simple_slice(self, extractor):
        """Extract user from ds01-{user}.slice format."""
        result = extractor("ds01-bob.slice")
        assert result == "bob"

    @pytest.mark.unit
    def test_extract_user_with_numbers(self, extractor):
        """Extract user with numbers in name."""
        result = extractor("ds01-researchers-user123.slice")
        assert result == "user123"

    @pytest.mark.unit
    def test_invalid_cgroup_returns_none(self, extractor):
        """Invalid cgroup format returns None."""
        result = extractor("docker.slice")
        assert result is None

    @pytest.mark.unit
    def test_empty_cgroup_returns_none(self, extractor):
        """Empty cgroup returns None."""
        result = extractor("")
        assert result is None
