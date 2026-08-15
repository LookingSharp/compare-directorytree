use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct TestPair {
    pub base: PathBuf,
    pub left: PathBuf,
    pub right: PathBuf,
}

impl TestPair {
    pub fn new() -> Self {
        let unique = format!(
            "case-{}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        );
        let base = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("test-work")
            .join(unique);
        let left = base.join("left");
        let right = base.join("right");
        fs::create_dir_all(&left).unwrap();
        fs::create_dir_all(&right).unwrap();
        Self { base, left, right }
    }

    pub fn make_file(&self, relative: &str, size: u64, side: Side) {
        let root = self.root(side);
        let path = root.join(relative.replace('\\', std::path::MAIN_SEPARATOR_STR));
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        let file = fs::File::create(path).unwrap();
        file.set_len(size).unwrap();
    }

    pub fn make_dir(&self, relative: &str, side: Side) {
        let root = self.root(side);
        fs::create_dir_all(root.join(relative.replace('\\', std::path::MAIN_SEPARATOR_STR)))
            .unwrap();
    }

    pub fn root(&self, side: Side) -> &Path {
        match side {
            Side::Left => &self.left,
            Side::Right => &self.right,
        }
    }
}

impl Drop for TestPair {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.base);
    }
}

#[derive(Clone, Copy)]
pub enum Side {
    Left,
    Right,
}

pub struct RunResult {
    pub output: Output,
    pub stdout: String,
    pub stderr: String,
    pub lines: Vec<String>,
}

impl RunResult {
    pub fn code(&self) -> i32 {
        self.output.status.code().unwrap_or(-1)
    }
}

pub fn run(pair: &TestPair, extra_args: &[&str]) -> RunResult {
    let mut command = Command::new(env!("CARGO_BIN_EXE_compare-directorytree"));
    command.arg(&pair.left).arg(&pair.right).args(extra_args);
    let output = command.output().unwrap();
    let stdout = String::from_utf8(output.stdout.clone()).unwrap();
    let stderr = String::from_utf8(output.stderr.clone()).unwrap();
    let lines = stdout.lines().map(str::to_string).collect();
    RunResult {
        output,
        stdout,
        stderr,
        lines,
    }
}

pub fn summary_value(lines: &[String], label: &str) -> u64 {
    let line = lines
        .iter()
        .find(|line| line.starts_with(label))
        .unwrap_or_else(|| panic!("missing summary line: {label}"));
    line[label.len()..].trim().parse::<u64>().unwrap()
}

pub fn verdict(lines: &[String]) -> &str {
    lines
        .iter()
        .find(|line| line.starts_with("RESULT:"))
        .map(String::as_str)
        .unwrap_or_else(|| panic!("missing verdict line"))
}

pub fn difference_rows(lines: &[String]) -> Vec<&str> {
    lines
        .iter()
        .filter(|line| line.starts_with("<<") || line.starts_with(">>") || line.starts_with("<>"))
        .map(String::as_str)
        .collect()
}

pub fn normalized_rows(lines: &[String]) -> Vec<String> {
    difference_rows(lines)
        .into_iter()
        .map(normalize_space)
        .collect()
}

pub fn normalize_space(line: &str) -> String {
    line.split_whitespace().collect::<Vec<_>>().join(" ")
}
