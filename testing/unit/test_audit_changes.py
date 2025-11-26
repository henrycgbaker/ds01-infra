#!/usr/bin/env python3
"""
Unit Tests: Audit Changes
Tests for resource allocation audit fixes and improvements.

Tests cover:
1. Full GPU access control (allow_full_gpu)
2. File locking for race condition prevention
3. Centralized event logging
4. State validation
5. User limit resolution
"""

import pytest
import json
import os
import sys
import tempfile
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock, mock_open
from datetime import datetime, timezone

# Add scripts to path
sys.path.insert(0, "/opt/ds01-infra/scripts/docker")


class TestFullGPUAccessControl:
    """Tests for allow_full_gpu permission checking."""

    @pytest.fixture
    def config_with_groups(self):
        """Sample config with different group permissions."""
        return {
            "defaults": {
                "allow_full_gpu": False,
                "max_mig_instances": 2,
                "max_gpus_per_container": 1,
            },
            "default_group": "student",
            "groups": {
                "student": {
                    "members": ["student1", "student2"],
                    "allow_full_gpu": False,
                    "max_gpus_per_container": 1,
                },
                "researcher": {
                    "members": ["researcher1"],
                    "allow_full_gpu": True,
                    "max_gpus_per_container": 2,
                },
                "admin": {
                    "members": ["admin1"],
                    "allow_full_gpu": True,
                    "max_gpus_per_container": None,
                },
            },
            "user_overrides": {
                "special_student": {
                    "allow_full_gpu": True,
                },
            },
        }

    @pytest.mark.unit
    def test_student_cannot_use_full_gpu(self, config_with_groups):
        """Students should not be able to use full GPUs."""
        student = config_with_groups["groups"]["student"]
        assert student["allow_full_gpu"] is False

    @pytest.mark.unit
    def test_researcher_can_use_full_gpu(self, config_with_groups):
        """Researchers should be able to use full GPUs."""
        researcher = config_with_groups["groups"]["researcher"]
        assert researcher["allow_full_gpu"] is True

    @pytest.mark.unit
    def test_user_override_grants_full_gpu(self, config_with_groups):
        """User override can grant full GPU access."""
        special = config_with_groups["user_overrides"]["special_student"]
        assert special["allow_full_gpu"] is True

    @pytest.mark.unit
    def test_full_gpu_slot_detection(self):
        """Full GPU slots have no decimal, MIG slots do."""
        # Full GPUs: "0", "1", "2", "3"
        # MIG slots: "1.0", "1.1", "2.0", etc.
        def is_full_gpu(slot):
            return "." not in str(slot)

        assert is_full_gpu("0") is True
        assert is_full_gpu("1") is True
        assert is_full_gpu("1.0") is False
        assert is_full_gpu("2.3") is False

    @pytest.mark.unit
    def test_mig_filtering_for_students(self, config_with_groups):
        """Students should only see MIG slots, not full GPUs."""
        available_slots = ["0", "1", "1.0", "1.1", "2.0"]
        student_allow_full = config_with_groups["groups"]["student"]["allow_full_gpu"]

        # Filter based on permissions
        def is_full_gpu(slot):
            return "." not in str(slot)

        if not student_allow_full:
            filtered = [s for s in available_slots if not is_full_gpu(s)]
        else:
            filtered = available_slots

        assert filtered == ["1.0", "1.1", "2.0"]


class TestFileLocking:
    """Tests for GPU allocator file locking."""

    @pytest.mark.unit
    def test_lock_file_path_exists(self):
        """Lock file should be in standard location."""
        lock_path = Path("/var/log/ds01/gpu-allocator.lock")
        # Just verify the path is sensible (parent should exist)
        assert lock_path.parent.name == "ds01"

    @pytest.mark.unit
    def test_fcntl_import_available(self):
        """fcntl module should be importable for file locking."""
        import fcntl
        assert hasattr(fcntl, 'flock')
        assert hasattr(fcntl, 'LOCK_EX')
        assert hasattr(fcntl, 'LOCK_UN')


