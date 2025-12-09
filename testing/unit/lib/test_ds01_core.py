#!/usr/bin/env python3
"""
Unit tests for ds01_core.py
/opt/ds01-infra/testing/unit/lib/test_ds01_core.py

Run: pytest testing/unit/lib/test_ds01_core.py -v
"""

import sys
from pathlib import Path

# Add lib to path
lib_path = Path(__file__).resolve().parent.parent.parent.parent / "scripts" / "lib"
sys.path.insert(0, str(lib_path))

import pytest
from ds01_core import parse_duration, format_duration, Colors


class TestParseDuration:
    """Tests for parse_duration() function."""

    def test_hours(self):
        """Test hour parsing."""
        assert parse_duration("1h") == 3600
        assert parse_duration("2h") == 7200
        assert parse_duration("24h") == 86400

    def test_fractional_hours(self):
        """Test fractional hour parsing (critical for bash scripts using 0.5h)."""
        assert parse_duration("0.5h") == 1800
        assert parse_duration("0.25h") == 900
        assert parse_duration("1.5h") == 5400

    def test_days(self):
        """Test day parsing."""
        assert parse_duration("1d") == 86400
        assert parse_duration("7d") == 604800
        assert parse_duration("0.5d") == 43200

    def test_weeks(self):
        """Test week parsing."""
        assert parse_duration("1w") == 604800
        assert parse_duration("2w") == 1209600

    def test_minutes(self):
        """Test minute parsing."""
        assert parse_duration("30m") == 1800
        assert parse_duration("90m") == 5400

    def test_seconds(self):
        """Test second parsing."""
        assert parse_duration("60s") == 60
        assert parse_duration("3600s") == 3600

    def test_no_unit_defaults_to_seconds(self):
        """Test that bare numbers default to seconds."""
        assert parse_duration("60") == 60
        assert parse_duration("3600") == 3600

    def test_null_values(self):
        """Test special no-limit values return -1."""
        assert parse_duration("null") == -1
        assert parse_duration("None") == -1
        assert parse_duration("never") == -1
        assert parse_duration("indefinite") == -1
        assert parse_duration("") == -1
        assert parse_duration(None) == -1

    def test_case_insensitive(self):
        """Test case insensitivity."""
        assert parse_duration("2H") == 7200
        assert parse_duration("1D") == 86400
        assert parse_duration("NULL") == -1
        assert parse_duration("NEVER") == -1

    def test_whitespace_handling(self):
        """Test whitespace is stripped."""
        assert parse_duration("  2h  ") == 7200
        assert parse_duration("1 h") == 3600  # Space between number and unit

    def test_invalid_returns_zero(self):
        """Test invalid values return 0."""
        assert parse_duration("invalid") == 0
        assert parse_duration("abc") == 0
        assert parse_duration("--") == 0


class TestFormatDuration:
    """Tests for format_duration() function."""

    def test_hours(self):
        """Test hour formatting."""
        assert format_duration(3600) == "1h"
        assert format_duration(7200) == "2h"

    def test_days_and_hours(self):
        """Test combined day and hour formatting."""
        assert format_duration(90000) == "1d 1h"  # 25 hours
        assert format_duration(86400) == "1d"

    def test_minutes(self):
        """Test minute formatting (only when < 1 hour)."""
        assert format_duration(1800) == "30m"
        assert format_duration(60) == "1m"

    def test_seconds(self):
        """Test second formatting (only when < 1 minute)."""
        assert format_duration(30) == "30s"
        assert format_duration(1) == "1s"

    def test_zero(self):
        """Test zero seconds."""
        assert format_duration(0) == "0s"

    def test_unlimited(self):
        """Test negative values (unlimited)."""
        assert format_duration(-1) == "unlimited"
        assert format_duration(-100) == "unlimited"


class TestColors:
    """Tests for Colors class."""

    def test_colors_are_ansi_codes(self):
        """Test that colors are valid ANSI escape codes."""
        assert Colors.RED.startswith('\033[')
        assert Colors.GREEN.startswith('\033[')
        assert Colors.YELLOW.startswith('\033[')
        assert Colors.BLUE.startswith('\033[')
        assert Colors.NC.startswith('\033[')

    def test_nc_resets_color(self):
        """Test that NC is the reset code."""
        assert Colors.NC == '\033[0m'


class TestRoundTrip:
    """Test round-trip parsing and formatting."""

    def test_common_durations(self):
        """Test that parsing and formatting are consistent for common values."""
        # These are common values used in resource-limits.yaml
        common_values = ["2h", "4h", "12h", "24h", "48h", "1d", "7d"]

        for val in common_values:
            seconds = parse_duration(val)
            # Formatting might produce a different but equivalent representation
            # (e.g., "24h" might become "1d"), but re-parsing should give same seconds
            formatted = format_duration(seconds)
            reparsed = parse_duration(formatted)
            assert reparsed == seconds, f"Round-trip failed for {val}: {seconds} -> {formatted} -> {reparsed}"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
