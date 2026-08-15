use std::collections::HashSet;

use crate::catalog;
use crate::format::{format_directory_summary, format_exact_bytes};
use crate::model::{
    ComparisonResult, ComparisonStats, DiffClass, DifferenceRow, DirNode, FileEntry, MetadataMatch,
    Mode, RelativePath, RowKind, SubtreeStats,
};

struct ComparisonContext {
    mode: Mode,
    stats: ComparisonStats,
    rows: Vec<DifferenceRow>,
    encountered_ids: HashSet<&'static str>,
    encountered_metadata: Vec<MetadataMatch>,
}

impl ComparisonContext {
    fn new(mode: Mode) -> Self {
        Self {
            mode,
            stats: ComparisonStats::default(),
            rows: Vec::new(),
            encountered_ids: HashSet::new(),
            encountered_metadata: Vec::new(),
        }
    }

    fn remember_metadata(&mut self, metadata: MetadataMatch) {
        if self.encountered_ids.insert(metadata.id) {
            self.encountered_metadata.push(metadata);
        }
    }

    fn add_file_row(
        &mut self,
        class: DiffClass,
        relative_path: RelativePath,
        file_name: &str,
        left_size: Option<u64>,
        right_size: Option<u64>,
    ) {
        let metadata = catalog::classify(file_name);
        if let Some(metadata) = metadata {
            self.remember_metadata(metadata);
        }
        let note = metadata.map(MetadataMatch::note);
        self.rows.push(DifferenceRow {
            class,
            relative_path,
            kind: RowKind::File {
                left_size,
                right_size,
                note,
            },
        });
    }

    fn add_directory_row(
        &mut self,
        class: DiffClass,
        relative_path: RelativePath,
        summary: String,
    ) {
        self.rows.push(DifferenceRow {
            class,
            relative_path,
            kind: RowKind::DirectorySummary { summary },
        });
    }
}

pub fn compare_trees(
    left_root: String,
    left: &DirNode,
    right_root: String,
    right: &DirNode,
    mode: Mode,
) -> ComparisonResult {
    let mut context = ComparisonContext::new(mode);
    compare_directory_pair(left, right, &mut context);

    let left_stats = left.subtree_stats(&catalog::is_ignored);
    let right_stats = right.subtree_stats(&catalog::is_ignored);
    context.stats.left_files = left_stats.file_count;
    context.stats.right_files = right_stats.file_count;

    context.rows.sort_by(|a, b| {
        class_rank(a.class)
            .cmp(&class_rank(b.class))
            .then_with(|| a.relative_path.cmp_case_insensitive(&b.relative_path))
    });

    ComparisonResult {
        left_root,
        right_root,
        mode,
        stats: context.stats,
        left_directory_count: left_stats.directory_count,
        right_directory_count: right_stats.directory_count,
        rows: context.rows,
        encountered_metadata: context.encountered_metadata,
    }
}

fn class_rank(class: DiffClass) -> u8 {
    match class {
        DiffClass::LeftOnly => 0,
        DiffClass::RightOnly => 1,
        DiffClass::DifferentSize => 2,
    }
}

