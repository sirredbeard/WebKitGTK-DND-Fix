#!/usr/bin/env bash
# Local gates that mirror what upstream WebKit + this private repo enforce.
# Missing includes / type errors are compile-time (EWS gtk build / our unit job).
# Style alone does not replace a TestWebCore build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
fail=0

log() { printf '+ %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; fail=1; }

# --- Private CI repo: workflows + shell ---
if command -v actionlint >/dev/null 2>&1; then
  log "actionlint .github/workflows"
  actionlint -shellcheck= || err "actionlint failed"
else
  err "actionlint not installed (go install or release binary)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  log "shellcheck scripts/*.sh containers/*.sh (severity error+)"
  # SC1091: sourced files vary by install path in CI.
  # Info-level style (SC2012 ls vs find) is noise for existing ops scripts; gate on error.
  mapfile -t sh_files < <(find scripts containers -name '*.sh' -type f | sort)
  shellcheck -x -S error -e SC1091 "${sh_files[@]}" || err "shellcheck failed"
else
  err "shellcheck not installed"
fi

# --- Engine fork: WebKit style (EWS "style" queue) ---
WEBKIT_SRC="${WEBKIT_SRC:-${ROOT}/../WebKit}"
if [[ ! -d "${WEBKIT_SRC}/Source/WebCore" ]]; then
  WEBKIT_SRC="${WEBKIT_DIR:-/home/fedora/WebKit}"
fi

if [[ -x "${WEBKIT_SRC}/Tools/Scripts/check-webkit-style" ]]; then
  # System python may be 3.15+ without sre_compile; prefer 3.12 like stable EWS images.
  PY=""
  for c in python3.12 python3.11 python3; do
    if command -v "$c" >/dev/null 2>&1; then
      if "$c" -c 'import sre_compile' 2>/dev/null || "$c" -c 'import re' 2>/dev/null; then
        if "$c" -c 'import sre_compile' 2>/dev/null; then PY=$c; break; fi
      fi
    fi
  done
  if [[ -z "$PY" ]]; then
    for c in python3.12 python3.11; do
      command -v "$c" >/dev/null 2>&1 && PY=$c && break
    done
  fi
  PY="${PY:-python3.12}"

  log "check-webkit-style via ${PY} (WEBKIT_SRC=${WEBKIT_SRC})"
  FILES=(
    Source/WebCore/platform/glib/SelectionData.cpp
    Source/WebCore/platform/glib/SelectionData.h
    Source/WebKit/Shared/glib/SelectionData.serialization.in
    Source/WebCore/platform/gtk/DragDataGLib.cpp
    Source/WebKit/UIProcess/API/gtk/DropTargetGtk3.cpp
    Source/WebKit/UIProcess/API/gtk/DropTargetGtk4.cpp
    Source/WebKit/UIProcess/API/gtk/DragSourceGtk3.cpp
    Source/WebKit/UIProcess/API/gtk/DragSourceGtk4.cpp
    Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp
  )
  existing=()
  for f in "${FILES[@]}"; do
    [[ -f "${WEBKIT_SRC}/${f}" ]] && existing+=("${f}")
  done
  if [[ ${#existing[@]} -gt 0 ]]; then
    (
      cd "${WEBKIT_SRC}"
      # webkitpy still imports sre_compile on some trees; 3.12 required on Fedora 45 hosts
      if ! "${PY}" -c 'import sre_compile' 2>/dev/null; then
        err "${PY} cannot import sre_compile; install python3.12"
      else
        "${PY}" Tools/Scripts/check-webkit-style --diff-files "${existing[@]}" || err "check-webkit-style failed"
      fi
    )
  else
    log "warn: no engine touch-set files under ${WEBKIT_SRC}"
  fi
else
  log "warn: WebKit checkout not found; skip check-webkit-style"
fi

if [[ "$fail" -ne 0 ]]; then
  err "lint-local failed"
  exit 1
fi
log "lint-local ok"
log "Still required before land: compile TestWebCore + SelectionData.* (EWS gtk build / our unit job)"
exit 0
