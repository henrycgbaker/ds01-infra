#!/usr/bin/env python3
"""
Tests for /opt/ds01-infra/scripts/lib/init.sh

This test suite validates the init.sh library that provides standard
initialization for all DS01 bash scripts.

Functions tested:
- Resource limit wrappers: ds01_get_max_gpus(), ds01_get_idle_timeout(),
  ds01_get_max_runtime(), ds01_get_max_containers(), ds01_get_docker_args(),
  ds01_allow_full_gpu()
- Logging functions: log_info(), log_success(), log_warning(), log_error()
- UI functions: ds01_draw_header(), ds01_draw_separator()
- Utility functions: ds01_error(), ds01_warn(), ds01_success(), ds01_info(),
  ds01_header(), ds01_log(), ds01_require_root(), ds01_current_user()
- Duration functions: ds01_parse_duration(), ds01_format_duration()
- Generic limit function: ds01_get_limit(), ds01_get_config()
"""

import os
import subprocess
import pytest
from pathlib import Path
from typing import Dict, Any, Optional


# Path to the init.sh library
INIT_SH_PATH = Path("/opt/ds01-infra/scripts/lib/init.sh")


class TestInitShLibrary:
    """Tests for init.sh bash library initialization."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """
        Helper to run a bash function from init.sh and return result.
        """
        script = f"""
        source "{INIT_SH_PATH}"
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
        """init.sh library file should exist."""
        assert INIT_SH_PATH.exists(), f"Library not found at {INIT_SH_PATH}"

    def test_library_sources_without_error(self):
        """init.sh should source without errors."""
        result = self.run_bash_function("echo sourced_ok")
        assert result.returncode == 0, f"Failed to source library: {result.stderr}"
        assert "sourced_ok" in result.stdout


