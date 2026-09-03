#!/usr/bin/env bash
# Docker bind-mounts run as root and leave __pycache__ / build crumbs the
# runner user cannot delete. actions/checkout Post then fails with EACCES.
# Call before checkout and after any root docker work on the workspace.
set -euo pipefail

WS="${1:-${GITHUB_WORKSPACE:-${WORKSPACE:-}}}"
if [[ -z "${WS}" || ! -d "${WS}" ]]; then
  echo "workspace-fix-root-owned: no workspace dir (arg='${1:-}')" >&2
  exit 0
fi

echo "workspace-fix-root-owned: fixing ${WS}"

# Prefer passwordless sudo (gha sudoers). Fall back to docker alpine root.
fix_as_root() {
  local cmd="$1"
  if sudo -n true 2>/dev/null; then
    sudo -n bash -c "${cmd}"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${WS}:${WS}" alpine:3.20 sh -c "${cmd}"
    return 0
  fi
  echo "workspace-fix-root-owned: no sudo -n and no docker; best-effort as user" >&2
  bash -c "${cmd}" || true
  return 0
}

# Reclaim ownership for the runner user so checkout cleanup and next wipe work.
RUN_UID="$(id -u)"
RUN_GID="$(id -g)"
fix_as_root "chown -R ${RUN_UID}:${RUN_GID} '${WS}' 2>/dev/null || true"

# Drop root-owned python caches specifically (common after container builds).
fix_as_root "find '${WS}' -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true"
fix_as_root "find '${WS}' -type f -name '*.pyc' -delete 2>/dev/null || true"

# Ensure writable for next clone/rm.
chmod -R u+w "${WS}" 2>/dev/null || true

echo "workspace-fix-root-owned: done"
exit 0
