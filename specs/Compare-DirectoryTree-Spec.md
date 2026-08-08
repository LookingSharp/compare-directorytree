# Directory File Comparison Specification

Status: Working draft
Version: 0.3

## 1. Purpose

Build a PowerShell utility that compares the files contained in two directories and produces a human-readable, self-describing report.

The report must show:

- files present only on the first/LEFT side,
- files present only on the second/RIGHT side,
- same-named files whose exact byte sizes differ,
- recognized metadata differences and whether they count toward the result,
- when recursive comparison is requested, directory-structure differences including empty directories,
- and whether the directories are considered the same under the selected comparison rules.

The utility is a comparison/reporting tool only. It must not modify either directory.

The comparison is preservation-oriented:

- relevant file differences determine whether substantive contents differ,
- directory-only differences remain visible,
- ignorable metadata remains visible,
- and an otherwise-MATCH verdict is qualified when structure or ignorable metadata differs.

## 2. Inputs and Scope

The command accepts two directory paths.

- The first supplied path is displayed as LEFT.
- The second supplied path is displayed as RIGHT.
- The parameter interface should remain neutral; LEFT/RIGHT is a report convention, not part of the parameter naming.
- By default, only files directly contained in each directory are compared, and subdirectories are not searched or compared.
- Hidden and system files are included.
- Directories themselves are outside the comparison unless `-Recurse` is specified.

Optional behavior:

`-ExplainMetadata`

When specified, the report appends a more detailed explanation for each recognized metadata type that appears among the reported differences. Each metadata type is explained once, regardless of how many files match that type.

`-Recurse`

Compare all descendant files beneath both supplied root directories, and observe directory structure so that missing or empty directories are not silently omitted. See Section 6.

`-Compact`

Recursive presentation mode that summarizes differences by directory. Requires `-Recurse`. See Section 6.2.

`-ExpandMissingSubtrees`

Recursive presentation mode that reports one-sided subtrees file by file. Requires `-Recurse`. See Section 6.3.

`-Compact` and `-ExpandMissingSubtrees` are alternative recursive presentation modes and must not be combined. Neither is accepted without `-Recurse`.

`-NoColor`

Suppresses console color even in an interactive terminal. See Section 7.

## 3. Definition of Same

Files are matched by filename, case-insensitively. Under `-Recurse`, files are matched by their root-relative path, with each path segment compared case-insensitively.

Two matched files are considered the same when their exact file sizes in bytes are equal.

The comparison does not establish byte-for-byte identity. It does not compare:

- file contents or hashes,
- timestamps,
- file attributes,
- permissions or ACLs,
- alternate data streams,
- extended attributes,
- embedded media metadata.

The report must describe these rules up front so saved output is understandable without reading the script.

## 4. Metadata Policy

Metadata recognition and ignore policy are separate concepts.

A file difference may be:

1. Ordinary/relevant.
2. Recognized metadata that remains relevant.
3. Recognized metadata that is safe to ignore for this comparison.

Ignored metadata is never hidden from the report. It remains visible and counted as a detected difference, but it does not count as a relevant difference and does not cause the overall comparison to fail. It does qualify an otherwise-MATCH verdict.

A file is not ignored merely because it:

- is hidden,
- has the System attribute,
- starts with `.`,
- is small,
- appears temporary,
- or has a metadata-oriented extension.

Only explicit catalog rules may classify a difference as ignored.

Recognized metadata classified as relevant continues to count as a relevant difference, including inside recursive subtrees.

The initial metadata catalog is defined in Appendix A.

## 5. Difference and Report Model

Difference classes:

```text
<<  Exists only on LEFT
>>  Exists only on RIGHT
<>  Same filename exists on both sides, but exact byte sizes differ
```

Display order is always:

```text
<<
>>
<>
```

This order intentionally follows a left-to-right reading model.

Within each class, entries are sorted deterministically by path.

A blank line separates non-empty difference classes.

Directory summary rows use the same markers and identify themselves with `DIR` in the `Type` column:

