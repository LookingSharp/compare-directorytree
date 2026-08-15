use std::cmp::Ordering;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Mode {
    #[default]
    Flat,
    RecursiveDefault,
    Compact,
    ExpandMissingSubtrees,
}

impl Mode {
    pub fn recurse(self) -> bool {
        !matches!(self, Self::Flat)
    }

    pub fn scope_line(self) -> &'static str {
        match self {
            Self::Flat => "Files in these directories only; subdirectories are NOT searched.",
            _ => "Files in these directories and all subdirectories.",
        }
    }

    pub fn presentation_name(self) -> Option<&'static str> {
        match self {
            Self::Flat => None,
            Self::RecursiveDefault => Some("default recursive mode"),
            Self::Compact => Some("compact"),
            Self::ExpandMissingSubtrees => Some("expand missing subtrees"),
        }
    }

    pub fn match_line(self) -> &'static str {
        match self {
            Self::Flat => "Filenames are compared case-insensitively.",
            _ => "Relative paths are compared case-insensitively.",
        }
    }

    pub fn same_line(self) -> &'static str {
        match self {
            Self::Flat => "Matching filename and exact size in bytes.",
            _ => "Matching relative path and exact size in bytes.",
        }
    }

    pub fn diff_legend_text(self) -> &'static str {
        match self {
            Self::Flat => "Same filename, different size",
            _ => "Same relative path, different size",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiffClass {
    LeftOnly,
    RightOnly,
    DifferentSize,
}

impl DiffClass {
    pub fn marker(self) -> &'static str {
        match self {
            Self::LeftOnly => "<<",
            Self::RightOnly => ">>",
            Self::DifferentSize => "<>",
        }
    }

    pub fn ordered() -> [Self; 3] {
        [Self::LeftOnly, Self::RightOnly, Self::DifferentSize]
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MetadataPolicy {
    Ignore,
    Relevant,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MetadataMatch {
    pub id: &'static str,
    pub policy: MetadataPolicy,
    pub short_note: &'static str,
    pub explanation: &'static str,
}

impl MetadataMatch {
    pub fn note(self) -> String {
        match self.policy {
            MetadataPolicy::Ignore => format!("Ignored: {}", self.short_note),
            MetadataPolicy::Relevant => format!("Recognized: {}", self.short_note),
        }
    }

    pub fn is_ignored(self) -> bool {
        matches!(self.policy, MetadataPolicy::Ignore)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct RelativePath {
    segments: Vec<String>,
}

impl RelativePath {
    pub fn root() -> Self {
        Self {
            segments: Vec::new(),
        }
    }

    pub fn child(&self, name: &str) -> Self {
        let mut segments = self.segments.clone();
        segments.push(name.to_string());
        Self { segments }
    }

    pub fn is_empty(&self) -> bool {
        self.segments.is_empty()
    }

    pub fn file_name(&self) -> Option<&str> {
        self.segments.last().map(String::as_str)
    }

    pub fn render_file(&self) -> String {
        self.segments.join("\\")
    }

    pub fn render_dir(&self) -> String {
        if self.is_empty() {
            ".\\".to_string()
        } else {
            format!("{}\\", self.render_file())
        }
    }

    pub fn cmp_case_insensitive(&self, other: &Self) -> Ordering {
        let mut left = self.segments.iter();
        let mut right = other.segments.iter();

        loop {
            match (left.next(), right.next()) {
                (Some(a), Some(b)) => {
                    let lowered = cmp_folded(a, b);
                    if lowered != Ordering::Equal {
                        return lowered;
                    }
                }
                (None, Some(_)) => return Ordering::Less,
                (Some(_), None) => return Ordering::Greater,
                (None, None) => return Ordering::Equal,
            }
        }
    }
}

fn cmp_folded(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

#[derive(Clone, Debug)]
pub struct FileEntry {
    pub name: String,
    pub relative_path: RelativePath,
    pub size: u64,
}

#[derive(Clone, Debug)]
pub struct DirNode {
    pub relative_path: RelativePath,
    pub files: Vec<FileEntry>,
    pub dirs: Vec<DirNode>,
}

impl DirNode {
    pub fn subtree_stats(&self, ignored_file_name: &impl Fn(&str) -> bool) -> SubtreeStats {
        let mut stats = SubtreeStats::default();

        for file in &self.files {
            stats.file_count += 1;
            stats.byte_count += file.size;
            if ignored_file_name(&file.name) {
                stats.ignored_count += 1;
            }
        }

        for dir in &self.dirs {
            let child = dir.subtree_stats(ignored_file_name);
            stats.directory_count += 1 + child.directory_count;
            stats.file_count += child.file_count;
            stats.byte_count += child.byte_count;
            stats.ignored_count += child.ignored_count;
        }

        stats
    }

    pub fn empty_leaf_count(&self, include_self: bool) -> u64 {
        let mut count = 0;
        if include_self && self.files.is_empty() && self.dirs.is_empty() {
            count += 1;
        }
        for dir in &self.dirs {
            count += dir.empty_leaf_count(true);
        }
        count
    }

    pub fn collect_files<'a>(&'a self, out: &mut Vec<&'a FileEntry>) {
        for file in &self.files {
            out.push(file);
        }
        for dir in &self.dirs {
            dir.collect_files(out);
        }
    }

    pub fn collect_empty_leaf_dirs<'a>(&'a self, include_self: bool, out: &mut Vec<&'a DirNode>) {
        if include_self && self.files.is_empty() && self.dirs.is_empty() {
            out.push(self);
            return;
        }
        for dir in &self.dirs {
            dir.collect_empty_leaf_dirs(true, out);
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct SubtreeStats {
    pub file_count: u64,
    pub directory_count: u64,
    pub byte_count: u64,
    pub ignored_count: u64,
}

#[derive(Clone, Debug, Default)]
pub struct ComparisonStats {
    pub left_files: u64,
    pub right_files: u64,
    pub same: u64,
    pub different_size: u64,
    pub left_only: u64,
    pub right_only: u64,
    pub ignored: u64,
    pub left_only_directories: u64,
    pub right_only_directories: u64,
    pub empty_directory_differences: u64,
}

impl ComparisonStats {
    pub fn total_differences(&self) -> u64 {
        self.different_size + self.left_only + self.right_only
    }

    pub fn relevant_differences(&self) -> u64 {
        self.total_differences() - self.ignored
    }

    pub fn structural_differences(&self) -> u64 {
        self.left_only_directories + self.right_only_directories
    }

    pub fn non_empty_structural_differences(&self) -> u64 {
        self.structural_differences() - self.empty_directory_differences
    }
}

#[derive(Clone, Debug)]
pub enum RowKind {
    File {
        left_size: Option<u64>,
        right_size: Option<u64>,
        note: Option<String>,
    },
    DirectorySummary {
        summary: String,
    },
}

#[derive(Clone, Debug)]
pub struct DifferenceRow {
    pub class: DiffClass,
    pub relative_path: RelativePath,
    pub kind: RowKind,
}

impl DifferenceRow {
    pub fn is_dir(&self) -> bool {
        matches!(self.kind, RowKind::DirectorySummary { .. })
    }
}

#[derive(Clone, Debug)]
pub struct ComparisonResult {
    pub left_root: String,
    pub right_root: String,
    pub mode: Mode,
    pub stats: ComparisonStats,
    pub left_directory_count: u64,
    pub right_directory_count: u64,
    pub rows: Vec<DifferenceRow>,
    pub encountered_metadata: Vec<MetadataMatch>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FinalVerdict {
    Match,
    Different,
}
