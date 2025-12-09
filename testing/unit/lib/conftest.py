#!/usr/bin/env python3
"""
Pytest configuration for /opt/ds01-infra/testing/unit/lib/ tests.

This conftest.py provides fixtures specific to library unit tests.
"""

import os
import sys
import shutil
import tempfile
import subprocess
from pathlib import Path
from typing import Generator

import pytest


# Add scripts to Python path for imports
INFRA_ROOT = Path("/opt/ds01-infra")
sys.path.insert(0, str(INFRA_ROOT / "scripts" / "docker"))
sys.path.insert(0, str(INFRA_ROOT / "scripts" / "lib"))


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for test artifacts."""
    tmp = Path(tempfile.mkdtemp(prefix="ds01-lib-test-"))
    yield tmp
    shutil.rmtree(tmp, ignore_errors=True)


@pytest.fixture
def scripts_lib_dir() -> Path:
    """Return the scripts/lib directory path."""
    return INFRA_ROOT / "scripts" / "lib"


@pytest.fixture
def docker_scripts_dir() -> Path:
    """Return the scripts/docker directory path."""
    return INFRA_ROOT / "scripts" / "docker"


# =============================================================================
# Helper Functions
# =============================================================================

def run_bash_script(script_path: Path, *args, env=None, timeout=30) -> subprocess.CompletedProcess:
    """Run a bash script and return the result."""
    script_env = os.environ.copy()
    if env:
        script_env.update(env)

    return subprocess.run(
        [str(script_path)] + list(args),
        capture_output=True,
        text=True,
        env=script_env,
        timeout=timeout
    )


def run_bash_code(code: str, env=None, timeout=10) -> subprocess.CompletedProcess:
    """Run bash code directly and return the result."""
    script_env = os.environ.copy()
    if env:
        script_env.update(env)

    return subprocess.run(
        ["bash", "-c", code],
        capture_output=True,
        text=True,
        env=script_env,
        timeout=timeout
    )


def source_and_run(library_path: Path, code: str, env=None) -> subprocess.CompletedProcess:
    """Source a bash library and run code."""
    full_code = f'''
    source "{library_path}"
    {code}
    '''
    return run_bash_code(full_code, env=env)


# Export helpers
pytest.run_bash_script = run_bash_script
pytest.run_bash_code = run_bash_code
pytest.source_and_run = source_and_run
