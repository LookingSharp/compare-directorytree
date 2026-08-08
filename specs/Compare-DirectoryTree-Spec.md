# Directory File Comparison Specification

Status: Working draft
Version: 0.2

## 1. Purpose

Build a PowerShell utility that compares the files directly contained in two directories and produces a human-readable, self-describing report.

The report must show:

- files present only on the first/LEFT side,
- files present only on the second/RIGHT side,
- same-named files whose exact byte sizes differ,
- recognized metadata differences and whether they count toward the result,
- and whether the directories are considered the same under the selected comparison rules.

The utility is a comparison/reporting tool only. It must not modify either directory.

## 2. Inputs and Scope

The command accepts two directory paths.

- The first supplied path is displayed as LEFT.
- The second supplied path is displayed as RIGHT.
- The parameter interface should remain neutral; LEFT/RIGHT is a report convention, not part of the parameter naming.
- Only files directly contained in each directory are compared.
- Subdirectories are not searched or compared.
- Hidden and system files are included.
- Directories themselves are outside the comparison.

Optional behavior:

`-ExplainMetadata`

When specified, the report appends a more detailed explanation for each recognized metadata type that appears among the reported differences. Each metadata type is explained once, regardless of how many files match that type.

## 3. Definition of Same

Files are matched by filename, case-insensitively.

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

Ignored metadata is never hidden from the report. It remains visible and counted as a detected difference, but it does not count as a relevant difference and does not cause the overall comparison to fail.

A file is not ignored merely because it:

- is hidden,
- has the System attribute,
- starts with `.`,
- is small,
- appears temporary,
- or has a metadata-oriented extension.

Only explicit catalog rules may classify a difference as ignored.

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

Within each class, files are sorted deterministically by filename.

A blank line separates non-empty difference classes.

All information for a difference should remain in one logical row.

Canonical format:

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

    File                                  LEFT size (bytes)   RIGHT size (bytes)   Note
    ----                                  -----------------   ------------------   ----
<<  IMG_1901.JPG                                  5,238,104            <missing>
<<  IMG_1902.JPG                                  4,921,772            <missing>
<<  Thumbs.db                                        81,920            <missing>   Ignored: Windows thumbnail cache

>>  IMG_1842-edited.jpg                           <missing>            4,790,441

<>  IMG_1842.JPG                                  4,821,334            4,817,902
<>  .DS_Store                                         6,148                8,196   Ignored: macOS Finder metadata

Legend:
  <<  Exists only on LEFT
  >>  Exists only on RIGHT
  <>  Same filename, different size

RESULT: NOT THE SAME - 4 relevant differences found.
        2 additional metadata differences were ignored.
```

Report requirements:

- Use plain ASCII text.
- Use thousands separators for byte sizes.
- Use `<missing>` when a file is absent from one side.
- Do not truncate filenames to preserve column alignment.
- Matching files are summarized by count and are not individually listed by default.
- Empty difference classes do not need placeholder rows.
- Metadata annotations appear in a final `Note` column.
- The report must distinguish detected differences from differences that affect the final result.

## 6. Summary and Result Semantics

Summary counts:

`LEFT files`
: All files in scope on the LEFT, including hidden, system, and metadata files.

`RIGHT files`
: All files in scope on the RIGHT, including hidden, system, and metadata files.

`Same`
: Matched filenames with equal exact byte sizes.

`Different size`
: Matched filenames with unequal byte sizes.

`LEFT only`
: Filenames present only on LEFT.

`RIGHT only`
: Filenames present only on RIGHT.

`Total differences`
: `Different size + LEFT only + RIGHT only`.

`Ignored metadata differences`
: Difference rows classified by policy as ignored metadata.

`Relevant differences`
: `Total differences - Ignored metadata differences`.

The overall result is based on `Relevant differences`.

### Result: relevant differences exist

```text
RESULT: NOT THE SAME - 4 relevant differences found.
        2 additional metadata differences were ignored.
```

### Result: only ignored metadata differs

```text
RESULT: SAME under these comparison rules.
        2 metadata differences were found and ignored.
```

### Result: no differences

```text
RESULT: SAME under these comparison rules.
        All 243 files match.
