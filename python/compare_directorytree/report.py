"""Difference/report model, summary and verdict semantics, and console color.

Behavior is defined by Sections 5-8 of
../../specs/Compare-DirectoryTree-Spec.md.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from . import metadata
from .formatting import (
    format_aggregate_byte_total,
    format_byte_count,
    format_count,
    path_sort_key,
)
from .tree import (
    DirectoryNode,
    SubtreeStatistic,
    build_directory_node,
    empty_leaf_directory_count,
    iter_empty_leaf_directories,
    iter_subtree_files,
    subtree_statistic,
    ComparisonError,
)


@dataclass
class Row:
    cls: str
    sort_key: str
    is_dir: bool
    path: str
    left: str = ""
    right: str = ""
    note: str = ""
    text: str = ""

    @property
    def type_column(self) -> str:
        return "DIR" if self.is_dir else ""


def _make_file_row(cls: str, path: str, file_name: str, left_size: Optional[int], right_size: Optional[int]) -> Row:
    classification = metadata.classify(file_name)
    left_text = "<missing>" if left_size is None else format_byte_count(left_size)
    right_text = "<missing>" if right_size is None else format_byte_count(right_size)
    return Row(
        cls=cls,
        sort_key=path_sort_key(path),
        is_dir=False,
        path=path,
        left=left_text,
        right=right_text,
        note=classification.note if classification else "",
    )


def _format_relative_directory_path(relative_path: str) -> str:
    return "./" if not relative_path else f"{relative_path}/"


def _make_directory_row(cls: str, relative_path: str, summary: str) -> Row:
    return Row(
        cls=cls,
        sort_key=path_sort_key(relative_path),
        is_dir=True,
        path=_format_relative_directory_path(relative_path),
        text=summary,
    )


def _format_directory_summary(stat: SubtreeStatistic) -> str:
    text = "{}, {}, {}".format(
        format_count(stat.file_count, "file", "files"),
        format_count(stat.directory_count, "dir", "dirs"),
        format_aggregate_byte_total(stat.byte_count),
    )
    if stat.ignored_count > 0:
        text += f" | ignored metadata {stat.ignored_count}"
    return text


@dataclass
class Stat:
    left_files: int = 0
    right_files: int = 0
    same: int = 0
    different_size: int = 0
    left_only: int = 0
    right_only: int = 0
    ignored: int = 0
    left_only_directories: int = 0
    right_only_directories: int = 0
    empty_directory_differences: int = 0
    total_differences: int = 0


@dataclass
class Context:
    rows: List[Row] = field(default_factory=list)
    stat: Stat = field(default_factory=Stat)
    mode: str = "Default"
    recurse: bool = False
    encountered_metadata: "Dict[str, metadata.MetadataClassification]" = field(default_factory=dict)


def _add_one_sided_subtree(node: DirectoryNode, cls: str, context: Context) -> None:
    stat = subtree_statistic(node)
    directories_represented = 1 + stat.directory_count

    if cls == "<<":
        context.stat.left_only += stat.file_count
        context.stat.left_only_directories += directories_represented
    else:
        context.stat.right_only += stat.file_count
        context.stat.right_only_directories += directories_represented

    context.stat.ignored += stat.ignored_count
    context.stat.empty_directory_differences += empty_leaf_directory_count(node, include_self=True)

    for file_entry in iter_subtree_files(node):
        classification = metadata.classify(file_entry.name)
        if classification:
            context.encountered_metadata[classification.id] = classification

    if context.mode != "Expand":
        context.rows.append(
            _make_directory_row(cls, node.relative_path, _format_directory_summary(stat))
        )
        return

    for file_entry in sorted(iter_subtree_files(node), key=lambda f: f.relative_path):
        left = file_entry.length if cls == "<<" else None
        right = file_entry.length if cls == ">>" else None
        context.rows.append(_make_file_row(cls, file_entry.relative_path, file_entry.name, left, right))

    empty_leaves = (
        [node] if not node.files and not node.dirs else list(iter_empty_leaf_directories(node))
    )
    for empty_directory in empty_leaves:
        empty_stat = subtree_statistic(empty_directory)
        context.rows.append(
            _make_directory_row(cls, empty_directory.relative_path, _format_directory_summary(empty_stat))
        )


def _add_directory_pair(left: DirectoryNode, right: DirectoryNode, context: Context) -> None:
    direct_same = 0
    direct_left_only = 0
    direct_right_only = 0
    direct_different = 0
    direct_ignored = 0
    direct_rows: List[Row] = []

    keys: List[str] = list(left.files.keys())
    keys.extend(key for key in right.files.keys() if key not in left.files)

    for key in keys:
        left_file = left.files.get(key)
        right_file = right.files.get(key)

        name = left_file.name if left_file else right_file.name
        path = left_file.relative_path if left_file else right_file.relative_path

        classification = metadata.classify(name)
        is_ignored = classification is not None and classification.is_ignored

        if left_file and right_file:
            if left_file.length == right_file.length:
                context.stat.same += 1
                direct_same += 1
                continue
            context.stat.different_size += 1
            direct_different += 1
            cls = "<>"
            row = _make_file_row(cls, path, name, left_file.length, right_file.length)
        elif left_file:
            context.stat.left_only += 1
            direct_left_only += 1
            cls = "<<"
            row = _make_file_row(cls, path, name, left_file.length, None)
        else:
            context.stat.right_only += 1
            direct_right_only += 1
            cls = ">>"
            row = _make_file_row(cls, path, name, None, right_file.length)

        if is_ignored:
            context.stat.ignored += 1
            direct_ignored += 1

        if classification:
            context.encountered_metadata[classification.id] = classification

        direct_rows.append(row)

    if context.mode == "Compact":
        if direct_rows:
            summary = f"{direct_same} same | << {direct_left_only} | >> {direct_right_only} | <> {direct_different}"
            if direct_ignored > 0:
                summary += f" | ignored {direct_ignored}"
            context.rows.append(_make_directory_row("<>", left.relative_path, summary))
    else:
        context.rows.extend(direct_rows)

    if not context.recurse:
        return

    dir_keys: List[str] = list(left.dirs.keys())
    dir_keys.extend(key for key in right.dirs.keys() if key not in left.dirs)

    for key in sorted(dir_keys):
        left_dir = left.dirs.get(key)
        right_dir = right.dirs.get(key)

        if left_dir and right_dir:
            _add_directory_pair(left_dir, right_dir, context)
        elif left_dir:
            _add_one_sided_subtree(left_dir, "<<", context)
        else:
            _add_one_sided_subtree(right_dir, ">>", context)


def _format_summary_line(label: str, value: int) -> str:
    width = 33
    value_text = str(value)
    padding = width - len(label) - len(value_text)
    if padding < 1:
        padding = 1
    return f"{label}{' ' * padding}{value_text}"


def _format_difference_row(row: Row, path_width: int, left_width: int, right_width: int) -> str:
    prefix = f"{row.cls}  {row.type_column.ljust(4)}  "

    if row.is_dir:
        return (prefix + row.path.ljust(path_width) + row.text).rstrip()

    return (
        prefix
        + row.path.ljust(path_width)
        + row.left.rjust(left_width)
        + "   "
        + row.right.rjust(right_width)
        + "   "
        + row.note
    ).rstrip()


def verdict_line(stat: Stat) -> str:
    relevant = stat.total_differences - stat.ignored
    empty_directories = stat.empty_directory_differences
    structural = stat.left_only_directories + stat.right_only_directories
    non_empty_directories = structural - empty_directories

    if relevant > 0:
        parts = [format_count(relevant, "relevant difference", "relevant differences")]
        if empty_directories > 0:
            parts.append(
                format_count(empty_directories, "empty-subdirectory difference", "empty-subdirectory differences")
            )
        if non_empty_directories > 0:
            parts.append(
                format_count(non_empty_directories, "directory-structure difference", "directory-structure differences")
            )
        if stat.ignored > 0:
            parts.append(format_count(stat.ignored, "ignored metadata difference", "ignored metadata differences"))
        return "RESULT: DIFFERENT - " + " | ".join(parts)

    clauses = []
    if empty_directories > 0:
        clauses.append("different empty subdirectories")
    if non_empty_directories > 0:
        clauses.append("directory structure differs")

    if stat.ignored > 0:
        if clauses:
            clauses.append("other differences limited to ignorable metadata")
        else:
            clauses.append(
                "differences limited to " + format_count(stat.ignored, "ignored metadata file", "ignored metadata files")
            )

    if clauses:
        return "RESULT: MATCH - qualified: " + "; ".join(clauses)

    return "RESULT: MATCH - all " + format_count(stat.same, "file", "files") + " match"


_ESC = "\x1b"
_RESET = f"{_ESC}[0m"
_MARKER_COLOR = {"<<": f"{_ESC}[36m", ">>": f"{_ESC}[35m", "<>": f"{_ESC}[33m"}


def _add_color(lines: List[str]) -> List[str]:
    colored_lines = []
    for text in lines:
        colored = text

        marker = text[:2]
        if marker in _MARKER_COLOR:
            colored = f"{_MARKER_COLOR[marker]}{marker}{_RESET}{text[2:]}"

        ignored_index = colored.find("Ignored: ")
        if ignored_index >= 0:
            colored = f"{colored[:ignored_index]}{_ESC}[2m{colored[ignored_index:]}{_RESET}"

        if text.startswith("RESULT: DIFFERENT"):
            colored = colored.replace("RESULT: DIFFERENT", f"RESULT: {_ESC}[31mDIFFERENT{_RESET}", 1)
        elif text.startswith("RESULT: MATCH"):
            colored = colored.replace("RESULT: MATCH", f"RESULT: {_ESC}[32mMATCH{_RESET}", 1)

        colored_lines.append(colored)
    return colored_lines


def color_supported(stream=None) -> bool:
    stream = stream if stream is not None else sys.stdout
    if os.environ.get("NO_COLOR"):
        return False
    try:
        return stream.isatty()
    except (AttributeError, ValueError):
        return False


def compare_directory_tree(
    reference_path: str,
    difference_path: str,
    *,
    recurse: bool = False,
    compact: bool = False,
    expand_missing_subtrees: bool = False,
    explain_metadata: bool = False,
    no_color: bool = False,
    stream=None,
) -> List[str]:
    """Compare the files contained in two directories.

    Returns the report as a list of plain-text lines (colored with ANSI
    escapes when color is enabled and supported).
    """

    if compact and expand_missing_subtrees:
        raise ComparisonError("--compact and --expand-missing-subtrees cannot be combined.")
    if compact and not recurse:
        raise ComparisonError("--compact requires --recurse.")
    if expand_missing_subtrees and not recurse:
        raise ComparisonError("--expand-missing-subtrees requires --recurse.")

    roots = []
    for candidate in (reference_path, difference_path):
        if not os.path.exists(candidate):
            raise ComparisonError(f"Path not found: {candidate}")
        if not os.path.isdir(candidate):
            raise ComparisonError(f"Path is not a directory: {candidate}")
        roots.append(os.path.abspath(candidate))

    left_root, right_root = roots

    left_tree = build_directory_node(left_root, "", recurse=recurse)
    right_tree = build_directory_node(right_root, "", recurse=recurse)

    mode = "Compact" if compact else "Expand" if expand_missing_subtrees else "Default"

    stat = Stat()
    context = Context(rows=[], stat=stat, mode=mode, recurse=recurse, encountered_metadata={})

    _add_directory_pair(left_tree, right_tree, context)

    left_stat = subtree_statistic(left_tree)
    right_stat = subtree_statistic(right_tree)
    stat.left_files = left_stat.file_count
    stat.right_files = right_stat.file_count
    stat.total_differences = stat.different_size + stat.left_only + stat.right_only
    relevant = stat.total_differences - stat.ignored

    rows_by_class: List[List[Row]] = []
    for cls in ("<<", ">>", "<>"):
        class_rows = [row for row in context.rows if row.cls == cls]
        class_rows.sort(key=lambda row: row.sort_key)
        rows_by_class.append(class_rows)

    file_rows = [row for row in context.rows if not row.is_dir]
    has_directory_row = any(row.is_dir for row in context.rows)

    path_width = 38
    left_width = 17
    right_width = 18
    for row in context.rows:
        if len(row.path) + 2 > path_width:
            path_width = len(row.path) + 2
    for row in file_rows:
        if len(row.left) > left_width:
            left_width = len(row.left)
        if len(row.right) > right_width:
            right_width = len(row.right)

    lines: List[str] = []

    lines.append("FILE COMPARISON")
    lines.append("===============")
    lines.append("")
    lines.append(f"LEFT : {left_root}")
    lines.append(f"RIGHT: {right_root}")
    lines.append("")

    if recurse:
        mode_text = {"Compact": "compact", "Expand": "expand missing subtrees"}.get(mode, "default recursive mode")
        lines.append("Scope : Files in these directories and all subdirectories.")
        lines.append(f"        Presentation: {mode_text}.")
        lines.append("        Hidden and system files ARE included.")
        lines.append("Match : Relative paths are compared case-insensitively.")
        lines.append("Same  : Matching relative path and exact size in bytes.")
    else:
        lines.append("Scope : Files in these directories only; subdirectories are NOT searched.")
        lines.append("        Hidden and system files ARE included.")
        lines.append("Match : Filenames are compared case-insensitively.")
        lines.append("Same  : Matching filename and exact size in bytes.")

    lines.append("Ignore: Known disposable metadata/cache files are reported but do not")
    lines.append("        affect the final comparison result.")
    lines.append("Note  : Contents, hashes, timestamps, attributes, and other metadata are")
    lines.append("        NOT compared.")
    lines.append("")
    lines.append("SUMMARY")
    lines.append("-------")
    lines.append(_format_summary_line("LEFT files:", stat.left_files))
    lines.append(_format_summary_line("RIGHT files:", stat.right_files))
    lines.append(_format_summary_line("Same:", stat.same))
    lines.append(_format_summary_line("Different size:", stat.different_size))
    lines.append(_format_summary_line("LEFT only:", stat.left_only))
    lines.append(_format_summary_line("RIGHT only:", stat.right_only))

    if recurse:
        lines.append("")
        lines.append(_format_summary_line("LEFT directories:", left_stat.directory_count))
        lines.append(_format_summary_line("RIGHT directories:", right_stat.directory_count))
        lines.append(_format_summary_line("LEFT-only directories:", stat.left_only_directories))
        lines.append(_format_summary_line("RIGHT-only directories:", stat.right_only_directories))
        lines.append(_format_summary_line("Empty-directory differences:", stat.empty_directory_differences))

    lines.append("")
    lines.append(_format_summary_line("Total differences:", stat.total_differences))
    lines.append(_format_summary_line("Ignored metadata differences:", stat.ignored))
    lines.append(_format_summary_line("Relevant differences:", relevant))

    if recurse:
        lines.append(
            _format_summary_line("Structural differences:", stat.left_only_directories + stat.right_only_directories)
        )

    if context.rows:
        lines.append("")
        lines.append("DIFFERENCES")
        lines.append("-----------")
        lines.append("")
        lines.append(
            "    {}  {}{}   {}   {}".format(
                "Type",
                "File / Directory".ljust(path_width),
                "LEFT size (bytes)".rjust(left_width),
                "RIGHT size (bytes)".rjust(right_width),
                "Note",
            )
        )
        lines.append(
            "    {}  {}{}   {}   {}".format(
                "----",
                ("-" * 16).ljust(path_width),
                ("-" * 17).rjust(left_width),
                ("-" * 18).rjust(right_width),
                "----",
            )
        )

        emitted = False
        for class_rows in rows_by_class:
            if not class_rows:
                continue
            if emitted:
                lines.append("")
            for row in class_rows:
                lines.append(_format_difference_row(row, path_width, left_width, right_width))
            emitted = True

        lines.append("")
        lines.append("Legend:")
        lines.append("  <<   Exists only on LEFT")
        lines.append("  >>   Exists only on RIGHT")
        if recurse:
            lines.append("  <>   Same relative path, different size")
        else:
            lines.append("  <>   Same filename, different size")
        if has_directory_row:
            lines.append("  DIR  Directory summary row")

    lines.append("")
    lines.append(verdict_line(stat))

    if explain_metadata and context.encountered_metadata:
        lines.append("")
        lines.append("METADATA EXPLANATIONS")
        lines.append("---------------------")
        for classification in context.encountered_metadata.values():
            lines.append(f"  {classification.id}  {classification.note} - {classification.explanation}")

    if not no_color and color_supported(stream):
        return _add_color(lines)

    return lines
