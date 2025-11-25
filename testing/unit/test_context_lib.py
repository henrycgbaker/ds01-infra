#!/usr/bin/env python3
"""
Unit Tests: Context Library (ds01-context.sh)
Tests context detection and conditional output via shell subprocess
"""

import pytest
import os
import subprocess
from pathlib import Path


CONTEXT_LIB = "/opt/ds01-infra/scripts/lib/ds01-context.sh"


class TestContextLibrary:
    """Tests for ds01-context.sh functions."""

    def run_bash(self, script: str, env: dict = None) -> subprocess.CompletedProcess:
        """Run bash script with context library sourced."""
        full_script = f"source {CONTEXT_LIB}; {script}"
        script_env = os.environ.copy()
        # Clear existing context
        script_env.pop("DS01_CONTEXT", None)
        script_env.pop("DS01_INTERFACE", None)
        if env:
            script_env.update(env)

        return subprocess.run(
            ["bash", "-c", full_script],
            capture_output=True,
            text=True,
            env=script_env
        )

    # =========================================================================
    # Context Detection Tests
    # =========================================================================

    @pytest.mark.unit
    def test_default_context_is_atomic(self):
        """Default context is atomic when DS01_CONTEXT not set."""
        result = self.run_bash("get_ds01_context")
        assert result.stdout.strip() == "atomic"

    @pytest.mark.unit
    def test_explicit_orchestration_context(self):
        """DS01_CONTEXT=orchestration returns orchestration."""
        result = self.run_bash(
            "get_ds01_context",
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert result.stdout.strip() == "orchestration"

    @pytest.mark.unit
    def test_explicit_atomic_context(self):
        """DS01_CONTEXT=atomic returns atomic."""
        result = self.run_bash(
            "get_ds01_context",
            env={"DS01_CONTEXT": "atomic"}
        )
        assert result.stdout.strip() == "atomic"

    # =========================================================================
    # Context Check Functions Tests
    # =========================================================================

    @pytest.mark.unit
    def test_is_orchestration_context_true(self):
        """is_orchestration_context returns 0 when in orchestration."""
        result = self.run_bash(
            "is_orchestration_context && echo yes || echo no",
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert result.stdout.strip() == "yes"

    @pytest.mark.unit
    def test_is_orchestration_context_false(self):
        """is_orchestration_context returns 1 when not in orchestration."""
        result = self.run_bash(
            "is_orchestration_context && echo yes || echo no",
            env={"DS01_CONTEXT": "atomic"}
        )
        assert result.stdout.strip() == "no"

    @pytest.mark.unit
    def test_is_atomic_context_true(self):
        """is_atomic_context returns 0 when in atomic."""
        result = self.run_bash(
            "is_atomic_context && echo yes || echo no",
            env={"DS01_CONTEXT": "atomic"}
        )
        assert result.stdout.strip() == "yes"

    @pytest.mark.unit
    def test_is_atomic_context_false(self):
        """is_atomic_context returns 1 when not in atomic."""
        result = self.run_bash(
            "is_atomic_context && echo yes || echo no",
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert result.stdout.strip() == "no"

    @pytest.mark.unit
    def test_default_is_atomic(self):
        """Default (no env var) is treated as atomic."""
        result = self.run_bash("is_atomic_context && echo yes || echo no")
        assert result.stdout.strip() == "yes"

    # =========================================================================
    # Context Setting Functions Tests
    # =========================================================================

    @pytest.mark.unit
    def test_set_orchestration_context(self):
        """set_orchestration_context sets context and interface."""
        result = self.run_bash(
            'set_orchestration_context; echo "$DS01_CONTEXT|$DS01_INTERFACE"'
        )
        assert result.stdout.strip() == "orchestration|orchestration"

    @pytest.mark.unit
    def test_set_atomic_context(self):
        """set_atomic_context sets context and interface."""
        result = self.run_bash(
            'set_atomic_context; echo "$DS01_CONTEXT|$DS01_INTERFACE"'
        )
        assert result.stdout.strip() == "atomic|atomic"

    # =========================================================================
    # Interface Label Tests
    # =========================================================================

    @pytest.mark.unit
    def test_get_interface_label_default(self):
        """get_interface_label returns atomic by default."""
        result = self.run_bash("get_interface_label")
        assert result.stdout.strip() == "atomic"

    @pytest.mark.unit
    def test_get_interface_label_orchestration(self):
        """get_interface_label returns orchestration when set."""
        result = self.run_bash(
            "get_interface_label",
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert result.stdout.strip() == "orchestration"

    @pytest.mark.unit
    def test_get_interface_label_explicit(self):
        """DS01_INTERFACE overrides DS01_CONTEXT for label."""
        result = self.run_bash(
            "get_interface_label",
            env={"DS01_CONTEXT": "atomic", "DS01_INTERFACE": "orchestration"}
        )
        assert result.stdout.strip() == "orchestration"

    # =========================================================================
    # Conditional Output Tests
    # =========================================================================

    @pytest.mark.unit
    def test_show_atomic_next_steps_in_atomic(self):
        """show_atomic_next_steps shows output in atomic context."""
        result = self.run_bash(
            'show_atomic_next_steps "step1" "step2"',
            env={"DS01_CONTEXT": "atomic"}
        )
        assert "Next steps" in result.stdout
        assert "step1" in result.stdout
        assert "step2" in result.stdout

    @pytest.mark.unit
    def test_show_atomic_next_steps_in_orchestration(self):
        """show_atomic_next_steps suppressed in orchestration context."""
        result = self.run_bash(
            'show_atomic_next_steps "step1" "step2"',
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert "Next steps" not in result.stdout
        assert "step1" not in result.stdout

    @pytest.mark.unit
    def test_show_success_in_atomic(self):
        """show_success shows output in atomic context."""
        result = self.run_bash(
            'show_success "Container created" "my-container"',
            env={"DS01_CONTEXT": "atomic"}
        )
        assert "SUCCESS" in result.stdout
        assert "Container created" in result.stdout

    @pytest.mark.unit
    def test_show_success_in_orchestration(self):
        """show_success silent in orchestration context."""
        result = self.run_bash(
            'show_success "Container created" "my-container"',
            env={"DS01_CONTEXT": "orchestration"}
        )
        # Should be empty or minimal
        assert "SUCCESS" not in result.stdout

    @pytest.mark.unit
    def test_show_warning_always_shown(self):
        """show_warning shown in both contexts."""
        for ctx in ["atomic", "orchestration"]:
            result = self.run_bash(
                'show_warning "Test warning"',
                env={"DS01_CONTEXT": ctx}
            )
            assert "WARNING" in result.stdout
            assert "Test warning" in result.stdout

    @pytest.mark.unit
    def test_show_error_always_shown(self):
        """show_error shown in both contexts."""
        for ctx in ["atomic", "orchestration"]:
            result = self.run_bash(
                'show_error "Test error"',
                env={"DS01_CONTEXT": ctx}
            )
            assert "ERROR" in result.stdout
            assert "Test error" in result.stdout

    @pytest.mark.unit
    def test_show_info_in_atomic(self):
        """show_info shown in atomic context."""
        result = self.run_bash(
            'show_info "Test info"',
            env={"DS01_CONTEXT": "atomic"}
        )
        assert "INFO" in result.stdout

    @pytest.mark.unit
    def test_show_info_in_orchestration(self):
        """show_info suppressed in orchestration context."""
        result = self.run_bash(
            'show_info "Test info"',
            env={"DS01_CONTEXT": "orchestration"}
        )
        assert "INFO" not in result.stdout

    # =========================================================================
    # Context Propagation Tests
    # =========================================================================

    @pytest.mark.unit
    def test_context_propagates_to_subshell(self):
        """Context propagates to subshells."""
        result = self.run_bash(
            'set_orchestration_context; (get_ds01_context)'
        )
        assert result.stdout.strip() == "orchestration"

    @pytest.mark.unit
    def test_context_available_after_export(self):
        """Exported functions available in subshells."""
        script = '''
        set_orchestration_context
        bash -c 'source /opt/ds01-infra/scripts/lib/ds01-context.sh; get_ds01_context'
        '''
        result = self.run_bash(script)
        # Note: subshell needs to inherit env var, not function
        assert result.returncode == 0

    # =========================================================================
    # Debug Output Tests
    # =========================================================================

    @pytest.mark.unit
    def test_show_debug_with_verbose(self):
        """show_debug shown when DS01_VERBOSE=1."""
        result = self.run_bash(
            'show_debug "Debug message"',
            env={"DS01_VERBOSE": "1"}
        )
        assert "DEBUG" in result.stdout

    @pytest.mark.unit
    def test_show_debug_without_verbose(self):
        """show_debug suppressed when DS01_VERBOSE not set."""
        result = self.run_bash('show_debug "Debug message"')
        assert "DEBUG" not in result.stdout
