#!/usr/bin/env bash
# Seed PREFIX_HOST from a last-good / tip WebKitGTK prefix tarball.
#
# Why this got us burned:
# - webkitgtk-prefix-last-good.tar.zst was a stale 48M d5bec handoff
# - tip tarball webkitgtk-prefix-17647b*.tar.zst (96M) sat next to it unused
# - seed always rsync --delete from last-good, wiping a correct tip PREFIX
# - AppImage then packed the wrong engine while validating tip HEAD
#
# Rules:
# - If EXPECTED_WEBKIT_SHA is set, only accept a tarball/tree whose stamp matches
# - Prefer DEST that already matches expected (no-op)
# - Prefer tip-named tarballs and OUT_DIR artifacts over stale last-good
# - Never replace a matching tip tree with a non-matching last-good
set -euo pipefail

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
DEST="${PREFIX_HOST:-$CACHE/prefix}"
OUT="${OUT_DIR:-$CACHE/out}"
EXPECTED="${EXPECTED_WEBKIT_SHA:-${EXPECTED_SHA:-}}"
EXPECTED="$(printf '%s' "${EXPECTED}" | tr -cd '0-9a-fA-F' | tr 'A-F' 'a-f' | head -c 40)"
mkdir -p "$DEST" "$OUT"

log() { printf '+ %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

read_stamp() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  tr -cd '0-9a-fA-F' <"$f" | tr 'A-F' 'a-f' | head -c 40
}

stamp_matches() {
  local stamp="$1"
  [[ -n "${EXPECTED}" ]] || return 0
  [[ -n "${stamp}" ]] || return 1
  [[ "${stamp}" == "${EXPECTED}"* || "${EXPECTED}" == "${stamp}"* ]]
}

pc_ok() {
  local root="$1"
  [[ -e "$root/lib64/pkgconfig/webkitgtk-6.0.pc" || -e "$root/lib/pkgconfig/webkitgtk-6.0.pc" ]]
}

if pc_ok "$DEST"; then
  cur="$(read_stamp "$DEST/.webkitgtk-dnd-sha" || true)"
  if stamp_matches "${cur:-}"; then
    log "PREFIX already matches expected=${EXPECTED:-<any>} stamp=${cur:-none}; leave in place"
    echo "prefix_seed_ok already_present stamp=${cur:-none}" | tee "$OUT/prefix-seed.log"
    exit 0
  fi
  log "PREFIX present but stamp=${cur:-none} expected=${EXPECTED:-<any>}; will reseed"
fi

candidates=()
if [[ -n "${EXPECTED}" ]]; then
  short12="${EXPECTED:0:12}"
  short7="${EXPECTED:0:7}"
  while IFS= read -r f; do candidates+=("$f"); done < <(
    ls -1t \
      "${OUT}/webkitgtk-prefix-${short12}"*.tar.zst \
      "${OUT}/webkitgtk-prefix-${short7}"*.tar.zst \
      "${CACHE}/prefix/webkitgtk-prefix-${short12}"*.tar.zst \
      "${CACHE}/prefix/webkitgtk-prefix-${short7}"*.tar.zst \
      "${CACHE}/out/webkitgtk-prefix-${short12}"*.tar.zst \
      2>/dev/null || true
  )
fi
while IFS= read -r f; do candidates+=("$f"); done < <(
  ls -1t \
    "${OUT}"/webkitgtk-prefix-*.tar.zst \
    "${CACHE}/prefix"/webkitgtk-prefix-*.tar.zst \
    "${CACHE}/prefix"/webkitgtk-prefix-last-good.tar.zst \
    "${CACHE}/out"/webkitgtk-prefix-*.tar.zst \
    2>/dev/null || true
)
if [[ -n "${1:-}" && -f "${1}" ]]; then
  candidates=("${1}" "${candidates[@]}")
fi

declare -A seen=()
uniq=()
for f in "${candidates[@]}"; do
  [[ -f "$f" ]] || continue
  [[ -n "${seen[$f]:-}" ]] && continue
  seen[$f]=1
  uniq+=("$f")
