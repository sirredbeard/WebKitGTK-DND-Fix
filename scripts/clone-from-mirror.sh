#!/usr/bin/env bash
# Clone a git ref using a persistent bare mirror on NVMe (host-local; never peer-rsynced).
# Env: REPO_URL REF CLONE_DIR MIRROR_DIR [OUT_DIR] [EXPECTED_SHA] [DISSOCIATE]
# Fails hard if final HEAD does not match origin/REF (or EXPECTED_SHA when set).
#
# Performance without fragility:
# - --reference $MIRROR borrows local objects during clone (fast)
# - NEVER --shared (working tree must own objects after dissociate)
# - DISSOCIATE=1 by default so later mirror repair cannot hollow the tree
set -euo pipefail
REPO_URL="${REPO_URL:?}"
REF="${REF:?}"
CLONE_DIR="${CLONE_DIR:?}"
MIRROR_DIR="${MIRROR_DIR:?}"
OUT_DIR="${OUT_DIR:-/tmp}"
mkdir -p "$(dirname "${CLONE_DIR}")" "$(dirname "${MIRROR_DIR}")" "${OUT_DIR}"
log() { printf '+ %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

wipe_dir() {
  local d="$1"
  [[ -e "$d" ]] || return 0
  if mountpoint -q "$d" 2>/dev/null; then
    chmod -R u+w "$d" 2>/dev/null || true
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    if command -v sudo >/dev/null 2>&1; then
      sudo -n find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    fi
    if [[ -n "$(ls -A "$d" 2>/dev/null || true)" ]] && command -v docker >/dev/null 2>&1; then
      docker run --rm -v "$d:/wipe:rw" alpine:3.20 sh -c 'rm -rf /wipe/* /wipe/.[!.]* /wipe/..?*' 2>/dev/null || true
    fi
    if [[ -n "$(ls -A "$d" 2>/dev/null || true)" ]]; then
      echo "cannot clear mount/dir contents: $d" >&2
      return 1
    fi
    return 0
  fi
  chmod -R u+w "$d" 2>/dev/null || true
  rm -rf "$d" 2>/dev/null || true
  if [[ -e "$d" ]] && command -v sudo >/dev/null 2>&1; then
    sudo -n rm -rf "$d" 2>/dev/null || true
  fi
  if [[ -e "$d" ]] && [[ -n "$(ls -A "$d" 2>/dev/null || true)" ]]; then
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi
  if [[ -e "$d" ]] && [[ -n "$(ls -A "$d" 2>/dev/null || true)" ]]; then
    echo "cannot remove stale clone dir: $d" >&2
    return 1
  fi
}

# Prefer fork-named mirror when cloning the fork (tip objects more complete).
if [[ "${REPO_URL}" == *sirredbeard*WebKit* || "${REPO_URL}" == *sirredbeard/WebKit* ]]; then
  alt="$(dirname "${MIRROR_DIR}")/WebKit-sirredbeard.git"
  if [[ -d "${alt}/objects" || -f "${alt}/HEAD" ]]; then
    log "prefer fork mirror ${alt}"
    MIRROR_DIR="${alt}"
  fi
fi

mirror_ok=0
if [[ -d "${MIRROR_DIR}/objects" || -f "${MIRROR_DIR}/HEAD" ]]; then
  if git -C "${MIRROR_DIR}" rev-parse --is-bare-repository >/dev/null 2>&1; then
    if [[ -w "${MIRROR_DIR}" ]]; then
      log "fetch bare mirror ${MIRROR_DIR}"
      # exclusive lock vs seeders
      exec 9>"${MIRROR_DIR}.lock"
      flock -w "${MIRROR_LOCK_WAIT:-300}" 9 || log "warn: exclusive mirror lock timeout"
      git -C "${MIRROR_DIR}" remote set-url origin "${REPO_URL}" 2>/dev/null || true
      if git -C "${MIRROR_DIR}" fetch --prune origin 2>"${OUT_DIR}/mirror-fetch.err"; then
        mirror_ok=1
      else
        log "mirror fetch failed; will rebuild mirror"
        tail -20 "${OUT_DIR}/mirror-fetch.err" 2>/dev/null || true
      fi
      flock -u 9 || true
    else
      log "mirror not writable (likely :ro mount); use as-is if healthy"
      if git -C "${MIRROR_DIR}" rev-parse HEAD >/dev/null 2>&1; then
        mirror_ok=1
      fi
    fi
  fi
fi

if [[ "$mirror_ok" -eq 0 ]]; then
  if [[ -w "$(dirname "${MIRROR_DIR}")" ]] || [[ -w "${MIRROR_DIR}" ]]; then
    log "recreate bare mirror ${MIRROR_DIR}"
    exec 9>"${MIRROR_DIR}.lock"
    flock -w "${MIRROR_LOCK_WAIT:-600}" 9 || true
    wipe_dir "${MIRROR_DIR}" || true
    rm -rf "${MIRROR_DIR}" 2>/dev/null || true
    git clone --mirror "${REPO_URL}" "${MIRROR_DIR}"
    mirror_ok=1
    flock -u 9 || true
  else
    log "cannot recreate read-only mirror; clone without reference"
    mirror_ok=0
  fi
fi

wipe_dir "${CLONE_DIR}"

clone_with_ref() {
  local extra=()
  if [[ "$mirror_ok" -eq 1 && -d "${MIRROR_DIR}" ]]; then
    # NEVER --shared. reference only for local object borrow during clone.
    extra+=(--reference "${MIRROR_DIR}")
  fi
  log "clone ${REF} ${extra[*]:-direct} from ${REPO_URL}"
  # shared lock so seed exclusive fetch waits/readers coexist
  if [[ -d "$(dirname "${MIRROR_DIR}")" ]]; then
    exec 8>"${MIRROR_DIR}.lock"
    flock -s -w "${MIRROR_LOCK_WAIT:-300}" 8 || log "warn: shared mirror lock timeout"
  fi
  git clone "${extra[@]}" --depth 1 --single-branch --branch "${REF}" \
    "${REPO_URL}" "${CLONE_DIR}"
  flock -u 8 2>/dev/null || true
}

set +e
clone_with_ref 2>"${OUT_DIR}/git-clone.err"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  log "reference clone failed; try direct network clone"
  tail -40 "${OUT_DIR}/git-clone.err" 2>/dev/null || true
  wipe_dir "${CLONE_DIR}"
  set +e
  git clone --depth 1 --single-branch --branch "${REF}" \
    "${REPO_URL}" "${CLONE_DIR}" 2>>"${OUT_DIR}/git-clone.err"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    log "shallow branch clone failed; fetch REF explicitly"
    tail -40 "${OUT_DIR}/git-clone.err" 2>/dev/null || true
    wipe_dir "${CLONE_DIR}"
    git clone --filter=blob:none --no-checkout "${REPO_URL}" "${CLONE_DIR}"
    git -C "${CLONE_DIR}" fetch --depth 50 origin "${REF}"
    if git -C "${CLONE_DIR}" rev-parse "origin/${REF}" >/dev/null 2>&1; then
      git -C "${CLONE_DIR}" checkout --force -B "${REF}" "origin/${REF}"
    else
      git -C "${CLONE_DIR}" checkout --force FETCH_HEAD
    fi
  fi
fi

# Always dissociate by default: self-contained tree.
if [[ "${DISSOCIATE:-1}" == "1" ]] || [[ ! -w "${MIRROR_DIR}" ]]; then
  if [[ -f "${CLONE_DIR}/.git/objects/info/alternates" ]]; then
    log "dissociate clone from reference mirror"
    git -C "${CLONE_DIR}" repack -a -d 2>/dev/null || true
    rm -f "${CLONE_DIR}/.git/objects/info/alternates"
  fi
fi

chmod -R u+w "${CLONE_DIR}" 2>/dev/null || true

HEAD_SHA="$(git -C "${CLONE_DIR}" rev-parse HEAD)"
{
  echo "${HEAD_SHA}"
  git -C "${CLONE_DIR}" log -1 --oneline
  du -sh "${CLONE_DIR}"
} | tee "${OUT_DIR}/git-head.txt" >/dev/null
log "HEAD=${HEAD_SHA}"

# Only WebKit clones may stamp webkit-sha/webkit-head. Epiphany and other
# repos reuse this helper and must not overwrite the engine pin (smoke/release
# notes previously saw gnome-web SHA in webkit-sha.txt).
is_webkit_repo=0
case "${REPO_URL}" in
  *[Ww]eb[Kk]it*|*[Ww]ebkit*) is_webkit_repo=1 ;;
