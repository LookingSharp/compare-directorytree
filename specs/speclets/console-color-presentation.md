# Console Color Presentation Speclet

Status: Relatively locked; intended for later merge into the main directory-comparison specification
Version: 0.1

## 1. Purpose

Use console color as a secondary visual cue that improves scanability without carrying information that is unavailable in plain-text output.

The existing textual report model remains authoritative:

```text
<<  Exists only on LEFT
>>  Exists only on RIGHT
<>  Exists on both sides but differs
```

The report must remain fully understandable when color is unavailable, disabled, redirected, copied as plain text, or viewed by a user who cannot distinguish the selected colors.

## 2. Design Principle

Color usage should be sparse.

Do not color entire rows, filenames, directory names, byte counts, headings, or ordinary explanatory text merely because a row represents a difference.

The primary use of color is a narrow visual classification gutter formed by the existing two-character difference markers.

This keeps the user's attention on filenames, paths, sizes, and counts rather than on large areas of saturated color.

## 3. Directional Marker Colors

In interactive color output:

```text
<<  cyan
>>  magenta
<>  yellow
```

Only the two-character marker is colored.

Example:

```text
<<  IMG_1901.JPG                       5,238,104        <missing>
>>  IMG_1842-edited.jpg                <missing>        4,790,441
<>  IMG_1842.JPG                       4,821,334        4,817,902
```

In the rendered console, only `<<`, `>>`, and `<>` receive their directional colors.

The same treatment applies to files and directory-summary rows:

```text
<<  [DIR] 2018\Camp\Raw\   214 files, 18 dirs, 7.8 GB
```

`[DIR]` and the path remain in the normal foreground color.

## 4. Semantic Colors

A small number of additional semantic states may use color.

### Ignored metadata

The `Ignored: ...` annotation is displayed in a dim/gray treatment when supported.

Example:

```text
<>  .DS_Store   6,148   8,196   Ignored: macOS Finder metadata
```

Only the ignored-metadata annotation is dimmed. The filename and values remain normal.

A metadata difference still retains its directional marker color. This communicates both facts independently:

- the row is a difference of a particular class,
- the difference is ignorable under policy.

### Final verdict

Only the verdict phrase receives verdict color:

```text
RESULT: SAME - all 243 files match
        ^^^^
        green
```

```text
RESULT: NOT THE SAME - 4 relevant file differences
        ^^^^^^^^^^^^
        red
```

`RESULT:` and all qualification/count text remain in the normal foreground color.

Green is reserved for `SAME`.

Red is reserved for `NOT THE SAME` and should not be used for ordinary LEFT-, RIGHT-, or different-file rows.

This prevents the report body from visually presenting every difference as an error.

## 5. Structural Qualifiers

Empty-directory differences and other qualified-SAME structural conditions do not receive a separate color.

Their existing `<<` or `>>` marker provides the directional cue, and the row text explains the condition.

Example:

```text
<<  [DIR] 2018\Camp\Empty\   0 files, 0 dirs, 0 B
```

If the final verdict is qualified:

```text
RESULT: SAME - qualified: different empty subdirectories
```

Only `SAME` is green.

The qualifier remains neutral text.

## 6. No Color Dependency

No meaning may depend solely on color.

Specifically:

- LEFT-only remains identified by `<<`.
- RIGHT-only remains identified by `>>`.
- different remains identified by `<>`.
- ignored metadata remains explicitly labeled `Ignored:`.
- SAME/NOT THE SAME remains written in text.
- structural qualifications remain written in text.

The color treatment is supplemental only.

## 7. Interactive Versus Plain-Text Output

Color should be emitted only when the output destination can reasonably display interactive terminal color.

Plain-text or redirected output must not contain raw ANSI escape sequences.

The implementation should provide a `-NoColor` option that suppresses color even in an interactive terminal.

Example:

```powershell
.\Compare-Files.ps1 <path1> <path2> -NoColor
```

The output produced with `-NoColor` must be semantically identical to the colored output.

The implementation may use the host/platform's normal mechanism for detecting whether color is appropriate; the specification does not mandate a particular detection technique.

## 8. Color Key / Legend

The normal product report should not include a separate color legend.

The existing textual difference legend remains sufficient:

```text
Legend:
  <<  Exists only on LEFT
  >>  Exists only on RIGHT
  <>  Same filename, different size
```

A separate explanation of cyan/magenta/yellow would add visual and textual clutter without adding semantic information.

Help/documentation may describe the color treatment.

## 9. One-Line Output Compatibility

This color design follows the recursive speclet's preference that comparison entries remain on one physical output line.

Color must not introduce:

- continuation lines,
- standalone color labels,
- extra explanatory rows,
- or layout changes between colored and non-colored output.

Apart from invisible terminal styling, colored and non-colored reports should have the same text and layout.

## 10. Accessibility and Terminal Variance

Exact rendered hue and intensity may vary across terminal themes and hosts.

The design therefore relies on:

- category separation rather than exact hue perception,
- persistent textual markers,
- sparse use of color,
- and neutral report content.

The implementation should use conventional terminal colors rather than attempting precise RGB branding.

Bright or normal cyan/magenta/yellow may be selected based on terminal readability, but the implementation should avoid background colors and avoid highly saturated full-row foreground treatments.

This is a presentation detail rather than a semantic contract.

## 11. Acceptance Cases

The implementation must demonstrate at least these behaviors:

1. In an interactive colored console, `<<` is cyan, `>>` is magenta, and `<>` is yellow.
2. Only the marker is directionally colored; filenames, paths, `[DIR]`, sizes, and ordinary notes remain neutral.
3. `Ignored: ...` annotations are dim/gray when color is enabled.
4. Ignored metadata rows retain the normal directional marker color.
5. Only `SAME` is green in a SAME verdict.
6. Only `NOT THE SAME` is red in a NOT THE SAME verdict.
7. Ordinary relevant difference rows are not red.
8. Empty-directory/structural differences do not receive an additional special color.
9. `-NoColor` removes all color without changing report text, ordering, spacing, or semantics.
10. Redirected/plain-text output contains no terminal color escape sequences.
11. The report remains fully understandable without color.
12. Color does not cause a comparison entry to span additional physical lines.
13. The normal report does not add a separate color legend.
