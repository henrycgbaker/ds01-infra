#!/usr/bin/env python3
"""
Unit Tests: Resource Limits Parser
Tests get_resource_limits.py functionality with mocked config
"""

import pytest
import yaml
from pathlib import Path
from unittest.mock import patch, mock_open

import sys
sys.path.insert(0, "/opt/ds01-infra/scripts/docker")


class TestResourceLimitParser:
    """Tests for ResourceLimitParser class."""

    @pytest.fixture
    def parser_with_config(self, temp_config_file):
        """Create parser with test config file."""
        from get_resource_limits import ResourceLimitParser
        return ResourceLimitParser(config_path=str(temp_config_file))

    @pytest.fixture
    def sample_config(self, sample_resource_limits):
        """Access the sample resource limits from conftest."""
        return sample_resource_limits

    # =========================================================================
    # User Group Resolution Tests
    # =========================================================================

    @pytest.mark.unit
    def test_user_in_students_group(self, parser_with_config):
        """User in students group returns 'students'."""
        group = parser_with_config.get_user_group("student1")
        assert group == "students"

    @pytest.mark.unit
    def test_user_in_researchers_group(self, parser_with_config):
        """User in researchers group returns 'researchers'."""
        group = parser_with_config.get_user_group("researcher1")
        assert group == "researchers"

    @pytest.mark.unit
    def test_user_with_override(self, parser_with_config):
        """User with override returns 'override'."""
        group = parser_with_config.get_user_group("special_user")
        assert group == "override"

    @pytest.mark.unit
    def test_unknown_user_gets_default_group(self, parser_with_config):
        """Unknown user gets default group."""
        group = parser_with_config.get_user_group("unknown_user")
        # Default group is 'student' per sample config
        assert group in ["student", "students"]

    # =========================================================================
    # Resource Limits Resolution Tests
    # =========================================================================

    @pytest.mark.unit
    def test_student_gets_student_limits(self, parser_with_config):
        """Student gets student-tier limits."""
        limits = parser_with_config.get_user_limits("student1")
        assert limits.get("max_mig_instances") == 1
        assert limits.get("max_cpus") == 8
        assert limits.get("memory") == "32g"
        assert limits.get("priority") == 10

    @pytest.mark.unit
    def test_researcher_gets_researcher_limits(self, parser_with_config):
        """Researcher gets researcher-tier limits."""
        limits = parser_with_config.get_user_limits("researcher1")
        assert limits.get("max_mig_instances") == 2
        assert limits.get("max_cpus") == 16
        assert limits.get("memory") == "64g"
        assert limits.get("priority") == 50

    @pytest.mark.unit
    def test_admin_gets_unlimited_gpus(self, parser_with_config):
        """Admin gets unlimited GPU allocation (None)."""
        limits = parser_with_config.get_user_limits("admin1")
        assert limits.get("max_mig_instances") is None  # unlimited
        assert limits.get("priority") == 100

    @pytest.mark.unit
    def test_override_takes_precedence(self, parser_with_config):
        """User override takes precedence over group membership."""
        limits = parser_with_config.get_user_limits("special_user")
        assert limits.get("max_mig_instances") == 4
        assert limits.get("priority") == 90

    @pytest.mark.unit
    def test_defaults_inherited(self, parser_with_config):
        """Group limits inherit from defaults."""
        limits = parser_with_config.get_user_limits("student1")
        # These should come from defaults since not specified in group
        assert "idle_timeout" in limits
        assert "max_runtime" in limits

    # =========================================================================
    # Priority Resolution Tests
    # =========================================================================

    @pytest.mark.unit
    def test_priority_order(self, parser_with_config):
        """Verify priority order: override > group > defaults."""
        student_priority = parser_with_config.get_user_limits("student1").get("priority")
        researcher_priority = parser_with_config.get_user_limits("researcher1").get("priority")
        admin_priority = parser_with_config.get_user_limits("admin1").get("priority")
        override_priority = parser_with_config.get_user_limits("special_user").get("priority")

        assert student_priority < researcher_priority < admin_priority
        assert override_priority == 90

    # =========================================================================
    # Docker Args Generation Tests
    # =========================================================================

    @pytest.mark.unit
    def test_docker_args_includes_cpus(self, parser_with_config):
        """Docker args include CPU limit."""
        args = parser_with_config.get_docker_args("student1")
        assert any("--cpus=" in arg for arg in args)

    @pytest.mark.unit
    def test_docker_args_includes_memory(self, parser_with_config):
        """Docker args include memory limit."""
        args = parser_with_config.get_docker_args("student1")
        assert any("--memory=" in arg or "-m" in arg for arg in args)

    # =========================================================================
    # Edge Cases
    # =========================================================================

    @pytest.mark.unit
    def test_empty_config_raises(self, temp_dir):
        """Empty config file raises appropriate error."""
        empty_config = temp_dir / "empty.yaml"
        empty_config.write_text("")

        from get_resource_limits import ResourceLimitParser

        with pytest.raises((ValueError, TypeError)):
            parser = ResourceLimitParser(str(empty_config))
            parser.get_user_limits("anyone")

    @pytest.mark.unit
    def test_missing_config_raises(self):
        """Missing config file raises FileNotFoundError."""
        from get_resource_limits import ResourceLimitParser

        with pytest.raises(FileNotFoundError):
            ResourceLimitParser("/nonexistent/config.yaml")

    @pytest.mark.unit
    def test_null_values_handled(self, temp_dir):
        """Null values in config are handled correctly."""
        config = {
            "defaults": {
                "max_mig_instances": 1,
                "max_cpus": 8,
                "memory": "32g",
                "idle_timeout": None,  # null = disabled
                "priority": 50
            },
            "groups": {},
            "user_overrides": {}
        }

        config_file = temp_dir / "null-config.yaml"
        with open(config_file, "w") as f:
            yaml.safe_dump(config, f)

        from get_resource_limits import ResourceLimitParser
        parser = ResourceLimitParser(str(config_file))
        limits = parser.get_user_limits("anyone")

        assert limits.get("idle_timeout") is None  # Should be None, not error


class TestResourceLimitParserIntegration:
    """Integration tests using real config file."""

    @pytest.mark.unit
    def test_real_config_loads(self, config_dir):
        """Real config file loads without errors."""
        config_file = config_dir / "resource-limits.yaml"
        if not config_file.exists():
            pytest.skip("Real config file not found")

        from get_resource_limits import ResourceLimitParser
        parser = ResourceLimitParser(str(config_file))

        # Should not raise
        defaults = parser.config.get("defaults", {})
        assert defaults is not None
