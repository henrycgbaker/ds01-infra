#!/usr/bin/env python3
"""
DS01 Infrastructure Test Configuration
Shared fixtures and configuration for all test modules
"""

import os
import sys
import json
import shutil
import tempfile
import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch
from typing import Generator, Dict, Any, Optional

import pytest

# Add scripts to Python path
INFRA_ROOT = Path("/opt/ds01-infra")
sys.path.insert(0, str(INFRA_ROOT / "scripts" / "docker"))


# =============================================================================
# Markers - Auto-skip based on environment
# =============================================================================

def pytest_configure(config):
    """Register custom markers."""
    pass  # Markers defined in pytest.ini


def pytest_collection_modifyitems(config, items):
    """Auto-skip tests based on environment capabilities."""

    # Check environment capabilities once
    has_docker = _check_docker()
    has_gpu = _check_gpu()
    is_root = os.geteuid() == 0

    for item in items:
        # Skip docker tests if docker unavailable
        if "requires_docker" in item.keywords and not has_docker:
            item.add_marker(pytest.mark.skip(reason="Docker not available"))

        # Skip GPU tests if no GPU
        if "requires_gpu" in item.keywords and not has_gpu:
            item.add_marker(pytest.mark.skip(reason="GPU/nvidia-smi not available"))

        # Skip root tests if not root
        if "requires_root" in item.keywords and not is_root:
            item.add_marker(pytest.mark.skip(reason="Requires root privileges"))


