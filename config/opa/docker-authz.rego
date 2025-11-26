# /opt/ds01-infra/config/opa/docker-authz.rego
# DS01 Docker Authorization Policy
#
# Design: FAIL-OPEN with aggressive alerting
# Priority: System availability > strict enforcement
#
# This policy:
# 1. ALLOWS all requests by default (fail-open)
# 2. Validates cgroup-parent when present
# 3. Generates events for invalid configurations
# 4. Only DENIES obvious bypass attempts
#
# Install OPA Docker authz plugin:
#   https://github.com/open-policy-agent/opa-docker-authz
#
# Deploy this policy:
#   opa-docker-authz -policy-file /opt/ds01-infra/config/opa/docker-authz.rego

package docker.authz

import rego.v1

# Default: ALLOW (fail-open for availability)
# If OPA fails or policy errors occur, containers still run
default allow := true

# Helper: Check if this is a container create/run request
is_container_create if {
    input.Method == "POST"
    contains(input.Path, "/containers/create")
}

is_container_run if {
    input.Method == "POST"
    contains(input.Path, "/containers/")
    contains(input.Path, "/start")
}

# Helper: Check if cgroup-parent is specified
has_cgroup_parent if {
    input.Body.HostConfig.CgroupParent != ""
}

# Helper: Validate cgroup-parent is a DS01 slice
# Must match pattern: ds01-{group}-{user}.slice or ds01.slice (daemon default)
valid_cgroup_parent if {
    cgroup := input.Body.HostConfig.CgroupParent
    startswith(cgroup, "ds01-")
    endswith(cgroup, ".slice")
    # Reject path traversal and invalid characters
    not contains(cgroup, "..")
    not contains(cgroup, "//")
    not contains(cgroup, " ")
}

# Also valid: the parent slice ds01.slice itself
valid_cgroup_parent if {
    input.Body.HostConfig.CgroupParent == "ds01.slice"
}

# Also allow no cgroup-parent (will use daemon default ds01.slice)
valid_cgroup_parent if {
    not has_cgroup_parent
}

# Generate alert for invalid cgroup attempts (doesn't block, just logs)
alert_invalid_cgroup if {
    is_container_create
    has_cgroup_parent
    not valid_cgroup_parent
}

# DENY: Explicit bypass attempts
# Only deny when someone explicitly sets an empty or clearly malicious cgroup
deny if {
    is_container_create
    cgroup := input.Body.HostConfig.CgroupParent

    # Block attempts to escape to root cgroup or non-DS01 slices
    some pattern in blocked_cgroup_patterns
    contains(cgroup, pattern)
}

# Blocked patterns - clear bypass attempts
blocked_cgroup_patterns := [
    "system.slice",     # Don't allow into system slice
    "user.slice",       # Don't allow into generic user slice
    "../",              # Path traversal (with slash)
    "..",               # Path traversal (without slash)
    "//",               # Double slash
]

# Information for monitoring/logging
info := {
    "user": input.User,
    "cgroup_parent": input.Body.HostConfig.CgroupParent,
    "is_valid": valid_cgroup_parent,
    "alert": alert_invalid_cgroup,
}
