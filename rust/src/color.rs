use std::env;
use std::io::{self, IsTerminal};

const RESET: &str = "\x1b[0m";

pub fn should_color(no_color: bool) -> bool {
    !no_color && env::var_os("NO_COLOR").is_none() && io::stdout().is_terminal()
}

pub fn colorize_lines(lines: &[String]) -> Vec<String> {
    lines.iter().map(|line| colorize_line(line)).collect()
}

pub fn colorize_line(line: &str) -> String {
    let mut colored = if let Some(color) = marker_color(line) {
        format!("{}{}{}{}", color, &line[..2], RESET, &line[2..])
    } else {
        line.to_string()
    };

    if let Some(index) = colored.find("Ignored: ") {
        colored = format!(
            "{}{}{}{}",
            &colored[..index],
            "\x1b[2m",
            &colored[index..],
            RESET
        );
    }

    if line.starts_with("RESULT: DIFFERENT") {
        colored = colored.replacen(
            "RESULT: DIFFERENT",
            &format!("RESULT: {}DIFFERENT{}", "\x1b[31m", RESET),
            1,
        );
    } else if line.starts_with("RESULT: MATCH") {
        colored = colored.replacen(
            "RESULT: MATCH",
            &format!("RESULT: {}MATCH{}", "\x1b[32m", RESET),
            1,
        );
    }

    colored
}

fn marker_color(line: &str) -> Option<&'static str> {
    if line.starts_with("<<") {
        Some("\x1b[36m")
    } else if line.starts_with(">>") {
        Some("\x1b[35m")
    } else if line.starts_with("<>") {
        Some("\x1b[33m")
    } else {
        None
    }
}
