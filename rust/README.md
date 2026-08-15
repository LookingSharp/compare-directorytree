# rust/

This directory contains the Rust implementation of Compare-DirectoryTree,
conforming to the implementation-independent specification under
[`../specs/`](../specs/Compare-DirectoryTree-Spec.md).

## Contents

- `Cargo.toml` — the zero-dependency Cargo package for the binary crate.
- `src/` — the Rust source for the `compare-directorytree` command.
- `tests/` — integration tests covering the specification scenarios and
  formatting/color invariants.

## Usage

Build and run with Cargo:

```bash
cargo run -- <path1> <path2>
cargo run -- <path1> <path2> --recurse --compact
cargo run -- <path1> <path2> --explain-metadata --no-color
```

Build a release binary:

```bash
cargo build --release
```

Flags:

- `--recurse`
- `--compact` (requires `--recurse`)
- `--expand-missing-subtrees` (requires `--recurse`)
- `--explain-metadata`
- `--no-color`
- `-h`, `--help`

Exit codes:

- `0` — MATCH
- `1` — DIFFERENT
- `2` — usage or comparison error

The report is written to standard output as plain text lines. Errors are
written to standard error and do not emit a partial comparison report.

## Tests

Run the Rust test suite with Cargo:

```bash
cargo test
```

Optional formatting/lint checks:

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```

See the authoritative specification for behavioral details; this README does
not duplicate it.
