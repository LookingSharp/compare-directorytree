# python/

This directory contains the Python implementation of
Compare-DirectoryTree, conforming to the implementation-independent
specification under [`../specs/`](../specs/Compare-DirectoryTree-Spec.md).

## Requirements

Python 3.9 or later. No third-party runtime dependencies.

## Contents

- `compare_directorytree/` — the `compare_directorytree` package:
  - `metadata.py` — the Appendix A metadata catalog and classification.
  - `formatting.py` — byte-size, count, and path-sort-key formatting.
  - `tree.py` — directory enumeration and subtree statistics.
  - `report.py` — the difference/report model, summary, verdict, and
    console color.
  - `cli.py` — the command-line entry point.
- `tests/test_compare_directorytree.py` — tests for the command, covering
  the Section 10 acceptance scenarios and the Appendix B invariants.

## Usage

Run as a module:

```sh
python3 -m compare_directorytree <path1> <path2>
python3 -m compare_directorytree <path1> <path2> --recurse --compact
python3 -m compare_directorytree <path1> <path2> --explain-metadata --no-color
python3 -m compare_directorytree <path1> <path2> --recurse --expand-missing-subtrees
```

Or use the library directly:

```python
from compare_directorytree import compare_directory_tree

for line in compare_directory_tree("/left", "/right", recurse=True):
    print(line)
```

The report is written to standard output as plain text lines, so it can be
piped, saved, or compared.

Flag names follow conventional Python/CLI style (`--recurse`, `--compact`,
`--expand-missing-subtrees`, `--explain-metadata`, `--no-color`) rather than
PowerShell's parameter-naming convention; the parameter interface is
otherwise neutral per Section 2 of the specification.

## Tests

The tests use only the standard library:

```sh
python3 -m unittest discover -s tests
```

One test self-skips when the environment does not permit its setup: the
enumeration-failure test needs POSIX permission bits and a non-root user.

See the authoritative specification for behavioral details; this README
does not duplicate it.