```text
<<  DIR   ...
>>  DIR   ...
<>  DIR   ...
```

Directory-summary rows and file rows begin their path in the same column. The narrow `Type` column carries the distinction so that the pathname itself is never shifted, which preserves vertical scanning. Ordinary file rows leave the `Type` column blank; `FILE` is never written.

### 5.1 One-line comparison entries

Every comparison entry occupies one physical output line. This applies to:

- file difference rows,
- `DIR` subtree summaries,
- empty-directory rows,
- metadata annotations associated with those rows,
- and the final verdict line.

Do not emit continuation lines beneath a comparison row merely to explain counts or metadata.

Correct:

```text
<<  DIR   2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB | ignored metadata 2
```

Not:

```text
<<  DIR   2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB
                              2 ignored metadata files
```

The fixed explanatory header block at the top of the report (`Scope`, `Match`, `Same`, `Ignore`, `Note`) is not a comparison entry and may occupy multiple lines.

### 5.2 Canonical format

```text
FILE COMPARISON
===============

LEFT : \\192.168.6.90\_root\LargeFiles\Pictures\2010 - 2019\2018\2018_05_25 UPC Family Camp at Lake Retreat
RIGHT: C:\Users\dgray\OneDrive\Shared\2018_05_25 UPC Family Camp at Lake Retreat

Scope : Files in these directories only; subdirectories are NOT searched.
        Hidden and system files ARE included.
Match : Filenames are compared case-insensitively.
Same  : Matching filename and exact size in bytes.
Ignore: Known disposable metadata/cache files are reported but do not
        affect the final comparison result.
Note  : Contents, hashes, timestamps, attributes, and other metadata are
        NOT compared.

SUMMARY
-------
LEFT files:                   243
RIGHT files:                  241
Same:                         237
Different size:                 2
LEFT only:                      3
RIGHT only:                     1

Total differences:              6
Ignored metadata differences:   2
Relevant differences:           4

DIFFERENCES
-----------

    Type  File / Directory                      LEFT size (bytes)   RIGHT size (bytes)   Note
    ----  ----------------                      -----------------   ------------------   ----
<<        IMG_1901.JPG                                  5,238,104            <missing>
<<        IMG_1902.JPG                                  4,921,772            <missing>
<<        Thumbs.db                                        81,920            <missing>   Ignored: Windows thumbnail cache

>>        IMG_1842-edited.jpg                           <missing>            4,790,441

<>        IMG_1842.JPG                                  4,821,334            4,817,902
<>        .DS_Store                                         6,148                8,196   Ignored: macOS Finder metadata

Legend:
  <<  Exists only on LEFT
  >>  Exists only on RIGHT
  <>  Same filename, different size

RESULT: DIFFERENT - 4 relevant differences | 2 ignored metadata differences
```

When `-Recurse` is specified, the `Scope` line must describe the recursive scope and the active presentation mode instead of stating that subdirectories are not searched.

Report requirements:

- Use plain ASCII text.
- Use thousands separators for byte sizes.
- Use `<missing>` when a file is absent from one side.
- Do not truncate filenames or paths to preserve column alignment.
- Matching files are summarized by count and are not individually listed by default.
- Empty difference classes do not need placeholder rows.
- Metadata annotations appear in a final `Note` column.
- Directory-summary rows write `DIR` in the `Type` column; ordinary file rows leave it blank.
- Directory-summary rows use their own free-form summary text in place of the `LEFT size`/`RIGHT size` columns; only file rows populate those columns.
- The report must distinguish detected differences from differences that affect the final result.

## 6. Recursive Comparison

When `-Recurse` is specified, compare all descendant files beneath both supplied root directories. Directory structure is also observed so that missing or empty directories are not silently omitted from the report.

Recursive entries are reported relative to the supplied roots:

```text
2018\Camp\IMG_1842.JPG
```

The first root remains LEFT and the second root remains RIGHT.

`-Recurse` supports three mutually exclusive presentation modes.

### 6.1 Default recursive mode

No additional presentation switch.

