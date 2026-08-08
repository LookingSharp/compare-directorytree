# Report Verdict Vocabulary and Type Column Speclet

Status: Proposed
Supersedes: parts of `specs/Compare-DirectoryTree-Spec.md` Sections 5, 6, 7, 8,
10, and Appendix B

## 1. Purpose

This speclet defines two presentation changes to the comparison report that
conflict with the current authoritative specification:

1. Replacing the `SAME` / `NOT THE SAME` verdict pair with `MATCH` /
   `DIFFERENT`.
2. Replacing the inline `[DIR]` name prefix with a dedicated narrow `Type`
   column so directory rows and file rows share one path column.

Other report-presentation concerns raised during design work — sparse color,
marker-only coloring, dim ignored-metadata annotations, `-NoColor`, absence of
ANSI sequences in redirected output, one physical line per comparison entry,
and the overall visual hierarchy — are already settled in the authoritative
specification (Sections 5.1, 7, 10.14, Appendix B) and are intentionally not
restated or reopened here.

## 2. Verdict vocabulary

### 2.1 Change

Replace:

```text
RESULT: SAME
RESULT: NOT THE SAME
```

with:

```text
RESULT: MATCH
RESULT: DIFFERENT
```

### 2.2 Rationale

`NOT THE SAME` contains the token `SAME`. A naive exact search, log filter, or
hurried human reader can match or read the negative verdict as the positive
one. `MATCH` and `DIFFERENT` share no substring, so an exact search for
`RESULT: MATCH` cannot also match a `RESULT: DIFFERENT` verdict.

### 2.3 Semantics

`MATCH` means the directories match under the comparison rules declared in the
report header. It does not imply byte-for-byte content identity unless a future
comparison mode explicitly establishes that. This is the same meaning `SAME`
carried; only the wording changes.

Qualified verdicts keep their existing structure:

```text
RESULT: MATCH - all 243 files match
RESULT: MATCH - qualified: differences limited to 2 ignored metadata files
RESULT: MATCH - qualified: different empty subdirectories
RESULT: MATCH - qualified: different empty subdirectories; other differences limited to ignorable metadata
RESULT: DIFFERENT - 4 relevant differences | 2 ignored metadata differences
RESULT: DIFFERENT - 4 relevant differences | 2 empty-subdirectory differences | 3 ignored metadata differences
```

### 2.4 Affected locations

Every verdict occurrence in the authoritative specification is rewritten:
Section 5.2 canonical format, Section 7.3 verdict colors, Section 7.4 no-color
dependency, Section 8 result-semantics examples, Section 10.6, Section 10.13
item 17, Section 10.14 items 5 and 6, and Appendix B invariant 26.

### 2.5 What is deliberately not renamed

The word "same" also appears in the specification where it describes per-file
equality rather than the overall verdict. Those uses are unchanged:

- Section 3, `Definition of Same`.
- The report header `Same  :` rule line.
- The `Same` summary counter and its Section 8 definition.
- The `-Compact` per-directory `<same> same` count.

Only the final `RESULT:` verdict token changes. A merge must not perform a
blind textual replacement of `SAME`.

### 2.6 Color impact

Section 7.3 of the authoritative specification is updated by substitution
only: green is reserved for `MATCH`, red is reserved for `DIFFERENT`. Red must
still not be used for ordinary `<<`, `>>`, or `<>` rows. `RESULT:` and all
qualification and count text remain in the normal foreground color.

## 3. Type column

### 3.1 Change

Remove the inline `[DIR]` prefix from directory-summary rows. Introduce a
narrow `Type` column between the difference marker and the path column.

- Directory-summary rows write `DIR` in the `Type` column.
- Ordinary file rows leave the `Type` column blank.
- `FILE` is never written; a blank cell is less noisy and equally
  unambiguous.

### 3.2 Rationale

An inline `[DIR]` prefix shifts the pathname horizontally, so directory paths
and file paths no longer begin in the same column. That defeats fast vertical
scanning of the report, which is the primary reading mode. A dedicated column
carries the same information without moving the path.

