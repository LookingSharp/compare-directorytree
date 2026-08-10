"""Metadata recognition and ignore-policy catalog.

Behavior is defined by Appendix A of
../../specs/Compare-DirectoryTree-Spec.md.

Metadata classification is centralized here so that adding a catalog rule
does not require changing comparison/report semantics (Appendix B, item 23).
"""

from __future__ import annotations

import fnmatch
from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass(frozen=True)
class MetadataRule:
    id: str
    policy: str  # 'Ignore' or 'Relevant'
    names: Sequence[str]
    patterns: Sequence[str]
    short_note: str
    explanation: str


@dataclass(frozen=True)
class MetadataClassification:
    id: str
    policy: str
    short_note: str
    explanation: str
    note: str

    @property
    def is_ignored(self) -> bool:
        return self.policy == "Ignore"


# The catalog is intentionally conservative. Recognition does not imply
# ignore. See Appendix A.
METADATA_CATALOG: tuple[MetadataRule, ...] = (
    MetadataRule(
        id="WIN-THUMBS",
        policy="Ignore",
        names=("Thumbs.db",),
        patterns=(),
        short_note="Windows thumbnail cache",
        explanation="Generated preview cache; not source content and normally regenerable.",
    ),
    MetadataRule(
        id="WIN-EHTHUMBS",
        policy="Ignore",
        names=("ehthumbs.db",),
        patterns=(),
        short_note="Windows Media Center thumbnail cache",
        explanation="Legacy generated media-preview cache.",
    ),
    MetadataRule(
        id="WIN-DESKTOPINI",
        policy="Ignore",
        names=("desktop.ini",),
        patterns=(),
        short_note="Windows folder presentation metadata",
        explanation="Explorer folder customization rather than substantive directory content.",
    ),
    MetadataRule(
        id="MAC-DSSTORE",
        policy="Ignore",
        names=(".DS_Store",),
        patterns=(),
        short_note="macOS Finder metadata",
        explanation="Finder view/presentation metadata rather than substantive directory content.",
    ),
    MetadataRule(
        id="KDE-DIRECTORY",
        policy="Ignore",
        names=(".directory",),
        patterns=(),
        short_note="KDE folder presentation metadata",
        explanation="Folder-specific KDE/Dolphin presentation metadata.",
    ),
    MetadataRule(
        id="MAC-APPLEDOUBLE",
        policy="Relevant",
        names=(),
        patterns=("._*",),
        short_note="AppleDouble sidecar",
        explanation="May preserve resource forks, Finder information, extended attributes, or other Mac filesystem metadata.",
    ),
    MetadataRule(
        id="PHOTO-XMP",
        policy="Relevant",
        names=(),
        patterns=("*.xmp",),
        short_note="XMP photo sidecar",
        explanation="May contain ratings, keywords, develop settings, edits, or intentionally maintained metadata.",
    ),
    MetadataRule(
        id="PHOTO-AAE",
        policy="Relevant",
        names=(),
        patterns=("*.aae",),
        short_note="Apple photo-edit sidecar",
        explanation="May represent nondestructive edits associated with a photo.",
    ),
    MetadataRule(
        id="PHOTO-PXD-SIDECAR",
        policy="Relevant",
        names=(),
        patterns=("*.pxd-sidecar",),
        short_note="Pixelmator edit sidecar",
        explanation="May contain layers or nondestructive editing state.",
    ),
    MetadataRule(
        id="PHOTO-PICASA",
        policy="Relevant",
        names=(".picasa.ini", "Picasa.ini"),
        patterns=(),
        short_note="Picasa photo metadata",
        explanation="May contain photo-specific metadata such as face/name tagging.",
    ),
)


def _name_matches(file_name: str, rule: MetadataRule) -> bool:
    for name in rule.names:
        if file_name.lower() == name.lower():
            return True
    for pattern in rule.patterns:
        if fnmatch.fnmatch(file_name.lower(), pattern.lower()):
            return True
    return False


def classify(file_name: str) -> Optional[MetadataClassification]:
    """Classify a file name against the metadata catalog.

    Preservation-first: a file recognized by any 'Relevant' rule stays
    relevant even when another rule would ignore it. Resolution is
    deterministic (first matching rule in catalog order, preferring
    'Relevant' matches).
    """

    matched = [rule for rule in METADATA_CATALOG if _name_matches(file_name, rule)]
    if not matched:
        return None

    relevant = [rule for rule in matched if rule.policy == "Relevant"]
    selected = relevant[0] if relevant else matched[0]

    note = (
        f"Ignored: {selected.short_note}"
        if selected.policy == "Ignore"
        else f"Recognized: {selected.short_note}"
    )

    return MetadataClassification(
        id=selected.id,
        policy=selected.policy,
        short_note=selected.short_note,
        explanation=selected.explanation,
        note=note,
    )


def is_ignored(file_name: str) -> bool:
    classification = classify(file_name)
    return classification is not None and classification.is_ignored