def _check_docker() -> bool:
    """Check if Docker is available and running."""
    try:
        result = subprocess.run(
            ["docker", "info"],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _check_gpu() -> bool:
    """Check if nvidia-smi is available."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=count", "--format=csv,noheader"],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


# =============================================================================
# Path Fixtures
# =============================================================================

@pytest.fixture
def infra_root() -> Path:
    """Return the DS01 infrastructure root path."""
    return INFRA_ROOT


@pytest.fixture
def scripts_dir(infra_root) -> Path:
    """Return the scripts directory."""
    return infra_root / "scripts"


@pytest.fixture
def config_dir(infra_root) -> Path:
    """Return the config directory."""
    return infra_root / "config"


# =============================================================================
# Temporary Directory Fixtures
# =============================================================================

@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for test artifacts."""
    tmp = Path(tempfile.mkdtemp(prefix="ds01-test-"))
    yield tmp
    shutil.rmtree(tmp, ignore_errors=True)


@pytest.fixture
def temp_state_dir(temp_dir) -> Path:
    """Create a temporary state directory (mimics /var/lib/ds01)."""
    state_dir = temp_dir / "state"
    state_dir.mkdir(parents=True)
    return state_dir


@pytest.fixture
def temp_log_dir(temp_dir) -> Path:
    """Create a temporary log directory (mimics /var/log/ds01)."""
    log_dir = temp_dir / "logs"
    log_dir.mkdir(parents=True)
    return log_dir


# =============================================================================
# Configuration Fixtures
# =============================================================================

@pytest.fixture
def sample_resource_limits() -> Dict[str, Any]:
    """Return sample resource limits configuration."""
    return {
        "defaults": {
            "max_mig_instances": 1,
            "max_cpus": 8,
            "memory": "32g",
            "shm_size": "16g",
            "max_containers_per_user": 2,
            "idle_timeout": "48h",
            "max_runtime": "168h",
            "gpu_hold_after_stop": "24h",
            "container_hold_after_stop": "12h",
            "priority": 50
        },
        "groups": {
            "students": {
                "max_mig_instances": 1,
                "max_cpus": 8,
                "memory": "32g",
                "priority": 10,
                "members": ["student1", "student2"]
            },
            "researchers": {
                "max_mig_instances": 2,
                "max_cpus": 16,
                "memory": "64g",
                "priority": 50,
                "members": ["researcher1"]
            },
            "admins": {
                "max_mig_instances": None,  # unlimited
                "max_cpus": 32,
                "memory": "128g",
                "priority": 100,
                "members": ["admin1"]
            }
        },
        "user_overrides": {
            "special_user": {
                "max_mig_instances": 4,
                "priority": 90
            }
        }
    }


@pytest.fixture
def temp_config_file(temp_dir, sample_resource_limits) -> Path:
    """Create a temporary resource-limits.yaml file."""
    import yaml
    config_file = temp_dir / "resource-limits.yaml"
    with open(config_file, "w") as f:
        yaml.safe_dump(sample_resource_limits, f)
    return config_file


# =============================================================================
# GPU State Fixtures
# =============================================================================

@pytest.fixture
def sample_gpu_state() -> Dict[str, Any]:
    """Return sample GPU allocator state."""
    return {
        "gpus": {
            "0": {
                "type": "physical_gpu",
                "containers": [],
                "total_memory": "40GB"
            },
            "1": {
                "type": "physical_gpu",
                "containers": [],
                "total_memory": "40GB"
            }
        },
        "mig_enabled": False,
        "last_updated": "2025-01-01T00:00:00Z"
    }


@pytest.fixture
def sample_gpu_state_with_allocations() -> Dict[str, Any]:
    """Return GPU state with some allocations."""
    return {
        "gpus": {
            "0": {
                "type": "physical_gpu",
                "containers": [
                    {
                        "container": "project-a._.1001",
                        "user": "student1",
                        "allocated_at": "2025-01-01T10:00:00Z",
                        "interface": "orchestration"
                    }
                ],
                "total_memory": "40GB"
            },
            "1": {
                "type": "physical_gpu",
                "containers": [],
                "total_memory": "40GB"
            }
        },
        "mig_enabled": False,
        "last_updated": "2025-01-01T10:00:00Z"
    }


@pytest.fixture
def temp_gpu_state_file(temp_state_dir, sample_gpu_state) -> Path:
    """Create a temporary GPU state file."""
    state_file = temp_state_dir / "gpu-state.json"
    with open(state_file, "w") as f:
        json.dump(sample_gpu_state, f)
    return state_file


# =============================================================================
# Mock Fixtures
# =============================================================================

@pytest.fixture
def mock_docker_client():
    """Create a mock Docker client."""
    mock = MagicMock()
    mock.containers.list.return_value = []
    mock.info.return_value = {
        "CgroupDriver": "systemd",
        "CgroupParent": "ds01.slice"
    }
    return mock


@pytest.fixture
def mock_nvidia_smi():
    """Create a mock nvidia-smi response."""
    def _mock_nvidia_smi(query_type="count"):
        responses = {
            "count": "4",
            "gpu": "0, NVIDIA A100-SXM4-40GB, 40960 MiB\n1, NVIDIA A100-SXM4-40GB, 40960 MiB",
            "mig": "GPU 0: No MIG devices found\nGPU 1: No MIG devices found"
        }
        return responses.get(query_type, "")
    return _mock_nvidia_smi


@pytest.fixture
def mock_subprocess_run():
    """Fixture to mock subprocess.run calls."""
    with patch("subprocess.run") as mock:
        yield mock


# =============================================================================
# Container Fixtures
# =============================================================================

@pytest.fixture
def sample_container_metadata() -> Dict[str, Any]:
    """Return sample container metadata."""
    return {
        "container_name": "project-a._.1001",
        "user": "student1",
        "image": "ds01-student1/project-a:latest",
        "created_at": "2025-01-01T10:00:00Z",
        "gpu_allocated": "0",
        "interface": "orchestration",
        "labels": {
            "ds01.interface": "orchestration",
            "ds01.user": "student1",
            "ds01.gpu.allocated": "0"
        }
    }


@pytest.fixture
def sample_docker_container() -> Dict[str, Any]:
    """Return sample Docker container inspect data."""
    return {
        "Id": "abc123def456",
        "Name": "/project-a._.1001",
        "State": {
            "Status": "running",
            "Running": True,
            "StartedAt": "2025-01-01T10:00:00Z"
        },
        "Config": {
            "Labels": {
                "ds01.interface": "orchestration",
                "ds01.user": "student1",
                "aime.mlc.USER": "student1"
            }
        },
        "HostConfig": {
            "CgroupParent": "ds01-students-student1.slice",
            "DeviceRequests": [
                {
                    "Driver": "nvidia",
                    "DeviceIDs": ["0"]
                }
            ]
        }
    }


# =============================================================================
# Environment Fixtures
# =============================================================================

@pytest.fixture
def orchestration_context():
    """Set up orchestration context environment."""
    original = os.environ.get("DS01_CONTEXT")
    os.environ["DS01_CONTEXT"] = "orchestration"
    yield
    if original is None:
        os.environ.pop("DS01_CONTEXT", None)
    else:
        os.environ["DS01_CONTEXT"] = original


@pytest.fixture
def atomic_context():
    """Set up atomic context environment."""
    original = os.environ.get("DS01_CONTEXT")
    os.environ.pop("DS01_CONTEXT", None)  # atomic is default
    yield
    if original is not None:
        os.environ["DS01_CONTEXT"] = original


# =============================================================================
# Helper Functions (available to all tests)
# =============================================================================

def run_script(script_path: Path, *args, env: Optional[Dict] = None, timeout: int = 30) -> subprocess.CompletedProcess:
    """Run a shell script and return the result."""
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


def run_python_script(script_path: Path, *args, env: Optional[Dict] = None, timeout: int = 30) -> subprocess.CompletedProcess:
    """Run a Python script and return the result."""
    script_env = os.environ.copy()
    if env:
        script_env.update(env)

    return subprocess.run(
        ["python3", str(script_path)] + list(args),
        capture_output=True,
        text=True,
        env=script_env,
        timeout=timeout
    )


# Export helpers for use in tests
pytest.run_script = run_script
pytest.run_python_script = run_python_script
