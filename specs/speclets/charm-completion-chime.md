# Speclet: `--charm` completion chime

Status: Draft — pending selection of final audio asset
Owner decision needed: Dave (final track selection; this speclet does not
pick one)

## Summary

Add an opt-in `--charm` flag to the Rust `compare-directorytree` CLI. When
present, and only when the comparison run completes successfully (i.e. the
process would otherwise exit 0), the CLI plays a short (~8-10 second),
original 8-bit/chiptune-style audio cue before exiting.

## Trigger and gating

- Off by default. The flag must be explicitly passed as `--charm`.
- Only plays after a successful run. It must not play when the CLI exits
  non-zero (argument errors, missing paths, I/O failures, etc.).
- Must not alter exit codes, stdout/stderr report content, or any other
  existing output. This is purely an added side effect for interactive use.
- If audio output is unavailable (headless/CI environment, no audio
  device, playback backend error), the CLI must not fail or hang: it
  should skip playback silently or emit, at most, a non-fatal warning on
  stderr, and still exit 0.
- `--charm` combined with `--no-color` or any other existing flag must not
  change the interaction of those flags with each other.

## Asset

- The chime is a small, embedded audio asset shipped with the crate
  (e.g. via `include_bytes!`), not synthesized at runtime. This avoids a
  runtime synthesis dependency and keeps behavior deterministic.
- Exactly one asset ships with the CLI. Candidate tracks considered for
  this slot are listed in `rust/assets/chime-candidates/README.md`; that
  directory is temporary and is removed once a candidate is selected.
- The shipped asset should be a short, mono, 16-bit PCM WAV to keep the
  embedded binary size small and the playback dependency surface simple.

## Playback mechanism

- Playback requires a small, well-maintained cross-platform audio crate
  (candidate: `rodio`). This is a new dependency and must be checked with
  the GitHub Advisory Database before being added, per the repository's
  dependency-vetting practice.
- Playback failures (missing audio device, unsupported platform, etc.)
  must be handled gracefully per the gating rules above.

## Out of scope for this speclet

- Runtime synthesis or user-supplied custom chimes.
- Volume control, muting via environment variable, or other configuration
  beyond the single `--charm` flag.
- Any change to non-Rust (PowerShell) implementation; this is Rust-only.

## Team-perspective notes

- **Priya (engineering):** the audio crate must support the same platforms
  the CLI already targets, and playback must not block process exit for
  more than the chime's own duration.
- **Marcus (security):** the new audio-playback dependency and its
  transitive dependencies must be scanned via the GitHub Advisory Database
  before being pinned in `Cargo.toml`.
- **Maya (design):** the chime should read as a short, unobtrusive
  "success" cue, not a jingle that overstays its welcome in repeated CLI
  use.
- **Alex (product):** opt-in via a flag (not on by default) avoids
  surprising users running the tool in scripts or CI.
- **Theo (convergence):** the flag name, gating rules, and asset-embedding
  approach in this speclet are considered cheaply reversible pre-release
  and do not require escalation; the specific audio asset is a matter of
  taste, so final track selection is left to Dave.

## Next steps

1. Repository owner selects one of the candidate tracks in
   `rust/assets/chime-candidates/`.
2. Copy the selected file to its permanent location (e.g.
   `rust/assets/charm.wav`), remove the candidates directory.
3. Fold this speclet into `specs/Compare-DirectoryTree-Spec.md`.
4. Implement `--charm` in `rust/src`, add the playback dependency (after
   advisory-database review), and add tests for flag parsing/gating
   behavior (not for audio content).
5. Add a changelog entry under `Unreleased`.
6. Assess SemVer impact (expected: minor — new, backward-compatible,
   opt-in feature).
