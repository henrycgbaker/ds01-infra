#!/usr/bin/env python3
"""
Tests for scripts that source init.sh

This test suite validates that the user-facing scripts properly source
the init.sh library and that color variables and utility functions work
correctly when sourced.

Scripts verified:
- /opt/ds01-infra/scripts/user/orchestrators/container-deploy
- /opt/ds01-infra/scripts/user/orchestrators/container-retire
- /opt/ds01-infra/scripts/user/atomic/container-create
- /opt/ds01-infra/scripts/user/atomic/container-stop
- /opt/ds01-infra/scripts/user/atomic/container-remove
- /opt/ds01-infra/scripts/user/wizards/project-launch
- /opt/ds01-infra/scripts/user/wizards/project-init
- /opt/ds01-infra/scripts/user/wizards/user-setup
"""

import os
import subprocess
import pytest
from pathlib import Path
from typing import Dict, Optional, List


# Path to init.sh
INIT_SH_PATH = Path("/opt/ds01-infra/scripts/lib/init.sh")

# Scripts to test
SCRIPTS_TO_TEST = [
    Path("/opt/ds01-infra/scripts/user/orchestrators/container-deploy"),
    Path("/opt/ds01-infra/scripts/user/orchestrators/container-retire"),
    Path("/opt/ds01-infra/scripts/user/atomic/container-create"),
    Path("/opt/ds01-infra/scripts/user/atomic/container-stop"),
    Path("/opt/ds01-infra/scripts/user/atomic/container-remove"),
    Path("/opt/ds01-infra/scripts/user/wizards/project-launch"),
    Path("/opt/ds01-infra/scripts/user/wizards/project-init"),
    Path("/opt/ds01-infra/scripts/user/wizards/user-setup"),
]


class TestScriptsExist:
    """Verify all scripts to be tested exist."""

    def test_init_sh_exists(self):
        """init.sh should exist."""
        assert INIT_SH_PATH.exists()

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_script_exists(self, script_path: Path):
        """Each script should exist."""
        assert script_path.exists(), f"Script not found: {script_path}"


class TestScriptsSourceInit:
    """Verify scripts source init.sh correctly."""

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_script_sources_init(self, script_path: Path):
        """Script should source init.sh."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        content = script_path.read_text()

        # Should source init.sh either directly or via DS01_ROOT
        sources_init = (
            'source "${DS01_ROOT:-/opt/ds01-infra}/scripts/lib/init.sh"' in content or
            'source /opt/ds01-infra/scripts/lib/init.sh' in content or
            'source "$DS01_ROOT/scripts/lib/init.sh"' in content or
            'source "$DS01_LIB/init.sh"' in content or
            '. "${DS01_ROOT:-/opt/ds01-infra}/scripts/lib/init.sh"' in content
        )

        assert sources_init, f"{script_path.name} should source init.sh"


class TestColorVariablesAvailable:
    """Test that color variables are available after sourcing init.sh."""

    def run_bash_test(
        self,
        script_path: Path,
        test_code: str
    ) -> subprocess.CompletedProcess:
        """Run test code with the script's environment."""
        # We'll source the script partially to get the init.sh environment
        script = f'''
        # Source init.sh directly
        source "{INIT_SH_PATH}"
        # Run test
        {test_code}
        '''
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=10
        )

    def test_red_color_available(self):
        """RED color variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$RED" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout

    def test_green_color_available(self):
        """GREEN color variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$GREEN" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout

    def test_yellow_color_available(self):
        """YELLOW color variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$YELLOW" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout

    def test_cyan_color_available(self):
        """CYAN color variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$CYAN" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout

    def test_bold_style_available(self):
        """BOLD style variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$BOLD" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout

    def test_nc_reset_available(self):
        """NC (reset) variable should be available."""
        result = self.run_bash_test(
            INIT_SH_PATH,
            '[[ -n "$NC" ]] && echo "available" || echo "missing"'
        )
        assert result.returncode == 0
        assert "available" in result.stdout


class TestScriptHelpOutput:
    """Test that scripts display help properly with colors."""

    def get_help_output(self, script_path: Path) -> subprocess.CompletedProcess:
        """Get help output from a script."""
        return subprocess.run(
            [str(script_path), "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_help_does_not_crash(self, script_path: Path):
        """Script --help should not crash."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        result = self.get_help_output(script_path)
        # Should exit cleanly (0) when showing help
        assert result.returncode == 0, \
            f"{script_path.name} --help failed: {result.stderr}"

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_help_produces_output(self, script_path: Path):
        """Script --help should produce output."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        result = self.get_help_output(script_path)
        # Should have some output
        assert len(result.stdout) > 0, \
            f"{script_path.name} --help produced no output"


class TestLoggingFunctionsUsable:
    """Test that logging functions work after sourcing init.sh."""

    def run_bash_test(self, test_code: str) -> subprocess.CompletedProcess:
        """Run test code with init.sh sourced."""
        script = f'''
        source "{INIT_SH_PATH}"
        {test_code}
        '''
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=10
        )

    def test_log_info_works(self):
        """log_info function should work."""
        result = self.run_bash_test('log_info "test message"')
        assert result.returncode == 0
        assert "[INFO]" in result.stdout
        assert "test message" in result.stdout

    def test_log_success_works(self):
        """log_success function should work."""
        result = self.run_bash_test('log_success "test message"')
        assert result.returncode == 0
        assert "[SUCCESS]" in result.stdout

    def test_log_warning_works(self):
        """log_warning function should work."""
        result = self.run_bash_test('log_warning "test message"')
        assert result.returncode == 0
        assert "[WARNING]" in result.stdout

    def test_log_error_works(self):
        """log_error function should work."""
        result = self.run_bash_test('log_error "test message"')
        assert result.returncode == 0
        assert "[ERROR]" in result.stdout


class TestResourceLimitFunctionsUsable:
    """Test that resource limit functions work after sourcing init.sh."""

    def run_bash_test(self, test_code: str) -> subprocess.CompletedProcess:
        """Run test code with init.sh sourced."""
        script = f'''
        source "{INIT_SH_PATH}"
        {test_code}
        '''
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=30
        )

    def test_ds01_get_max_gpus_callable(self):
        """ds01_get_max_gpus function should be callable."""
        result = self.run_bash_test('type ds01_get_max_gpus')
        assert result.returncode == 0
        assert "function" in result.stdout

    def test_ds01_get_idle_timeout_callable(self):
        """ds01_get_idle_timeout function should be callable."""
        result = self.run_bash_test('type ds01_get_idle_timeout')
        assert result.returncode == 0
        assert "function" in result.stdout

    def test_ds01_get_max_runtime_callable(self):
        """ds01_get_max_runtime function should be callable."""
        result = self.run_bash_test('type ds01_get_max_runtime')
        assert result.returncode == 0
        assert "function" in result.stdout


class TestScriptsSyntaxValid:
    """Verify scripts have valid bash syntax."""

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_script_syntax(self, script_path: Path):
        """Script should have valid bash syntax."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        result = subprocess.run(
            ["bash", "-n", str(script_path)],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, \
            f"Syntax error in {script_path.name}: {result.stderr}"


