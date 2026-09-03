#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in ccache-env.sh ci-build.sh ci-test-selectiondata.sh ci-build-dnd-verify.sh \
         seed-prefix-from-last-good.sh \
         clone-webkit.sh clone-from-mirror.sh print-layer-checklist.sh; do
  cp -a "$ROOT/scripts/$f" "$ROOT/containers/$f"
done
echo "synced container bake scripts"
