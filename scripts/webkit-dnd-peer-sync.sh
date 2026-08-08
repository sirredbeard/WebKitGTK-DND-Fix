#!/usr/bin/env bash
# Bidirectional peer cache sync. Quiet if peer down. Exit 0 unless SYNC_STRICT=1.
# SYNC_MODE=full|ccache|prefix|images|quick|buildsnap  (default quick)
set -u
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
LOG="${SYNC_LOG:-/var/log/webkit-dnd-cache-sync.log}"
PEERS="${PEER_HOSTS:-20.127.61.97 155.138.194.251}"
SSH_KEY="${SYNC_SSH_KEY:-/root/.ssh/id_ed25519_cache}"
SSH_USER="${SYNC_SSH_USER:-root}"
MODE="${SYNC_MODE:-quick}"
IMAGE_NAME="${IMAGE_NAME:-webkitgtk-dnd-fix-builder}"

mkdir -p "$(dirname "$LOG")" "$CACHE"
exec >>"$LOG" 2>&1 || true
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) peer-sync mode=${MODE} ===="
[[ -f "$SSH_KEY" ]] || { echo "no ssh key"; exit 0; }

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=6
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts -o Compression=no)
RSYNC=(rsync -aH --partial --inplace --timeout=90 --human-readable)
# hostname -I is often only the private NIC. Azure/Vultr public IPs used as
# PEER_HOSTS will not appear there. SELF_IPS (space-separated) should list this
# host's public address. We also try a default-route src and curl metadata.
my_ips=$(hostname -I 2>/dev/null || true)
my_ips="$my_ips ${SELF_IPS:-}"
if command -v ip >/dev/null 2>&1; then
  my_ips="$my_ips $(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
fi
# Best-effort public IP (no fail if offline).
pub=$(curl -4 -fsS --max-time 2 ifconfig.me 2>/dev/null || curl -4 -fsS --max-time 2 icanhazip.com 2>/dev/null || true)
my_ips="$my_ips $pub"
rsync_e() { printf 'ssh'; for o in "${SSH_OPTS[@]}"; do printf ' %q' "$o"; done; }

sync_dir() {
  local ip="$1" rel="$2"
  mkdir -p "$CACHE/$rel"
  "${RSYNC[@]}" -e "$(rsync_e)" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/$rel/" "$CACHE/$rel/" 2>/dev/null || echo "pull $rel quiet"
  "${RSYNC[@]}" -e "$(rsync_e)" "$CACHE/$rel/" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/$rel/" 2>/dev/null || echo "push $rel quiet"
}

