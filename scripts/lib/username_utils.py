#!/usr/bin/env python3
"""
/opt/ds01-infra/scripts/lib/username_utils.py
Username sanitization utilities for systemd compatibility.

LDAP/SSSD usernames like "h.baker@hertie-school.lan" contain characters
that are invalid or have special meaning in systemd unit names.
This library provides consistent sanitization across all DS01 Python scripts.

Usage:
    from username_utils import sanitize_username_for_slice, get_user_slice_name

    sanitized = sanitize_username_for_slice("h.baker@hertie-school.lan")
    # Result: "h_baker" (domain stripped, dots replaced with underscores)

    slice_name = get_user_slice_name("student", "h.baker@hertie-school.lan")
    # Result: "ds01-student-h_baker.slice"
"""

import re


def sanitize_username_for_slice(username: str) -> str:
    """
    Sanitize username for systemd slice naming.

    Strips domain (@...), replaces dots with underscores, removes invalid characters.
    Uses underscores (not hyphens) to avoid systemd hierarchy interpretation.

    IMPORTANT: Systemd interprets hyphens as hierarchy separators.
    Using hyphens causes slice names like "ds01-student-h-baker.slice" to create
    nested hierarchy: ds01.slice/ds01-student.slice/ds01-student-h.slice/...
    The intermediate slices don't have CPU accounting, causing container failures.

    Args:
        username: The original username (may contain @, ., etc.)

    Returns:
        Sanitized username safe for systemd slice names

    Examples:
        >>> sanitize_username_for_slice("h.baker@hertie-school.lan")
        'h_baker'
        >>> sanitize_username_for_slice("alice")
        'alice'
        >>> sanitize_username_for_slice("john.doe")
        'john_doe'
    """
    if not username:
        return username

    sanitized = username

    # Strip domain part (everything after @) for cleaner container usernames
    # e.g., "c.fusarbassini@hertie-school.lan" -> "c.fusarbassini"
    if '@' in sanitized:
        sanitized = sanitized.split('@')[0]

    # Replace dots with underscores (NOT hyphens - see docstring)
    sanitized = sanitized.replace('.', '_')

    # Replace any remaining invalid characters with underscores
    # Valid systemd chars: a-zA-Z0-9_:-
    # We use underscores to avoid hierarchy issues with hyphens
    sanitized = re.sub(r'[^a-zA-Z0-9_:]', '_', sanitized)

    # Collapse multiple consecutive underscores to single underscore
    sanitized = re.sub(r'_+', '_', sanitized)

    # Trim leading and trailing underscores
    sanitized = sanitized.strip('_')

    # Truncate to 32 characters (Linux username/groupname limit)
    # groupadd/useradd fail with names > 32 chars
    # Use hash suffix to avoid collisions when truncating
    if len(sanitized) > 32:
        import hashlib
        # Generate 4-char hash from original username to avoid collisions
        hash_suffix = hashlib.md5(username.encode()).hexdigest()[:4]
        # Truncate to 27 chars + underscore + 4-char hash = 32 chars
        sanitized = sanitized[:27].rstrip('_') + '_' + hash_suffix

    return sanitized


# Alias for container username sanitization (same logic as slice names)
# Used by mlc-patched.py for container user paths
sanitize_username_for_container = sanitize_username_for_slice


def get_user_slice_name(group: str, username: str) -> str:
    """
    Get the full systemd slice name for a user.

    Args:
        group: User's group (e.g., "student", "researcher", "admin")
        username: The original username

    Returns:
        Full slice name like "ds01-student-h_baker.slice"
    """
    sanitized = sanitize_username_for_slice(username)
    return f"ds01-{group}-{sanitized}.slice"


if __name__ == "__main__":
    # Quick test
    test_cases = [
        "alice",
        "john.doe",
        "h.baker@hertie-school.lan",
        "user@domain.org",
        "test.user@sub.domain.edu",
    ]

    print("Username Sanitization Test:")
    print("-" * 60)
    for username in test_cases:
        sanitized = sanitize_username_for_slice(username)
        slice_name = get_user_slice_name("student", username)
        print(f"  {username}")
        print(f"    -> sanitized: {sanitized}")
        print(f"    -> slice:     {slice_name}")
        print()