- Directories present on both sides are traversed and their file differences are reported normally, individually, using root-relative paths.
- A directory subtree present on only one side is collapsed at the highest missing directory into one `DIR` summary row.
- Descendants of that collapsed missing subtree are not redundantly listed.
- Empty missing directories are still reported.

### 6.2 `-Compact`

Summarize differences by directory instead of listing individual differing files within shared directories.

- A shared directory with direct file differences produces one `DIR` summary row.
- The summary counts files directly in that directory; descendant directories with differences receive their own rows.
- This preserves the location of differences rather than allowing a high-level directory to swallow all descendant detail.
- Fully one-sided subtrees remain collapsed at the highest missing directory, as in the default mode, using the Section 6.4 collapsed-summary grammar rather than the direct-file grammar below.
- Empty-directory differences remain explicit.

Shared-directory grammar:

```text
<>  DIR   <relative-path>\   <same> same | << <left-only> | >> <right-only> | <> <different-size> | ignored <count>
```

Example:

```text
<>  DIR   2018\Camp\Cache\   34 same | << 6 | >> 0 | <> 2 | ignored 1
```

Omit `| ignored <count>` when the count is zero.

The counts apply to files directly contained in that directory, not recursively to descendant shared directories. This prevents double-counting and preserves useful location information.

A Compact `DIR` row is shown only when that directory has:

- direct file differences,
- a directory-structure difference that must be surfaced,
- or a metadata-only difference that must remain visible.

A directory containing only matching direct files and whose descendant differences are reported elsewhere does not need its own row.

### 6.3 `-ExpandMissingSubtrees`

Use normal file-level reporting even inside directories that exist on only one side.

- A one-sided subtree is traversed instead of represented by one collapsed summary row.
- Descendant files are reported individually with their root-relative paths.
- Empty descendant directories are reported explicitly as `DIR` rows, because they otherwise have no visible descendant entry.
- Non-empty container directories are not redundantly listed when their contents make their existence evident; do not emit summary `DIR` rows for non-empty ancestor directories merely to restate that the subtree is missing.
- Metadata annotations use the normal file-note policy.
- Shared directories behave as in the default recursive mode.

Example:

```text
<<        2018\Camp\Raw\IMG_1001.JPG             5,238,104        <missing>
<<        2018\Camp\Raw\Nested\IMG_1002.JPG      4,921,772        <missing>
<<  DIR   2018\Camp\Raw\Empty\             0 files, 0 dirs, 0 B
```

This mode is intentionally verbose and is intended for cases where the user wants the full inventory of a missing subtree.

### 6.4 Missing subtree collapse

In the default and Compact modes, if an entire directory subtree exists only on one side, report the highest missing subtree once and do not additionally list its descendants.

```text
<<  DIR   2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB | ignored metadata 2
```

The one-line subtree summary must account for all descendants so the user can see that the entire subtree was considered.

A collapsed missing-subtree summary includes:

- descendant file count,
- descendant directory count,
- total descendant file bytes,
- ignored-metadata count when nonzero.

Counts are recursive for collapsed one-sided subtrees.

### 6.5 Empty directories

Empty directories are observable and must be reported in all recursive modes.

```text
<<  DIR   2018\Camp\Empty\   0 files, 0 dirs, 0 B
```

This prevents an empty-directory difference from appearing to have been overlooked.

An empty-directory-only difference does not create a relevant file difference, but it qualifies the final verdict.

Nested empty directories follow the selected presentation mode:

- Default and Compact may summarize a wholly one-sided nested subtree at its highest missing directory.
- `-ExpandMissingSubtrees` exposes the empty leaf directories that would otherwise have no visible file entry.

### 6.6 Metadata-only subtrees

A subtree whose only file differences are explicitly ignorable metadata is still visible.

Collapsed:

```text
<<  DIR   2018\Camp\Cache\   1 file, 0 dirs, 81,920 B | ignored metadata 1
```

Compact shared directory:

```text
<>  DIR   2018\Camp\Cache\   34 same | << 1 | >> 0 | <> 0 | ignored 1
```

