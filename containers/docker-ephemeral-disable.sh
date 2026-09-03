#!/usr/bin/env bash
# Point docker back at /var/lib/docker (OS disk). Export seeds first.
set -euo pipefail
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
LOG="${CACHE}/out/docker-ephemeral.log"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG"; }
/usr/local/sbin/docker-seed-export.sh || true
systemctl stop docker docker.socket 2>/dev/null || true
cat > /etc/docker/daemon.json << 'JSON'
{
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
systemctl start docker
/usr/local/sbin/docker-seed-load.sh || true
rm -f "${CACHE}/out/docker-on-ephemeral.enabled"
log "docker data-root back on OS disk"
