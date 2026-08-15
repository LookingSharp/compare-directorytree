# Compare-DirectoryTree

Compare-DirectoryTree is a tool for comparing directory trees and reporting
structural, content, and metadata differences.

This repository is implementation-language-neutral. Current implementations are
PowerShell under [`powershell/`](powershell/) and Rust under
[`rust/`](rust/). Additional language implementations may be added later
without restructuring the top-level project.

## Specification

The authoritative behavioral specification is
[`specs/Compare-DirectoryTree-Spec.md`](specs/Compare-DirectoryTree-Spec.md).
All implementations and tests must conform to it.

Proposed design changes that are still being developed or reviewed may exist
as focused documents under [`specs/speclets/`](specs/speclets/).

## Changelog and versioning

See [`CHANGELOG.md`](CHANGELOG.md) for a curated history of notable changes.
Releases of this project use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Review team and agent policy

[`TEAM.md`](TEAM.md) defines the review team applied to specification and
design changes. [`AGENTS.md`](AGENTS.md) is the repository policy for
coding agents.