sync_prefix_handoff() {
  local ip="$1" local_sz remote_sz local_sha remote_sha winner=""
  mkdir -p "$CACHE/prefix" "$CACHE/out"
  # Prefer the larger tip-sized last-good and matching stamp. Blind bidirectional
  # rsync re-spread a 48M d5bec last-good over a 96M tip handoff.
  local_sz=$(stat -c%s "$CACHE/prefix/webkitgtk-prefix-last-good.tar.zst" 2>/dev/null || echo 0)
  remote_sz=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "stat -c%s /var/cache/webkit-dnd/prefix/webkitgtk-prefix-last-good.tar.zst 2>/dev/null || echo 0" 2>/dev/null || echo 0)
  local_sha=$(tr -cd '0-9a-f' <"$CACHE/prefix/.webkitgtk-dnd-sha" 2>/dev/null | head -c 40 || true)
  remote_sha=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "tr -cd '0-9a-f' </var/cache/webkit-dnd/prefix/.webkitgtk-dnd-sha 2>/dev/null | head -c 40 || true" 2>/dev/null || true)
  if [[ "${local_sz}" -gt "${remote_sz}" ]]; then
    winner=local
  elif [[ "${remote_sz}" -gt "${local_sz}" ]]; then
    winner=remote
  elif [[ -n "${local_sha}" && -n "${remote_sha}" && "${local_sha}" != "${remote_sha}"* && "${remote_sha}" != "${local_sha}"* ]]; then
    # same size, different sha — prefer local to avoid thrash
    winner=local
  else
    winner=local
  fi
  echo "prefix handoff winner=${winner} local=${local_sz}b/${local_sha:-?} remote=${remote_sz}b/${remote_sha:-?}"
  if [[ "${winner}" == remote && "${remote_sz}" -gt 0 ]]; then
    for f in webkitgtk-prefix-last-good.tar.zst .webkitgtk-dnd-sha; do
      "${RSYNC[@]}" -e "$(rsync_e)" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/prefix/$f" "$CACHE/prefix/" 2>/dev/null || true
    done
    "${RSYNC[@]}" -e "$(rsync_e)" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/out/last-good-prefix-sha" "$CACHE/out/" 2>/dev/null || true
  fi
  if [[ -f "$CACHE/prefix/webkitgtk-prefix-last-good.tar.zst" ]]; then
    "${RSYNC[@]}" -e "$(rsync_e)" "$CACHE/prefix/webkitgtk-prefix-last-good.tar.zst" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/prefix/" 2>/dev/null || true
  fi
  if [[ -f "$CACHE/prefix/.webkitgtk-dnd-sha" ]]; then
    "${RSYNC[@]}" -e "$(rsync_e)" "$CACHE/prefix/.webkitgtk-dnd-sha" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/prefix/" 2>/dev/null || true
  fi
  if [[ -f "$CACHE/out/last-good-prefix-sha" ]]; then
    "${RSYNC[@]}" -e "$(rsync_e)" "$CACHE/out/last-good-prefix-sha" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/out/" 2>/dev/null || true
  fi
}

sync_newest_image() {
  local ip="$1" local_new remote_new
  mkdir -p "$CACHE/images"
  local_new=$(ls -1t "$CACHE/images/${IMAGE_NAME}-"*.tar.zst 2>/dev/null | head -1 || true)
  remote_new=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "ls -1t /var/cache/webkit-dnd/images/${IMAGE_NAME}-*.tar.zst 2>/dev/null | head -1" 2>/dev/null || true)
  if [[ -n "$remote_new" ]]; then
    "${RSYNC[@]}" -e "$(rsync_e)" "${SSH_USER}@${ip}:$remote_new" "$CACHE/images/" 2>/dev/null || true
  fi
  if [[ -n "$local_new" ]]; then
    "${RSYNC[@]}" -e "$(rsync_e)" "$local_new" "${SSH_USER}@${ip}:/var/cache/webkit-dnd/images/" 2>/dev/null || true
  fi
}

for ip in $PEERS; do
  [[ " $my_ips " == *" $ip "* ]] && { echo "skip self $ip"; continue; }
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" true 2>/dev/null || { echo "peer unreachable $ip"; continue; }
  echo "sync $ip mode=$MODE"
  case "$MODE" in
    ccache) sync_dir "$ip" ccache ;;
    prefix) sync_prefix_handoff "$ip"; [[ "${SYNC_PREFIX_TREE:-0}" == "1" ]] && sync_dir "$ip" prefix ;;
    images) sync_newest_image "$ip"; sync_dir "$ip" images ;;
    buildsnap) mkdir -p "$CACHE/build-snapshots"; sync_dir "$ip" build-snapshots ;;
    quick)  sync_dir "$ip" ccache; sync_prefix_handoff "$ip"; sync_newest_image "$ip"
            mkdir -p "$CACHE/build-snapshots"; sync_dir "$ip" build-snapshots ;;
    full|*) # NEVER rsync live git object stores (mirrors/*.git) — packs go inconsistent mid-write.
            # Hosts seed their own mirrors via git fetch under flock (seed-runner-mirrors.sh).
            for rel in tools images ccache build-snapshots; do sync_dir "$ip" "$rel"; done
            sync_prefix_handoff "$ip"
            [[ "${SYNC_PREFIX_TREE:-0}" == "1" ]] && sync_dir "$ip" prefix ;;
  esac
  chown -R gha:docker "$CACHE" 2>/dev/null || true
done
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) peer-sync end ===="
exit 0