done
candidates=("${uniq[@]}")
((${#candidates[@]})) || die "no last-good / tip prefix tarball found under ${OUT} or ${CACHE}/prefix"

extract_to() {
  local tar="$1" dest="$2"
  rm -rf "$dest"
  mkdir -p "$dest"
  local tmp
  tmp=$(mktemp -d)
  if [[ "$tar" == *.zst ]]; then
    zstd -dc "$tar" | tar -C "$tmp" -xf -
  else
    tar -C "$tmp" -xzf "$tar"
  fi
  if [[ -d "$tmp/prefix" ]] && pc_ok "$tmp/prefix"; then
    rsync -a "$tmp/prefix/" "$dest/"
  elif pc_ok "$tmp"; then
    rsync -a "$tmp/" "$dest/"
  elif [[ -e "$tmp/usr/lib64/pkgconfig/webkitgtk-6.0.pc" || -e "$tmp/usr/lib/pkgconfig/webkitgtk-6.0.pc" ]]; then
    rsync -a "$tmp/usr/" "$dest/"
  else
    local top
    top=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1 || true)
    if [[ -n "$top" ]] && pc_ok "$top"; then
      rsync -a "$top/" "$dest/"
    else
      rm -rf "$tmp"
      return 1
    fi
  fi
  rm -rf "$tmp"
  pc_ok "$dest"
}

picked=""
picked_sha=""
for tar in "${candidates[@]}"; do
  log "try $tar ($(stat -c%s "$tar" 2>/dev/null || echo ?) bytes)"
  trial=$(mktemp -d)
  if ! extract_to "$tar" "$trial"; then
    log "skip unrecognized layout: $tar"
    rm -rf "$trial"
    continue
  fi
  sha="$(read_stamp "$trial/.webkitgtk-dnd-sha" || true)"
  if [[ -z "${sha}" ]]; then
    base="$(basename "$tar")"
    if [[ "$base" =~ webkitgtk-prefix-([0-9a-f]{7,40}) ]]; then
      sha="${BASH_REMATCH[1]}"
    fi
  fi
  if stamp_matches "${sha:-}"; then
    picked="$tar"
    picked_sha="$sha"
    # DEST holds both the install tree and handoff tarballs (last-good, tip-*.tar.zst).
    # Never mv/rm the whole DEST — that deleted the 96M tip tarball and left us
    # re-seeding from a stale 48M last-good peer copy.
    mkdir -p "$DEST"
    rsync -a --delete \
      --exclude 'webkitgtk-prefix-*.tar.zst' \
      --exclude 'webkitgtk-prefix-last-good.tar.zst' \
      --exclude '.webkitgtk-dnd-sha' \
      --exclude 'last-good-prefix-sha' \
      "$trial/" "$DEST/"
    rm -rf "$trial"
    break
  fi
  log "skip stamp=${sha:-none} does not match expected=${EXPECTED:-<any>}"
  rm -rf "$trial"
done

[[ -n "$picked" ]] || die "no prefix tarball matched expected=${EXPECTED:-<any>} (refusing stale last-good)"
pc_ok "$DEST" || die "seeded tree missing webkitgtk-6.0.pc"

if [[ -n "${picked_sha}" ]]; then
  if [[ -n "${EXPECTED}" && ${#EXPECTED} -ge 12 ]]; then
    printf '%s' "${EXPECTED}" >"$DEST/.webkitgtk-dnd-sha"
    picked_sha="${EXPECTED}"
  else
    printf '%s' "${picked_sha}" >"$DEST/.webkitgtk-dnd-sha"
  fi
fi

if [[ -z "${EXPECTED}" ]] || stamp_matches "$(read_stamp "$DEST/.webkitgtk-dnd-sha" || true)"; then
  mkdir -p "$CACHE/prefix" "$CACHE/out"
  cp -f "$picked" "$CACHE/prefix/webkitgtk-prefix-last-good.tar.zst"
  printf '%s' "$(read_stamp "$DEST/.webkitgtk-dnd-sha" || true)" >"$CACHE/out/last-good-prefix-sha"
fi

{
  echo "prefix_seed_ok"
  echo "tarball=${picked}"
  echo "stamp=$(read_stamp "$DEST/.webkitgtk-dnd-sha" || true)"
  echo "expected=${EXPECTED:-<any>}"
  ls -la "$DEST/lib64/pkgconfig/webkitgtk-6.0.pc" "$DEST/lib/pkgconfig/webkitgtk-6.0.pc" 2>/dev/null || true
} | tee "$OUT/prefix-seed.log"

log "seeded stamp=$(read_stamp "$DEST/.webkitgtk-dnd-sha" || true) from $picked"
exit 0
