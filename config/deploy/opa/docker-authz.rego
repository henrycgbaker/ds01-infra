# /opt/ds01-infra/config/deploy/opa/docker-authz.rego
# DS01 Docker Authorization Policy
#
# This policy enforces:
# 1. Container ownership - users can only interact with their own containers
# 2. Admin bypass - admin users have full access to all containers
# 3. Service accounts - ds01-dashboard has read access to all containers
# 4. Cgroup validation - prevent escape from DS01 resource slices
#
# External data file: /var/lib/ds01/opa/container-owners.json
# Updated by: sync-container-owners.py (cron or systemd timer)
#
# Install OPA Docker authz plugin:
#   https://github.com/open-policy-agent/opa-docker-authz
#
# Deploy:
#   opa-docker-authz -policy-file /opt/ds01-infra/config/deploy/opa/docker-authz.rego \
#                    -data-file /var/lib/ds01/opa/container-owners.json

package docker.authz

import rego.v1

# Default: ALLOW (fail-open for availability)
# If OPA fails or policy errors occur, containers still run
default allow := true

# Default deny message (empty when allowed)
default deny_message := ""

# =============================================================================
# EXTERNAL DATA
# =============================================================================
# Loaded from /var/lib/ds01/opa/container-owners.json
# Structure:
# {
#   "containers": { "<id>": {"owner": "<user>", "name": "<name>", "ds01_managed": bool} },
#   "admins": ["user1", "user2"],
#   "service_users": ["ds01-dashboard"]
# }

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get the requesting user (from Docker socket authentication)
requesting_user := input.User

# Check if requesting user is an admin
is_admin if {
    requesting_user == data.admins[_]
}

# Check if requesting user is a service account
is_service_user if {
    requesting_user == data.service_users[_]
}

# Check if user has elevated privileges (admin or service)
is_privileged if {
    is_admin
}

is_privileged if {
    is_service_user
}

# Extract container ID from URL path
# Handles various Docker API paths like:
#   /containers/<id>/start
#   /containers/<id>/stop
#   /containers/<id>/exec
#   /v1.41/containers/<id>/json
container_id := id if {
    # Match paths like /containers/<id>/... or /v1.XX/containers/<id>/...
    parts := split(input.Path, "/")
    some i
    parts[i] == "containers"
    id := parts[i + 1]
    id != "json"  # Skip list endpoint
    id != "create"  # Skip create endpoint
}

# Get container info from external data
container_info := info if {
    info := data.containers[container_id]
}

# Get container owner
container_owner := owner if {
    owner := container_info.owner
}

# Check if user owns the container
is_owner if {
    container_owner == requesting_user
}

# Check if container has unknown owner (allow access for safety)
unknown_owner if {
    not container_owner
}

# =============================================================================
# REQUEST TYPE DETECTION
# =============================================================================

# Container create request
is_container_create if {
    input.Method == "POST"
    contains(input.Path, "/containers/create")
}

# Container list request (docker ps)
is_container_list if {
    input.Method == "GET"
    endswith(input.Path, "/containers/json")
}

# Container inspect request
is_container_inspect if {
    input.Method == "GET"
    regex.match(`/containers/[a-zA-Z0-9]+/json$`, input.Path)
}

# Container start request
is_container_start if {
    input.Method == "POST"
    contains(input.Path, "/start")
}

# Container stop request
is_container_stop if {
    input.Method == "POST"
    contains(input.Path, "/stop")
}

# Container kill request
is_container_kill if {
    input.Method == "POST"
    contains(input.Path, "/kill")
}

# Container remove request
is_container_remove if {
    input.Method == "DELETE"
    regex.match(`/containers/[a-zA-Z0-9]+$`, input.Path)
}

# Container exec request (docker exec)
is_container_exec if {
    input.Method == "POST"
    contains(input.Path, "/exec")
}

