use crate::model::{MetadataMatch, MetadataPolicy};

#[derive(Clone, Copy)]
enum MatchKind {
    Exact(&'static str),
    Prefix(&'static str),
    Suffix(&'static str),
}

#[derive(Clone, Copy)]
struct CatalogRule {
    metadata: MetadataMatch,
    matcher: MatchKind,
}

const CATALOG: [CatalogRule; 10] = [
    rule_ignore("WIN-THUMBS", MatchKind::Exact("Thumbs.db"), "Windows thumbnail cache", "Generated preview cache; not source content and normally regenerable."),
    rule_ignore("WIN-EHTHUMBS", MatchKind::Exact("ehthumbs.db"), "Windows Media Center thumbnail cache", "Legacy generated media-preview cache."),
    rule_ignore("WIN-DESKTOPINI", MatchKind::Exact("desktop.ini"), "Windows folder presentation metadata", "Explorer folder customization rather than substantive directory content."),
    rule_ignore("MAC-DSSTORE", MatchKind::Exact(".DS_Store"), "macOS Finder metadata", "Finder view/presentation metadata rather than substantive directory content."),
    rule_ignore("KDE-DIRECTORY", MatchKind::Exact(".directory"), "KDE folder presentation metadata", "Folder-specific KDE/Dolphin presentation metadata."),
    rule_relevant("MAC-APPLEDOUBLE", MatchKind::Prefix("._"), "AppleDouble sidecar", "May preserve resource forks, Finder information, extended attributes, or other Mac filesystem metadata."),
    rule_relevant("PHOTO-XMP", MatchKind::Suffix(".xmp"), "XMP photo sidecar", "May contain ratings, keywords, develop settings, edits, or intentionally maintained metadata."),
    rule_relevant("PHOTO-AAE", MatchKind::Suffix(".aae"), "Apple photo-edit sidecar", "May represent nondestructive edits associated with a photo."),
    rule_relevant("PHOTO-PXD-SIDECAR", MatchKind::Suffix(".pxd-sidecar"), "Pixelmator edit sidecar", "May contain layers or nondestructive editing state."),
    rule_relevant("PHOTO-PICASA", MatchKind::Exact(".picasa.ini"), "Picasa photo metadata", "May contain photo-specific metadata such as face/name tagging."),
];

const fn rule_ignore(
    id: &'static str,
    matcher: MatchKind,
    short_note: &'static str,
    explanation: &'static str,
) -> CatalogRule {
    CatalogRule {
        metadata: MetadataMatch {
            id,
            policy: MetadataPolicy::Ignore,
            short_note,
            explanation,
        },
        matcher,
    }
}

const fn rule_relevant(
    id: &'static str,
    matcher: MatchKind,
    short_note: &'static str,
    explanation: &'static str,
) -> CatalogRule {
    CatalogRule {
        metadata: MetadataMatch {
            id,
            policy: MetadataPolicy::Relevant,
            short_note,
            explanation,
        },
        matcher,
    }
}

fn matches(rule: MatchKind, file_name: &str) -> bool {
    match rule {
        MatchKind::Exact(expected) => {
            file_name.eq_ignore_ascii_case(expected)
                || file_name.to_lowercase() == expected.to_lowercase()
        }
        MatchKind::Prefix(prefix) => file_name.to_lowercase().starts_with(&prefix.to_lowercase()),
        MatchKind::Suffix(suffix) => file_name.to_lowercase().ends_with(&suffix.to_lowercase()),
    }
}

pub fn classify(file_name: &str) -> Option<MetadataMatch> {
    let mut first_match = None;
    let mut first_relevant = None;

    for rule in CATALOG {
        if matches(rule.matcher, file_name) {
            if first_match.is_none() {
                first_match = Some(rule.metadata);
            }
            if matches!(rule.metadata.policy, MetadataPolicy::Relevant) && first_relevant.is_none()
            {
                first_relevant = Some(rule.metadata);
            }
        }
    }

    first_relevant.or(first_match)
}

pub fn is_ignored(file_name: &str) -> bool {
    classify(file_name).is_some_and(MetadataMatch::is_ignored)
}
