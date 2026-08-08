#!/usr/bin/env bash
# Boot ephemeral overlay of golden image, inject AppImage+html, run guest suite, collect artifacts.
# Azure host only. Optional — after unit+AppImage green.
set -euo pipefail
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}/nested"
GOLDEN="${GOLDEN_QCOW2:-$CACHE/fedora-44-ws-dnd-golden.qcow2}"
APPIMAGE="${APPIMAGE_PATH:?set APPIMAGE_PATH to host path of Epiphany AppImage}"
HTML_DIR="${HTML_DIR:-$(cd "$(dirname "$0")/../../html" && pwd)}"
OUT_HOST="${OUT_HOST:-$CACHE/out/$(date -u +%Y%m%dT%H%M%SZ)}"
CPUS="${GUEST_CPUS:-8}"
MEM_MB="${GUEST_MEM_MB:-16384}"
HOLD="/etc/webkit-dnd/HOLD_AWAKE"
STAMP="/var/cache/webkit-dnd/out/last-runner-activity"

mkdir -p "$CACHE/in" "$OUT_HOST" /mnt/webkit-dnd/nested 2>/dev/null || true
echo "nested-gui suite start $(date -u -Iseconds)"
test -e /dev/kvm || { echo "no /dev/kvm"; exit 1; }
test -f "$GOLDEN" || { echo "missing golden $GOLDEN — run build-golden-image.sh first"; exit 1; }
test -f "$APPIMAGE" || { echo "missing AppImage $APPIMAGE"; exit 1; }

# Keep Azure idle watchdog away
sudo mkdir -p /etc/webkit-dnd /var/cache/webkit-dnd/out
sudo touch "$HOLD"
date -u +%s | sudo tee "$STAMP" >/dev/null || date -u +%s > "$STAMP"

cp -af "$APPIMAGE" "$CACHE/in/"
rm -rf "$CACHE/in/html" && cp -a "$HTML_DIR" "$CACHE/in/html"
cp -a "$(cd "$(dirname "$0")/../guest" && pwd)/." "$CACHE/in/scripts/" 2>/dev/null || true

OVERLAY="/mnt/webkit-dnd/nested/overlay-$$.qcow2"
qemu-img create -f qcow2 -b "$GOLDEN" -F qcow2 "$OVERLAY"

echo "TODO qemu-system-x86_64 \\"
echo "  -enable-kvm -cpu host -smp $CPUS -m $MEM_MB \\"
echo "  -drive file=$OVERLAY,if=virtio \\"
echo "  -device virtio-gpu-gl or virtio-vga \\"
echo "  -fsdev local,id=in,path=$CACHE/in,security_model=none -device virtio-9p-pci,fsdev=in,mount_tag=dndin \\"
echo "  -fsdev local,id=out,path=$OUT_HOST,security_model=none -device virtio-9p-pci,fsdev=out,mount_tag=dndout \\"
echo "  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0"
echo "TODO: wait guest agent/ssh; ssh run /mnt/dndin/scripts/run-dnd-suite.sh; pull results; shutdown"
echo "OUT_HOST=$OUT_HOST"

sudo rm -f "$HOLD"
date -u +%s | sudo tee "$STAMP" >/dev/null || true
# leave overlay for debug unless CLEAN_OVERLAY=1
[[ "${CLEAN_OVERLAY:-0}" == "1" ]] && rm -f "$OVERLAY"
echo "stub complete — implement qemu boot when AppImage green"
exit 0
