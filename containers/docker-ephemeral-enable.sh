#!/usr/bin/env bash
# Move Docker data-root to Azure resource disk (/mnt) for speed.
# Gate: DOCKER_ON_EPHEMERAL=1 force, or AUTO and uptime >= MIN_UPTIME_HOURS (default 2).
# Never runs while containers/jobs active unless FORCE=1.
# Persists seeds to OS disk before switch; loads seeds after.
set -euo pipefail

EPHEM="${WEBKIT_DND_EPHEMERAL:-/mnt}"
DATA="${EPHEM}/webkit-dnd/docker"
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
MIN_H="${AUTO_DOCKER_EPHEMERAL_HOURS:-2}"
FLAG="${CACHE}/out/docker-on-ephemeral.enabled"
LOG="${CACHE}/out/docker-ephemeral.log"
mkdir -p "$CACHE/out" "$(dirname "$LOG")"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG"; }

uptime_h() {
  local s
  s=$(cut -d. -f1 /proc/uptime)
  echo $(( s / 3600 ))
}

if [[ "${DOCKER_ON_EPHEMERAL:-}" == "0" ]]; then
  log "DOCKER_ON_EPHEMERAL=0; skip"
  exit 0
fi

uh=$(uptime_h)
if [[ "${DOCKER_ON_EPHEMERAL:-}" != "1" ]]; then
  # auto mode
  if (( uh < MIN_H )); then
    log "uptime ${uh}h < ${MIN_H}h; not enabling ephemeral docker yet"
    exit 0
  fi
  log "auto-enable: uptime ${uh}h >= ${MIN_H}h"
else
  log "forced DOCKER_ON_EPHEMERAL=1 (uptime ${uh}h)"
fi

if [[ ! -d "$EPHEM" ]] || ! mountpoint -q "$EPHEM" 2>/dev/null; then
  log "no ephemeral mount at $EPHEM"
  exit 1
fi

# already enabled?
if [[ -f "$FLAG" ]] && grep -q "$DATA" /etc/docker/daemon.json 2>/dev/null; then
  log "already on ephemeral"
  # still ensure load
  /usr/local/sbin/docker-seed-load.sh || true
  exit 0
fi

if [[ "${FORCE:-0}" != "1" ]]; then
  if pgrep -f 'Runner.Worker' >/dev/null 2>&1; then
    log "Runner.Worker active; skip migrate"
    exit 0
  fi
  if docker ps -q 2>/dev/null | grep -q .; then
    log "containers running; skip migrate"
    exit 0
  fi
fi

log "export seeds from current graph (best effort)"
/usr/local/sbin/docker-seed-export.sh || true

log "stop docker"
systemctl stop docker docker.socket containerd 2>/dev/null || systemctl stop docker || true
sleep 2

mkdir -p "$DATA"
# optional: copy existing graph once (slow) — prefer empty + seed load for speed
if [[ "${MIGRATE_GRAPH:-0}" == "1" && -d /var/lib/docker ]] && [[ -n "$(ls -A /var/lib/docker 2>/dev/null || true)" ]]; then
  log "rsync graph to ephemeral (MIGRATE_GRAPH=1)"
  rsync -aH --info=progress2 /var/lib/docker/ "$DATA/" || true
fi

mkdir -p /etc/docker
cat > /etc/docker/daemon.json << JSON
{
  "data-root": "${DATA}",
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" },
  "live-restore": true,
  "storage-driver": "overlay2",
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 1048576 }
  }
}
JSON

# bind-mount hot build dirs on ephemeral too
mkdir -p "$EPHEM/webkit-dnd"/{build-gtk,buildx-cache,tmp}
if [[ ! -L "${CACHE}/build-gtk" ]]; then
  if [[ -d "${CACHE}/build-gtk" && -z "$(ls -A "${CACHE}/build-gtk" 2>/dev/null || true)" ]]; then
    rmdir "${CACHE}/build-gtk" 2>/dev/null || true
  fi
  if [[ ! -e "${CACHE}/build-gtk" ]]; then
    ln -sfn "$EPHEM/webkit-dnd/build-gtk" "${CACHE}/build-gtk"
  fi
fi

systemctl daemon-reload
systemctl start containerd 2>/dev/null || true
systemctl start docker
sleep 2
docker info 2>/dev/null | grep -E 'Docker Root|Storage' | tee -a "$LOG" || true

log "load seeds into new graph"
/usr/local/sbin/docker-seed-load.sh || true

echo "$(date -u -Iseconds) root=${DATA}" >"$FLAG"
chown gha:docker "$FLAG" 2>/dev/null || true

# timer: non-blocking seed export every 30m while up
cat > /etc/systemd/system/webkit-dnd-docker-seed-export.service << 'U'
[Unit]
Description=Export docker builder image seeds to OS disk
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
Nice=15
IOSchedulingClass=idle
ExecStart=/usr/local/sbin/docker-seed-export.sh
U
cat > /etc/systemd/system/webkit-dnd-docker-seed-export.timer << 'U'
[Unit]
Description=Periodic docker seed export to OS disk
[Timer]
OnBootSec=20m
OnUnitActiveSec=30m
AccuracySec=5m
Persistent=true
[Install]
WantedBy=timers.target
U
systemctl daemon-reload
systemctl enable --now webkit-dnd-docker-seed-export.timer

# boot path: load seeds early
cat > /etc/systemd/system/webkit-dnd-docker-seed-load.service << 'U'
[Unit]
Description=Load docker image seeds after docker start
After=docker.service
Wants=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker-seed-load.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
U
systemctl enable webkit-dnd-docker-seed-load.service

log "DOCKER_ON_EPHEMERAL enabled at ${DATA}"
exit 0
