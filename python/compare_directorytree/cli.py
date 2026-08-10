"""Command-line entry point for compare-directorytree.

Behavior is defined by the authoritative specification at
../../specs/Compare-DirectoryTree-Spec.md. Section 2 requires the
parameter interface to remain neutral; flag names below follow
conventional Python/argparse CLI style rather than PowerShell's
parameter-naming convention.
"""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional

from .report import compare_directory_tree
from .tree import ComparisonError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="compare-directorytree",
        description=(
            "Compare the files contained in two directories and produce a "
            "human-readable, self-describing report."
        ),
    )
    parser.add_argument("left", metavar="LEFT", help="First directory (displayed as LEFT).")
    parser.add_argument("right", metavar="RIGHT", help="Second directory (displayed as RIGHT).")
    parser.add_argument(
        "--recurse",
        action="store_true",
        help="Compare all descendant files beneath both root directories.",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Recursive presentation mode that summarizes differences by directory. Requires --recurse.",
    )
    parser.add_argument(
        "--expand-missing-subtrees",
        action="store_true",
        help="Recursive presentation mode that reports one-sided subtrees file by file. Requires --recurse.",
    )
    parser.add_argument(
        "--explain-metadata",
        action="store_true",
        help="Append a detailed explanation for each recognized metadata type among the reported differences.",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Suppress console color even in an interactive terminal.",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        lines = compare_directory_tree(
            args.left,
            args.right,
            recurse=args.recurse,
            compact=args.compact,
            expand_missing_subtrees=args.expand_missing_subtrees,
            explain_metadata=args.explain_metadata,
            no_color=args.no_color,
        )
    except ComparisonError as exc:
        print(f"compare-directorytree: {exc}", file=sys.stderr)
        return 1

    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
