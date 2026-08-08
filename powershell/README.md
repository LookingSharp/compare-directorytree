# powershell/

This directory contains the PowerShell implementation of
Compare-DirectoryTree, conforming to the implementation-independent
specification under [`../specs/`](../specs/Compare-DirectoryTree-Spec.md).

## Contents

- `Compare-DirectoryTree.ps1` — the `Compare-DirectoryTree` command.
- `tests/Compare-DirectoryTree.Tests.ps1` — Pester tests for the command.

## Usage

Run the script directly:

```powershell
.\Compare-DirectoryTree.ps1 <path1> <path2>
.\Compare-DirectoryTree.ps1 <path1> <path2> -Recurse -Compact
.\Compare-DirectoryTree.ps1 <path1> <path2> -ExplainMetadata -NoColor
```

Dot-sourcing the file defines the command without running a comparison:

```powershell
. .\Compare-DirectoryTree.ps1
Compare-DirectoryTree C:\Left C:\Right -Recurse
```

The report is written to the success stream as plain text lines, so it can be
piped, saved, or compared.

## Tests

The tests require Pester 5 or later:

```powershell
Invoke-Pester -Path .\tests
```

Two tests self-skip when the environment does not permit their setup: the
case-insensitive collision test needs per-directory case sensitivity, and the
enumeration-failure test needs a deny ACL.

See the authoritative specification for behavioral details; this README
does not duplicate it.
