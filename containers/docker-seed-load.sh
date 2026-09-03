#!/usr/bin/env bash
# Load OS-disk image seeds if docker lacks the builder tag. Fast path for ephemeral graph.
set -u
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SEED_DIR="${CACHE}/images"
IMAGE_NAME="${IMAGE_NAME:-webkitgtk-dnd-fix-builder}"
OWNER="${IMAGE_OWNER:-sirredbeard}"
LOG="${CACHE}/out/docker-seed-load.log"
mkdir -p "$SEED_DIR" "$(dirname "$LOG")"
{
  echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) seed-load ===="
  shopt -s nullglob
  for seed in "$SEED_DIR"/${IMAGE_NAME}-*.tar.zst; do
    base=$(basename "$seed")
    tag="${base#${IMAGE_NAME}-}"
    tag="${tag%.tar.zst}"
    ref="ghcr.io/${OWNER}/${IMAGE_NAME}:${tag}"
    if docker image inspect "$ref" >/dev/null 2>&1; then
      echo "present $ref"
      continue
    fi
    echo "load $seed -> $ref"
    if zstd -dc "$seed" | docker load; then
      # ensure expected tag if load used different name
      docker image inspect "$ref" >/dev/null 2>&1 || \
        docker tag "$(docker images -q | head -1)" "$ref" 2>/dev/null || true
    else
      echo "load failed $seed"
    fi
  done
  docker images | head -10 || true
  echo "==== seed-load done ===="
} >>"$LOG" 2>&1
exit 0
