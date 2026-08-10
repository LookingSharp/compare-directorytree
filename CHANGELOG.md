# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Python implementation of `compare_directorytree` in
  `python/compare_directorytree/`, covering the report model, metadata
  catalog and policy, summary and verdict semantics, error and ambiguity
  handling, `--recurse` with all three presentation modes,
  `--explain-metadata`, and console color with `--no-color`.
- Standard-library `unittest` validation tests in
  `python/tests/test_compare_directorytree.py` covering the Section 10
  acceptance scenarios and the Appendix B invariants.
- PowerShell implementation of `Compare-DirectoryTree` in
  `powershell/Compare-DirectoryTree.ps1`, covering the report model, metadata
  catalog and policy, summary and verdict semantics, error and ambiguity
  handling, `-Recurse` with all three presentation modes, `-ExplainMetadata`,
  and console color with `-NoColor`.
- Pester validation tests in `powershell/tests/Compare-DirectoryTree.Tests.ps1`
  covering the Section 10 acceptance scenarios and the Appendix B invariants.
- Specified recursive comparison (`-Recurse`) with the Default, `-Compact`,
  and `-ExpandMissingSubtrees` presentation modes, directory-structure and
  empty-directory reporting, missing-subtree collapse, and qualified MATCH
  verdicts.
- Specified sparse console color presentation and the `-NoColor` switch.
- Specified byte-size formatting: file size columns always show exact bytes with
  thousands separators, while directory-summary rows use abbreviated 1024-based
  aggregate totals.
- Specified a canonical recursive report, including the `LEFT directories`,
  `RIGHT directories`, `LEFT-only directories`, `RIGHT-only directories`,
  `Empty-directory differences`, and `Structural differences` summary counters.
- Specified the verdict grammar: fixed segment and qualification-clause order,
  omission of zero-valued segments, and singular/plural count wording.
- Specified deterministic ordering within a difference class, including how
  directory-summary rows interleave with file rows.
- Specified legend content, including the `DIR` entry and the recursive
  `Same relative path, different size` wording.

### Changed

- Clarified Section 5.4 and Appendix B invariant 40: the legend always lists
  `<<`, `>>`, and `<>` whenever the `DIFFERENCES` section appears, `DIR` is
  listed only when a directory-summary row is present, and the whole
  `DIFFERENCES` section is omitted when there are no difference rows.
  Resolves the ambiguity tracked in issue #8.
- Clarified Section 6.2: the compared roots produce a `-Compact` summary row
  when they have direct file differences, and the empty root-relative path is
  rendered as `.\`.
- Clarified Section 6.3 and Section 10.13 items 14 and 15:
  `-ExpandMissingSubtrees` emits a `DIR` row for every truly empty descendant
  directory (no files and no child directories) and traverses fileless
  container directories rather than collapsing them.
- Corrected the Section 5.2 canonical example, whose `<>` rows were listed in
  an order that contradicted the Section 5 ordering rule.
- Corrected the Section 6.3 `-ExpandMissingSubtrees` example, whose rows were
  listed in an order that contradicted the Section 5 ordering rule.

- Replaced the placeholder authoritative specification
  `specs/Compare-DirectoryTree-Spec.md` with the working-draft Directory File
  Comparison Specification.
- Merged the recursive-comparison and console-color-presentation speclets into
  the authoritative specification and removed them from `specs/speclets/`.
- Verdict lines are now single-line, consistent with the one-line
  comparison-entry rule.
- **Breaking:** the report verdict pair is now `RESULT: MATCH` /
  `RESULT: DIFFERENT` instead of `RESULT: SAME` / `RESULT: NOT THE SAME`, so an
  exact search for the positive verdict cannot also match the negative one. The
  per-file `Same` counter, the `Same  :` header rule line, and the `-Compact`
  `<same> same` counts are unchanged.
- **Breaking:** directory-summary rows no longer carry an inline `[DIR]` name
  prefix. A narrow `Type` column now holds `DIR`, and ordinary file rows leave
  it blank, so directory paths and file paths begin in the same column. The
  differences table header is now `Type` / `File / Directory`.
- Merged the report verdict/Type-column speclet into the authoritative
  specification and removed it from `specs/speclets/`.

### Fixed

- PowerShell: root-relative file and directory paths were built with
  `Join-Path`, which uses the host's native path separator (`/` on
  non-Windows hosts) instead of the `\` convention used consistently
  elsewhere in the report (sorting, display, and the test suite). Paths are
  now always joined with a literal `\`.
- Both implementations: `Format-CDTAggregateByteTotal` /
  `format_aggregate_byte_total` could display a rounded value of `1024` in
  the current unit (e.g. `1024 KB`) instead of advancing to the next unit
  (`1 MB`), when the true value was just under a unit boundary. The
  unit selection is now re-checked after rounding.
- PowerShell: running `Compare-DirectoryTree.ps1` directly without the
  required `ReferencePath`/`DifferencePath` arguments produced a
  parameter-binding error but still exited with code `0`, making the
  failure indistinguishable from success to calling scripts. The script now
  fails with a clear error and a non-zero exit code.
- Python: an excessively deep directory tree under `--recurse` raised an
  uncaught `RecursionError` instead of the clear, catchable
  `ComparisonError` that Section 9 requires for input that cannot be fully
  enumerated.
