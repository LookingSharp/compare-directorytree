mod common;

use std::fs;
use std::path::Path;
use std::process::Command;

use common::{difference_rows, normalized_rows, run, summary_value, verdict, Side, TestPair};

#[test]
fn scenario_10_1_same_ordinary_files() {
    let pair = TestPair::new();
    pair.make_file("IMG_1001.JPG", 5_000, Side::Left);
    pair.make_file("IMG_1002.JPG", 6_000, Side::Left);
    pair.make_file("IMG_1001.JPG", 5_000, Side::Right);
    pair.make_file("IMG_1002.JPG", 6_000, Side::Right);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 0);
    assert_eq!(summary_value(&result.lines, "Same:"), 2);
    assert_eq!(summary_value(&result.lines, "Total differences:"), 0);
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 0);
    assert_eq!(verdict(&result.lines), "RESULT: MATCH - all 2 files match");
    assert!(difference_rows(&result.lines).is_empty());
}

#[test]
fn scenario_10_2_file_only_on_left() {
    let pair = TestPair::new();
    pair.make_file("IMG_1003.JPG", 4_096, Side::Left);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].contains("IMG_1003.JPG"));
    assert!(rows[0].contains("4,096"));
    assert!(rows[0].contains("<missing>"));
}

#[test]
fn scenario_10_3_file_only_on_right() {
    let pair = TestPair::new();
    pair.make_file("IMG_1004.JPG", 2_048, Side::Right);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].starts_with(">>"));
    assert!(rows[0].contains("IMG_1004.JPG"));
    assert!(rows[0].contains("2,048"));
}

#[test]
fn scenario_10_4_same_filename_different_size() {
    let pair = TestPair::new();
    pair.make_file("IMG_1005.JPG", 5_238_104, Side::Left);
    pair.make_file("IMG_1005.JPG", 5_238_105, Side::Right);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].starts_with("<>"));
    assert!(rows[0].contains("5,238,104"));
    assert!(rows[0].contains("5,238,105"));
    assert_eq!(summary_value(&result.lines, "Different size:"), 1);
    assert_eq!(
        verdict(&result.lines),
        "RESULT: DIFFERENT - 1 relevant difference"
    );
}

#[test]
fn scenario_10_5_ignored_metadata_only() {
    let pair = TestPair::new();
    pair.make_file("IMG_1001.JPG", 5_000, Side::Left);
    pair.make_file("IMG_1001.JPG", 5_000, Side::Right);
    pair.make_file("THUMBS.DB", 81_920, Side::Left);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 0);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].contains("Ignored: Windows thumbnail cache"));
    assert_eq!(summary_value(&result.lines, "Total differences:"), 1);
    assert_eq!(
        summary_value(&result.lines, "Ignored metadata differences:"),
        1
    );
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 0);
    assert_eq!(
        verdict(&result.lines),
        "RESULT: MATCH - qualified: differences limited to 1 ignored metadata file"
    );
}

#[test]
fn scenario_10_6_recognized_metadata_remains_relevant() {
    let pair = TestPair::new();
    pair.make_file("._IMG_1001.xmp", 512, Side::Right);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].contains("Recognized: AppleDouble sidecar"));
    assert_eq!(
        summary_value(&result.lines, "Ignored metadata differences:"),
        0
    );
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 1);
}

#[test]
fn scenario_10_7_hidden_ordinary_file_is_included() {
    let pair = TestPair::new();
    pair.make_file(".config", 1, Side::Left);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    let rows = difference_rows(&result.lines);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].contains(".config"));
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 1);
}

#[test]
fn scenario_10_8_both_directories_empty() {
    let pair = TestPair::new();
    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 0);
    assert_eq!(summary_value(&result.lines, "LEFT files:"), 0);
    assert_eq!(summary_value(&result.lines, "RIGHT files:"), 0);
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 0);
    assert_eq!(verdict(&result.lines), "RESULT: MATCH - all 0 files match");
}

#[test]
fn scenario_10_9_one_directory_empty() {
    let pair = TestPair::new();
    pair.make_file("a.txt", 1, Side::Left);
    pair.make_file("b.txt", 2, Side::Left);
    pair.make_file("Thumbs.db", 3, Side::Left);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 1);
    assert_eq!(difference_rows(&result.lines).len(), 3);
    assert_eq!(summary_value(&result.lines, "LEFT only:"), 3);
    assert_eq!(
        summary_value(&result.lines, "Ignored metadata differences:"),
        1
    );
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 2);
}

#[test]
fn scenario_10_10_case_insensitive_collision_fails() {
    let pair = TestPair::new();
    pair.make_file("IMG_1001.JPG", 10, Side::Left);
    pair.make_file("img_1001.jpg", 20, Side::Left);

    let result = run(&pair, &["--no-color"]);

    assert_eq!(result.code(), 2);
    assert!(result
        .stderr
        .contains("case-insensitive filename collision"));
    assert!(result.stdout.is_empty());
}