Expanded:

```text
<<        2018\Camp\Cache\Thumbs.db   81,920   <missing>   Ignored: Windows thumbnail cache
```

If every difference in the relevant subtree is ignorable metadata, it does not create a relevant difference, but the final verdict is qualified.

### 6.7 Counting semantics

Collapsed directory rows are presentation summaries, not single logical file differences.

Summary counts must reflect the actual objects represented by the report, not merely the number of displayed rows. A collapsed subtree containing 214 relevant files represents 214 relevant differences even though it occupies one displayed row. Compact summaries likewise preserve the underlying difference counts.

The recursive report must retain enough information to distinguish:

- relevant file differences,
- ignored metadata differences,
- empty/directory-structure-only differences,
- collapsed subtree rows,
- and displayed output rows.

No recursive mode may make an observed filesystem object appear to have been silently skipped.

## 7. Console Color Presentation

### 7.1 Purpose and principle

Console color is a secondary visual cue that improves scanability without carrying information that is unavailable in plain-text output. The textual report model of Section 5 remains authoritative.

Color usage is sparse. Do not color entire rows, filenames, directory names, byte counts, headings, or ordinary explanatory text merely because a row represents a difference. The primary use of color is a narrow visual classification gutter formed by the existing two-character difference markers, which keeps the user's attention on filenames, paths, sizes, and counts rather than on large areas of saturated color.

### 7.2 Directional marker colors

In interactive color output:

```text
<<  cyan
>>  magenta
<>  yellow
```

Only the two-character marker is colored, on both file rows and directory-summary rows. The `Type` column, paths, sizes, and notes remain in the normal foreground color.

### 7.3 Semantic colors

The `Ignored: ...` annotation is displayed in a dim/gray treatment when supported. Only the annotation is dimmed; the filename and values remain normal. A metadata difference still retains its directional marker color, communicating both facts independently: the row is a difference of a particular class, and the difference is ignorable under policy.

Only the verdict phrase receives verdict color:

```text
RESULT: MATCH - all 243 files match
        ^^^^^
        green
```

```text
RESULT: DIFFERENT - 4 relevant differences
        ^^^^^^^^^
        red
```

`RESULT:` and all qualification/count text remain in the normal foreground color.

Green is reserved for `MATCH`. Red is reserved for `DIFFERENT` and must not be used for ordinary LEFT-, RIGHT-, or different-file rows. This prevents the report body from visually presenting every difference as an error.

Empty-directory differences and other qualified-MATCH structural conditions do not receive a separate color; their existing `<<` or `>>` marker provides the directional cue and the row text explains the condition.

### 7.4 No color dependency

No meaning may depend solely on color:

- LEFT-only remains identified by `<<`.
- RIGHT-only remains identified by `>>`.
- Different remains identified by `<>`.
- Ignored metadata remains explicitly labeled `Ignored:`.
- MATCH/DIFFERENT remains written in text.
- Structural qualifications remain written in text.

The report must remain fully understandable when color is unavailable, disabled, redirected, copied as plain text, or viewed by a user who cannot distinguish the selected colors.

### 7.5 Interactive versus plain-text output

Color is emitted only when the output destination can reasonably display interactive terminal color. Plain-text or redirected output must not contain raw ANSI escape sequences.

`-NoColor` suppresses color even in an interactive terminal:

```powershell
.\Compare-DirectoryTree.ps1 <path1> <path2> -NoColor
```

Output produced with `-NoColor` must be semantically identical to the colored output. Apart from invisible terminal styling, colored and non-colored reports have the same text, ordering, spacing, and layout.

The implementation may use the host/platform's normal mechanism for detecting whether color is appropriate; this specification does not mandate a particular detection technique.

### 7.6 Legend and accessibility

The normal product report does not include a separate color legend. The existing textual difference legend remains sufficient, and a separate explanation of cyan/magenta/yellow would add clutter without adding semantic information. Help/documentation may describe the color treatment.

