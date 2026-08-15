use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::model::{DirNode, FileEntry, RelativePath};

#[derive(Debug)]
pub struct ScanResult {
    pub display_root: String,
    pub tree: DirNode,
}

pub fn scan_root(path_text: &str, recurse: bool) -> Result<ScanResult, String> {
    let path = PathBuf::from(path_text);
    if !path.exists() {
        return Err(format!("Path not found: {}", path_text));
    }

    let metadata =
        fs::metadata(&path).map_err(|err| format!("Cannot access '{}': {}", path_text, err))?;
    if !metadata.is_dir() {
        return Err(format!("Path is not a directory: {}", path_text));
    }

    let display_root = fs::canonicalize(&path)
        .unwrap_or(path.clone())
        .to_string_lossy()
        .into_owned();
    let tree = scan_directory(&path, &display_root, RelativePath::root(), recurse)?;

    Ok(ScanResult { display_root, tree })
}

fn scan_directory(
    full_path: &Path,
    display_root: &str,
    relative_path: RelativePath,
    recurse: bool,
) -> Result<DirNode, String> {
    let entries = fs::read_dir(full_path).map_err(|err| {
        format!(
            "Cannot enumerate directory '{}': {}",
            full_path.to_string_lossy(),
            err
        )
    })?;

    let mut file_entries = Vec::new();
    let mut dir_entries = Vec::new();
    let mut file_names: BTreeMap<String, String> = BTreeMap::new();
    let mut dir_names: BTreeMap<String, String> = BTreeMap::new();

    for entry_result in entries {
        let entry = entry_result.map_err(|err| {
            format!(
                "Cannot enumerate directory '{}': {}",
                full_path.to_string_lossy(),
                err
            )
        })?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let file_type = entry.file_type().map_err(|err| {
            format!(
                "Cannot inspect entry '{}' beneath '{}': {}",
                name,
                full_path.to_string_lossy(),
                err
            )
        })?;
        let folded = name.to_lowercase();

        if file_type.is_file() {
            if let Some(existing) = file_names.insert(folded, name.clone()) {
                return Err(format!(
                    "Ambiguous case-insensitive filename collision in '{}': {}, {}",
                    full_path.to_string_lossy(),
                    existing,
                    name
                ));
            }
            let metadata = entry.metadata().map_err(|err| {
                format!(
                    "Cannot read file metadata for '{}' beneath '{}': {}",
                    name,
                    full_path.to_string_lossy(),
                    err
                )
            })?;
            file_entries.push(FileEntry {
                name: name.clone(),
                relative_path: relative_path.child(&name),
                size: metadata.len(),
            });
        } else if file_type.is_dir() && recurse {
            if let Some(existing) = dir_names.insert(folded, name.clone()) {
                return Err(format!(
                    "Ambiguous case-insensitive directory name collision in '{}': {}, {}",
                    full_path.to_string_lossy(),
                    existing,
                    name
                ));
            }
            dir_entries.push((name, entry.path()));
        }
    }

    file_entries.sort_by(|a, b| a.relative_path.cmp_case_insensitive(&b.relative_path));
    dir_entries.sort_by(|(a, _), (b, _)| {
        a.to_lowercase()
            .cmp(&b.to_lowercase())
            .then_with(|| a.cmp(b))
    });

    let mut dirs = Vec::new();
    for (name, path) in dir_entries {
        let child_relative = relative_path.child(&name);
        dirs.push(scan_directory(
            &path,
            display_root,
            child_relative,
            recurse,
        )?);
    }

    let _ = display_root;

    Ok(DirNode {
        relative_path,
        files: file_entries,
        dirs,
    })
}
