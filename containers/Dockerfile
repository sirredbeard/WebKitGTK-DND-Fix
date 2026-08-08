# WebKitGTK-DND-Fix builder (Fedora 44)
# Layer strategy (top = changes least often):
#   1) base OS
#   2) core toolchain packages (packages-core.txt)
#   3) WebKit/GNOME heavy -devel set (packages-webkit.txt)
#   4) optional soft deps (woff2/openxr/...)
#   5) env that does not bust package layers
#   6) CI scripts last (edit scripts without dnf rebuild)
#
# Build with BuildKit so dnf metadata can use cache mounts:
#   DOCKER_BUILDKIT=1 docker build ...

# syntax=docker/dockerfile:1.6
FROM fedora:44

LABEL org.opencontainers.image.title="WebKitGTK-DND-Fix-builder"
LABEL org.opencontainers.image.description="Fedora 44 toolchain for WebKitGTK, SelectionData tests, GNOME Web AppImage"
LABEL org.opencontainers.image.source="https://github.com/sirredbeard/WebKitGTK-DND-Fix"

# --- Layer: core toolchain (stable) ---
COPY packages-core.txt /tmp/packages-core.txt
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/lib/dnf,sharing=locked \
    set -eux; \
    dnf -y upgrade --refresh --setopt=install_weak_deps=False || true; \
    dnf -y install --setopt=install_weak_deps=False \
        $(grep -vE '^\s*(#|$)' /tmp/packages-core.txt); \
    rm -f /tmp/packages-core.txt; \
    ccache --version; \
    cmake --version; \
    ninja --version; \
    mold --version; \
    g++ --version | head -1

# --- Layer: WebKit / GTK / GStreamer / AppImage deps ---
COPY packages-webkit.txt /tmp/packages-webkit.txt
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/lib/dnf,sharing=locked \
    set -eux; \
    dnf -y install --setopt=install_weak_deps=False \
        $(grep -vE '^\s*(#|$)' /tmp/packages-webkit.txt); \
    rm -f /tmp/packages-webkit.txt; \
    pkg-config --modversion gtk4; \
    pkg-config --modversion gtk+-3.0; \
    perl -Mbigint -e 'print "bigint ok\n"'; \
    command -v xdg-dbus-proxy; \
    command -v bwrap

# --- Layer: optional soft deps (may be missing on some spins; do not fail image) ---
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/lib/dnf,sharing=locked \
    set -eux; \
    dnf -y install --setopt=install_weak_deps=False --skip-unavailable \
        woff2-devel openxr-devel vulkan-headers vulkan-loader-devel \
        libwpe-devel wpebackend-fdo-devel || true; \
    dnf -y clean all

# Env after packages so script-only env tweaks can be a tiny later layer if split further.
ENV LANG=C.UTF-8 \
    CCACHE_DIR=/ccache \
    CCACHE_MAXSIZE=40G \
    CCACHE_COMPRESS=1 \
    CCACHE_COMPRESSLEVEL=5 \
    CCACHE_NOHASHDIR=true \
    CCACHE_DEPEND=true \
    CCACHE_COMPILERCHECK=content \
    CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime,pch_defines,file_macro \
    CCACHE_BASEDIR=/workspace \
    CMAKE_GENERATOR=Ninja \
    PATH=/usr/lib64/ccache:/usr/lib/ccache:/opt/webkitgtk-dnd-fix/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

RUN mkdir -p /workspace /ccache /out /opt/webkitgtk-dnd-fix/bin && chmod 777 /workspace /ccache /out

# --- Layer: CI scripts (change often; never force dnf rebuild) ---
COPY ccache-env.sh ci-build.sh ci-test-selectiondata.sh ci-build-and-test.sh \
    ci-build-webkitgtk-prefix.sh ci-build-gnome-web-appimage.sh \
    find-latest-webkit-prefix-artifact.sh clone-webkit.sh clone-from-mirror.sh \
    print-layer-checklist.sh \
    /opt/webkitgtk-dnd-fix/bin/
RUN chmod 755 /opt/webkitgtk-dnd-fix/bin/*.sh

WORKDIR /workspace
CMD ["/bin/bash"]
