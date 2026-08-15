#[allow(dead_code)]
#[path = "../src/color.rs"]
mod color;

#[test]
fn colors_only_markers_and_verdict_phrase() {
    let left = color::colorize_line(
        "<<        left-only.txt                                  1            <missing>",
    );
    let right = color::colorize_line(
        ">>        right-only.txt                           <missing>            2",
    );
    let diff = color::colorize_line(
        "<>        both.txt                                       3                    4",
    );
    let verdict_match = color::colorize_line("RESULT: MATCH - all 3 files match");
    let verdict_different = color::colorize_line(
        "RESULT: DIFFERENT - 2 relevant differences | 1 ignored metadata difference",
    );

    assert!(left.starts_with("\u{1b}[36m<<\u{1b}[0m"));
    assert!(right.starts_with("\u{1b}[35m>>\u{1b}[0m"));
    assert!(diff.starts_with("\u{1b}[33m<>\u{1b}[0m"));
    assert_eq!(
        verdict_match,
        "RESULT: \u{1b}[32mMATCH\u{1b}[0m - all 3 files match"
    );
    assert_eq!(
        verdict_different,
        "RESULT: \u{1b}[31mDIFFERENT\u{1b}[0m - 2 relevant differences | 1 ignored metadata difference"
    );
    assert!(!left["\u{1b}[36m<<\u{1b}[0m".len()..].contains("\u{1b}[31m"));
}

#[test]
fn dims_ignored_annotation_without_affecting_marker() {
    let row = color::colorize_line(
        "<<        Thumbs.db                                   81,920            <missing>   Ignored: Windows thumbnail cache",
    );

    assert!(row.starts_with("\u{1b}[36m<<\u{1b}[0m"));
    assert!(row.ends_with("\u{1b}[2mIgnored: Windows thumbnail cache\u{1b}[0m"));
}

#[test]
fn leaves_non_difference_lines_unchanged() {
    let line = "SUMMARY".to_string();
    assert_eq!(color::colorize_line(&line), line);
}
