#!/usr/bin/env bash
# Stamp last-good unit build metadata for peer handoff / tests-only lane.
set -euo pipefail
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
OUT="${OUT_DIR:-$CACHE/out}"
BUILD_HOST_DIR="${BUILD_HOST_DIR:-$CACHE/build-gtk}"
mkdir -p "$CACHE/out" "$OUT"
stamp="$CACHE/out/last-good-unit.json"
{
  echo "{"
  echo "  \"time\": \"$(date -u -Iseconds)\","
  echo "  \"host\": \"$(hostname)\","
  echo "  \"build_dir\": \"$BUILD_HOST_DIR\","
  echo "  \"git_head\": \"$(head -1 "$OUT/git-head.txt" 2>/dev/null || head -1 "$CACHE/out/git-head.txt" 2>/dev/null || echo unknown)\","
  echo "  \"ccache_bytes\": $(du -sb "$CACHE/ccache" 2>/dev/null | awk '{print $1}' || echo 0),"
  echo "  \"build_bytes\": $(du -sb "$BUILD_HOST_DIR" 2>/dev/null | awk '{print $1}' || echo 0),"
  echo "  \"test_log\": \"selectiondata-tests.log\","
  echo "  \"run_id\": \"${GITHUB_RUN_ID:-local}\""
  echo "}"
} | tee "$stamp"
cp -f "$stamp" "$OUT/last-good-unit.json" 2>/dev/null || true
echo "LAST_GOOD_UNIT $stamp"
