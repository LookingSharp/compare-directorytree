"""Directory tree enumeration.

Behavior is defined by Section 2 (Inputs and Scope), Section 3 (Definition
of Same), and Section 9 (Errors and Ambiguous Cases) of
../../specs/Compare-DirectoryTree-Spec.md.

Relative paths always use ``/`` as the segment separator, regardless of
host platform, so reports are deterministic across operating systems.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, Iterator, List


class ComparisonError(Exception):
    """Raised when the comparison cannot be completed reliably."""


@dataclass
class FileEntry:
    name: str
    relative_path: str
    length: int


@dataclass
class DirectoryNode:
    full_name: str
    relative_path: str
    files: "Dict[str, FileEntry]" = field(default_factory=dict)
    dirs: "Dict[str, DirectoryNode]" = field(default_factory=dict)


def _join_relative(parent: str, name: str) -> str:
    return f"{parent}/{name}" if parent else name


def _check_case_insensitive_collision(names: List[str], full_name: str, kind: str) -> None:
    seen: Dict[str, List[str]] = {}
    for name in names:
        seen.setdefault(name.lower(), []).append(name)
    for lowered, group in seen.items():
        if len(group) > 1:
            colliding = ", ".join(sorted(group))
            raise ComparisonError(
                f"Ambiguous case-insensitive {kind} collision in '{full_name}': {colliding}"
            )


def build_directory_node(full_name: str, relative_path: str, recurse: bool) -> DirectoryNode:
    try:
        with os.scandir(full_name) as it:
            entries = list(it)
    except OSError as exc:
        raise ComparisonError(f"Cannot enumerate directory '{full_name}': {exc}") from exc

    try:
        file_entries = [entry for entry in entries if entry.is_file(follow_symlinks=False)]
        dir_entries = [entry for entry in entries if entry.is_dir(follow_symlinks=False)]
    except OSError as exc:
        raise ComparisonError(f"Cannot enumerate directory '{full_name}': {exc}") from exc

    _check_case_insensitive_collision([entry.name for entry in file_entries], full_name, "filename")

    node = DirectoryNode(full_name=full_name, relative_path=relative_path)

    for entry in sorted(file_entries, key=lambda e: e.name):
        try:
            length = entry.stat(follow_symlinks=False).st_size
        except OSError as exc:
            raise ComparisonError(f"Cannot stat file '{entry.path}': {exc}") from exc
        node.files[entry.name.lower()] = FileEntry(
            name=entry.name,
            relative_path=_join_relative(relative_path, entry.name),
            length=length,
        )

    if not recurse:
        return node

    _check_case_insensitive_collision([entry.name for entry in dir_entries], full_name, "directory name")

    for entry in sorted(dir_entries, key=lambda e: e.name):
        child_relative = _join_relative(relative_path, entry.name)
        node.dirs[entry.name.lower()] = build_directory_node(entry.path, child_relative, recurse=True)

    return node


@dataclass
class SubtreeStatistic:
    file_count: int = 0
    directory_count: int = 0
    byte_count: int = 0
    ignored_count: int = 0


def subtree_statistic(node: DirectoryNode) -> SubtreeStatistic:
    from . import metadata

    stat = SubtreeStatistic()
    for file_entry in node.files.values():
        stat.file_count += 1
        stat.byte_count += file_entry.length
        if metadata.is_ignored(file_entry.name):
            stat.ignored_count += 1

    for child in node.dirs.values():
        child_stat = subtree_statistic(child)
        stat.directory_count += 1 + child_stat.directory_count
        stat.file_count += child_stat.file_count
        stat.byte_count += child_stat.byte_count
        stat.ignored_count += child_stat.ignored_count

    return stat


def empty_leaf_directory_count(node: DirectoryNode, include_self: bool) -> int:
    count = 0
    if include_self and not node.files and not node.dirs:
        count += 1
    for child in node.dirs.values():
        count += empty_leaf_directory_count(child, include_self=True)
    return count


def iter_subtree_files(node: DirectoryNode) -> Iterator[FileEntry]:
    for file_entry in node.files.values():
        yield file_entry
    for child in node.dirs.values():
        yield from iter_subtree_files(child)


def iter_empty_leaf_directories(node: DirectoryNode) -> Iterator[DirectoryNode]:
    for child in node.dirs.values():
        if not child.files and not child.dirs:
            yield child
        else:
            yield from iter_empty_leaf_directories(child)