```

The report should not use the unqualified word `identical`, because file contents are not compared.

## 7. Errors and Ambiguous Cases

The tool must not emit a normal comparison result when the comparison cannot be completed reliably.

### Invalid or inaccessible input

Fail clearly if either supplied path:

- does not exist,
- is not a directory,
- or cannot be fully enumerated.

Do not present a partial directory comparison as a valid result.

### Case-insensitive filename collisions

A source may contain filenames that are distinct on a case-sensitive filesystem but collide under this tool's case-insensitive comparison model.

Example:

```text
IMG_1001.JPG
img_1001.jpg
```

If such a collision exists within either directory, the comparison is ambiguous and must fail clearly rather than selecting an arbitrary match.

### Files changing during comparison

The tool does not promise filesystem snapshot semantics. The compared directories are expected to be reasonably stable during the operation.

If the implementation detects an error that prevents a reliable comparison, it should fail rather than silently continue with partial information.

## 8. Acceptance Scenarios

These scenarios define expected behavior rather than implementation technique.

### 8.1 Same ordinary files

LEFT and RIGHT each contain:

```text
IMG_1001.JPG   5,000 bytes
IMG_1002.JPG   6,000 bytes
```

Expected:

- Same = 2
- Total differences = 0
- Relevant differences = 0
- Result = SAME

### 8.2 File only on LEFT

LEFT contains `IMG_1003.JPG`; RIGHT does not.

Expected:

```text
<<  IMG_1003.JPG   <LEFT size>   <missing>
```

The difference is relevant unless an explicit metadata rule says otherwise.

### 8.3 File only on RIGHT

RIGHT contains `IMG_1004.JPG`; LEFT does not.

Expected:

```text
>>  IMG_1004.JPG   <missing>   <RIGHT size>
```

The difference is relevant unless an explicit metadata rule says otherwise.

### 8.4 Same filename, different size

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
<>  IMG_1005.JPG   5,238,104   5,238,105
```

This is one relevant difference.

### 8.5 Ignored metadata only

LEFT contains an extra `Thumbs.db`.

Expected:

- `Thumbs.db` appears as a `<<` row.
- The row is annotated as ignored metadata.
- Total differences increases by one.
- Ignored metadata differences increases by one.
- Relevant differences remains zero.
- Overall result = SAME under these comparison rules.

### 8.6 Recognized metadata that remains relevant

RIGHT contains an extra `IMG_1006.xmp`.

Expected:

- The file is recognized as an XMP sidecar.
- It is not ignored.
- The row remains a relevant difference.
- Overall result = NOT THE SAME.

### 8.7 Hidden or system ordinary file

A hidden or system file that does not match an explicit ignore rule differs between LEFT and RIGHT.

Expected:

- It is included in the comparison.
- It is reported normally.
- It counts as a relevant difference.

### 8.8 Both directories empty

Expected:

- LEFT files = 0
- RIGHT files = 0
- Total differences = 0
- Relevant differences = 0
- Result = SAME

### 8.9 One directory empty

Every file on the non-empty side appears in the corresponding `<<` or `>>` class.

Normal metadata policy still applies.

### 8.10 Case-insensitive collision

One directory contains both:

```text
IMG_1001.JPG
img_1001.jpg
```

Expected:

- No normal comparison result.
- A clear ambiguity/error is reported.

### 8.11 Enumeration failure

Enumeration of either directory fails or is incomplete.

Expected:

- No normal comparison result.
- A clear error identifies the affected input.

### 8.12 Verbose metadata explanation

Differences include three `Thumbs.db` files and two `.DS_Store` files, and `-ExplainMetadata` is specified.

Expected:

- Normal rows remain unchanged.
- The appended metadata section explains the Windows thumbnail-cache type once.
- It explains the macOS Finder-metadata type once.
- Unencountered catalog entries are not described.

## 9. Out of Scope for Version 1

Version 1 does not:

- recurse into subdirectories,
- compare directory structure,
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

## 10. Future Extensions

The design should not preclude later additions such as:

```text
-Recurse
-Hash
-ShowMatches
-NoMetadataIgnore
```

Recursive comparison, if added later, may extend the same metadata policy to recognized metadata directories.

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

## A.3 Future recursive-mode metadata directories

These do not affect Version 1 because directories are not compared.

Potential future catalog entries include:

| Platform | Directory pattern | Likely policy |
| --- | --- | --- |
| macOS | `.Spotlight-V100` | Ignore |
| macOS | `.fseventsd` | Ignore |
| macOS | `.Trashes` | Ignore |
| Synology DSM | `@eaDir` | Ignore |
| QNAP | known generated thumbnail directories | Ignore after exact patterns are verified |
| macOS/archive interchange | `.AppleDouble`, `__MACOSX` | Conditional/relevant; preservation implications require care |

Exact future patterns should be verified before they become normative rules.

# Appendix B - Engineering and Test Invariants

Implementation technique is intentionally not prescribed. The delivered behavior must satisfy these invariants:

1. The first supplied directory always maps to LEFT in the report.
2. The second supplied directory always maps to RIGHT in the report.
3. Hidden and system files are included.
4. Subdirectories are never traversed in Version 1.
5. Filename matching is case-insensitive.
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
18. Filenames are not silently truncated.
19. Failure to fully enumerate either directory produces no normal comparison result.
20. Case-insensitive filename collisions produce a clear ambiguity/error rather than guessed matching.
21. `-ExplainMetadata` explains only metadata types encountered among differences.
22. Each encountered metadata type is explained once.
23. Metadata classification behavior is centralized and extensible; adding a catalog rule should not require changing the comparison/report semantics.
24. Metadata classification is deterministic; conflicting classifications must not be silently resolved arbitrarily.
25. The utility never modifies either input directory.