esac
case "${REPO_URL}" in
  *epiphany*|*GNOME*|*gnome*) is_webkit_repo=0 ;;
esac
if [[ "${FORCE_WEBKIT_SHA_STAMP:-0}" == "1" ]]; then
  is_webkit_repo=1
fi
if ((is_webkit_repo)); then
  cp -f "${OUT_DIR}/git-head.txt" "${OUT_DIR}/webkit-head.txt"
  printf '%s\n' "${HEAD_SHA}" >"${OUT_DIR}/webkit-sha.txt"
  log "stamped webkit-sha=${HEAD_SHA}"
else
  log "non-webkit clone; left webkit-sha.txt untouched"
fi

EXPECTED="${EXPECTED_SHA:-}"
if [[ -z "$EXPECTED" ]]; then
  set +e
  EXPECTED="$(git ls-remote --heads "${REPO_URL}" "refs/heads/${REF}" | awk '{print $1}' | head -1)"
  set -e
fi
if [[ -n "${EXPECTED}" ]]; then
  log "expected ${REF}=${EXPECTED}"
  if [[ "${HEAD_SHA}" != "${EXPECTED}" && "${HEAD_SHA}" != "${EXPECTED}"* && "${EXPECTED}" != "${HEAD_SHA}"* ]]; then
    die "clone HEAD ${HEAD_SHA} != expected ${EXPECTED} for ${REF} - refusing to build wrong tree"
  fi
else
  log "warn: could not resolve expected tip via ls-remote; continuing with HEAD=${HEAD_SHA}"
fi

# WebKit trees only. Epiphany and other repos reuse this helper.
if [[ "${REQUIRE_WEBKIT_TREE:-}" == "1" ]] || [[ "${REPO_URL}" == *[Ww]eb[Kk]it* ]]; then
  # Fork URLs contain WebKit; epiphany/gnome do not.
  if [[ "${REPO_URL}" != *epiphany* && "${REPO_URL}" != *GNOME* && "${REPO_URL}" != *gnome* ]]; then
    [[ -d "${CLONE_DIR}/Source/WebCore" ]] || die "clone missing Source/WebCore - incomplete checkout"
  fi
fi
if [[ "${REQUIRE_MARKER_PATH:-}" ]]; then
  [[ -e "${CLONE_DIR}/${REQUIRE_MARKER_PATH}" ]] || die "clone missing ${REQUIRE_MARKER_PATH} - incomplete checkout"
fi

if [[ -w "${MIRROR_DIR}" ]]; then
  ( flock -w 5 9 && git -C "${MIRROR_DIR}" fetch --prune origin >/dev/null 2>&1 || true ) 9>"${MIRROR_DIR}.lock" &
fi
log "clone ok"