# Container attach request
is_container_attach if {
    input.Method == "POST"
    contains(input.Path, "/attach")
}

# Container logs request
is_container_logs if {
    input.Method == "GET"
    contains(input.Path, "/logs")
}

# Container wait request
is_container_wait if {
    input.Method == "POST"
    contains(input.Path, "/wait")
}

# Any container-modifying operation
is_container_modify if { is_container_start }
is_container_modify if { is_container_stop }
is_container_modify if { is_container_kill }
is_container_modify if { is_container_remove }
is_container_modify if { is_container_exec }
is_container_modify if { is_container_attach }
is_container_modify if { is_container_wait }

# Any container-read operation
is_container_read if { is_container_inspect }
is_container_read if { is_container_logs }

# Any operation targeting a specific container
is_container_specific if { is_container_modify }
is_container_specific if { is_container_read }

# =============================================================================
# CGROUP VALIDATION (existing functionality)
# =============================================================================

# Check if cgroup-parent is specified
has_cgroup_parent if {
    input.Body.HostConfig.CgroupParent != ""
}

# Validate cgroup-parent is a DS01 slice
valid_cgroup_parent if {
    cgroup := input.Body.HostConfig.CgroupParent
    startswith(cgroup, "ds01-")
    endswith(cgroup, ".slice")
    not contains(cgroup, "..")
    not contains(cgroup, "//")
    not contains(cgroup, " ")
}

valid_cgroup_parent if {
    input.Body.HostConfig.CgroupParent == "ds01.slice"
}

valid_cgroup_parent if {
    not has_cgroup_parent
}

# Blocked cgroup patterns
blocked_cgroup_patterns := [
    "system.slice",
    "user.slice",
    "../",
    "..",
    "//"
]

# =============================================================================
# AUTHORIZATION RULES
# =============================================================================

# DENY: Cgroup bypass attempts (high priority)
deny if {
    is_container_create
    cgroup := input.Body.HostConfig.CgroupParent
    some pattern in blocked_cgroup_patterns
    contains(cgroup, pattern)
}

deny_message := msg if {
    is_container_create
    cgroup := input.Body.HostConfig.CgroupParent
    some pattern in blocked_cgroup_patterns
    contains(cgroup, pattern)
    msg := sprintf("Permission denied: invalid cgroup-parent '%s'", [cgroup])
}

# DENY: Container operations on containers owned by others
deny if {
    is_container_specific
    not is_privileged
    not is_owner
    not unknown_owner
}

deny_message := msg if {
    is_container_specific
    not is_privileged
    not is_owner
    not unknown_owner
    msg := sprintf("Permission denied: container owned by %s", [container_owner])
}

# ALLOW: Override default when deny rule matched
allow := false if {
    deny
}

# =============================================================================
# AUDIT LOGGING INFO
# =============================================================================

# Information for monitoring/logging
info := {
    "user": requesting_user,
    "is_admin": is_admin,
    "is_service_user": is_service_user,
    "container_id": container_id,
    "container_owner": container_owner,
    "is_owner": is_owner,
    "operation": operation_type,
    "allowed": allow,
    "deny_message": deny_message
}

# Determine operation type for logging
operation_type := "container_create" if { is_container_create }
operation_type := "container_list" if { is_container_list }
operation_type := "container_inspect" if { is_container_inspect }
operation_type := "container_start" if { is_container_start }
operation_type := "container_stop" if { is_container_stop }
operation_type := "container_kill" if { is_container_kill }
operation_type := "container_remove" if { is_container_remove }
operation_type := "container_exec" if { is_container_exec }
operation_type := "container_attach" if { is_container_attach }
operation_type := "container_logs" if { is_container_logs }
operation_type := "other" if {
    not is_container_create
    not is_container_list
    not is_container_inspect
    not is_container_start
    not is_container_stop
    not is_container_kill
    not is_container_remove
    not is_container_exec
    not is_container_attach
    not is_container_logs
}
