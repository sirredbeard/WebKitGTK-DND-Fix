#!/usr/bin/env bash
# Configure and build thin WebKitGTK (API tests). Does not run tests.
# Tuned for private GHA minutes: fail-fast, strong ccache, mold, small logs.
set -euo pipefail

# Host bind-mount is owned by runner user; container often runs as root (git safe.directory).
git config --global --add safe.directory "*" 2>/dev/null || true
if [[ -n "${WEBKIT_DIR:-}" ]]; then
  git config --global --add safe.directory "${WEBKIT_DIR}" 2>/dev/null || true
fi
if [[ -n "${EPIPHANY_DIR:-}" ]]; then
  git config --global --add safe.directory "${EPIPHANY_DIR}" 2>/dev/null || true
fi


log() { printf '+ %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ccache-env.sh
source "${ROOT}/ccache-env.sh" 2>/dev/null || source /opt/webkitgtk-dnd-fix/bin/ccache-env.sh 2>/dev/null || true

WEBKIT_DIR="${WEBKIT_DIR:-/workspace/WebKit}"

# Build configuration selector. The drag-and-drop change spans three of them:
#   gtk4 - Source/WebKit/UIProcess/API/gtk/DropTarget*Gtk4.cpp (default lane)
#   gtk3 - Source/WebKit/UIProcess/API/gtk/DropTargetGtk3.cpp
#   wpe  - Source/WebCore/platform/glib + Source/WebCore/dom/DataTransfer.h
# Each config gets its own build dir so the lanes never clobber each other.
WEBKIT_CONFIG="${WEBKIT_CONFIG:-gtk4}"
case "${WEBKIT_CONFIG}" in
  gtk4) WEBKIT_PORT=GTK; CONFIG_ARGS=(-DUSE_GTK4=ON) ;;
  gtk3) WEBKIT_PORT=GTK; CONFIG_ARGS=(-DUSE_GTK4=OFF) ;;
  # This lane exists to compile the shared WebCore glib layer under PLATFORM(WPE),
  # not to produce a usable WPE runtime, so take the backend that needs the fewest
  # -devel packages: no libwpe legacy API, WPEPlatform headless only.
  wpe)  WEBKIT_PORT=WPE
        CONFIG_ARGS=(
          -DENABLE_WPE_LEGACY_API=OFF
          -DENABLE_WPE_PLATFORM=ON
          -DENABLE_WPE_PLATFORM_HEADLESS=ON
          -DENABLE_WPE_PLATFORM_DRM=OFF
          -DENABLE_WPE_PLATFORM_WAYLAND=OFF
          -DENABLE_WPE_QT_API=OFF
          -DENABLE_COG=OFF
        ) ;;
  *) die "unknown WEBKIT_CONFIG: ${WEBKIT_CONFIG} (want gtk4, gtk3 or wpe)" ;;
esac

BUILD_DIR="${BUILD_DIR:-${WEBKIT_DIR}/build-${WEBKIT_CONFIG}}"
OUT_DIR="${OUT_DIR:-/out}"
NINJA_TARGETS="${NINJA_TARGETS:-TestWebCore}"
JOBS="${JOBS:-$(nproc)}"
# BASEDIR must be the source root so hashes match across containers/runners.
export CCACHE_BASEDIR="${CCACHE_BASEDIR:-${WEBKIT_DIR}}"
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib64/ccache:/usr/lib/ccache:/opt/webkitgtk-dnd-fix/bin:${PATH}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-${JOBS}}"
export NINJA_STATUS="[%f/%t %e] "

mkdir -p "${OUT_DIR}" "${CCACHE_DIR}" "${BUILD_DIR}"

LINKER_FLAG=""
if command -v mold >/dev/null 2>&1; then
  LINKER_FLAG="-fuse-ld=mold"
elif command -v ld.lld >/dev/null 2>&1; then
  LINKER_FLAG="-fuse-ld=lld"
fi

{
  echo "=== build environment ==="
  date -u
  cat /etc/os-release || true
  echo "nproc=$(nproc) JOBS=${JOBS}"
  echo "WEBKIT_CONFIG=${WEBKIT_CONFIG} (PORT=${WEBKIT_PORT})"
  echo "NINJA_TARGETS=${NINJA_TARGETS}"
  echo "LINKER_FLAG=${LINKER_FLAG:-"(default)"}"
  echo "BUILD_DIR=${BUILD_DIR}"
  echo "WEBKIT_DIR=${WEBKIT_DIR}"
  if declare -F ccache_print_config >/dev/null; then ccache_print_config; else ccache -s || true; fi
  df -h
  free -h || true
  cmake --version
  ninja --version
  g++ --version | head -1
  mold --version 2>/dev/null || true
} | tee "${OUT_DIR}/environment.log"

