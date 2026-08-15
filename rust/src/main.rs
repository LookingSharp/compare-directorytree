mod catalog;
mod color;
mod compare;
mod format;
mod model;
mod report;
mod scan;

use std::env;
use std::process::ExitCode;

use compare::compare_trees;
use model::Mode;
use report::render_report;
use scan::scan_root;

#[derive(Debug, Default)]
struct Options {
    left: String,
    right: String,
    mode: Mode,
    explain_metadata: bool,
    no_color: bool,
    help: bool,
}

fn main() -> ExitCode {
    match parse_args(env::args().skip(1).collect()) {
        Ok(options) if options.help => {
            print_help();
            ExitCode::SUCCESS
        }
        Ok(options) => match run(options) {
            Ok(code) => code,
            Err(message) => {
                eprintln!("Error: {}", message);
                ExitCode::from(2)
            }
        },
        Err(message) => {
            eprintln!("Error: {}", message);
            eprintln!();
            print_usage_to_stderr();
            ExitCode::from(2)
        }
    }
}

fn run(options: Options) -> Result<ExitCode, String> {
    let left = scan_root(&options.left, options.mode.recurse())?;
    let right = scan_root(&options.right, options.mode.recurse())?;
    let result = compare_trees(
        left.display_root,
        &left.tree,
        right.display_root,
        &right.tree,
        options.mode,
    );
    let rendered = render_report(&result, options.explain_metadata);
    let lines = if color::should_color(options.no_color) {
        color::colorize_lines(&rendered.lines)
    } else {
        rendered.lines
    };
    for line in lines {
        println!("{}", line);
    }
    Ok(match rendered.verdict {
        model::FinalVerdict::Match => ExitCode::SUCCESS,
        model::FinalVerdict::Different => ExitCode::from(1),
    })
}

fn parse_args(args: Vec<String>) -> Result<Options, String> {
    let mut options = Options {
        mode: Mode::Flat,
        ..Options::default()
    };
    let mut saw_recurse = false;
    let mut saw_compact = false;
    let mut saw_expand = false;
    let mut positional = Vec::new();
    let mut parsing_flags = true;

    for arg in args {
        if parsing_flags && arg == "--" {
            parsing_flags = false;
            continue;
        }
        if parsing_flags && arg.starts_with('-') {
            match arg.as_str() {
                "-h" | "--help" => options.help = true,
                "--recurse" => saw_recurse = true,
                "--compact" => saw_compact = true,
                "--expand-missing-subtrees" => saw_expand = true,
                "--explain-metadata" => options.explain_metadata = true,
                "--no-color" => options.no_color = true,
                _ => return Err(format!("Unknown option: {}", arg)),
            }
        } else {
            positional.push(arg);
        }
    }

    if options.help {
        return Ok(options);
    }

    if positional.len() != 2 {
        return Err("Expected exactly two directory paths.".to_string());
    }

    if saw_compact && saw_expand {
        return Err("--compact and --expand-missing-subtrees cannot be combined.".to_string());
    }
    if saw_compact && !saw_recurse {
        return Err("--compact requires --recurse.".to_string());
    }
    if saw_expand && !saw_recurse {
        return Err("--expand-missing-subtrees requires --recurse.".to_string());
    }
    options.mode = if saw_compact {
        Mode::Compact
    } else if saw_expand {
        Mode::ExpandMissingSubtrees
    } else if saw_recurse {
        Mode::RecursiveDefault
    } else {
        Mode::Flat
    };

    options.left = positional.remove(0);
    options.right = positional.remove(0);
    Ok(options)
}

fn print_help() {
    println!("compare-directorytree\n");
    print_usage();
    println!();
    println!("Options:");
    println!("  --recurse                   Compare all descendant files and directories");
    println!(
        "  --compact                   Recursive mode: summarize shared-directory file differences"
    );
    println!(
        "  --expand-missing-subtrees   Recursive mode: expand one-sided subtrees file by file"
    );
    println!("  --explain-metadata          Explain encountered metadata types after the report");
    println!("  --no-color                  Disable ANSI color even on an interactive terminal");
    println!("  -h, --help                  Show this help text");
    println!();
    println!("Exit codes: 0 = MATCH, 1 = DIFFERENT, 2 = usage or error");
}

fn print_usage() {
    println!("Usage: compare-directorytree <left-path> <right-path> [--recurse] [--compact | --expand-missing-subtrees] [--explain-metadata] [--no-color]");
}

fn print_usage_to_stderr() {
    eprintln!("Usage: compare-directorytree <left-path> <right-path> [--recurse] [--compact | --expand-missing-subtrees] [--explain-metadata] [--no-color]");
}
