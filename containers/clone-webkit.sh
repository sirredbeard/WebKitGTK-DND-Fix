#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export REPO_URL="${REPO_URL:-https://github.com/sirredbeard/WebKit.git}"
export REF="${REF:?}"
export CLONE_DIR="${CLONE_DIR:?}"
export MIRROR_DIR="${MIRROR_DIR:-/var/cache/webkit-dnd/mirrors/WebKit.git}"
export OUT_DIR="${OUT_DIR:-/tmp}"
# shellcheck source=clone-from-mirror.sh
bash "${ROOT}/clone-from-mirror.sh"
# Compat names for workflows
cp -f "${OUT_DIR}/git-head.txt" "${OUT_DIR}/webkit-head.txt" 2>/dev/null || true
