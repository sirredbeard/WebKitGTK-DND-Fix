#!/usr/bin/env bash
# Build GNOME Web against an installed WebKitGTK PREFIX and pack an AppImage.
# Does NOT rebuild WebKitGTK when PREFIX already has webkitgtk-6.0 (or SKIP_WEBKIT_BUILD=1).
# Call ci-build-webkitgtk-prefix.sh first when a fresh engine install is required.
set -euo pipefail

# Host bind-mount is owned by runner user; container often runs as root (git safe.directory).
git config --global --add safe.directory "*" 2>/dev/null || true
if [[ -n "${WEBKIT_DIR:-}" ]]; then
  git config --global --add safe.directory "${WEBKIT_DIR}" 2>/dev/null || true
fi
if [[ -n "${EPIPHANY_DIR:-}" ]]; then
  git config --global --add safe.directory "${EPIPHANY_DIR}" 2>/dev/null || true
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "${ROOT}/ccache-env.sh" 2>/dev/null || source /opt/webkitgtk-dnd-fix/bin/ccache-env.sh 2>/dev/null || true

log() { printf '+ %s\n' "$*"; }

resolve_tool() {
  # $1 name pattern e.g. linuxdeploy-x86_64.AppImage
  local name="$1"
  if [[ -x "${TOOLS_DIR}/${name}" ]]; then
    echo "${TOOLS_DIR}/${name}"
    return 0
  fi
  if [[ -x "/tools/${name}" ]]; then
    echo "/tools/${name}"
    return 0
  fi
  return 1
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

WEBKIT_DIR="${WEBKIT_DIR:-/workspace/WebKit}"
EPIPHANY_DIR="${EPIPHANY_DIR:-/workspace/epiphany}"
PREFIX="${PREFIX:-/opt/webkitgtk-dnd}"
EPIPHANY_BUILD="${EPIPHANY_BUILD:-/workspace/gnome-web-build}"
APPDIR="${APPDIR:-/workspace/AppDir}"
OUT_DIR="${OUT_DIR:-/out}"
TOOLS_DIR="${TOOLS_DIR:-/workspace/appimage-tools}"
HOST_TOOLS="${HOST_TOOLS:-/tools}"
JOBS="${JOBS:-$(nproc)}"
EPIPHANY_REPO="${EPIPHANY_REPO:-https://gitlab.gnome.org/GNOME/epiphany.git}"
EPIPHANY_REF="${EPIPHANY_REF:-main}"
APPIMAGE_NAME="${APPIMAGE_NAME:-GNOME_Web-WebKitGTK-DnD-x86_64.AppImage}"
SKIP_WEBKIT_BUILD="${SKIP_WEBKIT_BUILD:-0}"
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib64/ccache:/usr/lib/ccache:/opt/webkitgtk-dnd-fix/bin:${PATH}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-${JOBS}}"
export NINJA_STATUS="[%f/%t %e] "

mkdir -p "${OUT_DIR}" "${TOOLS_DIR}"

{
  echo "=== GNOME Web AppImage environment ==="
  date -u
  cat /etc/os-release || true
  echo "JOBS=${JOBS} PREFIX=${PREFIX} SKIP_WEBKIT_BUILD=${SKIP_WEBKIT_BUILD}"
  echo "EPIPHANY_REPO=${EPIPHANY_REPO} EPIPHANY_REF=${EPIPHANY_REF}"
  df -h
  ccache -s || true
} | tee "${OUT_DIR}/appimage-environment.log"

export PKG_CONFIG_PATH="${PREFIX}/lib64/pkgconfig:${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${PREFIX}/lib64:${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export PATH="${PREFIX}/bin:${PATH}"

need_webkit=1
if [[ "${SKIP_WEBKIT_BUILD}" == "1" ]]; then
  need_webkit=0
fi
if pkg-config --exists webkitgtk-6.0 2>/dev/null; then
  need_webkit=0
  log "found webkitgtk-6.0 in PREFIX ($(pkg-config --modversion webkitgtk-6.0))"
fi