#[test]
fn scenario_10_11_invalid_or_inaccessible_input_fails() {
    let pair = TestPair::new();
    let missing = pair.left.join("missing");
    let output = Command::new(env!("CARGO_BIN_EXE_compare-directorytree"))
        .arg(&missing)
        .arg(&pair.right)
        .output()
        .unwrap();
    let stderr = String::from_utf8(output.stderr).unwrap();

    assert_eq!(output.status.code(), Some(2));
    assert!(stderr.contains("Path not found"));
}

#[cfg(unix)]
#[test]
fn scenario_10_11_recursive_enumeration_failure_fails_clearly() {
    use std::os::unix::fs::PermissionsExt;

    let pair = TestPair::new();
    pair.make_dir("denied", Side::Left);
    let denied = pair.left.join("denied");
    fs::set_permissions(&denied, fs::Permissions::from_mode(0o000)).unwrap();

    let result = run(&pair, &["--recurse", "--no-color"]);

    fs::set_permissions(&denied, fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(result.code(), 2);
    assert!(
        result.stderr.contains("Cannot enumerate directory")
            || result.stderr.contains("Permission denied")
    );
    assert!(result
        .stderr
        .contains(&denied.to_string_lossy().to_string()));
}

#[test]
fn scenario_10_12_explain_metadata_once_per_type() {
    let pair = TestPair::new();
    pair.make_file("Thumbs.db", 1, Side::Left);
    pair.make_file("Thumbs.db", 2, Side::Right);
    pair.make_file(".DS_Store", 3, Side::Left);
    pair.make_file(".DS_Store", 4, Side::Right);
    pair.make_file("ehthumbs.db", 5, Side::Left);

    let result = run(&pair, &["--explain-metadata", "--no-color"]);

    assert_eq!(result.code(), 0);
    assert_eq!(result.stdout.matches("WIN-THUMBS").count(), 1);
    assert_eq!(result.stdout.matches("MAC-DSSTORE").count(), 1);
    assert_eq!(result.stdout.matches("WIN-EHTHUMBS").count(), 1);
    assert!(!result.stdout.contains("PHOTO-XMP"));
}

#[test]
fn scenario_10_13_recursive_default_compact_and_expand_behaviors() {
    let pair = TestPair::new();
    pair.make_file("Shared\\same.txt", 10, Side::Left);
    pair.make_file("Shared\\same.txt", 10, Side::Right);
    pair.make_file("Shared\\diff.txt", 10, Side::Left);
    pair.make_file("Shared\\diff.txt", 11, Side::Right);
    pair.make_file("Missing\\a.bin", 100, Side::Left);
    pair.make_file("Missing\\Nested\\b.bin", 200, Side::Left);
    pair.make_file("Cache\\Thumbs.db", 81_920, Side::Left);
    pair.make_dir("Empty\\Deep", Side::Left);

    let default = run(&pair, &["--recurse", "--no-color"]);
    assert_eq!(default.code(), 1);
    let default_rows = normalized_rows(&default.lines);
    assert!(default_rows.contains(&"<< DIR Missing\\ 2 files, 1 dir, 300 B".to_string()));
    assert!(default_rows
        .contains(&"<< DIR Cache\\ 1 file, 0 dirs, 80 KB | ignored metadata 1".to_string()));
    assert!(default_rows
        .iter()
        .any(|row| row.contains("Shared\\diff.txt") && row.starts_with("<>")));
    assert!(!default.stdout.contains("Missing\\a.bin"));
    assert_eq!(summary_value(&default.lines, "LEFT only:"), 3);
    assert_eq!(summary_value(&default.lines, "Relevant differences:"), 3);
    assert_eq!(summary_value(&default.lines, "LEFT-only directories:"), 5);
    assert_eq!(
        summary_value(&default.lines, "Empty-directory differences:"),
        1
    );

    let compact = run(&pair, &["--recurse", "--compact", "--no-color"]);
    let compact_rows = normalized_rows(&compact.lines);
    assert!(compact_rows.contains(&"<> DIR Shared\\ 1 same | << 0 | >> 0 | <> 1".to_string()));
    assert!(compact_rows.contains(&"<< DIR Missing\\ 2 files, 1 dir, 300 B".to_string()));
    assert!(!compact.stdout.contains("Shared\\diff.txt"));

    let expanded = run(
        &pair,
        &["--recurse", "--expand-missing-subtrees", "--no-color"],
    );
    let expanded_rows = normalized_rows(&expanded.lines);
    assert!(expanded_rows
        .iter()
        .any(|row| row == "<< Missing\\a.bin 100 <missing>"));
    assert!(expanded_rows
        .iter()
        .any(|row| row == "<< Missing\\Nested\\b.bin 200 <missing>"));
    assert!(expanded_rows.contains(&"<< DIR Empty\\Deep\\ 0 files, 0 dirs, 0 B".to_string()));
    assert!(!expanded_rows.iter().any(|row| row == "<< DIR Missing\\"));

    for label in [
        "LEFT files:",
        "RIGHT files:",
        "Same:",
        "Different size:",
        "LEFT only:",
        "RIGHT only:",
        "LEFT directories:",
        "RIGHT directories:",
        "LEFT-only directories:",
        "RIGHT-only directories:",
        "Empty-directory differences:",
        "Total differences:",
        "Ignored metadata differences:",
        "Relevant differences:",
        "Structural differences:",
    ] {
        assert_eq!(
            summary_value(&compact.lines, label),
            summary_value(&default.lines, label),
            "{}",
            label
        );
        assert_eq!(
            summary_value(&expanded.lines, label),
            summary_value(&default.lines, label),
            "{}",
            label
        );
    }
    assert_eq!(verdict(&compact.lines), verdict(&default.lines));
    assert_eq!(verdict(&expanded.lines), verdict(&default.lines));
}

#[test]
fn scenario_10_13_case_insensitive_relative_path_matching_and_match_qualification() {
    let pair = TestPair::new();
    pair.make_file("Sub\\File.TXT", 5, Side::Left);
    pair.make_file("SUB\\file.txt", 5, Side::Right);
    pair.make_dir("OnlyHere", Side::Left);
    pair.make_file("Thumbs.db", 10, Side::Left);

    let result = run(&pair, &["--recurse", "--no-color"]);

    assert_eq!(result.code(), 0);
    assert_eq!(summary_value(&result.lines, "Same:"), 1);
    assert_eq!(summary_value(&result.lines, "Relevant differences:"), 0);
    assert_eq!(
        verdict(&result.lines),
        "RESULT: MATCH - qualified: different empty subdirectories; other differences limited to ignorable metadata"
    );
}

#[test]
fn scenario_10_13_rejects_invalid_recursive_switch_combinations() {
    let pair = TestPair::new();

    let both = run(
        &pair,
        &[
            "--recurse",
            "--compact",
            "--expand-missing-subtrees",
            "--no-color",
        ],
    );
    assert_eq!(both.code(), 2);
    assert!(both.stderr.contains("cannot be combined"));

    let compact_only = Command::new(env!("CARGO_BIN_EXE_compare-directorytree"))
        .arg(&pair.left)
        .arg(&pair.right)
        .arg("--compact")
        .output()
        .unwrap();
    assert_eq!(compact_only.status.code(), Some(2));
    assert!(String::from_utf8(compact_only.stderr)
        .unwrap()
        .contains("--compact requires --recurse"));

    let expand_only = Command::new(env!("CARGO_BIN_EXE_compare-directorytree"))
        .arg(&pair.left)
        .arg(&pair.right)
        .arg("--expand-missing-subtrees")
        .output()
        .unwrap();
    assert_eq!(expand_only.status.code(), Some(2));
    assert!(String::from_utf8(expand_only.stderr)
        .unwrap()
        .contains("--expand-missing-subtrees requires --recurse"));
}

#[test]
fn scenario_10_14_plain_text_and_no_color_have_no_ansi_and_no_extra_legend() {
    let pair = TestPair::new();
    pair.make_file("left-only.txt", 1, Side::Left);
    pair.make_file("right-only.txt", 2, Side::Right);
    pair.make_file("both.txt", 3, Side::Left);
    pair.make_file("both.txt", 4, Side::Right);
    pair.make_file("Thumbs.db", 5, Side::Left);

    let plain = run(&pair, &[]);
    let no_color = run(&pair, &["--no-color"]);

    assert_eq!(plain.code(), 1);
    assert!(!plain.stdout.contains("\u{1b}["));
    assert!(!no_color.stdout.contains("\u{1b}["));
    assert_eq!(plain.stdout, no_color.stdout);
    assert!(!plain.stdout.contains("cyan"));
    assert!(!plain.stdout.contains("magenta"));
    assert!(!plain.stdout.contains("yellow"));
}

#[test]
fn scenario_10_15_verdict_vocabulary_and_type_column() {
    let pair = TestPair::new();
    pair.make_file("one.txt", 10, Side::Left);
    pair.make_file("one.txt", 10, Side::Right);
    pair.make_file("two.txt", 10, Side::Left);
    pair.make_file("two.txt", 10, Side::Right);

    let match_result = run(&pair, &["--no-color"]);
    assert_eq!(
        verdict(&match_result.lines),
        "RESULT: MATCH - all 2 files match"
    );
    assert!(!match_result.stdout.contains("NOT THE SAME"));
    assert!(
        match_result
            .lines
            .iter()
            .any(|line| line.contains("Type") && line.contains("File / Directory"))
            || difference_rows(&match_result.lines).is_empty()
    );

    pair.make_file("extra.txt", 1, Side::Left);
    pair.make_dir("OnlyHere", Side::Left);
    let different = run(&pair, &["--recurse", "--no-color"]);
    let rows = difference_rows(&different.lines);
    assert_eq!(different.code(), 1);
    assert_eq!(
        verdict(&different.lines),
        "RESULT: DIFFERENT - 1 relevant difference | 1 empty-subdirectory difference"
    );
    assert!(different
        .lines
        .iter()
        .any(|line| line.contains("Type") && line.contains("File / Directory")));
    assert!(rows
        .iter()
        .any(|row| row.starts_with("<<  DIR") && row.contains("OnlyHere\\")));
    assert!(rows
        .iter()
        .any(|row| row.starts_with("<<      ") && row.contains("extra.txt")));
    assert!(rows.iter().all(|row| !row.contains("FILE")));
}

#[test]
fn scenario_10_16_formatting_ordering_legend_and_verdict_determinism() {
    let pair = TestPair::new();
    pair.make_file("Camp\\anchor.txt", 1, Side::Left);
    pair.make_file("Camp\\anchor.txt", 1, Side::Right);
    pair.make_dir("Camp\\Empty", Side::Left);
    pair.make_file("Camp\\IMG.JPG", 81_920, Side::Left);
    pair.make_file("Camp\\Raw\\a.cr2", 1, Side::Left);
    pair.make_file("Camp\\Thumbs.db", 1, Side::Left);
    pair.make_file("extra.txt", 1, Side::Left);

    let first = run(&pair, &["--recurse", "--no-color"]);
    let second = run(&pair, &["--recurse", "--no-color"]);

    assert_eq!(first.stdout, second.stdout);
    let rows = normalized_rows(&first.lines);
    assert!(rows.contains(&"<< extra.txt 1 <missing>".to_string()));
    assert!(rows.contains(&"<< DIR Camp\\Empty\\ 0 files, 0 dirs, 0 B".to_string()));
    assert!(rows.contains(&"<< DIR Camp\\Raw\\ 1 file, 0 dirs, 1 B".to_string()));
    assert!(rows
        .iter()
        .any(|row| row == "<< Camp\\IMG.JPG 81,920 <missing>"));

    let left_rows: Vec<String> = rows
        .into_iter()
        .filter(|row| row.starts_with("<<"))
        .collect();
    let path_order: Vec<String> = left_rows
        .iter()
        .filter_map(|row| {
            row.split(' ')
                .find(|part| part.starts_with("Camp\\") || *part == "extra.txt")
        })
        .map(ToString::to_string)
        .collect();
    assert_eq!(
        path_order,
        vec![
            "Camp\\Empty\\".to_string(),
            "Camp\\IMG.JPG".to_string(),
            "Camp\\Raw\\".to_string(),
            "Camp\\Thumbs.db".to_string(),
            "extra.txt".to_string(),
        ]
    );
    assert!(first.stdout.contains("  <<   Exists only on LEFT"));
    assert!(first.stdout.contains("  >>   Exists only on RIGHT"));
    assert!(first
        .stdout
        .contains("  <>   Same relative path, different size"));
    assert!(first.stdout.contains("  DIR  Directory summary row"));
    assert_eq!(summary_value(&first.lines, "Structural differences:"), 2);
    assert_eq!(
        summary_value(&first.lines, "Empty-directory differences:"),
        1
    );
    assert_eq!(
        verdict(&first.lines),
        "RESULT: DIFFERENT - 3 relevant differences | 1 empty-subdirectory difference | 1 directory-structure difference | 1 ignored metadata difference"
    );
    assert!(!verdict(&first.lines).contains("| 0 "));
}

#[test]
fn readme_header_maps_arguments_to_left_and_right() {
    let pair = TestPair::new();
    pair.make_file("left-only.txt", 1, Side::Left);
    let result = run(&pair, &["--no-color"]);

    let left_path = fs::canonicalize(&pair.left)
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let right_path = fs::canonicalize(&pair.right)
        .unwrap()
        .to_string_lossy()
        .into_owned();
    assert!(result.lines.contains(&format!("LEFT : {}", left_path)));
    assert!(result.lines.contains(&format!("RIGHT: {}", right_path)));
}

#[test]
fn help_and_usage_exit_cleanly() {
    let output = Command::new(env!("CARGO_BIN_EXE_compare-directorytree"))
        .arg("--help")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0));
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(stdout.contains("Usage: compare-directorytree"));
    assert!(stdout.contains("Exit codes: 0 = MATCH, 1 = DIFFERENT, 2 = usage or error"));
}

fn _path(_path: &Path) {}