fn compare_directory_pair(left: &DirNode, right: &DirNode, context: &mut ComparisonContext) {
    let mut direct_same = 0u64;
    let mut direct_left_only = 0u64;
    let mut direct_right_only = 0u64;
    let mut direct_different = 0u64;
    let mut direct_ignored = 0u64;
    let mut direct_rows = Vec::new();

    let mut left_index = 0usize;
    let mut right_index = 0usize;

    while left_index < left.files.len() || right_index < right.files.len() {
        match match_file_order(left.files.get(left_index), right.files.get(right_index)) {
            MatchOrder::Both(left_file, right_file) => {
                if left_file.size == right_file.size {
                    context.stats.same += 1;
                    direct_same += 1;
                } else {
                    context.stats.different_size += 1;
                    direct_different += 1;
                    let metadata = catalog::classify(&left_file.name);
                    if let Some(metadata) = metadata {
                        context.remember_metadata(metadata);
                    }
                    if metadata.is_some_and(MetadataMatch::is_ignored) {
                        context.stats.ignored += 1;
                        direct_ignored += 1;
                    }
                    direct_rows.push((
                        DiffClass::DifferentSize,
                        left_file.relative_path.clone(),
                        left_file.name.clone(),
                        Some(left_file.size),
                        Some(right_file.size),
                    ));
                }
                left_index += 1;
                right_index += 1;
            }
            MatchOrder::LeftOnly(left_file) => {
                context.stats.left_only += 1;
                direct_left_only += 1;
                let metadata = catalog::classify(&left_file.name);
                if let Some(metadata) = metadata {
                    context.remember_metadata(metadata);
                }
                if metadata.is_some_and(MetadataMatch::is_ignored) {
                    context.stats.ignored += 1;
                    direct_ignored += 1;
                }
                direct_rows.push((
                    DiffClass::LeftOnly,
                    left_file.relative_path.clone(),
                    left_file.name.clone(),
                    Some(left_file.size),
                    None,
                ));
                left_index += 1;
            }
            MatchOrder::RightOnly(right_file) => {
                context.stats.right_only += 1;
                direct_right_only += 1;
                let metadata = catalog::classify(&right_file.name);
                if let Some(metadata) = metadata {
                    context.remember_metadata(metadata);
                }
                if metadata.is_some_and(MetadataMatch::is_ignored) {
                    context.stats.ignored += 1;
                    direct_ignored += 1;
                }
                direct_rows.push((
                    DiffClass::RightOnly,
                    right_file.relative_path.clone(),
                    right_file.name.clone(),
                    None,
                    Some(right_file.size),
                ));
                right_index += 1;
            }
        }
    }

    if matches!(context.mode, Mode::Compact) {
        if !direct_rows.is_empty() {
            let mut summary = format!(
                "{} same | << {} | >> {} | <> {}",
                direct_same, direct_left_only, direct_right_only, direct_different
            );
            if direct_ignored > 0 {
                summary.push_str(&format!(" | ignored {}", direct_ignored));
            }
            context.add_directory_row(
                DiffClass::DifferentSize,
                left.relative_path.clone(),
                summary,
            );
        }
    } else {
        for (class, path, file_name, left_size, right_size) in direct_rows {
            context.add_file_row(class, path, &file_name, left_size, right_size);
        }
    }

    if !context.mode.recurse() {
        return;
    }

    let mut left_dir_index = 0usize;
    let mut right_dir_index = 0usize;
    while left_dir_index < left.dirs.len() || right_dir_index < right.dirs.len() {
        match match_dir_order(
            left.dirs.get(left_dir_index),
            right.dirs.get(right_dir_index),
        ) {
            MatchDirOrder::Both(left_dir, right_dir) => {
                compare_directory_pair(left_dir, right_dir, context);
                left_dir_index += 1;
                right_dir_index += 1;
            }
            MatchDirOrder::LeftOnly(left_dir) => {
                add_one_sided_subtree(left_dir, DiffClass::LeftOnly, context);
                left_dir_index += 1;
            }
            MatchDirOrder::RightOnly(right_dir) => {
                add_one_sided_subtree(right_dir, DiffClass::RightOnly, context);
                right_dir_index += 1;
            }
        }
    }
}

fn add_one_sided_subtree(node: &DirNode, class: DiffClass, context: &mut ComparisonContext) {
    let subtree = node.subtree_stats(&catalog::is_ignored);
    let represented_directories = 1 + subtree.directory_count;
    match class {
        DiffClass::LeftOnly => {
            context.stats.left_only += subtree.file_count;
            context.stats.left_only_directories += represented_directories;
        }
        DiffClass::RightOnly => {
            context.stats.right_only += subtree.file_count;
            context.stats.right_only_directories += represented_directories;
        }
        DiffClass::DifferentSize => {}
    }
    context.stats.ignored += subtree.ignored_count;
    context.stats.empty_directory_differences += node.empty_leaf_count(true);

    let mut files = Vec::new();
    node.collect_files(&mut files);
    for file in &files {
        if let Some(metadata) = catalog::classify(&file.name) {
            context.remember_metadata(metadata);
        }
    }

    match context.mode {
        Mode::ExpandMissingSubtrees => add_expanded_subtree(node, class, context, files),
        Mode::Flat | Mode::RecursiveDefault | Mode::Compact => {
            let summary = summarize_subtree(&subtree);
            context.add_directory_row(class, node.relative_path.clone(), summary);
        }
    }
}

