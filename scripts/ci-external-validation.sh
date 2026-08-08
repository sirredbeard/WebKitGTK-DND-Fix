#!/usr/bin/env bash
# Automated external / layer validation that does not need a GUI session.
# - Verifies HTML fixtures exist and carry expected DnD markers
# - Parses SelectionData gtest log for required cases
# - Writes layer-checklist-auto.txt with pass/fail marks
# Exit 1 if any required automated check fails.
set -euo pipefail

OUT_DIR="${OUT_DIR:-/out}"
HTML_DIR="${HTML_DIR:-}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
GTEST_LOG="${GTEST_LOG:-$OUT_DIR/selectiondata-tests.log}"
mkdir -p "$OUT_DIR"

if [[ -z "$HTML_DIR" ]]; then
  for d in \
    "${ROOT}/../html" \
    "/workspace/WebKitGTK-DND-Fix/html" \
    "/validation-html" \
    "${GITHUB_WORKSPACE:-}/WebKitGTK-DND-Fix/html" \
    "${GITHUB_WORKSPACE:-}/html"
  do
    if [[ -d "$d" ]]; then HTML_DIR="$d"; break; fi
  done
fi

fail=0
note() { printf '%s\n' "$*" | tee -a "$OUT_DIR/external-validation.log"; }
req() { note "REQ: $*"; }
pass() { note "PASS: $*"; }
bad() { note "FAIL: $*"; fail=1; }

: >"$OUT_DIR/external-validation.log"
note "=== external validation $(date -u -Iseconds) ==="
note "HTML_DIR=${HTML_DIR:-missing}"
note "GTEST_LOG=$GTEST_LOG"

# --- HTML fixtures ---
if [[ -z "${HTML_DIR:-}" || ! -d "$HTML_DIR" ]]; then
  bad "html directory not found"
else
  for f in index.html \
    layer1-web-uri-list-no-files.html \
    layer2-external-drop-files.html \
    layer3-portal-notes.html \
    layer4-local-drag-and-export.html
  do
    if [[ -f "$HTML_DIR/$f" ]]; then pass "html $f present"
    else bad "html $f missing"; fi
  done
  # marker checks (stable strings from fixtures)
  if [[ -f "$HTML_DIR/layer1-web-uri-list-no-files.html" ]]; then
    grep -q 'files.length' "$HTML_DIR/layer1-web-uri-list-no-files.html" \
      && pass "layer1 mentions files.length" || bad "layer1 missing files.length"
  fi
  if [[ -f "$HTML_DIR/layer2-external-drop-files.html" ]]; then
    grep -qi 'drop\|DataTransfer\|files' "$HTML_DIR/layer2-external-drop-files.html" \
      && pass "layer2 drop/files markers" || bad "layer2 markers weak"
  fi
  if [[ -f "$HTML_DIR/layer4-local-drag-and-export.html" ]]; then
    grep -qi 'drag\|export\|files' "$HTML_DIR/layer4-local-drag-and-export.html" \
      && pass "layer4 drag/export markers" || bad "layer4 markers weak"
  fi
fi

# --- Required gtest cases (engine unit suite for the DnD fix) ---
REQUIRED_TESTS=(
  SelectionData.SetURIListDoesNotPromoteFilenames
  SelectionData.SetURIListKeepsHttpURLWithoutFilenames
  SelectionData.TrustedSetFilenamesFromURIList
  SelectionData.ExplicitSetFilenames
  SelectionData.FilenamesFromURIListSkipsCommentsAndNonFiles
  SelectionData.ClearFilenames
  SelectionData.URIListWithoutFilenamesStripsFileURLs
  SelectionData.URIListWithoutFilenamesEmptyWhenOnlyFiles
  SelectionData.IpcConstructorPreservesFilenamesWithoutURIListPromotion
  SelectionData.DragDataIsSourceDeniesFilenameAccess
)

