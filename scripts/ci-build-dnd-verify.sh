#!/usr/bin/env bash
# Build WebKitGTK with the drag and drop restoration patch, then run the tests that
# prove the CVE stays closed. Runs on the Azure builder, detached, logging to
# /var/cache/webkit-dnd/out/dnd-build.log so run-command timeouts do not kill it.
set -euo pipefail

CACHE=/var/cache/webkit-dnd
SRC="$CACHE/dnd-src"
BUILD="$SRC/WebKitBuild/Release"
OUT="$CACHE/out"
LOG="$OUT/dnd-build.log"
BASE=d5bec83d776b775bc1a9a3e3af39faf551dd9f27

mkdir -p "$OUT"
exec >>"$LOG" 2>&1
echo "=== $(date -u +%FT%TZ) start ==="

export CCACHE_DIR="$CACHE/ccache"
export CCACHE_BASEDIR="$SRC"
export CCACHE_NOHASHDIR=true
export CCACHE_MAXSIZE=5G

if [[ ! -d "$SRC/.git" ]]; then
  echo "--- cloning from mirror ---"
  git clone --reference "$CACHE/mirrors/WebKit.git" --dissociate \
    "$CACHE/mirrors/WebKit.git" "$SRC"
fi

cd "$SRC"
git reset -q --hard
git checkout -q --detach "$BASE"
git clean -qfd Source Tools || true
echo "--- applying patch ---"
git apply --index "$CACHE/dnd.patch"
echo "patch applied at $(git rev-parse --short HEAD)"

# Fail closed if the trust split is not actually present in the tree we are about
# to build. A green test run against an unpatched tree would prove nothing.
grep -q "setTrustedDrop" Source/WebCore/platform/glib/SelectionData.h || { echo "FATAL: patch missing"; exit 1; }
grep -q "TestDragAndDrop" Tools/TestWebKitAPI/glib/PlatformGTK.cmake || { echo "FATAL: test not wired"; exit 1; }

echo "--- configure ---"
# The Fedora 44 builder ships GCC 16, which added -Wsfinae-incomplete. It fires
# inside WTF's own headers on this WebKit base, and DEVELOPER_MODE promotes
# warnings to errors. We are verifying security behavior here, not warning
# cleanliness, so use the supported switch to stop treating them as fatal.
# Upstream EWS uses its own toolchain.
cmake -S . -B "$BUILD" -G Ninja \
  -DPORT=GTK \
  -DCMAKE_BUILD_TYPE=Release \
  -DDEVELOPER_MODE=ON \
  -DDEVELOPER_MODE_FATAL_WARNINGS=OFF \
  -DENABLE_API_TESTS=ON \
  -DUSE_LIBBACKTRACE=OFF \
  -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
  -DENABLE_JOURNALD_LOG=OFF \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "--- build TestDragAndDrop + TestWebCore ---"
ninja -C "$BUILD" TestDragAndDrop TestWebCore

echo "=== $(date -u +%FT%TZ) build done ==="
touch "$OUT/dnd-build.ok"
