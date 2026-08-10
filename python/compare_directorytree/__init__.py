"""Public package API for compare_directorytree.

Behavior is defined by the authoritative specification at
../../specs/Compare-DirectoryTree-Spec.md.
"""

from .report import compare_directory_tree
from .tree import ComparisonError

__all__ = ["compare_directory_tree", "ComparisonError"]
