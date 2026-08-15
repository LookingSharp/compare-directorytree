use crate::model::RelativePath;

pub fn format_exact_bytes(bytes: u64) -> String {
    let digits = bytes.to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3);
    for (index, ch) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            out.push(',');
        }
        out.push(ch);
    }
    out
}

pub fn format_aggregate_bytes(bytes: u64) -> String {
    if bytes < 1024 {
        return format!("{} B", bytes);
    }

    const UNITS: [&str; 5] = ["KB", "MB", "GB", "TB", "PB"];
    let mut value = bytes as f64 / 1024.0;
    let mut unit = 0usize;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }

    let rounded = (value * 10.0).round() / 10.0;
    if (rounded.fract() - 0.0).abs() < f64::EPSILON {
        format!("{:.0} {}", rounded, UNITS[unit])
    } else {
        format!("{:.1} {}", rounded, UNITS[unit])
    }
}

pub fn format_count(count: u64, singular: &str, plural: &str) -> String {
    if count == 1 {
        format!("1 {}", singular)
    } else {
        format!("{} {}", count, plural)
    }
}

pub fn format_directory_summary(
    file_count: u64,
    directory_count: u64,
    bytes: u64,
    ignored: u64,
) -> String {
    let mut text = format!(
        "{}, {}, {}",
        format_count(file_count, "file", "files"),
        format_count(directory_count, "dir", "dirs"),
        format_aggregate_bytes(bytes)
    );
    if ignored > 0 {
        text.push_str(&format!(" | ignored metadata {}", ignored));
    }
    text
}

pub fn format_summary_line(label: &str, value: u64) -> String {
    let value_text = value.to_string();
    let width = 33usize;
    let padding = width.saturating_sub(label.len() + value_text.len()).max(1);
    format!("{}{}{}", label, " ".repeat(padding), value_text)
}

pub fn render_relative_path(path: &RelativePath, is_dir: bool) -> String {
    if is_dir {
        path.render_dir()
    } else {
        path.render_file()
    }
}
