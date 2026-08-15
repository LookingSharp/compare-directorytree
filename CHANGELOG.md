# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Rust implementation of `Compare-DirectoryTree` in `rust/`, including the
  zero-dependency Cargo CLI, recursive presentation modes, metadata catalog
  policy, summary and verdict semantics, report rendering, and `--no-color`
  / interactive-terminal color behavior.
- Rust integration tests in `rust/tests/` covering the Section 10 acceptance
  scenarios, recursive presentation modes, ANSI color rules, deterministic
  ordering, legend content, metadata classification, and verdict grammar.
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
