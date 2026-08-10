"""Byte size, count, and path-sort-key formatting.

Behavior is defined by Section 5.3 and the ordering rules of Section 5 of
../../specs/Compare-DirectoryTree-Spec.md.
"""

from __future__ import annotations

_UNITS = ("KB", "MB", "GB", "TB", "PB")


def format_byte_count(num_bytes: int) -> str:
    """Exact byte count with thousands separators, never abbreviated."""

    return f"{num_bytes:,}"


def format_aggregate_byte_total(num_bytes: int) -> str:
    """Abbreviated 1024-based aggregate total for directory-summary rows."""

    if num_bytes < 1024:
        return f"{num_bytes} B"

    value = float(num_bytes)
    unit_index = -1
    while value >= 1024 and unit_index < len(_UNITS) - 1:
        value /= 1024
        unit_index += 1

    rounded = round(value, 1)
    if rounded == int(rounded):
        text = str(int(rounded))
    else:
        text = f"{rounded:.1f}"

    return f"{text} {_UNITS[unit_index]}"


def format_count(count: int, singular: str, plural: str) -> str:
    noun = singular if count == 1 else plural
    return f"{count} {noun}"


def path_sort_key(path: str) -> str:
    """A NUL-joined, lowercased key so ordinal comparison behaves as a
    segment-by-segment, case-insensitive comparison (NUL sorts below every
    path character).
    """

    trimmed = path.rstrip("/\\")
    segments = trimmed.replace("\\", "/").split("/") if trimmed else [""]
    return "\0".join(segment.lower() for segment in segments)
