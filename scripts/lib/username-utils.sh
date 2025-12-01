#!/bin/bash
# /opt/ds01-infra/scripts/lib/username-utils.sh
# Username sanitization utilities for systemd compatibility
#
# LDAP/SSSD usernames like "h.baker@hertie-school.lan" contain characters
# that are invalid or have special meaning in systemd unit names.
# This library provides consistent sanitization across all DS01 scripts.
#
# Usage:
#   source /opt/ds01-infra/scripts/lib/username-utils.sh
#   sanitized=$(sanitize_username_for_slice "h.baker@hertie-school.lan")
#   # Result: h-baker-at-hertie-school-lan

# Sanitize username for systemd slice naming
# Replaces @ with -at-, dots with hyphens, and removes invalid characters
sanitize_username_for_slice() {
    local username="$1"

    # Return empty if input is empty
    if [[ -z "$username" ]]; then
        echo ""
        return
    fi

    local sanitized="$username"

    # Strip domain part (everything after @) for cleaner container usernames
    # e.g., "c.fusarbassini@hertie-school.lan" -> "c.fusarbassini"
    sanitized="${sanitized%%@*}"

    # Replace dots with hyphens
    sanitized="${sanitized//./-}"

    # Replace any remaining invalid characters with hyphens
    # Valid systemd chars: a-zA-Z0-9_:-
    sanitized=$(echo "$sanitized" | sed 's/[^a-zA-Z0-9_:-]/-/g')

    # Collapse multiple consecutive hyphens to single hyphen
    sanitized=$(echo "$sanitized" | sed 's/--*/-/g')

    # Trim leading and trailing hyphens
    sanitized=$(echo "$sanitized" | sed 's/^-//; s/-$//')

    # Truncate to 32 characters (Linux username/groupname limit)
    # groupadd/useradd fail with names > 32 chars
    # Use hash suffix to avoid collisions when truncating
    if [[ ${#sanitized} -gt 32 ]]; then
        # Generate 4-char hash from original username to avoid collisions
        local hash=$(echo -n "$username" | md5sum | cut -c1-4)
        # Truncate to 27 chars + hyphen + 4-char hash = 32 chars
        sanitized="${sanitized:0:27}"
        # Remove trailing hyphen if truncation created one
        sanitized="${sanitized%-}"
        sanitized="${sanitized}-${hash}"
    fi

    echo "$sanitized"
}

# Get the full slice name for a user
# Args: group, username
# Returns: ds01-{group}-{sanitized_username}.slice
get_user_slice_name() {
    local group="$1"
    local username="$2"
    local sanitized
    sanitized=$(sanitize_username_for_slice "$username")
    echo "ds01-${group}-${sanitized}.slice"
}

# Export functions for use in subshells
export -f sanitize_username_for_slice
export -f get_user_slice_name
