use crate::compare::render_file_size;
use crate::format::{format_summary_line, render_relative_path};
use crate::model::{ComparisonResult, DiffClass, DifferenceRow, FinalVerdict, RowKind};

pub struct RenderedReport {
    pub lines: Vec<String>,
    pub verdict: FinalVerdict,
}

pub fn render_report(result: &ComparisonResult, explain_metadata: bool) -> RenderedReport {
    let mut lines = Vec::new();
    lines.push("FILE COMPARISON".to_string());
    lines.push("===============".to_string());
    lines.push(String::new());
    lines.push(format!("LEFT : {}", result.left_root));
    lines.push(format!("RIGHT: {}", result.right_root));
    lines.push(String::new());

    lines.push(format!("Scope : {}", result.mode.scope_line()));
    if let Some(presentation) = result.mode.presentation_name() {
        lines.push(format!("        Presentation: {}.", presentation));
    }
    lines.push("        Hidden and system files ARE included.".to_string());
    lines.push(format!("Match : {}", result.mode.match_line()));
    lines.push(format!("Same  : {}", result.mode.same_line()));
    lines.push("Ignore: Known disposable metadata/cache files are reported but do not".to_string());
    lines.push("        affect the final comparison result.".to_string());
    lines.push(
        "Note  : Contents, hashes, timestamps, attributes, and other metadata are".to_string(),
    );
    lines.push("        NOT compared.".to_string());
    lines.push(String::new());

    lines.push("SUMMARY".to_string());
    lines.push("-------".to_string());
    lines.push(format_summary_line("LEFT files:", result.stats.left_files));
    lines.push(format_summary_line(
        "RIGHT files:",
        result.stats.right_files,
    ));
    lines.push(format_summary_line("Same:", result.stats.same));
    lines.push(format_summary_line(
        "Different size:",
        result.stats.different_size,
    ));
    lines.push(format_summary_line("LEFT only:", result.stats.left_only));
    lines.push(format_summary_line("RIGHT only:", result.stats.right_only));

    if result.mode.recurse() {
        lines.push(String::new());
        lines.push(format_summary_line(
            "LEFT directories:",
            result.left_directory_count,
        ));
        lines.push(format_summary_line(
            "RIGHT directories:",
            result.right_directory_count,
        ));
        lines.push(format_summary_line(
            "LEFT-only directories:",
            result.stats.left_only_directories,
        ));
        lines.push(format_summary_line(
            "RIGHT-only directories:",
            result.stats.right_only_directories,
        ));
        lines.push(format_summary_line(
            "Empty-directory differences:",
            result.stats.empty_directory_differences,
        ));
    }

    lines.push(String::new());
    lines.push(format_summary_line(
        "Total differences:",
        result.stats.total_differences(),
    ));
    lines.push(format_summary_line(
        "Ignored metadata differences:",
        result.stats.ignored,
    ));
    lines.push(format_summary_line(
        "Relevant differences:",
        result.stats.relevant_differences(),
    ));
    if result.mode.recurse() {
        lines.push(format_summary_line(
            "Structural differences:",
            result.stats.structural_differences(),
        ));
    }

    if !result.rows.is_empty() {
        lines.push(String::new());
        lines.push("DIFFERENCES".to_string());
        lines.push("-----------".to_string());
        lines.push(String::new());

        let path_width = path_width(&result.rows);
        let left_width = left_width(&result.rows);
        let right_width = right_width(&result.rows);
        lines.push(format!(
            "    {}  {}{}   {}   {}",
            "Type",
            "File / Directory".to_string().pad_to_width(path_width),
            "LEFT size (bytes)".to_string().pad_left(left_width),
            "RIGHT size (bytes)".to_string().pad_left(right_width),
            "Note"
        ));
        lines.push(format!(
            "    {}  {}{}   {}   {}",
            "----",
            "----------------".to_string().pad_to_width(path_width),
            "-----------------".to_string().pad_left(left_width),
            "------------------".to_string().pad_left(right_width),
            "----"
        ));

        let mut emitted_any = false;
        for class in DiffClass::ordered() {
            let class_rows: Vec<&DifferenceRow> = result
                .rows
                .iter()
                .filter(|row| row.class == class)
                .collect();
            if class_rows.is_empty() {
                continue;
            }
            if emitted_any {
                lines.push(String::new());
            }
            for row in class_rows {
                lines.push(render_difference_row(
                    row,
                    path_width,
                    left_width,
                    right_width,
                ));
            }
            emitted_any = true;
        }

        lines.push(String::new());
        lines.push("Legend:".to_string());
        lines.push("  <<   Exists only on LEFT".to_string());
        lines.push("  >>   Exists only on RIGHT".to_string());
        lines.push(format!("  <>   {}", result.mode.diff_legend_text()));
        if result.rows.iter().any(DifferenceRow::is_dir) {
            lines.push("  DIR  Directory summary row".to_string());
        }
    }

    let verdict_line = verdict_line(result);
    let verdict = if verdict_line.starts_with("RESULT: DIFFERENT") {
        FinalVerdict::Different
    } else {
        FinalVerdict::Match
    };
    lines.push(String::new());
    lines.push(verdict_line);

    if explain_metadata && !result.encountered_metadata.is_empty() {
        lines.push(String::new());
        lines.push("METADATA EXPLANATIONS".to_string());
        lines.push("---------------------".to_string());
        for metadata in &result.encountered_metadata {
            lines.push(format!(
                "  {}  {} - {}",
                metadata.id,
                metadata.note(),
                metadata.explanation
            ));
        }
    }

    RenderedReport { lines, verdict }
}

