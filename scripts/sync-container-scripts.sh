#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in ccache-env.sh ci-build.sh ci-test-selectiondata.sh ci-build-and-test.sh \
         ci-build-webkitgtk-prefix.sh ci-build-gnome-web-appimage.sh \
         find-latest-webkit-prefix-artifact.sh clone-webkit.sh clone-from-mirror.sh print-layer-checklist.sh; do
  cp -a "$ROOT/scripts/$f" "$ROOT/containers/$f"
done
echo "synced container bake scripts"
