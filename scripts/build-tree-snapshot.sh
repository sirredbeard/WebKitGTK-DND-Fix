#!/usr/bin/env bash
# Snapshot / restore persistent ninja build trees for cross-host resume.
# Same Fedora builder container + same in-container paths => tree is portable enough
# with ccache; still prefer ccache as primary and snapshot as resume assist.
#
# Usage:
#   MODE=save   BUILD_HOST_DIR=... SNAP_NAME=build-gtk-unit ./build-tree-snapshot.sh
#   MODE=restore BUILD_HOST_DIR=... SNAP_NAME=build-gtk-unit ./build-tree-snapshot.sh
#   MODE=pull   # rsync newest snap from peer
#   MODE=push   # rsync local snaps to peer
set -u
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SNAP_ROOT="${SNAPSHOT_DIR:-$CACHE/build-snapshots}"
BUILD_HOST_DIR="${BUILD_HOST_DIR:-$CACHE/build-gtk}"
SNAP_NAME="${SNAP_NAME:-build-gtk-unit}"
MODE="${MODE:-save}"
MAX_KEEP="${SNAPSHOT_MAX_KEEP:-3}"
SSH_KEY="${SYNC_SSH_KEY:-/root/.ssh/id_ed25519_cache}"
SSH_USER="${SYNC_SSH_USER:-root}"
PEERS="${PEER_HOSTS:-20.127.61.97 155.138.194.251}"
LOG="${CACHE}/out/build-tree-snapshot.log"
MIN_NINJA="${SNAPSHOT_MIN_FILES:-20}"

mkdir -p "$SNAP_ROOT" "$CACHE/out" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) mode=$MODE name=$SNAP_NAME dir=$BUILD_HOST_DIR ===="

ssh_opts=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts)

save_snap() {
  if [[ ! -f "$BUILD_HOST_DIR/build.ninja" ]]; then
    echo "no build.ninja; skip save"
    return 0
  fi
  local n
  n=$(find "$BUILD_HOST_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  if (( n < MIN_NINJA )); then
    echo "too few files ($n); skip save"
    return 0
  fi
  local ts out meta
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  out="$SNAP_ROOT/${SNAP_NAME}-${ts}.tar.zst"
  meta="$SNAP_ROOT/${SNAP_NAME}-${ts}.meta"
  {
    echo "name=$SNAP_NAME"
    echo "host=$(hostname)"
    echo "time=$ts"
    echo "build_host_dir=$BUILD_HOST_DIR"
    echo "files=$n"
    echo "bytes=$(du -sb "$BUILD_HOST_DIR" 2>/dev/null | awk '{print $1}')"
    if [[ -n "${GIT_HEAD:-}" ]]; then echo "git_head=$GIT_HEAD"; fi
    if [[ -f "${CACHE}/out/git-head.txt" ]]; then
      echo "git_head_file=$(head -1 "${CACHE}/out/git-head.txt" 2>/dev/null || true)"
    fi
  } >"$meta"
  echo "saving $out"
  # relative archive of tree contents
  if tar -C "$BUILD_HOST_DIR" -cf - . 2>/dev/null | zstd -T0 -3 -o "$out"; then
    ls -lh "$out" "$meta"
    # rotate
    ls -1t "$SNAP_ROOT"/${SNAP_NAME}-*.tar.zst 2>/dev/null | tail -n +$((MAX_KEEP + 1)) | xargs -r rm -f
    ls -1t "$SNAP_ROOT"/${SNAP_NAME}-*.meta 2>/dev/null | tail -n +$((MAX_KEEP + 1)) | xargs -r rm -f
    # stable "latest" pointers
    ln -sfn "$(basename "$out")" "$SNAP_ROOT/${SNAP_NAME}-latest.tar.zst"
    ln -sfn "$(basename "$meta")" "$SNAP_ROOT/${SNAP_NAME}-latest.meta"
    echo "SAVE_OK $out"
  else
    rm -f "$out"
    echo "SAVE_FAIL"
    return 1
  fi
}

restore_snap() {
  local src="${SNAPSHOT_FILE:-}"
  if [[ -z "$src" ]]; then
    if [[ -L "$SNAP_ROOT/${SNAP_NAME}-latest.tar.zst" || -f "$SNAP_ROOT/${SNAP_NAME}-latest.tar.zst" ]]; then
      src="$SNAP_ROOT/${SNAP_NAME}-latest.tar.zst"
      # resolve symlink
      if [[ -L "$src" ]]; then src="$SNAP_ROOT/$(readlink "$src")"; fi
    else
      src=$(ls -1t "$SNAP_ROOT"/${SNAP_NAME}-*.tar.zst 2>/dev/null | head -1 || true)
    fi
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    echo "no snapshot for $SNAP_NAME"
    return 0
  fi
  # skip restore if tree already looks warm unless FORCE_RESTORE=1
  if [[ "${FORCE_RESTORE:-0}" != "1" && -f "$BUILD_HOST_DIR/build.ninja" ]]; then
    local n
    n=$(find "$BUILD_HOST_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if (( n > MIN_NINJA * 2 )); then
      echo "local tree already warm ($n files); skip restore"
      return 0
    fi
  fi
  echo "restoring $src -> $BUILD_HOST_DIR"
  mkdir -p "$BUILD_HOST_DIR"
  # wipe only contents, keep mountpoint
  find "$BUILD_HOST_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  if zstd -dc "$src" | tar -C "$BUILD_HOST_DIR" -xf -; then
    echo "RESTORE_OK"
    ls "$BUILD_HOST_DIR/build.ninja" 2>/dev/null || echo "warn: no build.ninja after restore"
  else
    echo "RESTORE_FAIL"
    return 1
  fi
}

pull_peer() {
  [[ -f "$SSH_KEY" ]] || { echo "no ssh key"; return 0; }
  local my_ips ip
  my_ips=$(hostname -I 2>/dev/null || true)
  mkdir -p "$SNAP_ROOT"
  for ip in $PEERS; do
    [[ " $my_ips " == *" $ip "* ]] && continue
    ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" true 2>/dev/null || continue
    echo "pull snaps from $ip"
    rsync -aH --partial --timeout=120 -e "ssh ${ssh_opts[*]}" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/build-snapshots/" "$SNAP_ROOT/" 2>/dev/null || true
  done
}

push_peer() {
  [[ -f "$SSH_KEY" ]] || { echo "no ssh key"; return 0; }
  local my_ips ip
  my_ips=$(hostname -I 2>/dev/null || true)
  for ip in $PEERS; do
    [[ " $my_ips " == *" $ip "* ]] && continue
    ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" "mkdir -p /var/cache/webkit-dnd/build-snapshots" 2>/dev/null || continue
    echo "push snaps to $ip"
    rsync -aH --partial --timeout=120 -e "ssh ${ssh_opts[*]}" \
      "$SNAP_ROOT/" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/build-snapshots/" 2>/dev/null || true
  done
}

case "$MODE" in
  save) save_snap ;;
  restore) restore_snap ;;
  pull) pull_peer ;;
  push) push_peer ;;
  pull-restore) pull_peer; restore_snap ;;
  save-push) save_snap; push_peer ;;
  *) echo "unknown MODE=$MODE"; exit 1 ;;
esac
exit 0