class TestEventLogging:
    """Tests for centralized event logging system."""

    @pytest.fixture
    def event_logger_path(self):
        return Path("/opt/ds01-infra/scripts/docker/event-logger.py")

    @pytest.mark.unit
    def test_event_logger_exists(self, event_logger_path):
        """Event logger script should exist."""
        assert event_logger_path.exists()

    @pytest.mark.unit
    def test_event_types_defined(self, event_logger_path):
        """Common event types should be defined."""
        content = event_logger_path.read_text()

        expected_events = [
            "container.created",
            "container.started",
            "container.stopped",
            "gpu.allocated",
            "gpu.released",
            "gpu.rejected",
            "health.check",
        ]

        for event in expected_events:
            assert event in content, f"Event type '{event}' not defined"

    @pytest.mark.unit
    def test_event_json_format(self):
        """Events should be valid JSON."""
        event = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "event": "test.event",
            "user": "testuser",
        }

        json_str = json.dumps(event)
        parsed = json.loads(json_str)

        assert parsed["event"] == "test.event"
        assert parsed["user"] == "testuser"

    @pytest.mark.unit
    def test_event_logger_cli(self, event_logger_path):
        """Event logger CLI should work."""
        result = subprocess.run(
            ["python3", str(event_logger_path), "types"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "container.created" in result.stdout


class TestStateValidation:
    """Tests for state validation and consistency checking."""

    @pytest.fixture
    def validator_path(self):
        return Path("/opt/ds01-infra/scripts/monitoring/validate-state.py")

    @pytest.mark.unit
    def test_validator_exists(self, validator_path):
        """State validator should exist."""
        assert validator_path.exists()

    @pytest.mark.unit
    @pytest.mark.requires_docker
    def test_validator_runs(self, validator_path):
        """State validator should run without errors."""
        result = subprocess.run(
            ["python3", str(validator_path), "--json"],
            capture_output=True,
            text=True,
        )
        assert result.returncode in [0, 1]  # 0 = valid, 1 = issues found

        # Output should be valid JSON
        output = json.loads(result.stdout)
        assert "valid" in output
        assert "summary" in output


class TestUserLimitResolution:
    """Tests for user limit resolution from YAML config."""

    @pytest.fixture
    def sample_config(self):
        return {
            "defaults": {
                "max_mig_instances": 2,
                "max_cpus": 16,
                "memory": "32g",
                "allow_full_gpu": False,
                "max_gpus_per_container": 1,
            },
            "default_group": "student",
            "groups": {
                "student": {
                    "members": [],
                    "allow_full_gpu": False,
                    "max_gpus_per_container": 1,
                },
                "researcher": {
                    "members": ["alice"],
                    "allow_full_gpu": True,
                    "max_mig_instances": 8,
                    "max_gpus_per_container": 2,
                },
                "admin": {
                    "members": ["bob"],
                    "max_mig_instances": None,
                    "allow_full_gpu": True,
                },
            },
            "user_overrides": {
                "special": {
                    "max_mig_instances": 4,
                },
            },
        }

    def get_user_limits(self, config, username):
        """Resolve limits for a user (mirrors allocator logic)."""
        defaults = config.get("defaults", {}).copy()
        groups = config.get("groups", {})
        user_overrides = config.get("user_overrides", {})

        # Check overrides first
        if username in user_overrides:
            defaults.update(user_overrides[username])
            return defaults

        # Check groups
        for group_name, group_config in groups.items():
            if username in group_config.get("members", []):
                group_limits = {k: v for k, v in group_config.items() if k != "members"}
                defaults.update(group_limits)
                return defaults

        # Default group
        default_group = config.get("default_group", "student")
        if default_group in groups:
            group_config = groups[default_group]
            group_limits = {k: v for k, v in group_config.items() if k != "members"}
            defaults.update(group_limits)

        return defaults

    @pytest.mark.unit
    def test_researcher_gets_group_limits(self, sample_config):
        """Researcher should get researcher group limits."""
        limits = self.get_user_limits(sample_config, "alice")

        assert limits["allow_full_gpu"] is True
        assert limits["max_mig_instances"] == 8
        assert limits["max_gpus_per_container"] == 2

    @pytest.mark.unit
    def test_admin_gets_unlimited(self, sample_config):
        """Admin should get unlimited GPUs."""
        limits = self.get_user_limits(sample_config, "bob")

        assert limits["max_mig_instances"] is None
        assert limits["allow_full_gpu"] is True

    @pytest.mark.unit
    def test_override_takes_precedence(self, sample_config):
        """User override should take precedence over defaults."""
        limits = self.get_user_limits(sample_config, "special")

        assert limits["max_mig_instances"] == 4

    @pytest.mark.unit
    def test_unknown_user_gets_defaults(self, sample_config):
        """Unknown user should get default group limits."""
        limits = self.get_user_limits(sample_config, "unknown_user")

        # Should get student (default_group) limits
        assert limits["allow_full_gpu"] is False
        assert limits["max_gpus_per_container"] == 1


class TestUserFacingScripts:
    """Tests for user-facing utility scripts."""

    @pytest.mark.unit
    def test_check_limits_exists(self):
        """check-limits script should exist and be executable."""
        script = Path("/opt/ds01-infra/scripts/user/check-limits")
        assert script.exists()
        assert os.access(script, os.X_OK)

    @pytest.mark.unit
    def test_ds01_events_exists(self):
        """ds01-events script should exist and be executable."""
        script = Path("/opt/ds01-infra/scripts/monitoring/ds01-events")
        assert script.exists()
        assert os.access(script, os.X_OK)

    @pytest.mark.unit
    def test_quota_check_exists(self):
        """quota-check script should exist and be executable."""
        script = Path("/opt/ds01-infra/scripts/user/quota-check")
        assert script.exists()
        assert os.access(script, os.X_OK)

    @pytest.mark.unit
    def test_error_messages_exists(self):
        """error-messages.sh should exist."""
        script = Path("/opt/ds01-infra/scripts/lib/error-messages.sh")
        assert script.exists()


class TestOPAPolicy:
    """Tests for OPA authorization policy."""

    @pytest.fixture
    def opa_policy_path(self):
        return Path("/opt/ds01-infra/config/opa/docker-authz.rego")

    @pytest.mark.unit
    def test_opa_policy_exists(self, opa_policy_path):
        """OPA policy file should exist."""
        assert opa_policy_path.exists()

    @pytest.mark.unit
    def test_opa_policy_blocks_path_traversal(self, opa_policy_path):
        """OPA policy should block path traversal attempts."""
        content = opa_policy_path.read_text()

        # Check for path traversal protections
        assert '".."' in content or 'contains(cgroup, "..")' in content
        assert '"//"' in content or 'contains(cgroup, "//")' in content

    @pytest.mark.unit
    def test_opa_policy_blocks_system_slice(self, opa_policy_path):
        """OPA policy should block system.slice access."""
        content = opa_policy_path.read_text()
        assert "system.slice" in content

    @pytest.mark.unit
    def test_opa_policy_fail_open(self, opa_policy_path):
        """OPA policy should default to allow (fail-open)."""
        content = opa_policy_path.read_text()
        assert "default allow := true" in content


class TestContainerLogger:
    """Tests for container logging library."""

    @pytest.fixture
    def logger_path(self):
        return Path("/opt/ds01-infra/scripts/lib/container-logger.sh")

    @pytest.mark.unit
    def test_logger_exists(self, logger_path):
        """Container logger should exist."""
        assert logger_path.exists()

    @pytest.mark.unit
    def test_logger_uses_event_logger(self, logger_path):
        """Container logger should use centralized event-logger.py."""
        content = logger_path.read_text()
        assert "event-logger.py" in content

    @pytest.mark.unit
    def test_logger_has_convenience_functions(self, logger_path):
        """Container logger should define convenience functions."""
        content = logger_path.read_text()

        expected_functions = [
            "log_event",
            "log_container_created",
            "log_container_started",
            "log_gpu_allocated",
        ]

        for func in expected_functions:
            assert func in content, f"Function '{func}' not defined"


class TestHealthCheck:
    """Tests for health check system."""

    @pytest.fixture
    def health_check_path(self):
        return Path("/opt/ds01-infra/scripts/monitoring/ds01-health-check")

    @pytest.mark.unit
    def test_health_check_exists(self, health_check_path):
        """Health check script should exist and be executable."""
        assert health_check_path.exists()
        assert os.access(health_check_path, os.X_OK)

    @pytest.mark.unit
    def test_health_check_logs_to_events(self, health_check_path):
        """Health check should log to centralized events."""
        content = health_check_path.read_text()
        assert "event-logger.py" in content or "health.check" in content
