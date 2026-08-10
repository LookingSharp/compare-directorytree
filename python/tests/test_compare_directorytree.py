"""Validation tests for compare_directorytree.

These tests validate the acceptance scenarios in Section 10 and the
engineering and test invariants in Appendix B of
../../specs/Compare-DirectoryTree-Spec.md.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from compare_directorytree import compare_directory_tree, ComparisonError  # noqa: E402
from compare_directorytree.formatting import format_aggregate_byte_total  # noqa: E402
from compare_directorytree import metadata as metadata_module  # noqa: E402


def make_file(path: str, size: int = 0) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        if size:
            handle.seek(size - 1)
            handle.write(b"\0")


def summary_value(report, label: str) -> int:
    for line in report:
        if line.startswith(label):
            return int(line[len(label):].strip())
    raise AssertionError(f"Summary label not found: {label}")


def difference_rows(report):
    return [line for line in report if re.match(r"^(<<|>>|<>)\s", line)]


def verdict_line(report):
    for line in report:
        if line.startswith("RESULT:"):
            return line
    raise AssertionError("No verdict line found")


def collapsed_rows(report, contains: str):
    rows = []
    for line in difference_rows(report):
        collapsed = re.sub(r"\s+", " ", line).strip()
        if contains in collapsed:
            rows.append(collapsed)
    return rows


class CompareDirectoryTreeTestCase(unittest.TestCase):
    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="cdt-")
        self.left = os.path.join(self.base, "left")
        self.right = os.path.join(self.base, "right")
        os.makedirs(self.left)
        os.makedirs(self.right)

    def tearDown(self):
        shutil.rmtree(self.base, ignore_errors=True)

    def compare(self, **kwargs):
        kwargs.setdefault("no_color", True)
        return compare_directory_tree(self.left, self.right, **kwargs)

    # 10.1 Same ordinary files
    def test_10_1_same_ordinary_files(self):
        make_file(os.path.join(self.left, "IMG_1001.JPG"), 5000)
        make_file(os.path.join(self.left, "IMG_1002.JPG"), 6000)
        make_file(os.path.join(self.right, "IMG_1001.JPG"), 5000)
        make_file(os.path.join(self.right, "IMG_1002.JPG"), 6000)

        report = self.compare()

        self.assertEqual(summary_value(report, "Same:"), 2)
        self.assertEqual(summary_value(report, "Total differences:"), 0)
        self.assertEqual(summary_value(report, "Relevant differences:"), 0)
        self.assertEqual(verdict_line(report), "RESULT: MATCH - all 2 files match")
        self.assertEqual(difference_rows(report), [])

    # 10.2 File only on LEFT
    def test_10_2_file_only_on_left(self):
        make_file(os.path.join(self.left, "IMG_1003.JPG"), 4096)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertRegex(rows[0], r"^<<\s+IMG_1003\.JPG\s+4,096\s+<missing>$")
        self.assertEqual(summary_value(report, "LEFT only:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)

    # 10.3 File only on RIGHT
    def test_10_3_file_only_on_right(self):
        make_file(os.path.join(self.right, "IMG_1004.JPG"), 2048)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertRegex(rows[0], r"^>>\s+IMG_1004\.JPG\s+<missing>\s+2,048$")
        self.assertEqual(summary_value(report, "RIGHT only:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)

    # 10.4 Same filename, different size
    def test_10_4_same_filename_different_size(self):
        make_file(os.path.join(self.left, "IMG_1005.JPG"), 5238104)
        make_file(os.path.join(self.right, "IMG_1005.JPG"), 5238105)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertRegex(rows[0], r"^<>\s+IMG_1005\.JPG\s+5,238,104\s+5,238,105$")
        self.assertEqual(summary_value(report, "Different size:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)
        self.assertEqual(verdict_line(report), "RESULT: DIFFERENT - 1 relevant difference")

    # 10.5 Ignored metadata only
    def test_10_5_ignored_metadata_only(self):
        make_file(os.path.join(self.left, "IMG_1001.JPG"), 5000)
        make_file(os.path.join(self.right, "IMG_1001.JPG"), 5000)
        make_file(os.path.join(self.left, "Thumbs.db"), 81920)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertRegex(rows[0], r"^<<\s+Thumbs\.db\s+81,920\s+<missing>\s+Ignored: Windows thumbnail cache$")
        self.assertEqual(summary_value(report, "Total differences:"), 1)
        self.assertEqual(summary_value(report, "Ignored metadata differences:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 0)
        self.assertEqual(
            verdict_line(report), "RESULT: MATCH - qualified: differences limited to 1 ignored metadata file"
        )

    def test_appendix_a1_catalog_all_ignored(self):
        for name in ("Thumbs.db", "ehthumbs.db", "desktop.ini", ".DS_Store", ".directory"):
            self.assertTrue(metadata_module.is_ignored(name), f"{name} is an Appendix A.1 rule")

    def test_windows_metadata_names_case_insensitive(self):
        self.assertTrue(metadata_module.is_ignored("THUMBS.DB"))
        self.assertTrue(metadata_module.is_ignored("Desktop.INI"))

    def test_hidden_dotted_small_file_is_not_ignored(self):
        make_file(os.path.join(self.left, ".config"), 1)

        report = self.compare()

        self.assertEqual(summary_value(report, "Ignored metadata differences:"), 0)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)

    # 10.6 Recognized metadata that remains relevant
    def test_10_6_recognized_metadata_remains_relevant(self):
        make_file(os.path.join(self.right, "IMG_1006.xmp"), 512)

        report = self.compare()
        rows = difference_rows(report)

        self.assertTrue(rows[0].endswith("Recognized: XMP photo sidecar"))
        self.assertEqual(summary_value(report, "Ignored metadata differences:"), 0)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)
        self.assertTrue(verdict_line(report).startswith("RESULT: DIFFERENT"))

    def test_appendix_a2_catalog_all_relevant(self):
        for name in ("._IMG_1001.JPG", "IMG_1001.xmp", "IMG_1001.aae", "IMG_1001.pxd-sidecar", ".picasa.ini", "Picasa.ini"):
            classification = metadata_module.classify(name)
            self.assertIsNotNone(classification, f"{name} is an Appendix A.2 rule")
            self.assertEqual(classification.policy, "Relevant")

    def test_metadata_classification_deterministic_preservation_first(self):
        first = metadata_module.classify("._IMG_1001.xmp")
        second = metadata_module.classify("._IMG_1001.xmp")

        self.assertEqual(first.id, second.id)
        self.assertEqual(first.policy, "Relevant")

    # 10.7 Hidden or system ordinary file
    def test_10_7_hidden_file_included(self):
        make_file(os.path.join(self.left, "hidden.dat"), 10)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertRegex(rows[0], r"^<<\s+hidden\.dat\s")
        self.assertEqual(summary_value(report, "LEFT files:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 1)

    # 10.8 Both directories empty
    def test_10_8_both_empty(self):
        report = self.compare()

        self.assertEqual(summary_value(report, "LEFT files:"), 0)
        self.assertEqual(summary_value(report, "RIGHT files:"), 0)
        self.assertEqual(summary_value(report, "Total differences:"), 0)
        self.assertEqual(summary_value(report, "Relevant differences:"), 0)
        self.assertEqual(verdict_line(report), "RESULT: MATCH - all 0 files match")

    # 10.9 One directory empty
    def test_10_9_one_directory_empty(self):
        make_file(os.path.join(self.left, "a.txt"), 1)
        make_file(os.path.join(self.left, "b.txt"), 2)
        make_file(os.path.join(self.left, "Thumbs.db"), 3)

        report = self.compare()
        rows = difference_rows(report)

        self.assertEqual(len(rows), 3)
        self.assertEqual(len([r for r in rows if r.startswith("<<")]), 3)
        self.assertEqual(summary_value(report, "LEFT only:"), 3)
        self.assertEqual(summary_value(report, "Ignored metadata differences:"), 1)
        self.assertEqual(summary_value(report, "Relevant differences:"), 2)

    # 10.10 Case-insensitive collision
    def test_10_10_case_insensitive_collision(self):
        make_file(os.path.join(self.left, "IMG_1001.JPG"), 10)
        try:
            make_file(os.path.join(self.left, "img_1001.jpg"), 20)
        except OSError:
            self.skipTest("case-insensitive filesystem cannot hold both names")

        if len(os.listdir(self.left)) < 2:
            self.skipTest("filesystem is case-insensitive; collision cannot be created")

        with self.assertRaises(ComparisonError) as ctx:
            self.compare()
        self.assertIn("case-insensitive", str(ctx.exception).lower())

    # 10.11 Invalid, inaccessible, or unenumerable input
    def test_10_11_path_not_found(self):
        with self.assertRaises(ComparisonError) as ctx:
            compare_directory_tree(os.path.join(self.left, "missing"), self.right, no_color=True)
        self.assertIn("Path not found", str(ctx.exception))

    def test_10_11_path_not_a_directory(self):
        file_path = os.path.join(self.left, "a.txt")
        make_file(file_path, 1)

        with self.assertRaises(ComparisonError) as ctx:
            compare_directory_tree(file_path, self.right, no_color=True)
        self.assertIn("not a directory", str(ctx.exception))

    @unittest.skipIf(os.name == "nt" or os.geteuid() == 0, "requires POSIX permissions and non-root user")
    def test_10_11_enumeration_denied(self):
        denied = os.path.join(self.left, "denied")
        os.makedirs(denied)
        os.chmod(denied, 0o000)
        try:
            with self.assertRaises(ComparisonError) as ctx:
                compare_directory_tree(self.left, self.right, recurse=True, no_color=True)
            self.assertIn(denied, str(ctx.exception))
        finally:
            os.chmod(denied, 0o755)

    def test_10_11_excessively_deep_tree_fails_clearly(self):
        from unittest import mock

        from compare_directorytree import report as report_module

        with mock.patch.object(report_module, "build_directory_node", side_effect=RecursionError()):
            with self.assertRaises(ComparisonError) as ctx:
                compare_directory_tree(self.left, self.right, recurse=True, no_color=True)
        self.assertIn("too deeply nested", str(ctx.exception))

    # 10.12 Verbose metadata explanation
    def test_10_12_explains_each_type_once(self):
        make_file(os.path.join(self.left, "Thumbs.db"), 1)
        make_file(os.path.join(self.left, ".DS_Store"), 2)
        make_file(os.path.join(self.right, "Thumbs.db"), 3)
        make_file(os.path.join(self.right, ".DS_Store"), 4)
        make_file(os.path.join(self.left, "ehthumbs.db"), 5)

        report = self.compare(explain_metadata=True)

        self.assertEqual(len([line for line in report if "WIN-THUMBS" in line]), 1)
        self.assertEqual(len([line for line in report if "MAC-DSSTORE" in line]), 1)
        self.assertEqual(len([line for line in report if "WIN-EHTHUMBS" in line]), 1)

    def test_10_12_does_not_describe_unencountered_types(self):
        make_file(os.path.join(self.left, "Thumbs.db"), 1)
        make_file(os.path.join(self.right, "Thumbs.db"), 3)

        report = self.compare(explain_metadata=True)

        self.assertFalse(any("PHOTO-XMP" in line for line in report))
        self.assertFalse(any("KDE-DIRECTORY" in line for line in report))

    def test_10_12_normal_rows_unchanged(self):
        make_file(os.path.join(self.left, "Thumbs.db"), 1)
        make_file(os.path.join(self.right, "Thumbs.db"), 3)

        plain = difference_rows(self.compare())
        explained = difference_rows(self.compare(explain_metadata=True))

        self.assertEqual(plain, explained)

    def test_10_12_omits_section_by_default(self):
        make_file(os.path.join(self.left, "Thumbs.db"), 1)
        make_file(os.path.join(self.right, "Thumbs.db"), 3)

        report = self.compare()

        self.assertNotIn("METADATA EXPLANATIONS", report)

    # Section 5 / Appendix B report model
    def test_report_model_basics(self):
        make_file(os.path.join(self.left, "same.txt"), 10)
        make_file(os.path.join(self.right, "same.txt"), 10)
        make_file(os.path.join(self.left, "left-only.txt"), 11)
        make_file(os.path.join(self.right, "right-only.txt"), 12)
        make_file(os.path.join(self.left, "both.txt"), 13)
        make_file(os.path.join(self.right, "both.txt"), 14)

        report = self.compare()

        self.assertIn(f"LEFT : {os.path.abspath(self.left)}", report)
        self.assertIn(f"RIGHT: {os.path.abspath(self.right)}", report)

        classes = [row[:2] for row in difference_rows(report)]
        self.assertEqual(classes, ["<<", ">>", "<>"])

        self.assertFalse(any("same.txt" in row for row in difference_rows(report)))

        self.assertIn("Legend:", report)
        self.assertIn("  <<   Exists only on LEFT", report)
        self.assertIn("  >>   Exists only on RIGHT", report)
        self.assertIn("  <>   Same filename, different size", report)
        self.assertEqual(len([line for line in report if line.startswith("RESULT:")]), 1)

        for line in report:
            self.assertNotIn("\n", line)
            self.assertNotIn("\r", line)
            for ch in line:
                self.assertTrue(32 <= ord(ch) <= 126, f"non-ASCII character in: {line!r}")

        self.assertFalse(any("identical" in line for line in report))

    def test_does_not_truncate_long_filenames(self):
        long_name = ("x" * 120) + ".txt"
        make_file(os.path.join(self.left, long_name), 1)

        report = self.compare()

        self.assertTrue(any(long_name in line for line in report))

    def test_deterministic_sort_within_class(self):
        for name in ("c.txt", "a.txt", "b.txt"):
            make_file(os.path.join(self.left, name), 1)

        first = [row for row in difference_rows(self.compare()) if row.startswith("<<")]
        second = [row for row in difference_rows(self.compare()) if row.startswith("<<")]

        self.assertEqual(first, second)
        joined = "\n".join(first)
        self.assertLess(joined.index("a.txt"), joined.index("b.txt"))
        self.assertLess(joined.index("b.txt"), joined.index("c.txt"))

    def test_never_modifies_input_directories(self):
        make_file(os.path.join(self.left, "same.txt"), 10)
        make_file(os.path.join(self.right, "same.txt"), 10)

        def snapshot(path):
            result = []
            for root, dirs, files in os.walk(path):
                for name in files:
                    full = os.path.join(root, name)
                    result.append((full, os.path.getsize(full)))
            return sorted(result)

        before_left = snapshot(self.left)
        before_right = snapshot(self.right)

        self.compare(recurse=True, explain_metadata=True)

        self.assertEqual(snapshot(self.left), before_left)
        self.assertEqual(snapshot(self.right), before_right)

    def test_does_not_traverse_subdirectories_without_recurse(self):
        make_file(os.path.join(self.left, "sub", "deep.txt"), 99)

        report = self.compare()

        self.assertFalse(any("deep.txt" in row for row in difference_rows(report)))

    # 10.15 Verdict vocabulary and Type column
    def test_10_15_match_and_different_verdicts(self):
        for name in ("one.txt", "two.txt"):
            make_file(os.path.join(self.left, name), 10)
            make_file(os.path.join(self.right, name), 10)

        match_report = self.compare()
        make_file(os.path.join(self.left, "extra.txt"), 1)
        different_report = self.compare()

        self.assertEqual(verdict_line(match_report), "RESULT: MATCH - all 2 files match")
        self.assertEqual(verdict_line(different_report), "RESULT: DIFFERENT - 1 relevant difference")

    def test_10_15_exact_match_search_does_not_match_different(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        report = self.compare()

        self.assertFalse(any("RESULT: MATCH" in line for line in report))
        self.assertFalse(any("NOT THE SAME" in line for line in report))

    def test_10_15_type_column_dir_and_blank(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        os.makedirs(os.path.join(self.left, "OnlyHere"))

        report = self.compare(recurse=True)
        rows = difference_rows(report)

        dir_row = next(row for row in rows if "OnlyHere" in row)
        file_row = next(row for row in rows if "extra.txt" in row)

        self.assertTrue(dir_row.startswith("<<  DIR   "))
        self.assertTrue(file_row.startswith("<<        "))
        for row in rows:
            self.assertNotEqual(row[4:8], "FILE")
        self.assertFalse(any("[DIR]" in line for line in report))

    def test_10_15_directory_and_file_paths_share_column(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        os.makedirs(os.path.join(self.left, "OnlyHere"))

        rows = difference_rows(self.compare(recurse=True))

        for row in rows:
            self.assertRegex(row[:10], r"^(<<|>>|<>)  (DIR |    )  $")

    # 10.16 Report formatting determinism
    def test_10_16_aggregate_byte_total_formatting(self):
        self.assertEqual(format_aggregate_byte_total(0), "0 B")
        self.assertEqual(format_aggregate_byte_total(81), "81 B")
        self.assertEqual(format_aggregate_byte_total(1023), "1023 B")
        self.assertEqual(format_aggregate_byte_total(1024), "1 KB")
        self.assertEqual(format_aggregate_byte_total(81920), "80 KB")
        self.assertEqual(format_aggregate_byte_total(8375186227), "7.8 GB")

    def test_10_16_aggregate_byte_total_rounds_up_to_next_unit(self):
        # A value that rounds to 1024 of a unit must bump to the next unit
        # rather than displaying e.g. "1024 KB".
        self.assertEqual(format_aggregate_byte_total(1048575), "1 MB")
        self.assertEqual(format_aggregate_byte_total(1073741823), "1 GB")

    def test_10_16_directory_summary_vs_file_size_formatting(self):
        make_file(os.path.join(self.left, "Cache", "big.bin"), 81920)
        os.makedirs(os.path.join(self.left, "Empty"))
        make_file(os.path.join(self.left, "plain.bin"), 81920)

        report = self.compare(recurse=True)

        self.assertEqual(collapsed_rows(report, "Cache/"), ["<< DIR Cache/ 1 file, 0 dirs, 80 KB"])
        self.assertEqual(collapsed_rows(report, "Empty/"), ["<< DIR Empty/ 0 files, 0 dirs, 0 B"])
        self.assertEqual(collapsed_rows(report, "plain.bin"), ["<< plain.bin 81,920 <missing>"])

    def test_10_16_legend_dir_line_only_when_present(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        without_dir = self.compare()

        os.makedirs(os.path.join(self.left, "Empty"))
        with_dir = self.compare(recurse=True)

        self.assertNotIn("  DIR  Directory summary row", without_dir)
        self.assertIn("  DIR  Directory summary row", with_dir)

    def test_10_16_always_lists_three_markers(self):
        make_file(os.path.join(self.left, "only-left.txt"), 1)
        report = self.compare()

        self.assertFalse(any(row.startswith(">>") or row.startswith("<>") for row in difference_rows(report)))
        self.assertIn("  <<   Exists only on LEFT", report)
        self.assertIn("  >>   Exists only on RIGHT", report)
        self.assertIn("  <>   Same filename, different size", report)

    def test_10_16_omits_differences_section_when_empty(self):
        report = self.compare(recurse=True)

        self.assertNotIn("DIFFERENCES", report)
        self.assertNotIn("Legend:", report)
        self.assertFalse(any("File / Directory" in line for line in report))

    def test_10_16_legend_wording_switches_with_recurse(self):
        make_file(os.path.join(self.left, "diff.txt"), 1)
        make_file(os.path.join(self.right, "diff.txt"), 2)

        self.assertIn("  <>   Same filename, different size", self.compare())
        self.assertIn("  <>   Same relative path, different size", self.compare(recurse=True))

    def test_10_16_directory_block_only_under_recurse(self):
        os.makedirs(os.path.join(self.left, "Empty"))

        flat = self.compare()
        recursive = self.compare(recurse=True)

        self.assertFalse(any(line.startswith("LEFT directories:") for line in flat))
        self.assertFalse(any(line.startswith("Structural differences:") for line in flat))
        for label in (
            "LEFT directories:",
            "RIGHT directories:",
            "LEFT-only directories:",
            "RIGHT-only directories:",
            "Empty-directory differences:",
            "Structural differences:",
        ):
            self.assertTrue(any(line.startswith(label) for line in recursive), label)

    def test_10_16_empty_directory_differences_not_folded_into_structural(self):
        os.makedirs(os.path.join(self.left, "Empty"))
        make_file(os.path.join(self.left, "Full", "a.txt"), 1)

        report = self.compare(recurse=True)

        self.assertEqual(summary_value(report, "LEFT-only directories:"), 2)
        self.assertEqual(summary_value(report, "Empty-directory differences:"), 1)
        self.assertEqual(summary_value(report, "Structural differences:"), 2)

    def test_10_16_structural_differences_excluded_from_file_counters(self):
        os.makedirs(os.path.join(self.left, "Empty"))

        report = self.compare(recurse=True)

        self.assertEqual(summary_value(report, "Total differences:"), 0)
        self.assertEqual(summary_value(report, "Ignored metadata differences:"), 0)
        self.assertEqual(summary_value(report, "Relevant differences:"), 0)

    def test_10_16_verdict_segment_order_and_zero_omission(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        make_file(os.path.join(self.left, "Thumbs.db"), 1)
        os.makedirs(os.path.join(self.left, "Empty"))
        make_file(os.path.join(self.left, "Full", "a.txt"), 1)

        verdict = verdict_line(self.compare(recurse=True))

        self.assertEqual(
            verdict,
            "RESULT: DIFFERENT - 2 relevant differences | 1 empty-subdirectory difference "
            "| 1 directory-structure difference | 1 ignored metadata difference",
        )
        self.assertNotIn("| 0 ", verdict)

    def test_10_16_structural_verdict_segments_sum_to_structural_counter(self):
        make_file(os.path.join(self.left, "extra.txt"), 1)
        os.makedirs(os.path.join(self.left, "Empty"))
        make_file(os.path.join(self.left, "Full", "Deep", "a.txt"), 1)

        report = self.compare(recurse=True)
        verdict = verdict_line(report)

        empty = int(re.search(r"(\d+) empty-subdirectory", verdict).group(1))
        structural = int(re.search(r"(\d+) directory-structure", verdict).group(1))
        self.assertEqual(empty + structural, summary_value(report, "Structural differences:"))

    # 10.13 Recursive comparison behaviors
    def test_10_13_default_mode_collapses_missing_subtree(self):
        make_file(os.path.join(self.left, "Raw", "Nested", "a.cr2"), 5000)
        make_file(os.path.join(self.left, "Raw", "b.cr2"), 3000)

        report = self.compare(recurse=True)
        rows = difference_rows(report)

        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0].startswith("<<  DIR   Raw/"))
        self.assertIn("2 files, 1 dir, 7.8 KB", rows[0])

    def test_10_13_empty_one_sided_directory_reports_zero_counts(self):
        os.makedirs(os.path.join(self.left, "Empty"))

        report = self.compare(recurse=True)

        self.assertEqual(collapsed_rows(report, "Empty/"), ["<< DIR Empty/ 0 files, 0 dirs, 0 B"])

    def test_10_13_metadata_only_subtree_not_relevant(self):
        make_file(os.path.join(self.left, "Cache", "Thumbs.db"), 81920)

        report = self.compare(recurse=True)

        self.assertEqual(summary_value(report, "Relevant differences:"), 0)
        self.assertTrue(verdict_line(report).startswith("RESULT: MATCH - qualified:"))
        self.assertIn("ignored metadata 1", " ".join(collapsed_rows(report, "Cache/")))

    def test_10_13_shared_directory_reports_individual_files_in_default_mode(self):
        make_file(os.path.join(self.left, "Shared", "a.txt"), 1)
        make_file(os.path.join(self.right, "Shared", "a.txt"), 2)

        report = self.compare(recurse=True)
        rows = difference_rows(report)

        self.assertTrue(any(row.startswith("<>") and "Shared/a.txt" in row for row in rows))

    def test_10_13_compact_mode_summarizes_shared_directory(self):
        make_file(os.path.join(self.left, "Shared", "a.txt"), 1)
        make_file(os.path.join(self.right, "Shared", "a.txt"), 1)
        make_file(os.path.join(self.left, "Shared", "b.txt"), 1)
        make_file(os.path.join(self.right, "Shared", "b.txt"), 2)

        report = self.compare(recurse=True, compact=True)
        rows = collapsed_rows(report, "Shared/")

        self.assertEqual(rows, ["<> DIR Shared/ 1 same | << 0 | >> 0 | <> 1"])

    def test_10_13_compact_retains_collapsed_one_sided_subtree(self):
        make_file(os.path.join(self.left, "Raw", "a.cr2"), 1)

        report = self.compare(recurse=True, compact=True)
        rows = difference_rows(report)

        self.assertTrue(any(row.startswith("<<  DIR   Raw/") for row in rows))

    def test_10_13_expand_missing_subtrees_reports_individual_files(self):
        make_file(os.path.join(self.left, "Raw", "Nested", "a.cr2"), 5000)

        report = self.compare(recurse=True, expand_missing_subtrees=True)
        rows = difference_rows(report)

        self.assertTrue(any("Raw/Nested/a.cr2" in row for row in rows))
        self.assertFalse(any(row.startswith("<<  DIR   Raw/") and "files," in row for row in rows))

    def test_10_13_expand_missing_subtrees_reports_empty_descendant_directories(self):
        make_file(os.path.join(self.left, "Raw", "a.cr2"), 1)
        os.makedirs(os.path.join(self.left, "Raw", "Empty"))

        report = self.compare(recurse=True, expand_missing_subtrees=True)
        rows = difference_rows(report)

        self.assertTrue(any("Raw/Empty/" in row and "0 files, 0 dirs, 0 B" in row for row in rows))

    def test_10_13_compact_and_expand_missing_subtrees_conflict(self):
        with self.assertRaises(ComparisonError):
            self.compare(recurse=True, compact=True, expand_missing_subtrees=True)

    def test_10_13_recursive_switches_require_recurse(self):
        with self.assertRaises(ComparisonError):
            self.compare(compact=True)
        with self.assertRaises(ComparisonError):
            self.compare(expand_missing_subtrees=True)

    # 10.14 Console color
    def test_10_14_no_color_matches_plain_semantics(self):
        make_file(os.path.join(self.left, "a.txt"), 1)
        make_file(os.path.join(self.left, "Thumbs.db"), 2)

        report = self.compare(no_color=True)

        for line in report:
            self.assertNotIn("\x1b[", line)

    def test_10_14_color_output_contains_markers_when_forced(self):
        make_file(os.path.join(self.left, "a.txt"), 1)

        class FakeStream:
            def isatty(self):
                return True

        report = compare_directory_tree(self.left, self.right, no_color=False, stream=FakeStream())

        self.assertTrue(any("\x1b[36m<<\x1b[0m" in line for line in report))
        verdict = next(line for line in report if "RESULT:" in line)
        self.assertIn("\x1b[31mDIFFERENT\x1b[0m", verdict)

    def test_10_14_match_verdict_colored_green(self):
        class FakeStream:
            def isatty(self):
                return True

        report = compare_directory_tree(self.left, self.right, no_color=False, stream=FakeStream())
        verdict = next(line for line in report if "RESULT:" in line)
        self.assertIn("\x1b[32mMATCH\x1b[0m", verdict)


if __name__ == "__main__":
    unittest.main()