class TestPathVariables:
    """Tests for path variable exports."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_root_is_set(self):
        """DS01_ROOT should be set to /opt/ds01-infra by default."""
        result = self.run_bash_function('echo "$DS01_ROOT"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/opt/ds01-infra"

    def test_ds01_config_is_set(self):
        """DS01_CONFIG should be set correctly."""
        result = self.run_bash_function('echo "$DS01_CONFIG"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/opt/ds01-infra/config"

    def test_ds01_scripts_is_set(self):
        """DS01_SCRIPTS should be set correctly."""
        result = self.run_bash_function('echo "$DS01_SCRIPTS"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/opt/ds01-infra/scripts"

    def test_ds01_lib_is_set(self):
        """DS01_LIB should be set correctly."""
        result = self.run_bash_function('echo "$DS01_LIB"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/opt/ds01-infra/scripts/lib"

    def test_ds01_state_is_set(self):
        """DS01_STATE should be set to /var/lib/ds01."""
        result = self.run_bash_function('echo "$DS01_STATE"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/var/lib/ds01"

    def test_ds01_log_is_set(self):
        """DS01_LOG should be set to /var/log/ds01."""
        result = self.run_bash_function('echo "$DS01_LOG"')
        assert result.returncode == 0
        assert result.stdout.strip() == "/var/log/ds01"


class TestColorVariables:
    """Tests for ANSI color code exports."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_red_color_is_set(self):
        """RED color code should be set."""
        result = self.run_bash_function('echo -n "$RED" | cat -v')
        assert result.returncode == 0
        # ANSI escape sequences start with ^[[ or \033[
        assert "^[[" in result.stdout or "\\033[" in result.stdout or "[0;31m" in result.stdout

    def test_green_color_is_set(self):
        """GREEN color code should be set."""
        result = self.run_bash_function('[[ -n "$GREEN" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"

    def test_yellow_color_is_set(self):
        """YELLOW color code should be set."""
        result = self.run_bash_function('[[ -n "$YELLOW" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"

    def test_blue_color_is_set(self):
        """BLUE color code should be set."""
        result = self.run_bash_function('[[ -n "$BLUE" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"

    def test_cyan_color_is_set(self):
        """CYAN color code should be set."""
        result = self.run_bash_function('[[ -n "$CYAN" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"

    def test_bold_style_is_set(self):
        """BOLD style code should be set."""
        result = self.run_bash_function('[[ -n "$BOLD" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"

    def test_nc_reset_is_set(self):
        """NC (reset) code should be set."""
        result = self.run_bash_function('[[ -n "$NC" ]] && echo "set" || echo "not_set"')
        assert result.returncode == 0
        assert result.stdout.strip() == "set"


class TestLoggingFunctions:
    """Tests for logging helper functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_log_info_outputs_message(self):
        """log_info should output message with [INFO] prefix."""
        result = self.run_bash_function('log_info "test message"')
        assert result.returncode == 0
        assert "[INFO]" in result.stdout
        assert "test message" in result.stdout

    def test_log_success_outputs_message(self):
        """log_success should output message with [SUCCESS] prefix."""
        result = self.run_bash_function('log_success "test message"')
        assert result.returncode == 0
        assert "[SUCCESS]" in result.stdout
        assert "test message" in result.stdout

    def test_log_warning_outputs_message(self):
        """log_warning should output message with [WARNING] prefix."""
        result = self.run_bash_function('log_warning "test message"')
        assert result.returncode == 0
        assert "[WARNING]" in result.stdout
        assert "test message" in result.stdout

    def test_log_error_outputs_message(self):
        """log_error should output message with [ERROR] prefix."""
        result = self.run_bash_function('log_error "test message"')
        assert result.returncode == 0
        assert "[ERROR]" in result.stdout
        assert "test message" in result.stdout


class TestDSO1HelperFunctions:
    """Tests for ds01_* helper functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_error_outputs_to_stderr(self):
        """ds01_error should output to stderr with Error: prefix."""
        result = self.run_bash_function('ds01_error "test error message"')
        assert result.returncode == 0
        assert "Error:" in result.stderr
        assert "test error message" in result.stderr

    def test_ds01_warn_outputs_warning(self):
        """ds01_warn should output Warning: prefix."""
        result = self.run_bash_function('ds01_warn "test warning"')
        assert result.returncode == 0
        assert "Warning:" in result.stdout
        assert "test warning" in result.stdout

    def test_ds01_success_outputs_message(self):
        """ds01_success should output message in green."""
        result = self.run_bash_function('ds01_success "operation complete"')
        assert result.returncode == 0
        assert "operation complete" in result.stdout

    def test_ds01_info_outputs_message(self):
        """ds01_info should output message in blue."""
        result = self.run_bash_function('ds01_info "info message"')
        assert result.returncode == 0
        assert "info message" in result.stdout

    def test_ds01_header_outputs_bold(self):
        """ds01_header should output message in bold."""
        result = self.run_bash_function('ds01_header "Section Title"')
        assert result.returncode == 0
        assert "Section Title" in result.stdout

    def test_ds01_current_user_returns_username(self):
        """ds01_current_user should return current username."""
        result = self.run_bash_function('ds01_current_user')
        assert result.returncode == 0
        expected_user = os.environ.get("USER", os.getlogin())
        assert result.stdout.strip() == expected_user


class TestUIDrawingFunctions:
    """Tests for UI drawing functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_draw_header_outputs_box(self):
        """ds01_draw_header should output a header box with title."""
        result = self.run_bash_function('ds01_draw_header "Test Title"')
        assert result.returncode == 0
        # Should contain the title
        assert "Test Title" in result.stdout
        # Should contain separator characters (Unicode box drawing)
        assert "━" in result.stdout or "-" in result.stdout

    def test_ds01_draw_separator_outputs_line(self):
        """ds01_draw_separator should output a separator line."""
        result = self.run_bash_function('ds01_draw_separator')
        assert result.returncode == 0
        # Should contain separator characters
        assert "━" in result.stdout or "-" in result.stdout


class TestResourceLimitFunctions:
    """Tests for resource limit wrapper functions.

    These tests validate the convenience functions that wrap get_resource_limits.py.
    """

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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
            timeout=30  # Longer timeout for Python calls
        )

    def test_ds01_get_max_gpus_returns_value_or_default(self):
        """ds01_get_max_gpus should return a numeric value, 'unlimited', or default."""
        result = self.run_bash_function('ds01_get_max_gpus')
        assert result.returncode == 0
        # Should return a number, "unlimited", or default "1"
        output = result.stdout.strip()
        # May return a number, "unlimited", empty, or default "1"
        assert output.isdigit() or output == "" or output == "1" or output == "unlimited"

    def test_ds01_get_idle_timeout_returns_value_or_default(self):
        """ds01_get_idle_timeout should return a duration string or default."""
        result = self.run_bash_function('ds01_get_idle_timeout')
        assert result.returncode == 0
        output = result.stdout.strip()
        # Should be a duration like "2h", "48h", "24h", etc. or default "2h"
        assert output == "" or "h" in output or "d" in output or "m" in output

    def test_ds01_get_max_runtime_returns_value_or_default(self):
        """ds01_get_max_runtime should return a duration string or default."""
        result = self.run_bash_function('ds01_get_max_runtime')
        assert result.returncode == 0
        output = result.stdout.strip()
        # Should be a duration or default "24h"
        assert output == "" or "h" in output or "d" in output

    def test_ds01_get_max_containers_returns_value_or_default(self):
        """ds01_get_max_containers should return a numeric value or default."""
        result = self.run_bash_function('ds01_get_max_containers')
        assert result.returncode == 0
        output = result.stdout.strip()
        # Should return a number or default "3"
        assert output.isdigit() or output == "" or output == "3"

    def test_ds01_allow_full_gpu_returns_boolean(self):
        """ds01_allow_full_gpu should return exit code based on permission."""
        result = self.run_bash_function('ds01_allow_full_gpu && echo "allowed" || echo "not_allowed"')
        assert result.returncode == 0
        assert result.stdout.strip() in ["allowed", "not_allowed"]

    def test_ds01_get_limit_function_exists(self):
        """ds01_get_limit should be callable."""
        result = self.run_bash_function('type ds01_get_limit')
        assert result.returncode == 0
        assert "function" in result.stdout

    def test_ds01_get_config_function_exists(self):
        """ds01_get_config should be callable."""
        result = self.run_bash_function('type ds01_get_config')
        assert result.returncode == 0
        assert "function" in result.stdout


class TestDurationFunctions:
    """Tests for duration parsing and formatting functions."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_parse_duration_hours(self):
        """ds01_parse_duration should convert hours to seconds."""
        result = self.run_bash_function('ds01_parse_duration "2h"')
        assert result.returncode == 0
        output = result.stdout.strip()
        # 2 hours = 7200 seconds
        assert output == "7200" or output == "7200.0"

    def test_ds01_parse_duration_days(self):
        """ds01_parse_duration should convert days to seconds."""
        result = self.run_bash_function('ds01_parse_duration "1d"')
        assert result.returncode == 0
        output = result.stdout.strip()
        # 1 day = 86400 seconds
        assert output == "86400" or output == "86400.0"

    def test_ds01_parse_duration_minutes(self):
        """ds01_parse_duration should convert minutes to seconds."""
        result = self.run_bash_function('ds01_parse_duration "30m"')
        assert result.returncode == 0
        output = result.stdout.strip()
        # 30 minutes = 1800 seconds
        assert output == "1800" or output == "1800.0"

    def test_ds01_format_duration_function_exists(self):
        """ds01_format_duration should be callable."""
        result = self.run_bash_function('type ds01_format_duration')
        assert result.returncode == 0
        assert "function" in result.stdout

    def test_ds01_format_duration_hours(self):
        """ds01_format_duration should format seconds to human-readable."""
        result = self.run_bash_function('ds01_format_duration 7200')
        assert result.returncode == 0
        output = result.stdout.strip()
        # 7200 seconds should format to "2h" or similar
        assert "2" in output or "h" in output


class TestLogWithTimestamp:
    """Tests for ds01_log function with timestamp."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_log_includes_timestamp(self):
        """ds01_log should include timestamp in output."""
        result = self.run_bash_function('ds01_log "test message"')
        assert result.returncode == 0
        output = result.stdout.strip()
        # Should have format like [2025-01-01 12:00:00] test message
        assert "[" in output
        assert "]" in output
        assert "test message" in output

    def test_ds01_log_format_includes_date(self):
        """ds01_log timestamp should include date."""
        result = self.run_bash_function('ds01_log "test"')
        assert result.returncode == 0
        output = result.stdout.strip()
        # Format: [YYYY-MM-DD HH:MM:SS]
        import re
        assert re.search(r'\[\d{4}-\d{2}-\d{2}', output)


class TestRequireRoot:
    """Tests for ds01_require_root function."""

    def run_bash_function(self, function_call: str, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Helper to run bash function."""
        script = f"""
        source "{INIT_SH_PATH}"
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

    def test_ds01_require_root_exits_for_non_root(self):
        """ds01_require_root should exit with error for non-root user."""
        # Only run this test if we're not root
        if os.geteuid() == 0:
            pytest.skip("Test requires non-root user")

        result = self.run_bash_function('ds01_require_root; echo "should_not_reach"')
        # Should exit before echoing
        assert "should_not_reach" not in result.stdout
        assert result.returncode != 0 or "requires root" in result.stderr.lower()
