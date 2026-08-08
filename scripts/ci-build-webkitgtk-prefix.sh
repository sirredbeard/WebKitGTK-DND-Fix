#!/usr/bin/env bash
# Build and install WebKitGTK into PREFIX for GNOME Web / AppImage consumers.
# Produces a reusable install tree (and optional tarball) keyed by WebKit HEAD.
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
# shellcheck source=ccache-env.sh
source "${ROOT}/ccache-env.sh" 2>/dev/null || source /opt/webkitgtk-dnd-fix/bin/ccache-env.sh 2>/dev/null || true

log() { printf '+ %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

WEBKIT_DIR="${WEBKIT_DIR:-/workspace/WebKit}"
BUILD_DIR="${BUILD_DIR:-${WEBKIT_DIR}/build-gtk-install}"
PREFIX="${PREFIX:-/opt/webkitgtk-dnd}"
OUT_DIR="${OUT_DIR:-/out}"
JOBS="${JOBS:-$(nproc)}"
MAKE_TARBALL="${MAKE_TARBALL:-1}"
CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export CCACHE_BASEDIR="${CCACHE_BASEDIR:-${WEBKIT_DIR:-/workspace/WebKit}}"
export CCACHE_MAXSIZE
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"
export PATH="/usr/lib64/ccache:/usr/lib/ccache:/opt/webkitgtk-dnd-fix/bin:${PATH}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-${JOBS}}"
export NINJA_STATUS="[%f/%t %e] "

mkdir -p "${OUT_DIR}" "${CCACHE_DIR}" "${PREFIX}"

LINKER_FLAG=""
if command -v mold >/dev/null 2>&1; then
  LINKER_FLAG="-fuse-ld=mold"
elif command -v ld.lld >/dev/null 2>&1; then
  LINKER_FLAG="-fuse-ld=lld"
fi

{
  echo "=== webkitgtk prefix build ==="
  date -u
  cat /etc/os-release || true
  echo "JOBS=${JOBS} PREFIX=${PREFIX} BUILD_DIR=${BUILD_DIR}"
  echo "LINKER_FLAG=${LINKER_FLAG:-default}"
  df -h
  ccache -s || true
} | tee "${OUT_DIR}/webkit-prefix-environment.log"

[[ -d "${WEBKIT_DIR}/Source/WebCore" ]] || die "WEBKIT_DIR is not a WebKit checkout: ${WEBKIT_DIR}"

git -C "${WEBKIT_DIR}" rev-parse HEAD | tee "${OUT_DIR}/webkit-head.txt"
git -C "${WEBKIT_DIR}" log -1 --oneline >>"${OUT_DIR}/webkit-head.txt" || true
WEBKIT_SHA="$(git -C "${WEBKIT_DIR}" rev-parse HEAD)"
echo "${WEBKIT_SHA}" >"${OUT_DIR}/webkit-sha.txt"

# Reuse existing prefix if it already matches this SHA and pkg-config works.
STAMP="${PREFIX}/.webkitgtk-dnd-sha"
if [[ -f "${STAMP}" ]] && [[ "$(cat "${STAMP}")" == "${WEBKIT_SHA}" ]]; then
  export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  if pkg-config --exists webkitgtk-6.0 2>/dev/null; then
    log "reusing existing PREFIX for ${WEBKIT_SHA}"
    pkg-config --modversion webkitgtk-6.0 | tee "${OUT_DIR}/webkitgtk-pc-version.txt"
    echo "reused_prefix=1" | tee "${OUT_DIR}/webkit-prefix-summary.log"
    exit 0
  fi
fi

cd "${WEBKIT_DIR}"
CMAKE_ARGS=(
  -S .
  -B "${BUILD_DIR}"
  -GNinja
  -DPORT=GTK
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="${PREFIX}"
  -DDEVELOPER_MODE=ON
  -DDEVELOPER_MODE_FATAL_WARNINGS=OFF
  -DENABLE_API_TESTS=OFF
  -DENABLE_LAYOUT_TESTS=OFF
  -DENABLE_MINIBROWSER=ON
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

log "configure WebKitGTK install prefix"
if ! cmake "${CMAKE_ARGS[@]}" >"${OUT_DIR}/webkit-cmake.log" 2>&1; then
  tail -n 200 "${OUT_DIR}/webkit-cmake.log" >&2 || true
  die "webkit cmake failed"
fi
tail -n 60 "${OUT_DIR}/webkit-cmake.log" >"${OUT_DIR}/webkit-cmake.tail.log"
rm -f "${OUT_DIR}/webkit-cmake.log"

log "ninja install -j${JOBS}"
set +e
ninja -C "${BUILD_DIR}" -j "${JOBS}" install >"${OUT_DIR}/webkit-ninja-install.log" 2>&1
NINJA_RC=$?
set -e
if ((NINJA_RC != 0)); then
  tail -n 300 "${OUT_DIR}/webkit-ninja-install.log" | tee "${OUT_DIR}/webkit-ninja-install.fail.tail.log" >&2
  die "webkit ninja install failed rc=${NINJA_RC}"
fi
tail -n 80 "${OUT_DIR}/webkit-ninja-install.log" >"${OUT_DIR}/webkit-ninja-install.tail.log"
if command -v zstd >/dev/null 2>&1; then
  zstd -q -f -19 -o "${OUT_DIR}/webkit-ninja-install.log.zst" "${OUT_DIR}/webkit-ninja-install.log"
  rm -f "${OUT_DIR}/webkit-ninja-install.log"
else
  gzip -9 -f "${OUT_DIR}/webkit-ninja-install.log" || true
fi

echo "${WEBKIT_SHA}" >"${STAMP}"
export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
pkg-config --modversion webkitgtk-6.0 | tee "${OUT_DIR}/webkitgtk-pc-version.txt" \
  || die "webkitgtk-6.0.pc missing after install"

if [[ "${MAKE_TARBALL}" == "1" ]]; then
  log "pack prefix tarball"
  TARBALL="${OUT_DIR}/webkitgtk-prefix-${WEBKIT_SHA:0:12}.tar.zst"
  if command -v zstd >/dev/null 2>&1; then
    tar -C "${PREFIX}" -I 'zstd -T0 -19' -cf "${TARBALL}" .
  else
    TARBALL="${OUT_DIR}/webkitgtk-prefix-${WEBKIT_SHA:0:12}.tar.gz"
    tar -C "${PREFIX}" -czf "${TARBALL}" .
  fi
  ls -lh "${TARBALL}" | tee "${OUT_DIR}/webkit-prefix-tarball-ls.txt"
  echo "${TARBALL}" >"${OUT_DIR}/webkit-prefix-tarball.path"
fi

ccache -s | tee "${OUT_DIR}/ccache-after-prefix-build.log" || true
{
  echo "reused_prefix=0"
  echo "webkit_sha=${WEBKIT_SHA}"
  echo "prefix=${PREFIX}"
  date -u
} | tee "${OUT_DIR}/webkit-prefix-summary.log"

log "prefix ready at ${PREFIX}"
exit 0