if ((need_webkit)); then
  log "PREFIX missing webkitgtk-6.0; building install via ci-build-webkitgtk-prefix.sh"
  ROOT="$(cd "$(dirname "$0")" && pwd)"
  # Prefer sibling script; fall back to baked path
  if [[ -x "${ROOT}/ci-build-webkitgtk-prefix.sh" ]]; then
    bash "${ROOT}/ci-build-webkitgtk-prefix.sh"
  elif [[ -x /opt/webkitgtk-dnd-fix/bin/ci-build-webkitgtk-prefix.sh ]]; then
    bash /opt/webkitgtk-dnd-fix/bin/ci-build-webkitgtk-prefix.sh
  elif [[ -x /validation-scripts/ci-build-webkitgtk-prefix.sh ]]; then
    bash /validation-scripts/ci-build-webkitgtk-prefix.sh
  else
    die "ci-build-webkitgtk-prefix.sh not found and PREFIX has no webkitgtk-6.0"
  fi
else
  echo "reused_or_provided_prefix=1" | tee -a "${OUT_DIR}/webkit-prefix-summary.log" || true
fi

pkg-config --modversion webkitgtk-6.0 | tee "${OUT_DIR}/webkitgtk-pc-version.txt" \
  || die "webkitgtk-6.0.pc still missing"

# Always record the engine pin used for this AppImage (prefix stamp preferred).
# Never let a later epiphany clone overwrite this via clone-from-mirror.
stamp_webkit_sha() {
  local prefix_sha="" tree_sha="" sha=""
  if [[ -f "${PREFIX}/.webkitgtk-dnd-sha" ]]; then
    prefix_sha="$(tr -cd "0-9a-f" <"${PREFIX}/.webkitgtk-dnd-sha" | head -c 40)"
  fi
  if [[ -d "${WEBKIT_DIR}/.git" ]]; then
    tree_sha="$(git -C "${WEBKIT_DIR}" rev-parse HEAD 2>/dev/null | tr -cd "0-9a-f" | head -c 40 || true)"
  fi
  # Prefer the WebKit tree we are validating. PREFIX must match when both present.
  if [[ -n "${tree_sha}" && -n "${prefix_sha}" && "${tree_sha}" != "${prefix_sha}" ]]; then
    die "PREFIX stamp ${prefix_sha} != WebKit HEAD ${tree_sha}. Refusing to pack AppImage against wrong engine. Rebuild prefix or reseed tip last-good."
  fi
  sha="${tree_sha:-${prefix_sha}}"
  if [[ -z "${sha}" && -f "${OUT_DIR}/webkit-sha.txt" ]]; then
    sha="$(tr -cd "0-9a-f" <"${OUT_DIR}/webkit-sha.txt" | head -c 40)"
  fi
  [[ -n "${sha}" ]] || die "cannot determine WebKit SHA for AppImage stamp"
  printf "%s\n" "${sha}" >"${OUT_DIR}/webkit-sha.txt"
  {
    echo "${sha}"
    if [[ -d "${WEBKIT_DIR}/.git" ]]; then
      git -C "${WEBKIT_DIR}" log -1 --oneline 2>/dev/null || true
    fi
  } >"${OUT_DIR}/webkit-head.txt"
  printf "%s" "${sha}" >"${PREFIX}/.webkitgtk-dnd-sha"
  log "webkit_sha=${sha}"
}
stamp_webkit_sha

# --- tools ---
fetch_tool() {
  local url="$1" dest="$2"
  local base
  base="$(basename "${dest}")"
  if [[ -x "${dest}" ]]; then
    return 0
  fi
  # Prefer NVMe-cached tools bind-mounted from the runner host.
  for cand in       "${HOST_TOOLS}/${base}"       "${HOST_TOOLS}/linuxdeploy-x86_64.AppImage"       "${HOST_TOOLS}/appimagetool-x86_64.AppImage"       "/var/cache/webkit-dnd/tools/${base}"; do
    if [[ -x "${cand}" ]] && [[ "$(basename "${cand}")" == "${base}" || "${base}" == linuxdeploy || "${base}" == appimagetool ]]; then
      if [[ "$(basename "${cand}")" == "${base}" ]]; then
        log "use cached tool ${cand}"
        mkdir -p "$(dirname "${dest}")"
        cp -a "${cand}" "${dest}"
        chmod +x "${dest}"
        return 0
      fi
    fi
  done
  # Name mapping: dest linuxdeploy <- linuxdeploy-x86_64.AppImage
  if [[ "${base}" == "linuxdeploy" && -x "${HOST_TOOLS}/linuxdeploy-x86_64.AppImage" ]]; then
    log "use cached ${HOST_TOOLS}/linuxdeploy-x86_64.AppImage"
    cp -a "${HOST_TOOLS}/linuxdeploy-x86_64.AppImage" "${dest}"
    chmod +x "${dest}"
    return 0
  fi
  if [[ "${base}" == "appimagetool" && -x "${HOST_TOOLS}/appimagetool-x86_64.AppImage" ]]; then
    log "use cached ${HOST_TOOLS}/appimagetool-x86_64.AppImage"
    cp -a "${HOST_TOOLS}/appimagetool-x86_64.AppImage" "${dest}"
    chmod +x "${dest}"
    return 0
  fi
  log "fetch ${base}"
  curl -fsSL -o "${dest}" "${url}"
  chmod +x "${dest}"
}

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) APPIMAGE_ARCH=x86_64 ;;
  aarch64) APPIMAGE_ARCH=aarch64 ;;
  *) die "unsupported arch ${ARCH}" ;;
