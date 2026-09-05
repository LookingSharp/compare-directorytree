# asm/

This directory contains the x86-64 assembly (NASM, Windows x64 calling
convention) implementation of Compare-DirectoryTree, conforming to the
implementation-independent specification under
[`../specs/`](../specs/Compare-DirectoryTree-Spec.md).

## Contents

- `src/main.asm` — the entire implementation in a single NASM source file.
  Uses only `kernel32.dll` (no CRT, no heap): `GetCommandLineW`,
  `GetStdHandle`, `WriteFile`, `GetFileAttributesW`, `FindFirstFileW`,
  `FindNextFileW`, `FindClose`, `GetLastError`, `ExitProcess`.
- `tests/` — a smoke-test harness driving the built executable against
  fixture directories covering the Section 10 acceptance scenarios in
  scope for this version.

## Scope of this version

This is a v1 implementation covering the **non-recursive base comparison**
only. The following spec features are **not yet implemented**:

- `-Recurse`, `-Compact`, `-ExpandMissingSubtrees` (recursive comparison and
  its presentation modes; Sections 6-7).
- `-ExplainMetadata` (Section 9 metadata explanations block).
- Color output / `-NoColor` (Section 7.2); all output is plain, uncolored
  ASCII text regardless of terminal capability.
- Appendix A.2 "recognized but relevant" wildcard metadata patterns (e.g.
  `*.xmp`, `._*`). Only the exact-name Appendix A.1 catalog (`Thumbs.db`,
  `ehthumbs.db`, `desktop.ini`, `.DS_Store`, `.directory`) is recognized as
  ignorable metadata.
- Non-ASCII filenames/paths: names and paths are rendered by truncating each
  UTF-16 code unit to its low byte. Non-ASCII characters will not render
  correctly. Enumeration, sorting, and comparison of non-ASCII names are
  otherwise correct (they operate on the full UTF-16 code units); only the
  *display* is best-effort ASCII.
- A hard cap of `MAX_ENTRIES` (4096) files per side. Exceeding it is treated
  as an enumeration failure (exit code 2), per the spec's "no partial
  comparison result" requirement.

Everything else in Section 5 (report format), Section 8.1 (verdict
grammar), and Appendix A.1 is implemented, including dynamic column widths
in the `DIFFERENCES` table and `Ignored: <note>` annotations using the
actual Appendix A.1 note text for each matched entry.

## Building

Requires [NASM](https://www.nasm.us/) and a Win64-capable linker. This has
been built and tested cross-compiling from Linux with the mingw-w64
toolchain:

```bash
nasm -f win64 src/main.asm -o src/main.obj
x86_64-w64-mingw32-ld src/main.obj -o src/main.exe -lkernel32 --subsystem console -e start
```

It can equally be linked with a native Windows toolchain (e.g. `link.exe`
from the MSVC Build Tools, or `lld-link`) against `kernel32.lib`, using
`start` as the entry point.

## Usage

```
main.exe <left-dir> <right-dir>
```

Exit codes:

- `0` — MATCH
- `1` — DIFFERENT
- `2` — usage, validation, enumeration, or collision error

The report is written to standard output as plain text lines. Errors are
written to standard error and do not emit a partial comparison report.

## Tests

`tests/run-tests.sh [path-to-main.exe]` builds fixture directories and
asserts exit codes and key output lines against the built executable
(default `src/main.exe`). On Linux/CI it runs the executable under Wine; on
Windows it can run the executable directly. See that script for exact
invocation.

See the authoritative specification for behavioral details; this README
does not duplicate it.
