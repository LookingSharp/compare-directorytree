# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- PowerShell implementation of `Compare-DirectoryTree` in
  `powershell/Compare-DirectoryTree.ps1`, covering the report model, metadata
  catalog and policy, summary and verdict semantics, error and ambiguity
  handling, `-Recurse` with all three presentation modes, `-ExplainMetadata`,
  and console color with `-NoColor`.
- Pester validation tests in `powershell/tests/Compare-DirectoryTree.Tests.ps1`
  covering the Section 10 acceptance scenarios and the Appendix B invariants.
- Specified recursive comparison (`-Recurse`) with the Default, `-Compact`,
  and `-ExpandMissingSubtrees` presentation modes, directory-structure and
  empty-directory reporting, missing-subtree collapse, and qualified SAME
  verdicts.
- Specified sparse console color presentation and the `-NoColor` switch.

### Changed

- Replaced the placeholder authoritative specification
  `specs/Compare-DirectoryTree-Spec.md` with the working-draft Directory File
  Comparison Specification.
- Merged the recursive-comparison and console-color-presentation speclets into
  the authoritative specification and removed them from `specs/speclets/`.
- Verdict lines are now single-line, consistent with the one-line
  comparison-entry rule.