[[ -d "${WEBKIT_DIR}/Source/WebCore" ]] || die "WEBKIT_DIR is not a WebKit checkout: ${WEBKIT_DIR}"

# Record HEAD for cache/artifact correlation
git -C "${WEBKIT_DIR}" rev-parse HEAD 2>/dev/null | tee "${OUT_DIR}/webkit-sha.txt" || true
git -C "${WEBKIT_DIR}" log -1 --oneline 2>/dev/null | tee -a "${OUT_DIR}/webkit-head.txt" || true

cd "${WEBKIT_DIR}"

# Incremental: if BUILD_DIR already has build.ninja from a restored snapshot, reconfigure in place.
CMAKE_ARGS=(
  -S .
  -B "${BUILD_DIR}"
  -GNinja
  "-DPORT=${WEBKIT_PORT}"
  "${CONFIG_ARGS[@]}"
  -DCMAKE_BUILD_TYPE=Release
  -DDEVELOPER_MODE=ON
  -DDEVELOPER_MODE_FATAL_WARNINGS=OFF
  -DENABLE_API_TESTS=ON
  -DENABLE_LAYOUT_TESTS=OFF
  -DENABLE_MINIBROWSER=OFF
  -DENABLE_DOCUMENTATION=OFF
  -DENABLE_WEBDRIVER=OFF
  -DENABLE_SPEECH_SYNTHESIS=OFF
  -DENABLE_GAMEPAD=OFF
  -DENABLE_PDFJS=OFF
  -DENABLE_JOURNALD_LOG=OFF
  -DUSE_LIBBACKTRACE=OFF
  -DCMAKE_C_COMPILER_LAUNCHER=ccache
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
)

if [[ -n "${LINKER_FLAG}" ]]; then
  CMAKE_ARGS+=(
    "-DCMAKE_EXE_LINKER_FLAGS=${LINKER_FLAG}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LINKER_FLAG}"
    "-DCMAKE_MODULE_LINKER_FLAGS=${LINKER_FLAG}"
  )
fi

log "configure (thin GTK / API tests; reuses BUILD_DIR if present)"
if ! cmake "${CMAKE_ARGS[@]}" >"${OUT_DIR}/cmake.log" 2>&1; then
  tail -n 200 "${OUT_DIR}/cmake.log" | tee "${OUT_DIR}/cmake.fail.tail.log" >&2 || true
  die "cmake failed (see cmake.log)"
fi
tail -n 80 "${OUT_DIR}/cmake.log" >"${OUT_DIR}/cmake.tail.log"
rm -f "${OUT_DIR}/cmake.log"

log "build: ${NINJA_TARGETS} -j${JOBS} (ninja incremental if BUILD_DIR warm)"
set +e
# shellcheck disable=SC2086
ninja -C "${BUILD_DIR}" -j "${JOBS}" ${NINJA_TARGETS} >"${OUT_DIR}/ninja.log" 2>&1
NINJA_RC=$?
set -e
if ((NINJA_RC != 0)); then
  tail -n 300 "${OUT_DIR}/ninja.log" | tee "${OUT_DIR}/ninja.fail.tail.log" >&2
  die "ninja failed rc=${NINJA_RC}"
fi
tail -n 100 "${OUT_DIR}/ninja.log" >"${OUT_DIR}/ninja.tail.log"
# Keep a short ninja summary for cache diagnostics
grep -E '^\[' "${OUT_DIR}/ninja.log" | tail -n 5 >>"${OUT_DIR}/ninja.tail.log" || true
if command -v zstd >/dev/null 2>&1; then
  zstd -q -f -19 -o "${OUT_DIR}/ninja.log.zst" "${OUT_DIR}/ninja.log"
  rm -f "${OUT_DIR}/ninja.log"
else
  gzip -9 -f "${OUT_DIR}/ninja.log" || true
fi

log "ccache stats after build"
ccache -s | tee "${OUT_DIR}/ccache-after-build.log" || true

{
  echo "build_exit=0"
  echo "webkit_config=${WEBKIT_CONFIG}"
  echo "webkit_port=${WEBKIT_PORT}"
  echo "ninja_targets=${NINJA_TARGETS}"
  echo "linker=${LINKER_FLAG:-default}"
  echo "build_dir=${BUILD_DIR}"
  echo "ccache_maxsize=${CCACHE_MAXSIZE}"
  date -u
} | tee "${OUT_DIR}/build-summary.log"

log "build complete"
exit 0
