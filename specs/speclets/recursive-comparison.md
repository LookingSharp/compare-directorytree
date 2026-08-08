# Recursive Comparison Speclet

Status: Relatively locked; intended for later merge into the main directory-comparison specification
Version: 0.2

## 1. Recursive Scope

When `-Recurse` is specified, compare all descendant files beneath both supplied root directories.

Directory structure is also observed so that missing or empty directories are not silently omitted from the report.

The comparison remains preservation-oriented:

- relevant file differences determine whether substantive contents differ,
- directory-only differences remain visible,
- ignorable metadata remains visible,
- and an otherwise-SAME verdict is qualified when structure or ignorable metadata differs.

## 2. Recursive Presentation Modes

`-Recurse` supports three mutually exclusive presentation modes.

### Default

No additional presentation switch.

- Directories present on both sides are traversed and their file differences are reported normally.
- A directory subtree present on only one side is collapsed at the highest missing directory into one `[DIR]` summary row.
- Descendants of that collapsed missing subtree are not redundantly listed.
- Empty missing directories are still reported.

### `-Compact`

Summarize differences by directory instead of listing individual differing files within shared directories.

- A shared directory with direct file differences produces one `[DIR]` summary row.
- The summary counts files directly in that directory; descendant directories with differences receive their own rows.
- This preserves the location of differences rather than allowing a high-level directory to swallow all descendant detail.
- Fully one-sided subtrees remain collapsed at the highest missing directory, as in the default mode.
- Empty-directory differences remain explicit.

Example:

```text
<>  [DIR] 2018\Camp\Cache\   34 same | << 6 | >> 0 | <> 2 | ignored 1
```

### `-ExpandMissingSubtrees`

Use normal file-level reporting even inside directories that exist on only one side.

- A one-sided subtree is traversed instead of represented by one collapsed summary row.
- Descendant files are reported individually with their root-relative paths.
- Non-empty container directories are not redundantly listed when their contents make their existence evident.
- Empty directories are still reported explicitly because they otherwise have no visible descendant entry.
- Shared directories behave as in the default recursive mode.

Example:

```text
<<  2018\Camp\Raw\IMG_1001.JPG             5,238,104        <missing>
<<  2018\Camp\Raw\Nested\IMG_1002.JPG      4,921,772        <missing>
<<  [DIR] 2018\Camp\Raw\Empty\             0 files, 0 dirs, 0 B
```

`-Compact` and `-ExpandMissingSubtrees` are alternative recursive presentation modes and must not be combined.

They are meaningful only with `-Recurse`.

## 3. Relative Paths

Recursive entries are reported relative to the supplied roots.

Example:

```text
2018\Camp\IMG_1842.JPG
```

The first root remains LEFT and the second root remains RIGHT.

## 4. One-Line Output Preference

Every comparison entry should occupy one physical output line.

This applies to:

- file difference rows,
- `[DIR]` subtree summaries,
- empty-directory rows,
- metadata annotations associated with those rows.

Do not emit continuation lines beneath a comparison row merely to explain counts or metadata.

Example:

```text
<<  [DIR] 2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB | ignored metadata 2
```

Not:

```text
<<  [DIR] 2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB
                              2 ignored metadata files
```

Intent for later merge: adopt this one-line comparison-entry preference throughout the full specification unless doing so conflicts with an existing report requirement or materially harms clarity. Any such conflict should be resolved explicitly during the merge rather than silently introducing multiline compare rows.

Verdict qualifications should also remain on one line when reasonably concise.

Example:

```text
RESULT: SAME - qualified: different empty subdirectories; differences otherwise limited to ignorable metadata
```

## 5. Missing Subtree Collapse

In the default and Compact modes, if an entire directory subtree exists only on one side, report the highest missing subtree once.

Example:

```text
<<  [DIR] 2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB | ignored metadata 2
```

Do not additionally list descendants of that subtree.

The one-line subtree summary must account for all descendants so the user can see that the entire subtree was considered.

A collapsed missing-subtree summary includes:

- descendant file count,
- descendant directory count,
- total descendant file bytes,
- ignored-metadata count when nonzero.

Counts are recursive for collapsed one-sided subtrees.

## 6. Empty Directories

Empty directories are observable and must be reported in all recursive modes.

Example:

```text
<<  [DIR] 2018\Camp\Empty\   0 files, 0 dirs, 0 B
```

This prevents an empty-directory difference from appearing to have been overlooked.

An empty-directory-only difference does not create a relevant file-content difference, but it qualifies the final verdict.

Nested empty directories follow the selected presentation mode:

- Default and Compact may summarize a wholly one-sided nested subtree at its highest missing directory.
- `-ExpandMissingSubtrees` exposes the empty leaf directories that would otherwise have no visible file entry.

## 7. Metadata-Only Subtrees

A subtree whose only file differences are explicitly ignorable metadata is still visible.

Collapsed example:

```text
<<  [DIR] 2018\Camp\Cache\   1 file, 0 dirs, 81,920 B | ignored metadata 1
```

Compact shared-directory example:

```text
<>  [DIR] 2018\Camp\Cache\   34 same | << 1 | >> 0 | <> 0 | ignored 1
```

Expanded example:

```text
<<  2018\Camp\Cache\Thumbs.db   81,920   <missing>   Ignored: Windows thumbnail cache
```

If every difference in the relevant subtree is ignorable metadata, it does not create a relevant file-content difference, but the final verdict is qualified.

Recognized metadata classified as relevant continues to count as a relevant difference.

## 8. Recursive Difference Classes

The existing visual model remains:

```text
<<  Exists only on LEFT
>>  Exists only on RIGHT
<>  Exists on both sides but differs
```

Directory summaries use the same markers:

```text
<<  [DIR] ...
>>  [DIR] ...
<>  [DIR] ...
```

Difference classes remain ordered:

```text
<<

>>

<>
```

with a blank line between non-empty classes.

## 9. Compact Directory-Summary Semantics

For a shared directory in Compact mode:

```text
<>  [DIR] <relative-path>\   <same> same | << <left-only> | >> <right-only> | <> <different-size> | ignored <count>
```

The counts apply to files directly contained in that directory, not recursively to descendant shared directories.

This prevents double-counting and preserves useful location information.

Omit `| ignored <count>` when the count is zero.

A Compact `[DIR]` row is shown only when that directory has:

- direct file differences,
- a directory-structure difference that must be surfaced,
- or a metadata-only difference that must remain visible.

A directory containing only matching direct files and whose descendant differences are reported elsewhere does not need its own row.

Fully one-sided subtrees use the collapsed recursive summary from Section 5 rather than the direct-file Compact grammar.

## 10. Expanded Missing-Subtree Semantics

With `-ExpandMissingSubtrees`, a one-sided subtree is represented by its observable leaf content rather than by a collapsed parent row.

Report:

- each descendant file as an ordinary `<<` or `>>` file row,
- each empty descendant directory as a `[DIR]` row,
- metadata annotations using the normal file-note policy.

Do not also emit summary `[DIR]` rows for non-empty ancestor directories merely to restate that the subtree is missing.

This mode is intentionally verbose and is intended for cases where the user wants the full inventory of a missing subtree.

## 11. Counting Semantics

Collapsed directory rows are presentation summaries, not single logical file differences.

Summary counts must reflect the actual objects represented by the report, not merely the number of displayed rows.

The recursive report must retain enough information to distinguish:

- relevant file differences,
- ignored metadata differences,
- empty/directory-structure-only differences,
- collapsed subtree rows,
- and displayed output rows.

A collapsed subtree containing 214 relevant files represents 214 relevant file differences even though it occupies one displayed row.

Compact summaries likewise preserve the underlying difference counts.

## 12. Qualified Verdicts

If no relevant file differences exist, the overall verdict remains SAME under the selected comparison rules, but observed structural or ignorable differences qualify it.

Examples:

```text
RESULT: SAME - qualified: different empty subdirectories
```

```text
RESULT: SAME - qualified: subdirectories differ only in ignorable metadata files
```

```text
RESULT: SAME - qualified: different empty subdirectories; other differences limited to ignorable metadata
```

If relevant file differences exist:

```text
RESULT: NOT THE SAME - 4 relevant file differences | 2 empty-subdirectory differences | 3 ignored metadata differences
```

Exact final wording may be harmonized with the main report during merge, but the qualification semantics are normative.

## 13. Acceptance Cases

The recursive implementation must demonstrate at least these behaviors:

1. A fully missing nested subtree is collapsed at its highest missing directory in Default mode.
2. Descendants of a collapsed missing subtree are not redundantly listed.
3. A collapsed subtree summary is entirely one line.
4. Ignored-metadata counts on `[DIR]` rows are on the same line as the subtree summary.
5. An empty directory existing on only one side is reported as `0 files, 0 dirs, 0 B`.
6. Nested empty-directory structure is not silently omitted.
7. A metadata-only subtree remains visible without creating a relevant difference when every differing file is ignorable.
8. A subtree containing any relevant file difference contributes those underlying relevant differences to the overall result.
9. File differences inside directories present on both sides are reported individually in Default mode using root-relative paths.
10. Compact mode emits directory-level summaries for direct file differences and recursively reports deeper differing directories separately.
11. Compact counts do not recursively double-count files already represented by descendant directory rows.
12. Compact mode retains collapsed one-sided subtree behavior.
13. `-ExpandMissingSubtrees` reports descendant files from one-sided subtrees individually.
14. `-ExpandMissingSubtrees` reports empty descendant directories explicitly.
15. `-ExpandMissingSubtrees` does not redundantly emit non-empty ancestor directory rows in addition to their expanded contents.
16. Summary counts reflect actual represented files/directories rather than merely displayed rows.
17. A SAME verdict is qualified whenever directory structure differs or file differences consist only of ignored metadata.
18. `-Compact` and `-ExpandMissingSubtrees` cannot be combined.
19. Recursive presentation switches are not accepted without `-Recurse`.
20. No recursive mode should make an observed filesystem object appear to have been silently skipped.