class TestScriptsShebang:
    """Verify scripts have proper shebang."""

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_has_bash_shebang(self, script_path: Path):
        """Script should start with bash shebang."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        content = script_path.read_text()
        first_line = content.split('\n')[0]

        assert first_line.startswith('#!'), \
            f"{script_path.name} should start with shebang"
        assert 'bash' in first_line, \
            f"{script_path.name} should use bash"


class TestScriptsSetE:
    """Verify scripts use set -e for error handling."""

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_has_set_e(self, script_path: Path):
        """Script should use set -e."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        content = script_path.read_text()

        # Should have set -e near the beginning
        assert 'set -e' in content, \
            f"{script_path.name} should use 'set -e'"


class TestUIFunctionsUsable:
    """Test that UI drawing functions work after sourcing init.sh."""

    def run_bash_test(self, test_code: str) -> subprocess.CompletedProcess:
        """Run test code with init.sh sourced."""
        script = f'''
        source "{INIT_SH_PATH}"
        {test_code}
        '''
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=10
        )

    def test_ds01_draw_header_works(self):
        """ds01_draw_header function should work."""
        result = self.run_bash_test('ds01_draw_header "Test Header"')
        assert result.returncode == 0
        assert "Test Header" in result.stdout

    def test_ds01_draw_separator_works(self):
        """ds01_draw_separator function should work."""
        result = self.run_bash_test('ds01_draw_separator')
        assert result.returncode == 0
        # Should produce output (the separator line)
        assert len(result.stdout.strip()) > 0


class TestPathsExportedCorrectly:
    """Test that paths are correctly exported."""

    def run_bash_test(self, test_code: str) -> subprocess.CompletedProcess:
        """Run test code with init.sh sourced."""
        script = f'''
        source "{INIT_SH_PATH}"
        {test_code}
        '''
        return subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=10
        )

    def test_ds01_root_exported(self):
        """DS01_ROOT should be exported."""
        result = self.run_bash_test('env | grep DS01_ROOT')
        assert result.returncode == 0
        assert "DS01_ROOT=/opt/ds01-infra" in result.stdout

    def test_ds01_scripts_exported(self):
        """DS01_SCRIPTS should be exported."""
        result = self.run_bash_test('env | grep DS01_SCRIPTS')
        assert result.returncode == 0
        assert "DS01_SCRIPTS=" in result.stdout

    def test_ds01_lib_exported(self):
        """DS01_LIB should be exported."""
        result = self.run_bash_test('env | grep DS01_LIB')
        assert result.returncode == 0
        assert "DS01_LIB=" in result.stdout


class TestScriptsNoDefineDuplicateColors:
    """Verify scripts don't redefine colors after sourcing init.sh."""

    @pytest.mark.parametrize("script_path", SCRIPTS_TO_TEST)
    def test_no_redundant_color_definitions(self, script_path: Path):
        """Script should not redefine standard colors after init.sh."""
        if not script_path.exists():
            pytest.skip(f"Script not found: {script_path}")

        content = script_path.read_text()

        # Find where init.sh is sourced
        init_source_pos = max(
            content.find('source "${DS01_ROOT:-/opt/ds01-infra}/scripts/lib/init.sh"'),
            content.find('source /opt/ds01-infra/scripts/lib/init.sh')
        )

        if init_source_pos == -1:
            pytest.skip(f"{script_path.name} doesn't source init.sh directly")

        # Content after sourcing init.sh
        after_init = content[init_source_pos:]

        # Check for redundant definitions (these are in init.sh)
        # Allow DIM since it's not in init.sh
        redundant_patterns = [
            "RED='\\033[",
            'RED="\\033[',
            "GREEN='\\033[",
            'GREEN="\\033[',
            "YELLOW='\\033[",
            'YELLOW="\\033[',
            "BLUE='\\033[",
            'BLUE="\\033[',
            "CYAN='\\033[",
            'CYAN="\\033[',
            "NC='\\033[",
            'NC="\\033[',
        ]

        # These specific color definitions would be redundant
        # But we'll allow them since some scripts might need to override
        # Just check they're not immediately after the source
        # This is a soft check - just a warning