fn path_width(rows: &[DifferenceRow]) -> usize {
    let mut width = 38usize;
    for row in rows {
        let path = render_relative_path(&row.relative_path, row.is_dir());
        width = width.max(path.len() + 2);
    }
    width
}

fn left_width(rows: &[DifferenceRow]) -> usize {
    let mut width = 17usize;
    for row in rows {
        if let RowKind::File { left_size, .. } = &row.kind {
            width = width.max(render_file_size(*left_size).len());
        }
    }
    width
}

fn right_width(rows: &[DifferenceRow]) -> usize {
    let mut width = 18usize;
    for row in rows {
        if let RowKind::File { right_size, .. } = &row.kind {
            width = width.max(render_file_size(*right_size).len());
        }
    }
    width
}

fn render_difference_row(
    row: &DifferenceRow,
    path_width: usize,
    left_width: usize,
    right_width: usize,
) -> String {
    let marker = row.class.marker();
    let type_text = if row.is_dir() { "DIR " } else { "    " };
    let prefix = format!("{}  {}  ", marker, type_text);
    let path = render_relative_path(&row.relative_path, row.is_dir());

    match &row.kind {
        RowKind::DirectorySummary { summary } => {
            format!("{}{}{}", prefix, path.pad_to_width(path_width), summary)
                .trim_end()
                .to_string()
        }
        RowKind::File {
            left_size,
            right_size,
            note,
        } => {
            let left = render_file_size(*left_size);
            let right = render_file_size(*right_size);
            let note = note.as_deref().unwrap_or("");
            format!(
                "{}{}{}   {}   {}",
                prefix,
                path.pad_to_width(path_width),
                left.pad_left(left_width),
                right.pad_left(right_width),
                note
            )
            .trim_end()
            .to_string()
        }
    }
}

fn verdict_line(result: &ComparisonResult) -> String {
    let relevant = result.stats.relevant_differences();
    let empty = result.stats.empty_directory_differences;
    let non_empty = result.stats.non_empty_structural_differences();

    if relevant > 0 {
        let mut segments = vec![noun_count(
            relevant,
            "relevant difference",
            "relevant differences",
        )];
        if empty > 0 {
            segments.push(noun_count(
                empty,
                "empty-subdirectory difference",
                "empty-subdirectory differences",
            ));
        }
        if non_empty > 0 {
            segments.push(noun_count(
                non_empty,
                "directory-structure difference",
                "directory-structure differences",
            ));
        }
        if result.stats.ignored > 0 {
            segments.push(noun_count(
                result.stats.ignored,
                "ignored metadata difference",
                "ignored metadata differences",
            ));
        }
        return format!("RESULT: DIFFERENT - {}", segments.join(" | "));
    }

    let mut clauses = Vec::new();
    if empty > 0 {
        clauses.push("different empty subdirectories".to_string());
    }
    if non_empty > 0 {
        clauses.push("directory structure differs".to_string());
    }
    if result.stats.ignored > 0 {
        if clauses.is_empty() {
            clauses.push(format!(
                "differences limited to {}",
                noun_count(
                    result.stats.ignored,
                    "ignored metadata file",
                    "ignored metadata files"
                )
            ));
        } else {
            clauses.push("other differences limited to ignorable metadata".to_string());
        }
    }

    if clauses.is_empty() {
        format!(
            "RESULT: MATCH - all {} match",
            noun_count(result.stats.same, "file", "files")
        )
    } else {
        format!("RESULT: MATCH - qualified: {}", clauses.join("; "))
    }
}

fn noun_count(count: u64, singular: &str, plural: &str) -> String {
    if count == 1 {
        format!("1 {}", singular)
    } else {
        format!("{} {}", count, plural)
    }
}

trait PadText {
    fn pad_to_width(self, width: usize) -> String;
    fn pad_left(self, width: usize) -> String;
}

impl PadText for String {
    fn pad_to_width(self, width: usize) -> String {
        if self.len() >= width {
            self
        } else {
            format!("{}{}", self, " ".repeat(width - self.len()))
        }
    }

    fn pad_left(self, width: usize) -> String {
        if self.len() >= width {
            self
        } else {
            format!("{}{}", " ".repeat(width - self.len()), self)
        }
    }
}