fn add_expanded_subtree(
    node: &DirNode,
    class: DiffClass,
    context: &mut ComparisonContext,
    mut files: Vec<&FileEntry>,
) {
    files.sort_by(|a, b| a.relative_path.cmp_case_insensitive(&b.relative_path));
    for file in files {
        let (left_size, right_size) = match class {
            DiffClass::LeftOnly => (Some(file.size), None),
            DiffClass::RightOnly => (None, Some(file.size)),
            DiffClass::DifferentSize => continue,
        };
        context.add_file_row(
            class,
            file.relative_path.clone(),
            &file.name,
            left_size,
            right_size,
        );
    }

    let mut empty_dirs = Vec::new();
    node.collect_empty_leaf_dirs(true, &mut empty_dirs);
    empty_dirs.sort_by(|a, b| a.relative_path.cmp_case_insensitive(&b.relative_path));
    for dir in empty_dirs {
        let stats = dir.subtree_stats(&catalog::is_ignored);
        context.add_directory_row(class, dir.relative_path.clone(), summarize_subtree(&stats));
    }
}

fn summarize_subtree(stats: &SubtreeStats) -> String {
    format_directory_summary(
        stats.file_count,
        stats.directory_count,
        stats.byte_count,
        stats.ignored_count,
    )
}

enum MatchOrder<'a> {
    Both(&'a FileEntry, &'a FileEntry),
    LeftOnly(&'a FileEntry),
    RightOnly(&'a FileEntry),
}

fn match_file_order<'a>(
    left: Option<&'a FileEntry>,
    right: Option<&'a FileEntry>,
) -> MatchOrder<'a> {
    match (left, right) {
        (Some(left), Some(right)) => {
            let ordering = left.name.to_lowercase().cmp(&right.name.to_lowercase());
            if ordering.is_eq() {
                MatchOrder::Both(left, right)
            } else if ordering.is_lt() {
                MatchOrder::LeftOnly(left)
            } else {
                MatchOrder::RightOnly(right)
            }
        }
        (Some(left), None) => MatchOrder::LeftOnly(left),
        (None, Some(right)) => MatchOrder::RightOnly(right),
        (None, None) => unreachable!("file order called without inputs"),
    }
}

enum MatchDirOrder<'a> {
    Both(&'a DirNode, &'a DirNode),
    LeftOnly(&'a DirNode),
    RightOnly(&'a DirNode),
}

fn match_dir_order<'a>(left: Option<&'a DirNode>, right: Option<&'a DirNode>) -> MatchDirOrder<'a> {
    match (left, right) {
        (Some(left), Some(right)) => {
            let left_name = left.relative_path.file_name().unwrap_or("");
            let right_name = right.relative_path.file_name().unwrap_or("");
            let ordering = left_name.to_lowercase().cmp(&right_name.to_lowercase());
            if ordering.is_eq() {
                MatchDirOrder::Both(left, right)
            } else if ordering.is_lt() {
                MatchDirOrder::LeftOnly(left)
            } else {
                MatchDirOrder::RightOnly(right)
            }
        }
        (Some(left), None) => MatchDirOrder::LeftOnly(left),
        (None, Some(right)) => MatchDirOrder::RightOnly(right),
        (None, None) => unreachable!("directory order called without inputs"),
    }
}

pub fn render_file_size(size: Option<u64>) -> String {
    match size {
        Some(value) => format_exact_bytes(value),
        None => "<missing>".to_string(),
    }
}
