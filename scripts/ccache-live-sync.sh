#!/usr/bin/env bash
# During-build background ccache push/pull. Does not block the build.
# Usage: ccache-live-sync.sh start|stop|once
set -u

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SSH_KEY="${SYNC_SSH_KEY:-/root/.ssh/id_ed25519_cache}"
SSH_USER="${SYNC_SSH_USER:-root}"
PEERS="${PEER_HOSTS:-20.127.61.97 155.138.194.251}"
INTERVAL="${LIVE_SYNC_INTERVAL_SEC:-180}"
PIDFILE="${CACHE}/out/ccache-live-sync.pid"
LOG="${CACHE}/out/ccache-live-sync.log"
WORKER="${CACHE}/out/ccache-live-sync-worker.sh"

mkdir -p "$CACHE/ccache" "$CACHE/out"

push_pull_once() {
  [[ -f "$SSH_KEY" ]] || return 0
  local my_ips ip peer
  my_ips=$(hostname -I 2>/dev/null || true)
  for ip in $PEERS; do
    [[ " $my_ips " == *" $ip "* ]] && continue
    peer="${SSH_USER}@${ip}"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=4 \
      -o StrictHostKeyChecking=accept-new -o Compression=no \
      "$peer" true 2>/dev/null || continue
    timeout 90 rsync -aH --partial --inplace --timeout=45 \
      -e "ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new -o Compression=no" \
      "$CACHE/ccache/" "$peer:/var/cache/webkit-dnd/ccache/" >>"$LOG" 2>&1 || true
    timeout 90 rsync -aH --partial --inplace --timeout=45 \
      -e "ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new -o Compression=no" \
      "$peer:/var/cache/webkit-dnd/ccache/" "$CACHE/ccache/" >>"$LOG" 2>&1 || true
  done
  chown -R gha:docker "$CACHE/ccache" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) live-sync tick ok" >>"$LOG"
}

cmd="${1:-once}"
case "$cmd" in
  once)
    push_pull_once
    exit 0
    ;;
  start)
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
      echo "live-sync already running pid=$(cat "$PIDFILE")"
      exit 0
    fi
    cat >"$WORKER" <<WORKER
#!/usr/bin/env bash
set -u
CACHE="\${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
PIDFILE="\${CACHE}/out/ccache-live-sync.pid"
LOG="\${CACHE}/out/ccache-live-sync.log"
INTERVAL="${INTERVAL}"
SELF="/usr/local/sbin/ccache-live-sync.sh"
echo \$\$ >"\$PIDFILE"
echo "==== \$(date -u +%Y-%m-%dT%H:%M:%SZ) live-sync start interval=\${INTERVAL}s pid=\$\$ ====" >>"\$LOG"
while true; do
  "\$SELF" once || true
  sleep "\$INTERVAL"
done
WORKER
    chmod +x "$WORKER"
    if command -v systemd-run >/dev/null 2>&1; then
      systemd-run --unit="webkit-dnd-ccache-live-$RANDOM" --collect \
        --property=Nice=10 --property=KillMode=process \
        /bin/bash "$WORKER" >/dev/null 2>&1 || \
        nohup /bin/bash "$WORKER" >/dev/null 2>&1 &
    else
      nohup /bin/bash "$WORKER" >/dev/null 2>&1 &
    fi
    sleep 0.5
    echo "live-sync started pid=$(cat "$PIDFILE" 2>/dev/null || echo '?')"
    ;;
  stop)
    if [[ -f "$PIDFILE" ]]; then
      pid=$(cat "$PIDFILE" 2>/dev/null || true)
      if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 0.5
        kill -9 "$pid" 2>/dev/null || true
      fi
      rm -f "$PIDFILE"
    fi
    push_pull_once || true
    echo "live-sync stopped"
    ;;
  *)
    echo "usage: $0 start|stop|once" >&2
    exit 2
    ;;
esac
exit 0
