#!/usr/bin/env bash
# Smoke-test a GNOME Web AppImage inside a clean Fedora 44 container.
# No display required: --version / --help / embedded WebKit stamp + libs.
set -euo pipefail

APPIMAGE="${1:-}"
OUT_DIR="${OUT_DIR:-/out}"
EXPECTED_WEBKIT_SHA="${EXPECTED_WEBKIT_SHA:-}"
FEDORA_IMAGE="${FEDORA_SMOKE_IMAGE:-fedora:44}"
mkdir -p "${OUT_DIR}"
LOG="${OUT_DIR}/appimage-smoke.log"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "+ $*" | tee -a "${LOG}"; }

[[ -n "${APPIMAGE}" && -f "${APPIMAGE}" ]] || die "usage: $0 /path/to.AppImage (file missing: ${APPIMAGE:-})"
# VMs use docker; local host uses podman. Prefer docker when present (CI/self-hosted).
if command -v docker >/dev/null 2>&1; then
  CTR=(docker)
elif command -v podman >/dev/null 2>&1; then
  CTR=(podman)
else
  die "docker or podman required"
fi
log "container_engine=${CTR[0]}"

ABS="$(cd "$(dirname "${APPIMAGE}")" && pwd)/$(basename "${APPIMAGE}")"
NAME="$(basename "${ABS}")"
log "smoke AppImage=${ABS}"
log "fedora_image=${FEDORA_IMAGE}"
log "expected_webkit_sha=${EXPECTED_WEBKIT_SHA:-<any>}"

# Host-side basics
file "${ABS}" | tee -a "${LOG}"
size_b=$(stat -c%s "${ABS}" 2>/dev/null || stat -f%z "${ABS}")
log "size_bytes=${size_b}"
[[ "${size_b}" -gt 50000000 ]] || die "AppImage too small (${size_b} bytes)"

# Clean F44 container: extract + run CLI (no FUSE required)
"${CTR[@]}" run --rm \
  -e EXPECTED_WEBKIT_SHA="${EXPECTED_WEBKIT_SHA}" \
  -e APPIMAGE_NAME="${NAME}" \
  -v "${ABS}:/app/${NAME}:ro" \
  "${FEDORA_IMAGE}" \
  bash -lc '
set -euo pipefail
echo "=== smoke container ==="
cat /etc/os-release | grep -E "^(NAME|VERSION_ID)="
dnf -y install -q file binutils which >/dev/null
# Bind mount is often :ro; copy then chmod.
cp -a "/app/${APPIMAGE_NAME}" "/tmp/${APPIMAGE_NAME}"
chmod +x "/tmp/${APPIMAGE_NAME}"
AI="/tmp/${APPIMAGE_NAME}"
echo "=== appimage runtime ==="
"${AI}" --appimage-version
echo "=== extract ==="
rm -rf /tmp/ai && mkdir -p /tmp/ai && cd /tmp/ai
"${AI}" --appimage-extract >/dev/null
ROOT=/tmp/ai/squashfs-root
test -x "${ROOT}/AppRun" || test -x "${ROOT}/AppRun.wrapped"
test -x "${ROOT}/usr/bin/epiphany"
echo "=== path integrity (no baked /opt/webkitgtk-dnd in epiphany) ==="
if strings "${ROOT}/usr/bin/epiphany" | grep -q '/opt/webkitgtk-dnd'; then
  echo "error: epiphany binary still contains /opt/webkitgtk-dnd (rebuild with prefix=/usr DESTDIR=AppDir)"
  strings "${ROOT}/usr/bin/epiphany" | grep '/opt/webkitgtk-dnd' | head -5
  exit 1
fi
echo "no_opt_prefix_in_epiphany=ok"
echo "=== migrator present at /usr/libexec path ==="
test -x "${ROOT}/usr/libexec/epiphany/ephy-profile-migrator" \
  || { echo "error: ephy-profile-migrator missing under usr/libexec/epiphany"; exit 1; }
