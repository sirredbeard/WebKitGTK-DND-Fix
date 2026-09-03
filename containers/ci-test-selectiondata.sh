#!/usr/bin/env bash
# Run SelectionData.* gtests against an already-built TestWebCore tree.
# Separate from configure/build so CI can fail-fast per phase and keep ccache warm.
set -euo pipefail

# Host bind-mount is owned by runner user; container often runs as root (git safe.directory).
git config --global --add safe.directory "*" 2>/dev/null || true
if [[ -n "${WEBKIT_DIR:-}" ]]; then
  git config --global --add safe.directory "${WEBKIT_DIR}" 2>/dev/null || true
fi
if [[ -n "${EPIPHANY_DIR:-}" ]]; then
  git config --global --add safe.directory "${EPIPHANY_DIR}" 2>/dev/null || true
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "${ROOT}/ccache-env.sh" 2>/dev/null || true

log() { printf '+ %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

WEBKIT_DIR="${WEBKIT_DIR:-/workspace/WebKit}"
WEBKIT_CONFIG="${WEBKIT_CONFIG:-gtk4}"
BUILD_DIR="${BUILD_DIR:-${WEBKIT_DIR}/build-${WEBKIT_CONFIG}}"
OUT_DIR="${OUT_DIR:-/out}"
# DropTargetState is registered by PlatformGTK.cmake only, so the WPE lane runs
# just the shared WebCore glib suite.
if [[ "${WEBKIT_CONFIG}" == gtk* ]]; then
  GTEST_FILTER="${GTEST_FILTER:-SelectionData.*:DropTargetState.*}"
else
  GTEST_FILTER="${GTEST_FILTER:-SelectionData.*}"
fi
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib64/ccache:/usr/lib/ccache:/opt/webkitgtk-dnd-fix/bin:${PATH}"

mkdir -p "${OUT_DIR}"

{
  echo "=== test environment ==="
  date -u
  echo "WEBKIT_CONFIG=${WEBKIT_CONFIG}"
  echo "BUILD_DIR=${BUILD_DIR}"
  echo "GTEST_FILTER=${GTEST_FILTER}"
  ccache -s || true
} | tee "${OUT_DIR}/test-environment.log"

[[ -d "${BUILD_DIR}" ]] || die "build dir missing (run ci-build.sh first): ${BUILD_DIR}"

TESTBIN=""
for candidate in \
  "${BUILD_DIR}/bin/TestWebCore" \
  "${BUILD_DIR}/bin/TestWebKitAPI/TestWebCore"
do
  if [[ -x "${candidate}" ]]; then
    TESTBIN="${candidate}"
    break
  fi
done
if [[ -z "${TESTBIN}" ]]; then
  find "${BUILD_DIR}" -name 'TestWebCore' 2>/dev/null | head -n 20 | tee "${OUT_DIR}/find-TestWebCore.txt" || true
  die "TestWebCore binary not found under ${BUILD_DIR}"
fi

log "run ${TESTBIN} --gtest_filter=${GTEST_FILTER}"
set +e
"${TESTBIN}" --gtest_filter="${GTEST_FILTER}" --gtest_color=no \
  >"${OUT_DIR}/selectiondata-tests.log" 2>&1
TEST_RC=$?
set -e
tail -n 80 "${OUT_DIR}/selectiondata-tests.log" >"${OUT_DIR}/selectiondata-tests.tail.log"
# Always surface log in docker-test stream
if [[ -s "${OUT_DIR}/selectiondata-tests.log" ]]; then
  log "gtest log ($(wc -l <"${OUT_DIR}/selectiondata-tests.log") lines)"
  tail -n 100 "${OUT_DIR}/selectiondata-tests.log" || true
else
  log "gtest log EMPTY"
fi
if ((TEST_RC != 0)); then
  cat "${OUT_DIR}/selectiondata-tests.log" >&2 || true
fi
# Fail closed: exit 0 with zero matching tests is not success for our lane.
# TestWebKitAPI prints **PASS** / **FAIL** (not stock gtest "[  PASSED  ]").
if ! grep -qE '\*\*PASS\*\*|\[ *PASSED *\]' "${OUT_DIR}/selectiondata-tests.log" 2>/dev/null; then
  if ! grep -qE 'PASSED|OK \(' "${OUT_DIR}/selectiondata-tests.log" 2>/dev/null; then
    echo "error: SelectionData gtest produced no PASS lines (filter=${GTEST_FILTER})" >&2
    "${TESTBIN}" --gtest_list_tests 2>&1 | head -n 100 | tee "${OUT_DIR}/gtest-list.txt" || true
    TEST_RC=1
  fi
fi
if grep -qE '\*\*FAIL\*\*|\[ *FAILED *\]' "${OUT_DIR}/selectiondata-tests.log" 2>/dev/null; then
  echo "error: SelectionData gtest reported FAIL" >&2
  TEST_RC=1
fi
if ! grep -q 'SelectionData' "${OUT_DIR}/selectiondata-tests.log" 2>/dev/null; then
  echo "error: SelectionData tests not present in log - wrong tree or not linked?" >&2
  TEST_RC=1
fi

{
  echo "test_exit=${TEST_RC}"
  echo "webkit_config=${WEBKIT_CONFIG}"
  echo "gtest_filter=${GTEST_FILTER}"
  echo "testbin=${TESTBIN}"
  ccache -s || true
  date -u
} | tee "${OUT_DIR}/summary.log"

if [[ -x /opt/webkitgtk-dnd-fix/bin/print-layer-checklist.sh ]]; then
  /opt/webkitgtk-dnd-fix/bin/print-layer-checklist.sh >"${OUT_DIR}/layer-checklist.txt" 2>&1 || true
elif [[ -x /workspace/WebKitGTK-DND-Fix/scripts/print-layer-checklist.sh ]]; then
  /workspace/WebKitGTK-DND-Fix/scripts/print-layer-checklist.sh >"${OUT_DIR}/layer-checklist.txt" 2>&1 || true
fi

exit "${TEST_RC}"
