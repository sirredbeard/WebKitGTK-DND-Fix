#!/usr/bin/env bash
# Sync heavy caches between self-hosted runners (Vultr <-> Azure).
# Pull-oriented: run on the destination host, or from laptop with both SSH hosts.
#
# Usage:
#   # from laptop: push Vultr caches to Azure (or reverse)
#   MODE=push SRC_HOST=vultr-webkit-dnd DST_HOST=azure-webkit-dnd ./scripts/sync-runner-caches.sh
#   MODE=pull SRC_HOST=azure-webkit-dnd DST_HOST=vultr-webkit-dnd ./scripts/sync-runner-caches.sh
#
#   # on a runner: pull from peer over SSH
#   PEER=azure-webkit-dnd ./scripts/sync-runner-caches.sh
#
# Syncs (in order of importance for cold start):
#   mirrors/   NEVER by default — each host git-fetches its own bare repos
#   images/    optional docker save tarballs
#   tools/     linuxdeploy, appimagetool
#   ccache/    optional (large; set SYNC_CCACHE=1)
#   prefix/    optional install trees (set SYNC_PREFIX=1)
#
# Does NOT sync build-gtk object trees by default (host-specific, huge, low reuse).
set -euo pipefail

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
RSYNC_OPTS=(-aH --info=stats2,progress2 --human-readable --delete-delay --partial --partial-dir=.rsync-partial)
# Prefer compress only on slow links
if [[ "${RSYNC_COMPRESS:-0}" == "1" ]]; then
  RSYNC_OPTS+=(-z)
fi

SYNC_MIRRORS="${SYNC_MIRRORS:-0}"  # do not rsync live git object stores
SYNC_TOOLS="${SYNC_TOOLS:-1}"
SYNC_IMAGES="${SYNC_IMAGES:-1}"
SYNC_CCACHE="${SYNC_CCACHE:-0}"
SYNC_PREFIX="${SYNC_PREFIX:-0}"

sync_pair() {
  local src="$1" dst="$2" rel="$3"
  echo "== rsync ${rel}  ${src} -> ${dst} =="
  # shellcheck disable=SC2086
  if [[ "$src" == local ]]; then
    mkdir -p "${CACHE}/${rel}"
    rsync "${RSYNC_OPTS[@]}" "${CACHE}/${rel}/" "${dst}:${CACHE}/${rel}/"
  elif [[ "$dst" == local ]]; then
    mkdir -p "${CACHE}/${rel}"
    rsync "${RSYNC_OPTS[@]}" "${src}:${CACHE}/${rel}/" "${CACHE}/${rel}/"
  else
    # laptop bridge: stream src -> dst without landing full tree locally when possible
    ssh "$src" "test -d ${CACHE}/${rel}" || { echo "skip missing ${src}:${CACHE}/${rel}"; return 0; }
    ssh "$dst" "mkdir -p ${CACHE}/${rel}"
    ssh "$src" "tar -C ${CACHE}/${rel} -cf - ." | ssh "$dst" "tar -C ${CACHE}/${rel} -xf -"
  fi
}

if [[ -n "${PEER:-}" ]]; then
  # On-runner pull from PEER
  SRC_HOST="$PEER"
  DST_HOST=local
  MODE=pull
fi

MODE="${MODE:-pull}"
SRC_HOST="${SRC_HOST:?set SRC_HOST or PEER}"
DST_HOST="${DST_HOST:?set DST_HOST or PEER mode}"

if [[ "$MODE" == "push" ]]; then
  A="$SRC_HOST"; B="$DST_HOST"
else
  # pull: content moves SRC -> DST where DST is usually local
  A="$SRC_HOST"; B="$DST_HOST"
fi

paths=()
if [[ "$SYNC_MIRRORS" == "1" ]]; then
  if [[ "${FORCE_MIRROR_RSYNC:-0}" == "1" ]]; then
    echo "WARN: FORCE_MIRROR_RSYNC=1 — rsyncing live git mirrors is unsafe" >&2
    paths+=(mirrors)
  else
    echo "refusing SYNC_MIRRORS=1 without FORCE_MIRROR_RSYNC=1 (seed each host with git fetch)" >&2
  fi
fi
[[ "$SYNC_TOOLS" == "1" ]] && paths+=(tools)
[[ "$SYNC_IMAGES" == "1" ]] && paths+=(images)
[[ "$SYNC_CCACHE" == "1" ]] && paths+=(ccache)
[[ "$SYNC_PREFIX" == "1" ]] && paths+=(prefix)

for rel in "${paths[@]}"; do
  sync_pair "$A" "$B" "$rel"
done

echo "SYNC_OK mode=$MODE src=$A dst=$B paths=${paths[*]}"
