#!/usr/bin/env bash
# Smoke tests for the asm/ implementation, covering the Section 10
# acceptance scenarios in scope for this version (see ../README.md).
#
# Usage: tests/run-tests.sh [path-to-main.exe]
# Defaults to ../src/main.exe relative to this script.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXE="${1:-$SCRIPT_DIR/../src/main.exe}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
PASS_COUNT=0

# run_prog LEFT RIGHT -> sets RC and OUT (stdout+stderr combined)
run_prog() {
    local left="$1" right="$2"
    if command -v wine >/dev/null 2>&1; then
        # Wine's own top-level exit code is unreliable (see asm/README.md);
        # use cmd.exe's %errorlevel% instead, which reliably reflects the
        # target program's actual exit code.
        local leftw rightw
        leftw="$(winepath -w "$left" 2>/dev/null)"
        rightw="$(winepath -w "$right" 2>/dev/null)"
        OUT="$(cd "$(dirname "$EXE")" && wine cmd /c "$(basename "$EXE") $leftw $rightw & echo RC=%errorlevel%" 2>/dev/null)"
        RC="$(printf '%s\n' "$OUT" | grep -o 'RC=-\?[0-9]*' | tail -1 | cut -d= -f2)"
    else
        OUT="$("$EXE" "$left" "$right" 2>&1)"
        RC=$?
    fi
}

check() {
    local desc="$1" ok="$2"
    if [ "$ok" = "1" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL: $desc"
        echo "--- output ---"
        printf '%s\n' "$OUT"
        echo "--------------"
        FAILURES=$((FAILURES + 1))
    fi
}

contains() { printf '%s\n' "$OUT" | grep -qF "$1"; }

# 10.1: same files on both sides -> MATCH
d="$WORK/10.1"; mkdir -p "$d/left" "$d/right"
head -c 5000 /dev/zero > "$d/left/IMG_1001.JPG"
head -c 6000 /dev/zero > "$d/left/IMG_1002.JPG"
head -c 5000 /dev/zero > "$d/right/IMG_1001.JPG"
head -c 6000 /dev/zero > "$d/right/IMG_1002.JPG"
run_prog "$d/left" "$d/right"
check "10.1 exit code 0" "$([ "$RC" = "0" ] && echo 1 || echo 0)"
check "10.1 verdict" "$(contains 'RESULT: MATCH - all 2 files match' && echo 1 || echo 0)"

# 10.2/10.3: one-sided files -> DIFFERENT
d="$WORK/10.2_10.3"; mkdir -p "$d/left" "$d/right"
head -c 4096 /dev/zero > "$d/left/IMG_1003.JPG"
head -c 2048 /dev/zero > "$d/right/IMG_1004.JPG"
run_prog "$d/left" "$d/right"
check "10.2/10.3 exit code 1" "$([ "$RC" = "1" ] && echo 1 || echo 0)"
check "10.2/10.3 LEFT-only row" "$(contains 'IMG_1003.JPG' && contains '4,096' && echo 1 || echo 0)"
check "10.2/10.3 RIGHT-only row" "$(contains 'IMG_1004.JPG' && contains '2,048' && echo 1 || echo 0)"

# 10.4: same filename, different size -> DIFFERENT
d="$WORK/10.4"; mkdir -p "$d/left" "$d/right"
head -c 6000 /dev/zero > "$d/left/IMG_1002.JPG"
head -c 7000 /dev/zero > "$d/right/IMG_1002.JPG"
run_prog "$d/left" "$d/right"
check "10.4 exit code 1" "$([ "$RC" = "1" ] && echo 1 || echo 0)"
check "10.4 size-diff row" "$(contains '6,000' && contains '7,000' && echo 1 || echo 0)"

# 10.5: ignored metadata only -> qualified MATCH
d="$WORK/10.5"; mkdir -p "$d/left" "$d/right"
head -c 100 /dev/zero > "$d/left/photo.jpg"
head -c 100 /dev/zero > "$d/right/photo.jpg"
head -c 50 /dev/zero > "$d/left/Thumbs.db"
head -c 90 /dev/zero > "$d/right/Thumbs.db"
run_prog "$d/left" "$d/right"
check "10.5 exit code 0 (qualified MATCH)" "$([ "$RC" = "0" ] && echo 1 || echo 0)"
check "10.5 qualified verdict text" "$(contains 'RESULT: MATCH - qualified: differences limited to 1 ignored metadata file' && echo 1 || echo 0)"
check "10.5 Ignored note text" "$(contains 'Ignored: Windows thumbnail cache' && echo 1 || echo 0)"

# 10.8/10.9: both directories empty -> MATCH
d="$WORK/10.8_10.9"; mkdir -p "$d/left" "$d/right"
run_prog "$d/left" "$d/right"
check "10.8/10.9 exit code 0" "$([ "$RC" = "0" ] && echo 1 || echo 0)"
check "10.8/10.9 verdict" "$(contains 'RESULT: MATCH - all 0 files match' && echo 1 || echo 0)"

# 10.10: case-insensitive filename collision within one side -> error
d="$WORK/10.10"; mkdir -p "$d/left" "$d/right"
: > "$d/left/File.txt"; : > "$d/left/file.txt"
: > "$d/right/File.txt"
run_prog "$d/left" "$d/right"
check "10.10 exit code 2" "$([ "$RC" = "2" ] && echo 1 || echo 0)"

# 10.11: nonexistent directory -> error
d="$WORK/10.11"; mkdir -p "$d/right"
run_prog "$d/does-not-exist" "$d/right"
check "10.11 exit code 2" "$([ "$RC" = "2" ] && echo 1 || echo 0)"

echo
echo "$PASS_COUNT checks passed, $FAILURES failed."
[ "$FAILURES" -eq 0 ]
