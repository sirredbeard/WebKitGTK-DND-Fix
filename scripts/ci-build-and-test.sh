#!/usr/bin/env bash
# Compatibility wrapper: build then test (local use).
# CI prefers separate steps: ci-build.sh then ci-test-selectiondata.sh.
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
bash "${ROOT}/ci-build.sh"
bash "${ROOT}/ci-test-selectiondata.sh"
