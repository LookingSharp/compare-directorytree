# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