Exact rendered hue and intensity may vary across terminal themes and hosts. The design therefore relies on category separation rather than exact hue perception, persistent textual markers, sparse use of color, and neutral report content. The implementation should use conventional terminal colors rather than precise RGB branding; bright or normal cyan/magenta/yellow may be selected based on terminal readability, but background colors and highly saturated full-row foreground treatments should be avoided. This is a presentation detail rather than a semantic contract.

Color must not introduce continuation lines, standalone color labels, extra explanatory rows, or layout changes between colored and non-colored output.

## 8. Summary and Result Semantics

Summary counts:

`LEFT files`
: All files in scope on the LEFT, including hidden, system, and metadata files.

`RIGHT files`
: All files in scope on the RIGHT, including hidden, system, and metadata files.

`Same`
: Matched files with equal exact byte sizes.

`Different size`
: Matched files with unequal byte sizes.

`LEFT only`
: Files present only on LEFT.

`RIGHT only`
: Files present only on RIGHT.

`Total differences`
: `Different size + LEFT only + RIGHT only`.

`Ignored metadata differences`
: Difference rows classified by policy as ignored metadata.

`Relevant differences`
: `Total differences - Ignored metadata differences`.

Under `-Recurse`, the counts above are file counts across the whole compared tree, and the summary additionally reports directory-structure differences, including empty-directory differences, separately from file differences. Directory-structure differences never contribute to `Relevant differences`.

The overall result is based on `Relevant differences`. Structural and ignorable differences do not change the verdict but qualify it.

Verdict lines are single lines.

The verdict vocabulary is `MATCH` and `DIFFERENT`. These tokens share no substring, so an exact search for `RESULT: MATCH` cannot also match a `RESULT: DIFFERENT` verdict. `MATCH` means the directories match under the comparison rules declared in the report header; it does not imply byte-for-byte content identity.

The per-file `Same` summary counter, the `Same  :` header rule line, the Section 3 definition of same, and the `-Compact` `<same> same` counts describe per-file equality rather than the overall verdict, and retain that wording.

### Result: relevant differences exist

```text
RESULT: DIFFERENT - 4 relevant differences | 2 ignored metadata differences
```

Under `-Recurse`, structural counts are included when nonzero:

```text
RESULT: DIFFERENT - 4 relevant differences | 2 empty-subdirectory differences | 3 ignored metadata differences
```

### Result: only ignored metadata differs

```text
RESULT: MATCH - qualified: differences limited to 2 ignored metadata files
```

### Result: only directory structure differs

```text
RESULT: MATCH - qualified: different empty subdirectories
```

### Result: structure and ignorable metadata differ

```text
RESULT: MATCH - qualified: different empty subdirectories; other differences limited to ignorable metadata
```

### Result: no differences

```text
RESULT: MATCH - all 243 files match
```

The report must not use the unqualified word `identical`, because file contents are not compared.

## 9. Errors and Ambiguous Cases

The tool must not emit a normal comparison result when the comparison cannot be completed reliably.

### Invalid or inaccessible input

Fail clearly if either supplied path:

- does not exist,
- is not a directory,
- or cannot be fully enumerated, including any in-scope subdirectory under `-Recurse`.

Do not present a partial directory comparison as a valid result.

### Invalid switch combinations

Fail clearly if:

- `-Compact` and `-ExpandMissingSubtrees` are both specified,
- or either recursive presentation switch is specified without `-Recurse`.

### Case-insensitive filename collisions

A source may contain filenames that are distinct on a case-sensitive filesystem but collide under this tool's case-insensitive comparison model.

Example:

```text
IMG_1001.JPG
img_1001.jpg
```

If such a collision exists within either directory, the comparison is ambiguous and must fail clearly rather than selecting an arbitrary match. Under `-Recurse`, the same rule applies to colliding directory names within a directory.

### Files changing during comparison

The tool does not promise filesystem snapshot semantics. The compared directories are expected to be reasonably stable during the operation.

If the implementation detects an error that prevents a reliable comparison, it should fail rather than silently continue with partial information.

## 10. Acceptance Scenarios

These scenarios define expected behavior rather than implementation technique.