### 3.3 Column header

The differences table header changes from `File` to `File / Directory`, and
gains the `Type` column:

```text
    Type  File / Directory                         LEFT size (bytes)   RIGHT size (bytes)   Note
    ----  ----------------                         -----------------   ------------------   ----
<<        IMG_1901.JPG                                   5,238,104            <missing>
<<  DIR   2018\Camp\Raw\                   214 files, 18 dirs, 7.8 GB | ignored metadata 2
<<  DIR   2018\Camp\Empty\                   0 files, 0 dirs, 0 B

>>        IMG_1842-edited.jpg                            <missing>            4,790,441

<>        IMG_1842.JPG                                   4,821,334            4,817,902
<>        .DS_Store                                          6,148                8,196   Ignored: macOS Finder metadata
```

Directory-summary rows continue to use their own free-form summary text rather
than the LEFT/RIGHT size columns, as they do today.

### 3.4 Affected grammar

Every occurrence of the `[DIR]` prefix in the authoritative specification is
rewritten to use the `Type` column. This affects:

- Section 5 difference-class directory rows,
- Section 5.1 one-line entry examples,
- Section 5.2 canonical format and its table header,
- Section 6.1 default-recursive-mode collapsed summary row,
- Section 6.2 `-Compact` shared-directory grammar and row-visibility rules,
- Section 6.3 `-ExpandMissingSubtrees` empty-descendant and ancestor rules,
- Section 6.4 missing-subtree collapse example,
- Section 6.5 empty-directory rows,
- Section 6.6 metadata-only subtree rows,
- Section 7.2, which exempts `[DIR]` from directional color,
- Section 10.13 item 4 and Section 10.14 item 2.

Appendix B does not currently reference `[DIR]`, so no invariant there needs a
`Type`-column rewrite.

The `-Compact` shared-directory grammar becomes:

```text
<>  DIR   <relative-path>\   <same> same | << <left-only> | >> <right-only> | <> <different-size> | ignored <count>
```

The color rule in Section 7.2 that exempts `[DIR]` from directional color
applies unchanged to the `Type` column: only the two-character marker is
colored.

## 4. Non-goals

- No change to difference-class markers, ordering, sorting, or blank-line
  separation.
- No change to the one-line comparison-entry rule.
- No change to color selection, `-NoColor`, or plain-text guarantees beyond
  the `MATCH` / `DIFFERENT` substitution in Section 2.4.
- No change to comparison semantics, metadata policy, or counting.

## 5. Acceptance requirements

1. No report output contains `NOT THE SAME`.
2. An exact search for `RESULT: MATCH` does not match a `RESULT: DIFFERENT`
   verdict.
3. Qualified positive verdicts read `RESULT: MATCH - qualified: ...`.
4. `MATCH` and `DIFFERENT` are unambiguous with color disabled.
5. Green is applied only to `MATCH`; red only to `DIFFERENT`.
6. No report output contains the `[DIR]` prefix.
7. Directory-summary rows and file rows begin their path in the same column.
8. Directory-summary rows show `DIR` in the `Type` column.
9. File rows leave the `Type` column blank and never show `FILE`.
10. The differences table header includes `Type` and `File / Directory`.
11. Introducing the `Type` column does not cause any comparison entry to span
    more than one physical line.
12. The `Same` summary counter, the `Same  :` header rule line, and the
    `-Compact` `<same> same` counts are unchanged by the verdict rename.

## 6. Release impact

Both changes alter externally observable report text. Under Semantic
Versioning this is a breaking change for any consumer that parses or greps the
report, and must be released as a major version bump once an implementation
exists. No released version currently emits this output.

## 7. Merge instructions

On acceptance, apply Sections 2 and 3 throughout
`specs/Compare-DirectoryTree-Spec.md` by substitution, add the acceptance
requirements in Section 5 to the appropriate acceptance scenarios and
Appendix B invariants, record the change in `CHANGELOG.md` under
`Unreleased`, and delete this speclet.
