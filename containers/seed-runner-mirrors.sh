#!/usr/bin/env bash
# Seed bare git mirrors + optional docker image save under /var/cache/webkit-dnd.
# Safe to re-run. Run as root or gha with write access to the cache root.
#
# Integrity model:
# - Each host owns its mirrors; we do NOT rsync live *.git object stores between peers.
# - Updates take an exclusive flock so clone jobs never race fetch/repack.
# - After fetch, connectivity fsck; on failure quarantine and rebuild.
# - CI clones with --reference + dissociate (no --shared) so a later mirror wipe
#   cannot hollow out an in-flight working tree.
set -euo pipefail

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
MIRRORS="${CACHE}/mirrors"
TOOLS="${CACHE}/tools"
IMAGES="${CACHE}/images"
mkdir -p "$MIRRORS" "$TOOLS" "$IMAGES"

fsck_mirror() {
  local path="$1"
  # Connectivity-only is cheap relative to full fsck on a multi-GB WebKit mirror.
  git -C "$path" fsck --connectivity-only --no-dangling 2>"${path}.fsck.err"
}

with_mirror_lock() {
  local path="$1"
  shift
  local lock="${path}.lock"
  mkdir -p "$(dirname "$path")"
  exec 9>"$lock"
  if ! flock -w "${MIRROR_LOCK_WAIT:-600}" 9; then
    echo "error: could not lock $lock" >&2
    return 1
  fi
  "$@"
  flock -u 9 || true
}

rebuild_mirror() {
  local name="$1" url="$2" path="$3"
  local tmp="${path}.new.$$"
  rm -rf "$tmp"
  echo "+ rebuild bare $name from $url"
  git clone --mirror "$url" "$tmp"
  if ! git -C "$tmp" fsck --connectivity-only --no-dangling 2>"${tmp}.fsck.err"; then
    echo "error: fresh mirror fsck failed" >&2
    cat "${tmp}.fsck.err" >&2 || true
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "${path}.bad" 2>/dev/null || true
  if [[ -d "$path" ]]; then
    mv "$path" "${path}.bad.$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mv "$tmp" "$path"
  # keep at most one bad quarantine
  ls -1d "${path}.bad."* 2>/dev/null | head -n -1 | xargs -r rm -rf
}

mirror_one() {
  local name="$1" url="$2"
  local path="${MIRRORS}/${name}.git"

  update() {
    if [[ -d "$path" ]]; then
      echo "+ update $name"
      git -C "$path" remote set-url origin "$url" 2>/dev/null || true
      if ! git -C "$path" fetch --prune origin 2>"${path}.fetch.err"; then
        echo "fetch failed for $name; rebuild"
        cat "${path}.fetch.err" | tail -20 || true
        rebuild_mirror "$name" "$url" "$path"
        return 0
      fi
      if ! fsck_mirror "$path"; then
        echo "fsck failed for $name; rebuild"
        tail -20 "${path}.fsck.err" || true
        rebuild_mirror "$name" "$url" "$path"
      fi
    else
      rebuild_mirror "$name" "$url" "$path"
    fi
  }

  with_mirror_lock "$path" update
}

echo "== bare mirrors (host-local; not peer-rsynced) =="
# Upstream objects (huge). CI may --reference this when cloning the fork — common
# blobs resolve locally; fork-only commits still fetch from network.
mirror_one WebKit https://github.com/WebKit/WebKit.git
# Fork tip + our branches (small incremental after upstream is warm).
mirror_one WebKit-sirredbeard https://github.com/sirredbeard/WebKit.git || true
mirror_one epiphany https://gitlab.gnome.org/GNOME/epiphany.git || \
  mirror_one epiphany https://github.com/GNOME/epiphany.git || true

echo "== appimage tools =="
if [[ ! -x "${TOOLS}/linuxdeploy-x86_64.AppImage" ]]; then
  curl -fsSL -o "${TOOLS}/linuxdeploy-x86_64.AppImage" \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x "${TOOLS}/linuxdeploy-x86_64.AppImage"
fi
if [[ ! -x "${TOOLS}/appimagetool-x86_64.AppImage" ]]; then
  curl -fsSL -o "${TOOLS}/appimagetool-x86_64.AppImage" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "${TOOLS}/appimagetool-x86_64.AppImage"
fi

echo "== docker builder image (local pull + optional save) =="
if command -v docker >/dev/null && command -v gh >/dev/null; then
  OWNER="${GITHUB_REPOSITORY_OWNER:-sirredbeard}"
  IMAGE_NAME=webkitgtk-dnd-fix-builder
  TAG="${IMAGE_TAG:-}"
  if [[ -z "$TAG" ]]; then
    TAG=$(gh api --paginate "/users/${OWNER}/packages/container/${IMAGE_NAME}/versions" \
      --jq '[.[].metadata.container.tags[]?] | map(select(test("^[0-9]{8}$"))) | sort | reverse | .[0] // empty' 2>/dev/null || true)
  fi
  if [[ -n "$TAG" ]]; then
    IMG="ghcr.io/${OWNER}/${IMAGE_NAME}:${TAG}"
    echo "+ docker pull $IMG"
    docker pull "$IMG" || true
    SAVE="${IMAGES}/webkitgtk-dnd-fix-builder-${TAG}.tar.zst"
    if [[ ! -f "$SAVE" ]]; then
      echo "+ docker save $SAVE"
      docker save "$IMG" | zstd -T0 -1 -o "$SAVE" || true
    fi
  else
    echo "no date tag on GHCR yet; skip image seed"
  fi
else
  echo "docker/gh missing; skip image seed"
fi

echo "SEED_OK"
du -sh "$MIRRORS"/* "$TOOLS"/* "$IMAGES"/* 2>/dev/null | head -40 || true