### 10.1 Same ordinary files

LEFT and RIGHT each contain:

```text
IMG_1001.JPG   5,000 bytes
IMG_1002.JPG   6,000 bytes
```

Expected:

- Same = 2
- Total differences = 0
- Relevant differences = 0
- Result = MATCH

### 10.2 File only on LEFT

LEFT contains `IMG_1003.JPG`; RIGHT does not.

Expected:

```text
<<        IMG_1003.JPG   <LEFT size>   <missing>
```

The difference is relevant unless an explicit metadata rule says otherwise.

### 10.3 File only on RIGHT

RIGHT contains `IMG_1004.JPG`; LEFT does not.

Expected:

```text
>>        IMG_1004.JPG   <missing>   <RIGHT size>
```

The difference is relevant unless an explicit metadata rule says otherwise.

### 10.4 Same filename, different size

LEFT:

```text
IMG_1005.JPG   5,238,104 bytes
```

RIGHT:

```text
IMG_1005.JPG   5,238,105 bytes
```

Expected:

```text
<>        IMG_1005.JPG   5,238,104   5,238,105
```

This is one relevant difference.

### 10.5 Ignored metadata only

LEFT contains an extra `Thumbs.db`.

Expected:

- `Thumbs.db` appears as a `<<` row.
- The row is annotated as ignored metadata.
- Total differences increases by one.
- Ignored metadata differences increases by one.
- Relevant differences remains zero.
- Overall result = MATCH, qualified.

### 10.6 Recognized metadata that remains relevant

RIGHT contains an extra `IMG_1006.xmp`.

Expected:

- The file is recognized as an XMP sidecar.
- It is not ignored.
- The row remains a relevant difference.
- Overall result = DIFFERENT.

### 10.7 Hidden or system ordinary file

A hidden or system file that does not match an explicit ignore rule differs between LEFT and RIGHT.

Expected:

- It is included in the comparison.
- It is reported normally.
- It counts as a relevant difference.

### 10.8 Both directories empty

Expected:

- LEFT files = 0
- RIGHT files = 0
- Total differences = 0
- Relevant differences = 0
- Result = MATCH

### 10.9 One directory empty

Every file on the non-empty side appears in the corresponding `<<` or `>>` class.

Normal metadata policy still applies.

### 10.10 Case-insensitive collision

One directory contains both:

```text
IMG_1001.JPG
img_1001.jpg
```

Expected:

- No normal comparison result.
- A clear ambiguity/error is reported.

### 10.11 Enumeration failure

Enumeration of either directory fails or is incomplete.

Expected:

- No normal comparison result.
- A clear error identifies the affected input.

### 10.12 Verbose metadata explanation

Differences include three `Thumbs.db` files and two `.DS_Store` files, and `-ExplainMetadata` is specified.

Expected:

- Normal rows remain unchanged.
- The appended metadata section explains the Windows thumbnail-cache type once.
- It explains the macOS Finder-metadata type once.
- Unencountered catalog entries are not described.

### 10.13 Recursive comparison

The recursive implementation must demonstrate at least these behaviors:

1. A fully missing nested subtree is collapsed at its highest missing directory in Default mode.
2. Descendants of a collapsed missing subtree are not redundantly listed.
3. A collapsed subtree summary is entirely one line.
4. Ignored-metadata counts on `DIR` rows are on the same line as the subtree summary.
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
17. A MATCH verdict is qualified whenever directory structure differs or file differences consist only of ignored metadata.
18. `-Compact` and `-ExpandMissingSubtrees` cannot be combined.
19. Recursive presentation switches are not accepted without `-Recurse`.
20. No recursive mode makes an observed filesystem object appear to have been silently skipped.

### 10.14 Console color

The color implementation must demonstrate at least these behaviors:

1. In an interactive colored console, `<<` is cyan, `>>` is magenta, and `<>` is yellow.
2. Only the marker is directionally colored; filenames, paths, the `Type` column, sizes, and ordinary notes remain neutral.
3. `Ignored: ...` annotations are dim/gray when color is enabled.
4. Ignored metadata rows retain the normal directional marker color.
5. Only `MATCH` is green in a MATCH verdict.
6. Only `DIFFERENT` is red in a DIFFERENT verdict.
7. Ordinary relevant difference rows are not red.
8. Empty-directory/structural differences do not receive an additional special color.
9. `-NoColor` removes all color without changing report text, ordering, spacing, or semantics.
10. Redirected/plain-text output contains no terminal color escape sequences.
11. The report remains fully understandable without color.
12. Color does not cause a comparison entry to span additional physical lines.
13. The normal report does not add a separate color legend.

### 10.15 Verdict vocabulary and Type column

The report implementation must demonstrate at least these behaviors:

1. A positive verdict reads `RESULT: MATCH`; a negative verdict reads `RESULT: DIFFERENT`.
2. An exact search for `RESULT: MATCH` does not match a `RESULT: DIFFERENT` verdict.
3. Qualified positive verdicts read `RESULT: MATCH - qualified: ...`.
4. The `Same` summary counter, the `Same  :` header rule line, and the `-Compact` `<same> same` counts retain the per-file "same" wording.
5. The differences table header includes `Type` and `File / Directory`.
6. Directory-summary rows show `DIR` in the `Type` column.
7. File rows leave the `Type` column blank and never show `FILE`.
8. Directory paths and file paths begin in the same column.
9. Introducing the `Type` column does not cause any comparison entry to span more than one physical line.

## 11. Out of Scope

The utility does not:

- hash or byte-compare file contents,
- compare timestamps or filesystem attributes,
- compare permissions or ACLs,
- compare alternate data streams or extended attributes,
- inspect embedded EXIF/IPTC/XMP data,
- determine whether two entries refer to the same hard-link target,
- establish semantic equivalence of symbolic/reparse-point targets,
- perform Unicode normalization beyond the filename comparison behavior selected by the implementation,
- provide filesystem snapshot or transactional consistency,
- modify, copy, delete, or synchronize files,
- automatically ignore unknown metadata-like files.

These are deliberately excluded unless a later requirement makes them necessary.

## 12. Future Extensions

The design should not preclude later additions such as:

```text
-Hash
-ShowMatches
-NoMetadataIgnore
```

Recursive comparison may later extend the same metadata policy to recognized metadata directories (see Appendix A.3).

The current specification does not require implementing these capabilities.

# Appendix A - Initial Metadata Catalog

The catalog is intentionally conservative. Recognition does not imply ignore.

## A.1 Ignored by default

| ID | Platform | Pattern | Short note | Policy rationale |
| --- | --- | --- | --- | --- |
| WIN-THUMBS | Windows | `Thumbs.db` | Windows thumbnail cache | Generated preview cache; not source content and normally regenerable. |
| WIN-EHTHUMBS | Windows | `ehthumbs.db` | Windows Media Center thumbnail cache | Legacy generated media-preview cache. |
| WIN-DESKTOPINI | Windows | `desktop.ini` | Windows folder presentation metadata | Explorer folder customization rather than substantive directory content. |
| MAC-DSSTORE | macOS | `.DS_Store` | macOS Finder metadata | Finder view/presentation metadata rather than substantive directory content. |
| KDE-DIRECTORY | KDE/Linux | `.directory` | KDE folder presentation metadata | Folder-specific KDE/Dolphin presentation metadata. |

Filename matching for these catalog rules should follow the filename semantics appropriate to the rule. Windows metadata names should be recognized case-insensitively.

## A.2 Recognized but relevant