ls -lah "${ROOT}/usr/libexec/epiphany/ephy-profile-migrator"
echo "=== run with bundled lib path (clean container) ==="
export LD_LIBRARY_PATH="${ROOT}/usr/lib64/epiphany:${ROOT}/usr/lib/epiphany:${ROOT}/usr/lib64:${ROOT}/usr/lib:${LD_LIBRARY_PATH:-}"
export PATH="${ROOT}/usr/bin:${PATH}"
export WEBKIT_EXEC_PATH="${ROOT}/usr/libexec/webkitgtk-6.0"
[[ -d "${WEBKIT_EXEC_PATH}" ]] || export WEBKIT_EXEC_PATH="${ROOT}/usr/libexec"
export WEBKIT_TOP_LEVEL="${ROOT}/usr"
export XDG_DATA_DIRS="${ROOT}/usr/share:${XDG_DATA_DIRS:-/usr/share}"
# --version is a weak check alone (skips GUI/migrator). Still useful for linkage.
set +e
ver_out=$("${ROOT}/usr/bin/epiphany" --version 2>&1)
ver_rc=$?
help_out=$("${ROOT}/usr/bin/epiphany" --help 2>&1 | head -n 20)
help_rc=${PIPESTATUS[0]}
set -e
echo "version_rc=${ver_rc}"
echo "${ver_out}"
echo "help_rc=${help_rc}"
echo "${help_out}"
# Accept either direct binary or AppRun once libs resolve.
if [[ ${ver_rc} -ne 0 ]]; then
  echo "warn: direct epiphany --version failed (rc=${ver_rc}); trying AppRun"
  set +e
  ver_out=$("${ROOT}/AppRun" --version 2>&1)
  ver_rc=$?
  set -e
  echo "apprun_version_rc=${ver_rc}"
  echo "${ver_out}"
fi
[[ ${ver_rc} -eq 0 ]] || { echo "error: epiphany --version failed in clean F44 (missing bundled libs?)"; exit 1; }
echo "${ver_out}" | grep -qiE "Web|Epiphany" || { echo "error: unexpected --version output"; exit 1; }
# Migrator must be executable under the same lib path (spawn check, no profile).
set +e
mig_out=$("${ROOT}/usr/libexec/epiphany/ephy-profile-migrator" --help 2>&1 | head -n 15)
mig_rc=${PIPESTATUS[0]}
set -e
echo "migrator_help_rc=${mig_rc}"
echo "${mig_out}"
# migrator may not support --help; accept 0 or usage-like exit, reject 127 (missing lib)
[[ ${mig_rc} -ne 127 ]] || { echo "error: migrator cannot load (exit 127)"; exit 1; }
echo "=== embedded webkit ==="
sha=$(cat "${ROOT}/usr/.webkitgtk-dnd-sha" 2>/dev/null || cat "${ROOT}/.webkitgtk-dnd-sha" 2>/dev/null || true)
echo "embedded_webkit_sha=${sha:-missing}"
if [[ -n "${EXPECTED_WEBKIT_SHA}" ]]; then
  exp="${EXPECTED_WEBKIT_SHA}"
  case "${sha}" in
    ${exp}|${exp:0:12}*) echo "sha_match=ok" ;;
    *) echo "error: embedded sha ${sha} != expected ${exp}"; exit 1 ;;
  esac
fi
if ls "${ROOT}/usr/lib64/libwebkitgtk-6.0.so"* >/dev/null 2>&1; then
  ls -lah "${ROOT}/usr/lib64/libwebkitgtk-6.0.so"* | head -5
elif ls "${ROOT}/usr/lib/libwebkitgtk-6.0.so"* >/dev/null 2>&1; then
  ls -lah "${ROOT}/usr/lib/libwebkitgtk-6.0.so"* | head -5
else
  echo "error: libwebkitgtk-6.0 missing from AppImage"
  exit 1
fi
test -f "${ROOT}/usr/share/applications/org.gnome.Epiphany.desktop" \
  || test -f "${ROOT}/usr/share/applications/org.gnome.Epiphany.DnD.desktop" \
  || { echo "error: desktop file missing"; exit 1; }
echo "SMOKE_OK"
' | tee -a "${LOG}"

grep -q "SMOKE_OK" "${LOG}" || die "smoke did not report SMOKE_OK"
log "appimage smoke passed"
echo "appimage_smoke=ok" >> "${OUT_DIR}/appimage-smoke.status"
exit 0
