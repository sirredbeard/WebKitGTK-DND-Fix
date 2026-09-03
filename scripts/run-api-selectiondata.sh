#!/usr/bin/env bash
set -euo pipefail
WEBKIT_DIR="${WEBKIT_DIR:-/home/fedora/WebKit}"
cd "$WEBKIT_DIR"
if [[ -x build-gtk/bin/TestWebCore ]]; then
  exec ./build-gtk/bin/TestWebCore --gtest_filter='SelectionData.*' "$@"
fi
if [[ -x WebKitBuild/GTK/Debug/bin/TestWebCore ]]; then
  exec ./WebKitBuild/GTK/Debug/bin/TestWebCore --gtest_filter='SelectionData.*' "$@"
fi
if [[ -x Tools/Scripts/run-api-tests ]]; then
  exec Tools/Scripts/run-api-tests --gtk SelectionData "$@"
fi
echo "No TestWebCore binary found. Build GTK WebKit first." >&2
exit 1
