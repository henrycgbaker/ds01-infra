# DS01 Layered Architecture Test Suite

Test suite for validating the DS01 5-layer implementation hierarchy and 4-interface model.

## Test Categories

| Test File | Description | Requires Root |
|-----------|-------------|---------------|
| `test-phase1-enforcement.sh` | Universal enforcement (cgroups, wrapper, OPA) | Yes |
| `test-phase4-robustness.sh` | Robustness systems (health check, event logger, bare metal) | No |
| `test-phase5-context.sh` | Conditional output system (context detection) | No |
| `test-phase6-dashboard.sh` | Dashboard interface tracking | No |
| `test-integration.sh` | Full workflow integration tests | Partial |

## Quick Start

```bash
# Run all tests (some require root)
./run-all-tests.sh

# Run specific test suite
./test-phase5-context.sh

# Run with verbose output
./test-phase5-context.sh --verbose
```

## Architecture Being Tested

### 5-Layer Implementation Hierarchy
- L0: Docker (Foundational Container Runtime)
- L1: MLC (HIDDEN - AIME Machine Learning Containers)
- L2: Atomic (Single-Purpose Commands)
- L3: Orchestrators (Multi-Step Container Sequences)
- L4: Wizards (Complete Guided Workflows)

### 4 User-Facing Interfaces
- DS01 Orchestration Interface (DEFAULT)
- DS01 Atomic Interface (ADMIN)
- Docker Interface (ADVANCED)
- Other Interface (External Tools)

## Test Results

Results are written to `results/` directory with timestamps.

## Prerequisites

- Docker with NVIDIA Container Toolkit
- DS01 infrastructure installed at `/opt/ds01-infra`
- User in `docker` group (for non-root tests)
- Root access (for Phase 1 tests)
