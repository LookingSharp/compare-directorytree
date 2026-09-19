# `--charm` chime candidates

These are candidate completion chimes for the proposed `--charm` flag
(see `specs/speclets/charm-completion-chime.md`). None of them is wired
into the CLI yet — they are here only so the repository owner can download
and listen to them locally before one is selected as the shipped asset.

Each file is a mono 16-bit PCM WAV, 44.1 kHz, roughly 8-10 seconds long,
synthesized from simple square/triangle waveforms (classic 8-bit/chiptune
style). To listen, download the file and play it with any standard audio
player (e.g. `afplay candidate1_triumphant_fanfare.wav` on macOS,
`aplay candidate1_triumphant_fanfare.wav` on Linux, or just double-click it
on Windows).

Five candidates were composed; these are the three finalists:

1. **`candidate1_triumphant_fanfare.wav` — Triumphant Fanfare** (C major).
   Brassy square-wave chords with a rising arpeggio into a held high note.
   Classic "task accomplished" fanfare feel.
2. **`candidate2_playful_arpeggio.wav` — Playful Arpeggio** (A minor
   pentatonic). Fast, bouncy arpeggio loop over a walking bass with light
   noise-channel percussion. Light and energetic rather than grandiose.
3. **`candidate4_retro_victory.wav` — Retro Victory Jingle** (G major).
   Up-tempo NES-style victory jingle with a rising melodic run, bass line,
   and hi-hat-style noise hits. The most "video game level-clear" of the
   three.

Two additional candidates were composed but not advanced to the shortlist:

- **Calm Resolve** (D major, triangle-wave lead): a slower, warmer cue.
  Pleasant but low-energy for a "your comparison finished" signal.
- **Digital Sunrise** (E major, accelerating pulse-wave run): an
  interesting rising build, but tonally close to Triumphant Fanfare while
  being less immediately readable as a completion cue.

Once the repository owner picks a finalist, it should be copied to
`rust/assets/charm.wav` (or similar), this candidates directory should be
removed, and the implementation in `specs/speclets/charm-completion-chime.md`
should be finished per the AGENTS.md behavioral-change workflow (spec
update, changelog entry, SemVer assessment, tests).