esac

fetch_tool \
  "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${APPIMAGE_ARCH}.AppImage" \
  "${TOOLS_DIR}/linuxdeploy"
fetch_tool \
  "https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/raw/master/linuxdeploy-plugin-gtk.sh" \
  "${TOOLS_DIR}/linuxdeploy-plugin-gtk.sh"
fetch_tool \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
  "${TOOLS_DIR}/appimagetool"
export APPIMAGE_EXTRACT_AND_RUN=1

# --- GNOME Web (upstream project path: epiphany.git) ---
# Always prefer a clean writable tree; stale shared alternates against RO mirrors break meson/git.
clear_tree() {
  local d="$1"
  if [[ ! -e "$d" ]]; then
    mkdir -p "$d"
    return 0
  fi
  if mountpoint -q "$d" 2>/dev/null; then
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  else
    rm -rf "$d"
  fi
  mkdir -p "$d"
}

if [[ -d "${EPIPHANY_DIR}/.git" ]] && [[ ! -w "${EPIPHANY_DIR}/.git/HEAD" ]]; then
  log "epiphany tree not writable; clearing"
  clear_tree "${EPIPHANY_DIR}"
fi
if [[ -d "${EPIPHANY_DIR}/.git" ]] && [[ -f "${EPIPHANY_DIR}/.git/objects/info/alternates" ]]; then
  log "drop shared alternates on epiphany clone"
  rm -f "${EPIPHANY_DIR}/.git/objects/info/alternates"
  if ! git -C "${EPIPHANY_DIR}" repack -a -d 2>/dev/null; then
    log "repack failed; clearing epiphany tree"
    clear_tree "${EPIPHANY_DIR}"
  fi
fi
export DISSOCIATE="${DISSOCIATE:-1}"
if [[ ! -d "${EPIPHANY_DIR}/.git" ]]; then
  log "clone GNOME Web sources (epiphany.git) ${EPIPHANY_REF}"
  MIRROR_DEFAULT=/var/cache/webkit-dnd/mirrors/epiphany.git
  # Host mirror is bind-mounted only if present; fall back to network.
  if [[ -d "${MIRROR_DEFAULT}" ]] || [[ -d "${EPIPHANY_MIRROR_DIR:-}" ]]; then
    export REPO_URL="${EPIPHANY_REPO}"
    export REF="${EPIPHANY_REF}"
    export CLONE_DIR="${EPIPHANY_DIR}"
    export MIRROR_DIR="${EPIPHANY_MIRROR_DIR:-${MIRROR_DEFAULT}}"
    export OUT_DIR
    if [[ -f /validation-scripts/clone-from-mirror.sh ]]; then
      bash /validation-scripts/clone-from-mirror.sh
    elif [[ -f "${ROOT}/clone-from-mirror.sh" ]]; then
      bash "${ROOT}/clone-from-mirror.sh"
    else
      git clone --depth 1 --single-branch --branch "${EPIPHANY_REF}" \
        "${EPIPHANY_REPO}" "${EPIPHANY_DIR}" \
        || git clone --depth 1 "${EPIPHANY_REPO}" "${EPIPHANY_DIR}"
    fi
  else
    git clone --depth 1 --single-branch --branch "${EPIPHANY_REF}" \
      "${EPIPHANY_REPO}" "${EPIPHANY_DIR}" \
      || git clone --depth 1 "${EPIPHANY_REPO}" "${EPIPHANY_DIR}"
  fi
