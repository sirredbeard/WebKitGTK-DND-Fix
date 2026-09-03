#!/usr/bin/env bash
# Pre-build peer warm: ccache (+ optional last-good prefix tarball + builder image seed). Git mirrors are host-local only.
# Block a little (default ~5 min) for ccache. Soft-fail unless STRICT=1.
set -u

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SSH_KEY="${SYNC_SSH_KEY:-/root/.ssh/id_ed25519_cache}"
SSH_USER="${SYNC_SSH_USER:-root}"
PEERS="${PEER_HOSTS:-20.127.61.97 155.138.194.251}"
TIMEOUT_SEC="${WARM_TIMEOUT_SEC:-300}"
WARM_PREFIX="${WARM_PREFIX:-1}"
WARM_IMAGES="${WARM_IMAGES:-1}"
MIN_USEFUL_MB="${WARM_MIN_USEFUL_MB:-64}"
IMAGE_NAME="${IMAGE_NAME:-webkitgtk-dnd-fix-builder}"
LOG="${CACHE}/out/warm-ccache-from-peer.log"

mkdir -p "$CACHE/ccache" "$CACHE/prefix" "$CACHE/out" "$CACHE/mirrors" "$CACHE/images"
exec > >(tee -a "$LOG" 2>/dev/null || cat) 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) warm start timeout=${TIMEOUT_SEC}s ===="

if [[ ! -f "$SSH_KEY" ]]; then
  echo "no peer ssh key; skip warm"
  exit 0
fi

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=4
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts
  -o Compression=no -o ServerAliveInterval=15)
RSYNC_BASE=(rsync -aH --partial --inplace --info=stats1 --timeout=60 --human-readable)
if [[ "${RSYNC_COMPRESS:-0}" == "1" ]]; then RSYNC_BASE+=(-z); fi

my_ips=$(hostname -I 2>/dev/null || true)
before_bytes=$(du -sb "$CACHE/ccache" 2>/dev/null | awk '{print $1}' || echo 0)
echo "local_ccache_bytes=${before_bytes}"

best_ip=""; best_sz=0
declare -A PEER_OK
for ip in $PEERS; do
  if [[ " $my_ips " == *" $ip "* ]]; then echo "skip self $ip"; continue; fi
  if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" true 2>/dev/null; then
    echo "peer down $ip"; continue
  fi
  PEER_OK[$ip]=1
  sz=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "du -sb /var/cache/webkit-dnd/ccache 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo 0)
  sz=${sz:-0}
  echo "peer $ip ccache_bytes=$sz"
  if (( sz > best_sz )); then best_sz=$sz; best_ip=$ip; fi
done

if [[ -z "$best_ip" ]]; then
  echo "no reachable peer; skip"; exit 0
fi

if (( before_bytes > MIN_USEFUL_MB * 1024 * 1024 && before_bytes * 10 > best_sz * 9 )); then
  echo "local ccache competitive; quick delta (90s)"
  if (( TIMEOUT_SEC > 90 )); then TIMEOUT_SEC=90; fi
fi

deadline=$((SECONDS + TIMEOUT_SEC))
warmed=0
rsync_e() { printf 'ssh'; for o in "${SSH_OPTS[@]}"; do printf ' %q' "$o"; done; }

pull_ccache() {
  local ip="$1" remain
  remain=$((deadline - SECONDS)); (( remain < 15 )) && return 1
  echo "pull ccache from $ip budget=${remain}s"
  mkdir -p "$CACHE/ccache"
  if timeout "$remain" "${RSYNC_BASE[@]}" -e "$(rsync_e)" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/ccache/" "$CACHE/ccache/"; then
    warmed=1
  else
    echo "ccache soft-fail $ip"
  fi
}

pull_prefix_tb() {
  local ip="$1" remain local_sz remote_sz local_sha remote_sha
  remain=$((deadline - SECONDS)); (( remain < 20 )) && return 0
  echo "pull last-good prefix tarball from $ip budget=${remain}s"
  mkdir -p "$CACHE/prefix" "$CACHE/out"
  # Never clobber a larger/newer local tip handoff with a smaller stale peer last-good
  # (d5bec 48M overwrote tip 96M path before).
  local_sz=$(stat -c%s "$CACHE/prefix/webkitgtk-prefix-last-good.tar.zst" 2>/dev/null || echo 0)
  remote_sz=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "stat -c%s /var/cache/webkit-dnd/prefix/webkitgtk-prefix-last-good.tar.zst 2>/dev/null || echo 0" 2>/dev/null || echo 0)
  local_sha=$(tr -cd '0-9a-f' <"$CACHE/prefix/.webkitgtk-dnd-sha" 2>/dev/null | head -c 40 || true)
  remote_sha=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "tr -cd '0-9a-f' </var/cache/webkit-dnd/prefix/.webkitgtk-dnd-sha 2>/dev/null | head -c 40 || true" 2>/dev/null || true)
  if [[ "${local_sz}" -gt 0 && "${remote_sz}" -gt 0 && "${local_sz}" -gt "${remote_sz}" ]]; then
    echo "keep local last-good (${local_sz}b sha=${local_sha:-?}) > peer ${ip} (${remote_sz}b sha=${remote_sha:-?})"
    return 0
  fi
  if [[ -n "${local_sha}" && -n "${remote_sha}" && "${local_sha}" == "${remote_sha}"* ]]; then
    echo "local prefix sha already matches peer ${ip} (${local_sha}); skip pull"
    return 0
  fi
  timeout "$remain" "${RSYNC_BASE[@]}" -e "$(rsync_e)" \
    "${SSH_USER}@${ip}:/var/cache/webkit-dnd/prefix/webkitgtk-prefix-last-good.tar.zst" \
    "$CACHE/prefix/" 2>/dev/null || true
  timeout 30 "${RSYNC_BASE[@]}" -e "$(rsync_e)" \
    "${SSH_USER}@${ip}:/var/cache/webkit-dnd/prefix/.webkitgtk-dnd-sha" \
    "$CACHE/prefix/" 2>/dev/null || true
  timeout 30 "${RSYNC_BASE[@]}" -e "$(rsync_e)" \
    "${SSH_USER}@${ip}:/var/cache/webkit-dnd/out/last-good-prefix-sha" \
    "$CACHE/out/" 2>/dev/null || true
}

