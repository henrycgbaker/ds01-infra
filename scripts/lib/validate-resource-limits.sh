#!/bin/bash
# DS01 Infrastructure - Resource Limits Validation Library
# Provides functions to validate resource requests against user limits
# Source this file: source /usr/local/lib/validate-resource-limits.sh (??)

validate_resource_request() {
    local username="$1"
    local requested_migs="$2"
    local container_name="$3"
    
    # Parse user's limits using existing Python script
    USER_LIMITS=$(python3 /opt/ds01-infra/scripts/docker/get_resource_limits.py "$username")
    
    # Check current allocations
    CURRENT_CONTAINERS=$(docker ps --filter "label=ds01.user=$username" -q | wc -l)
    CURRENT_MIGS=$(python3 /opt/ds01-infra/scripts/docker/gpu_allocator.py user-status "$username")
    
    # Validate and return appropriate error message
    # Use templates from resource-limits.yaml 
}