fi
git -C "${EPIPHANY_DIR}" rev-parse HEAD | tee "${OUT_DIR}/gnome-web-head.txt"
git -C "${EPIPHANY_DIR}" log -1 --oneline >>"${OUT_DIR}/gnome-web-head.txt"

clear_tree "${EPIPHANY_BUILD}"

# GNOME Web host deps from Fedora epiphany SRPM BuildRequires (dnf provides on F45).
# Distro webkitgtk*-devel omitted - PREFIX supplies webkitgtk-6.0.
# Image should bake these; this block is the lag safety net.
need_pkgs=()
pc_need() { pkg-config --exists "$1" 2>/dev/null || need_pkgs+=("$2"); }
bin_need() { command -v "$1" >/dev/null 2>&1 || need_pkgs+=("$2"); }
pc_need iso-codes iso-codes-devel
# iso-codes runtime data often paired with -devel on Fedora
pkg-config --exists iso-codes 2>/dev/null || need_pkgs+=(iso-codes)
pc_need pwquality libpwquality-devel
pc_need gcr-4 gcr-devel
pc_need gck-2 gcr-devel
pc_need libportal-gtk4 libportal-gtk4-devel
pc_need libadwaita-1 libadwaita-devel
pc_need libsecret-1 libsecret-devel
pc_need libsoup-3.0 libsoup3-devel
pc_need json-glib-1.0 json-glib-devel
pc_need libarchive libarchive-devel
pc_need nettle nettle-devel
pc_need hogweed nettle-devel
pc_need sqlite3 sqlite-devel
pc_need cairo cairo-devel
pc_need gdk-pixbuf-2.0 gdk-pixbuf2-devel
pc_need gsettings-desktop-schemas gsettings-desktop-schemas-devel
pc_need gstreamer-1.0 gstreamer1-devel
pc_need gtk4 gtk4-devel
pc_need libxml-2.0 libxml2-devel
# Fedora epiphany uses libappstream-glib-devel (pc: appstream-glib)
pkg-config --exists appstream-glib 2>/dev/null || need_pkgs+=(libappstream-glib-devel)
bin_need blueprint-compiler blueprint-compiler
bin_need desktop-file-validate desktop-file-utils
bin_need itstool itstool
bin_need rst2man python3-docutils
bin_need msgfmt gettext-devel
# de-dupe
if ((${#need_pkgs[@]})); then
  mapfile -t need_pkgs < <(printf '%s\n' "${need_pkgs[@]}" | awk 'NF && !seen[$0]++')
fi
if ((${#need_pkgs[@]})); then
  log "install meson host deps: ${need_pkgs[*]}"
  dnf install -y --setopt=install_weak_deps=False "${need_pkgs[@]}" \
    >"${OUT_DIR}/gnome-web-host-deps.log" 2>&1 || {
    tail -n 120 "${OUT_DIR}/gnome-web-host-deps.log" >&2 || true
    die "failed installing GNOME Web host deps: ${need_pkgs[*]}"
  }
fi
for bin in blueprint-compiler desktop-file-validate; do
  command -v "${bin}" >/dev/null 2>&1 || die "missing ${bin} after host dep install"
done
pkg-config --exists pwquality 2>/dev/null || die "pkg-config pwquality missing after host dep install"
pkg-config --exists iso-codes 2>/dev/null || die "pkg-config iso-codes missing after host dep install"
# Install GNOME Web with prefix=/usr into DESTDIR=AppDir.
# Baked PKGLIBEXECDIR must be /usr/libexec/... so ephy-profile-migrator is found
# inside the AppImage (not /opt/webkitgtk-dnd from the WebKit PREFIX).
clear_tree "${APPDIR}"
mkdir -p "${APPDIR}"

log "meson setup GNOME Web (prefix=/usr for AppImage paths)"
meson setup "${EPIPHANY_BUILD}" "${EPIPHANY_DIR}" \
  --prefix=/usr \
  --buildtype=release \
  -Dunit_tests=disabled \
  >"${OUT_DIR}/gnome-web-meson.log" 2>&1 || {
    tail -n 200 "${OUT_DIR}/gnome-web-meson.log" >&2 || true
    die "GNOME Web meson failed"
  }
tail -n 80 "${OUT_DIR}/gnome-web-meson.log" >"${OUT_DIR}/gnome-web-meson.tail.log"

log "ninja GNOME Web install DESTDIR=AppDir"
DESTDIR="${APPDIR}" ninja -C "${EPIPHANY_BUILD}" -j "${JOBS}" install \
  >"${OUT_DIR}/gnome-web-ninja.log" 2>&1 || {
  tail -n 200 "${OUT_DIR}/gnome-web-ninja.log" >&2 || true
  die "GNOME Web ninja install failed"
}
tail -n 60 "${OUT_DIR}/gnome-web-ninja.log" >"${OUT_DIR}/gnome-web-ninja.tail.log"

# Merge patched WebKitGTK PREFIX into AppDir (libs, gir, libexec helpers).
log "merge WebKitGTK PREFIX into AppDir"
mkdir -p "${APPDIR}/usr"
# Copy without clobbering epiphany files already installed under /usr.
cp -a --update=none "${PREFIX}/." "${APPDIR}/usr/" 2>/dev/null \
  || cp -an "${PREFIX}/." "${APPDIR}/usr/" 2>/dev/null \
  || rsync -a --ignore-existing "${PREFIX}/" "${APPDIR}/usr/"

# Keep a stamp for smoke tests / support.
if [[ -f "${PREFIX}/.webkitgtk-dnd-sha" ]]; then
  cp -a "${PREFIX}/.webkitgtk-dnd-sha" "${APPDIR}/usr/.webkitgtk-dnd-sha"
fi

# Rewrite leftover text paths from WebKit PREFIX install (dbus services, rdf, pc).
log "rewrite PREFIX text paths in AppDir"
while IFS= read -r -d '' f; do
  sed -i "s|/opt/webkitgtk-dnd|/usr|g" "$f" 2>/dev/null || true
done < <(find "${APPDIR}/usr" -type f \( \
  -name '*.desktop' -o -name '*.service' -o -name '*.pc' -o -name '*.rdf' \
  -o -name '*.ini' -o -name '*.xml' -o -name '*.js' \
\) -print0 2>/dev/null)

# Fail closed: migrator must live where prefix=/usr baked it.
[[ -x "${APPDIR}/usr/libexec/epiphany/ephy-profile-migrator" ]] \
  || die "missing ${APPDIR}/usr/libexec/epiphany/ephy-profile-migrator after DESTDIR install"
[[ -x "${APPDIR}/usr/bin/epiphany" ]] || die "missing epiphany binary in AppDir"

DESKTOP="${APPDIR}/usr/share/applications/org.gnome.Epiphany.DnD.desktop"
mkdir -p "$(dirname "${DESKTOP}")"
if [[ -f "${APPDIR}/usr/share/applications/org.gnome.Epiphany.desktop" ]]; then
  cp -a "${APPDIR}/usr/share/applications/org.gnome.Epiphany.desktop" "${DESKTOP}"
  sed -i \
    -e 's/^Name=.*/Name=GNOME Web (WebKitGTK DnD fix)/' \
    -e 's/^Comment=.*/Comment=Private validation build with patched WebKitGTK file DnD/' \
    -e 's|/opt/webkitgtk-dnd/bin/||g' \
    -e 's|^Exec=.*|Exec=epiphany %U|' \
    "${DESKTOP}" || true
else
  cat >"${DESKTOP}" <<'DEOF'
[Desktop Entry]
Name=GNOME Web (WebKitGTK DnD fix)
Comment=Private validation build with patched WebKitGTK file DnD
Exec=epiphany %U
Icon=org.gnome.Epiphany
Terminal=false
Type=Application
Categories=Network;WebBrowser;
StartupNotify=true
DEOF
fi

# Written before linuxdeploy; linuxdeploy may wrap it as AppRun.wrapped.
cat >"${APPDIR}/AppRun" <<'AEOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
export PATH="${HERE}/usr/bin:${PATH}"
# Prefer bundled libs over host (order matters for clean containers).
export LD_LIBRARY_PATH="${HERE}/usr/lib64/epiphany:${HERE}/usr/lib/epiphany:${HERE}/usr/lib64:${HERE}/usr/lib:${HERE}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GIO_EXTRA_MODULES="${HERE}/usr/lib64/gio/modules:${HERE}/usr/lib/gio/modules:${GIO_EXTRA_MODULES:-}"
export GI_TYPELIB_PATH="${HERE}/usr/lib64/girepository-1.0:${HERE}/usr/lib/girepository-1.0:${GI_TYPELIB_PATH:-}"
export GST_PLUGIN_SYSTEM_PATH_1_0="${HERE}/usr/lib64/gstreamer-1.0:${HERE}/usr/lib/gstreamer-1.0:${GST_PLUGIN_SYSTEM_PATH_1_0:-}"
export WEBKIT_EXEC_PATH="${HERE}/usr/libexec/webkitgtk-6.0"
if [[ ! -d "${WEBKIT_EXEC_PATH}" ]]; then
  export WEBKIT_EXEC_PATH="${HERE}/usr/libexec"
fi
export WEBKIT_TOP_LEVEL="${HERE}/usr"
# GSettings schemas shipped in the image
export GSETTINGS_SCHEMA_DIR="${HERE}/usr/share/glib-2.0/schemas:${GSETTINGS_SCHEMA_DIR:-}"
exec "${HERE}/usr/bin/epiphany" "$@"
AEOF
chmod 755 "${APPDIR}/AppRun"

# Bundle HTML harness for manual QA inside the AppImage when present
if [[ -d /validation-scripts/../html ]]; then
  mkdir -p "${APPDIR}/usr/share/webkitgtk-dnd-fix/html"
  cp -a /validation-scripts/../html/. "${APPDIR}/usr/share/webkitgtk-dnd-fix/html/" || true
elif [[ -d /workspace/WebKitGTK-DND-Fix/html ]]; then
  mkdir -p "${APPDIR}/usr/share/webkitgtk-dnd-fix/html"
  cp -a /workspace/WebKitGTK-DND-Fix/html/. "${APPDIR}/usr/share/webkitgtk-dnd-fix/html/" || true
fi

# Epiphany private libs live in $libdir/epiphany (pkglibdir). linuxdeploy only
# searches standard lib paths unless LD_LIBRARY_PATH points at pkglibdir.
EPHY_PKGLIB=""
for d in "${APPDIR}/usr/lib64/epiphany" "${APPDIR}/usr/lib/epiphany"; do
  if [[ -d "$d" ]]; then
    EPHY_PKGLIB="$d"
    break
  fi
done
[[ -n "${EPHY_PKGLIB}" ]] || die "epiphany pkglibdir missing under AppDir (expected usr/lib64/epiphany)"
[[ -e "${EPHY_PKGLIB}/libephymain.so" || -e "${EPHY_PKGLIB}/libephymain.so.0" ]] \
  || die "libephymain.so missing in ${EPHY_PKGLIB}"
# Also stage copies into usr/lib64 so runtime and ldd see them without rpath quirks.
mkdir -p "${APPDIR}/usr/lib64"
shopt -s nullglob
for so in "${EPHY_PKGLIB}"/*.so "${EPHY_PKGLIB}"/*.so.*; do
  base="$(basename "$so")"
  [[ -e "${APPDIR}/usr/lib64/${base}" ]] || cp -a "$so" "${APPDIR}/usr/lib64/${base}" || true
done
shopt -u nullglob
export LD_LIBRARY_PATH="${EPHY_PKGLIB}:${APPDIR}/usr/lib64:${APPDIR}/usr/lib:${PREFIX}/lib64:${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
log "EPHY_PKGLIB=${EPHY_PKGLIB} LD_LIBRARY_PATH includes pkglibdir"

log "linuxdeploy (bundle deps)"
set +e
(
  cd /workspace
  LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" \
  "${TOOLS_DIR}/linuxdeploy" --appimage-extract-and-run \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/epiphany" \
    --desktop-file "${DESKTOP}" \
    --library "${EPHY_PKGLIB}/libephymain.so" \
    --plugin gtk \
    2>&1
) | tee "${OUT_DIR}/linuxdeploy.log"
LD_RC=${PIPESTATUS[0]}
set -e
if ((LD_RC != 0)); then
  log "linuxdeploy retry without gtk plugin"
  LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" \
  "${TOOLS_DIR}/linuxdeploy" --appimage-extract-and-run \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/epiphany" \
    --desktop-file "${DESKTOP}" \
    --library "${EPHY_PKGLIB}/libephymain.so" \
    >"${OUT_DIR}/linuxdeploy-retry.log" 2>&1 || {
      tail -n 200 "${OUT_DIR}/linuxdeploy-retry.log" >&2 || true
      die "linuxdeploy failed"
    }
fi
tail -n 80 "${OUT_DIR}/linuxdeploy.log" >"${OUT_DIR}/linuxdeploy.tail.log" || true

# linuxdeploy wraps AppRun; force our env wrapper as AppRun.wrapped so LD_LIBRARY_PATH
# and WEBKIT_* point at the AppDir, not the build PREFIX.
if [[ -f "${APPDIR}/AppRun" ]]; then
  cat >"${APPDIR}/AppRun.wrapped" <<'AEOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib64/epiphany:${HERE}/usr/lib/epiphany:${HERE}/usr/lib64:${HERE}/usr/lib:${HERE}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GIO_EXTRA_MODULES="${HERE}/usr/lib64/gio/modules:${HERE}/usr/lib/gio/modules:${GIO_EXTRA_MODULES:-}"
export GI_TYPELIB_PATH="${HERE}/usr/lib64/girepository-1.0:${HERE}/usr/lib/girepository-1.0:${GI_TYPELIB_PATH:-}"
export GST_PLUGIN_SYSTEM_PATH_1_0="${HERE}/usr/lib64/gstreamer-1.0:${HERE}/usr/lib/gstreamer-1.0:${GST_PLUGIN_SYSTEM_PATH_1_0:-}"
export WEBKIT_EXEC_PATH="${HERE}/usr/libexec/webkitgtk-6.0"
if [[ ! -d "${WEBKIT_EXEC_PATH}" ]]; then
  export WEBKIT_EXEC_PATH="${HERE}/usr/libexec"
fi
export WEBKIT_TOP_LEVEL="${HERE}/usr"
export GSETTINGS_SCHEMA_DIR="${HERE}/usr/share/glib-2.0/schemas:${GSETTINGS_SCHEMA_DIR:-}"
exec "${HERE}/usr/bin/epiphany" "$@"
AEOF
  chmod 755 "${APPDIR}/AppRun.wrapped"
fi

# linuxdeploy often misses recursive deps (e.g. libharfbuzz). Copy missing .so from
# the build host into AppDir so clean F44 smoke does not rely on system libs.
log "bundle missing shared libs via ldd"
bundle_missing_libs() {
  local dest_lib="${APPDIR}/usr/lib64"
  mkdir -p "${dest_lib}"
  local -a seeds=()
  local f
  for f in \
    "${APPDIR}/usr/bin/epiphany" \
    "${APPDIR}/usr/libexec/epiphany/ephy-profile-migrator" \
    "${APPDIR}/usr/libexec/webkitgtk-6.0/WebKitNetworkProcess" \
    "${APPDIR}/usr/libexec/webkitgtk-6.0/WebKitWebProcess" \
    "${APPDIR}/usr/libexec/webkitgtk-6.0/WebKitGPUProcess"
  do
    [[ -e "$f" ]] && seeds+=("$f")
  done
  # A few direct .so seeds under AppDir (webkit + gtk stack already merged).
  while IFS= read -r f; do
    seeds+=("$f")
  done < <(find "${APPDIR}/usr/lib64" "${APPDIR}/usr/lib" -maxdepth 2 -type f \( -name 'libwebkit*.so*' -o -name 'libjavascriptcore*.so*' -o -name 'libepiphany*.so*' \) 2>/dev/null | head -n 40 || true)

  local -A seen=()
  local -a queue=("${seeds[@]}")
  local path name dest
  local pass=0
  while ((${#queue[@]})) && ((pass < 12)); do
    pass=$((pass + 1))
    local -a next=()
    for f in "${queue[@]}"; do
      [[ -e "$f" ]] || continue
      while IFS= read -r line; do
        path="$(sed -n 's/.*=> \([^ ]\+\) (0x.*/\1/p' <<<"$line")"
        [[ -n "${path}" && -e "${path}" ]] || continue
        name="$(basename "${path}")"
        # Skip glibc/loader — host must supply those.
        case "${name}" in
          ld-linux*.so.*|libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libresolv.so.*|libnss_*.so.*|libstdc++.so.*|libgcc_s.so.*)
            continue
            ;;
        esac
        dest="${dest_lib}/${name}"
        if [[ -e "${dest}" || -n "${seen[$name]:-}" ]]; then
          continue
        fi
        seen[$name]=1
        cp -aL "${path}" "${dest}" 2>/dev/null || cp -a "${path}" "${dest}" || true
        if [[ -e "${dest}" ]]; then
          next+=("${dest}")
        fi
      done < <(ldd "$f" 2>/dev/null || true)
    done
    queue=("${next[@]}")
  done
  {
    echo "bundled_extra_libs=${#seen[@]}"
    printf '%s\n' "${!seen[@]}" | sort
  } | tee "${OUT_DIR}/appimage-bundled-libs.log" >/dev/null
  # Fail closed on harfbuzz — known miss that broke clean F44 --version
  [[ -e "${dest_lib}/libharfbuzz.so.0" || -e "${APPDIR}/usr/lib/libharfbuzz.so.0" ]] \
    || die "libharfbuzz.so.0 not bundled into AppDir after ldd pass"
}
bundle_missing_libs

# Fail closed again after linuxdeploy/ldd (they must not drop migrator or re-bake /opt paths).
[[ -x "${APPDIR}/usr/libexec/epiphany/ephy-profile-migrator" ]] \
  || die "migrator missing after linuxdeploy/ldd bundle"
if strings "${APPDIR}/usr/bin/epiphany" | grep -q '/opt/webkitgtk-dnd'; then
  die "epiphany still contains baked /opt/webkitgtk-dnd after pack (use meson --prefix=/usr DESTDIR=AppDir)"
fi
# Stamp must survive into AppDir
if [[ -f "${OUT_DIR}/webkit-sha.txt" ]]; then
  cp -a "${OUT_DIR}/webkit-sha.txt" "${APPDIR}/usr/.webkitgtk-dnd-sha"
  # file may be multi-line from earlier bugs; keep first 40 hex chars only
  sha="$(tr -cd '0-9a-f' <"${OUT_DIR}/webkit-sha.txt" | head -c 40)"
  printf '%s' "${sha}" >"${APPDIR}/usr/.webkitgtk-dnd-sha"
fi

log "appimagetool"
rm -f "/workspace/${APPIMAGE_NAME}" "${OUT_DIR}/${APPIMAGE_NAME}"
(
  cd /workspace
  ARCH="${APPIMAGE_ARCH}" "${TOOLS_DIR}/appimagetool" --appimage-extract-and-run \
    "${APPDIR}" \
    "${APPIMAGE_NAME}" \
    >"${OUT_DIR}/appimagetool.log" 2>&1
) || {
  tail -n 200 "${OUT_DIR}/appimagetool.log" >&2 || true
  die "appimagetool failed"
}

if [[ -f "/workspace/${APPIMAGE_NAME}" ]]; then
  mv -f "/workspace/${APPIMAGE_NAME}" "${OUT_DIR}/${APPIMAGE_NAME}"
fi
[[ -f "${OUT_DIR}/${APPIMAGE_NAME}" ]] || die "AppImage missing after pack"
chmod +x "${OUT_DIR}/${APPIMAGE_NAME}"
ls -lh "${OUT_DIR}/${APPIMAGE_NAME}" | tee "${OUT_DIR}/appimage-ls.txt"

# glibc floor for release notes / smoke (AppImage links against builder glibc)
GLIBC_VER="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
GLIBC_VER="${GLIBC_VER:-unknown}"
printf '%s\n' "${GLIBC_VER}" | tee "${OUT_DIR}/builder-glibc.txt" >/dev/null
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  printf 'ID=%s\nVERSION_ID=%s\n' "${ID:-}" "${VERSION_ID:-}" | tee "${OUT_DIR}/builder-os.txt" >/dev/null
fi

{
  echo "appimage=${APPIMAGE_NAME}"
  echo "webkit_prefix=${PREFIX}"
  echo "gnome_web_ref=${EPIPHANY_REF}"
  echo "builder_glibc=${GLIBC_VER}"
  echo "builder_os_file=${OUT_DIR}/builder-os.txt"
  cat "${OUT_DIR}/gnome-web-head.txt" 2>/dev/null || true
  ccache -s || true
  df -h
  date -u
} | tee "${OUT_DIR}/appimage-summary.log"

log "done ${OUT_DIR}/${APPIMAGE_NAME} (builder glibc ${GLIBC_VER})"
exit 0