pull_images() {
  local ip="$1" remain newest
  remain=$((deadline - SECONDS)); (( remain < 30 )) && return 0
  mkdir -p "$CACHE/images"
  # newest remote builder seed
  newest=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
    "ls -1t /var/cache/webkit-dnd/images/${IMAGE_NAME}-*.tar.zst 2>/dev/null | head -1" 2>/dev/null || true)
  [[ -n "$newest" ]] || return 0
  local base; base=$(basename "$newest")
  if [[ -f "$CACHE/images/$base" ]]; then
    echo "image seed already local: $base"
  else
    echo "pull image seed $base from $ip budget=${remain}s"
    timeout "$remain" "${RSYNC_BASE[@]}" -e "$(rsync_e)" \
      "${SSH_USER}@${ip}:/var/cache/webkit-dnd/images/$base" "$CACHE/images/" 2>/dev/null || true
  fi
  # load into docker if tag missing
  if ! docker image inspect "ghcr.io/sirredbeard/${IMAGE_NAME}:${base#${IMAGE_NAME}-}" >/dev/null 2>&1 \
     && ! docker image inspect "ghcr.io/sirredbeard/${IMAGE_NAME}:${base#${IMAGE_NAME}-}" >/dev/null 2>&1; then
    tag="${base#${IMAGE_NAME}-}"; tag="${tag%.tar.zst}"
    if [[ -f "$CACHE/images/$base" ]] && command -v zstd >/dev/null 2>&1; then
      echo "docker load $base -> tag $tag"
      zstd -dc "$CACHE/images/$base" | docker load || true
      # ensure expected tag name if load used a different ref
      docker images --format '{{.Repository}}:{{.Tag}}' | grep -F "${IMAGE_NAME}" | head -5 || true
    fi
  fi
}

pull_ccache "$best_ip" || true
for ip in $PEERS; do
  [[ "$ip" == "$best_ip" ]] && continue
  [[ -z "${PEER_OK[$ip]:-}" ]] && continue
  (( SECONDS >= deadline )) && break
  pull_ccache "$ip" || true
done
if [[ "$WARM_PREFIX" == "1" ]] && (( SECONDS < deadline )); then
  pull_prefix_tb "$best_ip" || true
fi
if [[ "$WARM_IMAGES" == "1" ]] && (( SECONDS < deadline )); then
  pull_images "$best_ip" || true
fi
# mirrors: never peer-rsync; each host seeds via seed-runner-mirrors.sh

chown -R gha:docker "$CACHE/ccache" "$CACHE/prefix" "$CACHE/images" 2>/dev/null || true
after_bytes=$(du -sb "$CACHE/ccache" 2>/dev/null | awk '{print $1}' || echo 0)
echo "local_ccache_bytes_after=${after_bytes} delta=$((after_bytes - before_bytes))"
CCACHE_DIR="$CACHE/ccache" ccache -s 2>/dev/null | tail -12 || true
echo "==== warm done warmed=${warmed} ===="
[[ "${STRICT:-0}" == "1" && "$warmed" != "1" ]] && exit 1

# Optional ninja tree resume assist
if [[ "${WARM_BUILD_SNAP:-1}" == "1" && -x /usr/local/sbin/build-tree-snapshot.sh ]]; then
  remain=$((deadline - SECONDS))
  if (( remain > 45 )); then
    echo "pull/restore build snapshot budget=${remain}s"
    timeout "$remain" env MODE=pull /usr/local/sbin/build-tree-snapshot.sh || true
    SNAP_NAME="${SNAP_NAME:-build-gtk-unit}" BUILD_HOST_DIR="${BUILD_HOST_DIR:-$CACHE/build-gtk}"       MODE=restore /usr/local/sbin/build-tree-snapshot.sh || true
  fi
fi

exit 0
