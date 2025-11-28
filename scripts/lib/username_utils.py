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
    # Result: "h-baker-at-hertie-school-lan"

    slice_name = get_user_slice_name("student", "h.baker@hertie-school.lan")
    # Result: "ds01-student-h-baker-at-hertie-school-lan.slice"
"""

import re


def sanitize_username_for_slice(username: str) -> str:
    """
    Sanitize username for systemd slice naming.

    Replaces @ with -at-, dots with hyphens, and removes invalid characters.
    Valid systemd chars: a-zA-Z0-9_:-

    Args:
        username: The original username (may contain @, ., etc.)

    Returns:
        Sanitized username safe for systemd slice names

    Examples:
        >>> sanitize_username_for_slice("h.baker@hertie-school.lan")
        'h-baker-at-hertie-school-lan'
        >>> sanitize_username_for_slice("alice")
        'alice'
        >>> sanitize_username_for_slice("john.doe")
        'john-doe'
    """
    if not username:
        return username

    sanitized = username

    # Replace @ with -at- (readable and reversible)
    sanitized = sanitized.replace('@', '-at-')

    # Replace dots with hyphens
    sanitized = sanitized.replace('.', '-')

    # Replace any remaining invalid characters with hyphens
    # Valid systemd chars: a-zA-Z0-9_:-
    sanitized = re.sub(r'[^a-zA-Z0-9_:-]', '-', sanitized)

    # Collapse multiple consecutive hyphens to single hyphen
    sanitized = re.sub(r'-+', '-', sanitized)

    # Trim leading and trailing hyphens
    sanitized = sanitized.strip('-')

    return sanitized


def get_user_slice_name(group: str, username: str) -> str:
    """
    Get the full systemd slice name for a user.

    Args:
        group: User's group (e.g., "student", "researcher", "admin")
        username: The original username

    Returns:
        Full slice name like "ds01-student-h-baker-at-hertie-school-lan.slice"
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