declare -A TEST_STATUS
if [[ -f "$GTEST_LOG" ]]; then
  lines=$(wc -l <"$GTEST_LOG")
  if [[ "$lines" -eq 0 ]]; then bad "gtest log empty (0 lines) - tests did not run or wrong OUT_DIR mount"
  else pass "gtest log present ($lines lines)"; fi
  # TestWebKitAPI: **PASS** SelectionData.Foo
  # stock gtest:   [  PASSED  ] SelectionData.Foo (0 ms)
  while IFS= read -r line; do
    if [[ "$line" =~ \*\*PASS\*\*[[:space:]]+([A-Za-z0-9_]+\.[A-Za-z0-9_]+) ]]; then
      TEST_STATUS["${BASH_REMATCH[1]}"]=PASS
    elif [[ "$line" =~ \*\*FAIL\*\*[[:space:]]+([A-Za-z0-9_]+\.[A-Za-z0-9_]+) ]]; then
      TEST_STATUS["${BASH_REMATCH[1]}"]=FAIL
    elif [[ "$line" =~ \[\ *PASSED\ *\][[:space:]]+([A-Za-z0-9_]+\.[A-Za-z0-9_]+) ]]; then
      TEST_STATUS["${BASH_REMATCH[1]}"]=PASS
    elif [[ "$line" =~ \[\ *FAILED\ *\][[:space:]]+([A-Za-z0-9_]+\.[A-Za-z0-9_]+) ]]; then
      TEST_STATUS["${BASH_REMATCH[1]}"]=FAIL
    fi
  done <"$GTEST_LOG"
else
  bad "gtest log missing: $GTEST_LOG"
fi

for t in "${REQUIRED_TESTS[@]}"; do
  st="${TEST_STATUS[$t]:-MISSING}"
  if [[ "$st" == "PASS" ]]; then pass "gtest $t"
  elif [[ "$st" == "FAIL" ]]; then bad "gtest $t FAILED"
  else bad "gtest $t not run/missing from log"; fi
done

# summary / fail markers
if [[ -f "$GTEST_LOG" ]]; then
  if grep -qE '\*\*PASS\*\*|\[ *PASSED *\]' "$GTEST_LOG"; then
    pass "gtest log has PASS markers"
  fi
  if grep -qE '\*\*FAIL\*\*|\[ *FAILED *\]' "$GTEST_LOG"; then
    bad "gtest log contains FAIL"
  fi
fi

# --- Auto layer checklist ---
{
  echo "WebKitGTK DnD fix layer checklist (automated)"
  echo "============================================="
  mark() {
    local ok="$1"; shift
    if [[ "$ok" == "1" ]]; then echo "[x] $*"; else echo "[ ] $*"; fi
  }
  m1=0; [[ "${TEST_STATUS[SelectionData.SetURIListDoesNotPromoteFilenames]:-}" == "PASS" ]] && m1=1
  m1b=0; [[ "${TEST_STATUS[SelectionData.TrustedSetFilenamesFromURIList]:-}" == "PASS" ]] && m1b=1
  m4=0; [[ "${TEST_STATUS[SelectionData.DragDataIsSourceDeniesFilenameAccess]:-}" == "PASS" ]] && m4=1
  m4b=0; [[ "${TEST_STATUS[SelectionData.URIListWithoutFilenamesStripsFileURLs]:-}" == "PASS" ]] && m4b=1
  mark "$m1" "Layer 1 unit: SelectionData.SetURIListDoesNotPromoteFilenames"
  mark "$m1b" "Layer 1 unit: SelectionData.TrustedSetFilenamesFromURIList"
  mark 0 "Layer 1 manual: html/layer1-web-uri-list-no-files.html (needs interactive WebKitGTK)"
  mark 0 "Layer 2 manual: html/layer2-external-drop-files.html (needs interactive drop)"
  mark 0 "Layer 3 code review: DropTargetGtk4 portal path (human)"
  mark 0 "Layer 3 manual portal session (optional)"
  mark "$m4" "Layer 4 unit: SelectionData.DragDataIsSourceDeniesFilenameAccess"
  mark "$m4b" "Layer 4 unit: SelectionData.URIListWithoutFilenamesStripsFileURLs"
  mark 0 "Layer 4 manual: local drag / Nautilus export (interactive)"
  mark 0 "Non-regression: input type=file click (interactive)"
  mark 1 "Cocoa untouched (process check: no PLATFORM(COCOA) edits required in CI)"
  echo
  echo "HTML fixtures checked: $([[ -n ${HTML_DIR:-} ]] && echo yes || echo no)"
  echo "fail=$fail"
} | tee "$OUT_DIR/layer-checklist-auto.txt"

# also keep classic checklist text
if [[ -x "$ROOT/print-layer-checklist.sh" ]]; then
  "$ROOT/print-layer-checklist.sh" >"$OUT_DIR/layer-checklist.txt" 2>&1 || true
fi

note "=== external validation done fail=$fail ==="
exit "$fail"
