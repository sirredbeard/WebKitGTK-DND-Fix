#!/usr/bin/env bash
# Export key builder image(s) to OS-disk zstd seeds. Safe concurrent; flock.
# Does not block builds — nice/ionice, short timeout optional.
set -u
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
SEED_DIR="${CACHE}/images"
IMAGE_NAME="${IMAGE_NAME:-webkitgtk-dnd-fix-builder}"
OWNER="${IMAGE_OWNER:-sirredbeard}"
LOCK="${CACHE}/out/docker-seed-export.lock"
LOG="${CACHE}/out/docker-seed-export.log"
mkdir -p "$SEED_DIR" "$(dirname "$LOG")"

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "seed-export already running" >>"$LOG"
  exit 0
fi

{
  echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) seed-export ===="
  mapfile -t tags < <(docker images --format '{{.Repository}}:{{.Tag}}' \
    | grep -E "^ghcr.io/${OWNER}/${IMAGE_NAME}:" || true)
  if [[ ${#tags[@]} -eq 0 ]]; then
    # bare name tags
    mapfile -t tags < <(docker images --format '{{.Repository}}:{{.Tag}}' \
      | grep -E "${IMAGE_NAME}:" | head -5 || true)
  fi
  for ref in "${tags[@]}"; do
    [[ "$ref" == *"<none>"* ]] && continue
    tag="${ref##*:}"
    [[ "$tag" =~ ^[0-9]{8}$ || "$tag" == "latest" ]] || continue
    out="${SEED_DIR}/${IMAGE_NAME}-${tag}.tar.zst"
    # skip if seed newer than 12h and non-trivial size
    if [[ -f "$out" ]]; then
      age=$(( $(date +%s) - $(stat -c %Y "$out" 2>/dev/null || echo 0) ))
      sz=$(stat -c %s "$out" 2>/dev/null || echo 0)
      if (( age < 43200 && sz > 10000000 )); then
        echo "skip fresh seed $out age=${age}s"
        continue
      fi
    fi
    tmp="${out}.partial.$$"
    echo "export $ref -> $out"
    if nice -n 15 ionice -c3 docker save "$ref" 2>>"$LOG" | nice -n 15 ionice -c3 zstd -T0 -1 -o "$tmp"; then
      mv -f "$tmp" "$out"
      chown gha:docker "$out" 2>/dev/null || chown gha:gha "$out" 2>/dev/null || true
      ls -lh "$out"
    else
      rm -f "$tmp"
      echo "export failed $ref"
    fi
  done
  # keep last 5 seeds only
  ls -1t "$SEED_DIR"/${IMAGE_NAME}-*.tar.zst 2>/dev/null | tail -n +6 | xargs -r rm -f
  echo "==== seed-export done ===="
} >>"$LOG" 2>&1
exit 0