| ID | Platform/Application | Pattern | Short note | Why it remains relevant |
| --- | --- | --- | --- | --- |
| MAC-APPLEDOUBLE | macOS | `._*` | AppleDouble sidecar | May preserve resource forks, Finder information, extended attributes, or other Mac filesystem metadata. |
| PHOTO-XMP | Photography applications | `*.xmp` | XMP photo sidecar | May contain ratings, keywords, develop settings, edits, or intentionally maintained metadata. |
| PHOTO-AAE | Apple Photos/iOS | `*.aae` | Apple photo-edit sidecar | May represent nondestructive edits associated with a photo. |
| PHOTO-PXD-SIDECAR | Pixelmator Pro | `*.pxd-sidecar` | Pixelmator edit sidecar | May contain layers or nondestructive editing state. |
| PHOTO-PICASA | Picasa | `.picasa.ini`, `Picasa.ini` | Picasa photo metadata | May contain photo-specific metadata such as face/name tagging. |

Examples intentionally not auto-ignored unless later policy explicitly adds them:

```text
*.pp3
*.dop
Folder.jpg
cover.jpg
AlbumArt*.jpg
```

The principle is preservation-first: unknown or potentially user-authored metadata remains relevant.

## A.3 Candidate metadata directories

There are currently no normative directory-level catalog rules. Under `-Recurse`, directories are compared structurally and no directory is ignored.

Potential future catalog entries include:

| Platform | Directory pattern | Likely policy |
| --- | --- | --- |
| macOS | `.Spotlight-V100` | Ignore |
| macOS | `.fseventsd` | Ignore |
| macOS | `.Trashes` | Ignore |
| Synology DSM | `@eaDir` | Ignore |
| QNAP | known generated thumbnail directories | Ignore after exact patterns are verified |
| macOS/archive interchange | `.AppleDouble`, `__MACOSX` | Conditional/relevant; preservation implications require care |

Exact future patterns must be verified before they become normative rules.

# Appendix B - Engineering and Test Invariants

Implementation technique is intentionally not prescribed. The delivered behavior must satisfy these invariants:

1. The first supplied directory always maps to LEFT in the report.
2. The second supplied directory always maps to RIGHT in the report.
3. Hidden and system files are included.
4. Subdirectories are traversed only when `-Recurse` is specified.
5. Filename and path-segment matching is case-insensitive.
6. Same-name/same-size pairs produce no difference row.
7. Same-name/different-size pairs produce exactly one `<>` row.
8. LEFT-only files produce exactly one `<<` row.
9. RIGHT-only files produce exactly one `>>` row.
10. Ignored metadata remains visible in the report.
11. Ignored metadata does not increase Relevant differences.
12. Recognized-but-relevant metadata does increase Relevant differences.
13. Difference classes are ordered `<<`, `>>`, `<>`.
14. Blank lines separate non-empty difference classes.
15. Ordering within each class is deterministic.
16. `<missing>` identifies an absent file size.
17. File sizes are reported in exact bytes with thousands separators.
18. Filenames and root-relative paths are not silently truncated.
19. Failure to fully enumerate either directory produces no normal comparison result.
20. Case-insensitive filename or directory-name collisions produce a clear ambiguity/error rather than guessed matching.
21. `-ExplainMetadata` explains only metadata types encountered among differences.
22. Each encountered metadata type is explained once.
23. Metadata classification behavior is centralized and extensible; adding a catalog rule should not require changing the comparison/report semantics.
24. Metadata classification is deterministic; conflicting classifications must not be silently resolved arbitrarily.
25. Every comparison entry and the verdict occupy exactly one physical output line.
26. Directory-structure differences never increase Relevant differences but do qualify a MATCH verdict.
27. Summary counts reflect represented files and directories rather than displayed rows.
28. `-Compact` and `-ExpandMissingSubtrees` are mutually exclusive and require `-Recurse`.
29. No meaning depends solely on color; `-NoColor` and redirected output are semantically identical to colored output.
30. Redirected or plain-text output contains no terminal color escape sequences.
31. The utility never modifies either input directory.
32. Verdicts use `MATCH` and `DIFFERENT`; no report output contains `NOT THE SAME`, and an exact search for `RESULT: MATCH` cannot match a `RESULT: DIFFERENT` verdict.
33. Directory-summary rows and file rows begin their path in the same column; directory rows show `DIR` in the `Type` column, file rows leave it blank, and `FILE` is never written.
34. No report output contains the `[DIR]` name prefix.
