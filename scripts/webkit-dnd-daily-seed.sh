#!/usr/bin/env bash
# Daily (or on-demand) maintenance: update git mirrors, refresh GHCR builder image, peer sync.
# Holds awake via MAINTENANCE_LOCK so idle watchdog will not deallocate mid-run.
set -u
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
LOG=/var/log/webkit-dnd-daily-seed.log
LOCK=/etc/webkit-dnd/MAINTENANCE_LOCK
mkdir -p "$CACHE" /etc/webkit-dnd "$(dirname "$LOG")"
exec >>"$LOG" 2>&1 || true
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) daily seed start ===="
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"; echo lock cleared' EXIT

# activity stamp so idle clock resets after maintenance
mkdir -p "$CACHE/out"
date -u +%s > "$CACHE/out/last-runner-activity"

# mirrors
if [[ -x /usr/local/sbin/seed-runner-mirrors.sh ]]; then
  /usr/local/sbin/seed-runner-mirrors.sh || true
elif [[ -f /opt/webkit-dnd/seed-runner-mirrors.sh ]]; then
  bash /opt/webkit-dnd/seed-runner-mirrors.sh || true
else
  mkdir -p "$CACHE/mirrors"
  for spec in \
    "WebKit|https://github.com/WebKit/WebKit.git" \
    "WebKit-sirredbeard|https://github.com/sirredbeard/WebKit.git" \
    "epiphany|https://gitlab.gnome.org/GNOME/epiphany.git"
  do
    name=${spec%%|*}
    url=${spec#*|}
    path="$CACHE/mirrors/${name}.git"
    if [[ -d "$path" ]]; then
      git -C "$path" fetch --all --prune --tags 2>&1 | tail -3 || true
    else
      git clone --mirror "$url" "$path" 2>&1 | tail -5 || true
    fi
  done
fi

# GHCR builder: try docker pull if credentials exist; else leave tarball seed
OWNER="${GITHUB_REPOSITORY_OWNER:-sirredbeard}"
IMAGE_NAME=webkitgtk-dnd-fix-builder
if command -v docker >/dev/null; then
  if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-}" ]]; then
    echo "$GH_TOKEN" | docker login ghcr.io -u "$OWNER" --password-stdin 2>/dev/null || true
  fi
  TAG=$(gh api --paginate "/users/${OWNER}/packages/container/${IMAGE_NAME}/versions" \
    --jq '[.[].metadata.container.tags[]?] | map(select(test("^[0-9]{8}$"))) | sort | reverse | .[0] // empty' 2>/dev/null || true)
  if [[ -n "$TAG" ]]; then
    IMG="ghcr.io/${OWNER}/${IMAGE_NAME}:${TAG}"
    docker pull "$IMG" 2>&1 | tail -5 || true
    mkdir -p "$CACHE/images"
    SAVE="$CACHE/images/${IMAGE_NAME}-${TAG}.tar.zst"
    if docker image inspect "$IMG" >/dev/null 2>&1; then
      docker save "$IMG" | zstd -T0 -1 -o "$SAVE" 2>/dev/null || true
    fi
  fi
  # load newest local tarball if pull failed
  SEED=$(ls -1 "$CACHE/images/${IMAGE_NAME}"-*.tar.zst 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$SEED" ]]; then
    zstd -dc "$SEED" | docker load 2>&1 | tail -3 || true
  fi
fi

# peer sync last
if [[ -x /usr/local/sbin/webkit-dnd-peer-sync.sh ]]; then
  /usr/local/sbin/webkit-dnd-peer-sync.sh || true
elif [[ -x /usr/local/sbin/webkit-dnd-cache-sync.sh ]]; then
  /usr/local/sbin/webkit-dnd-cache-sync.sh || true
fi

chown -R gha:docker "$CACHE" 2>/dev/null || true
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) daily seed end ===="
exit 0
