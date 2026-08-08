#!/usr/bin/env bash
# One-time/rare: build Fedora 44 Workstation golden qcow2 for nested DnD GUI tests.
# Run on Azure host with nested KVM. Not invoked by default CI.
set -euo pipefail
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}/nested"
IMG="${GOLDEN_QCOW2:-$CACHE/fedora-44-ws-dnd-golden.qcow2}"
SIZE_G="${GOLDEN_SIZE_G:-48}"
# Official Fedora Workstation netinst/live URL — pin when implementing.
ISO_URL="${FEDORA_WS_ISO_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/}"
mkdir -p "$CACHE"
echo "TODO: virt-install Fedora 44 WS -> $IMG (${SIZE_G}G)"
echo "  - GDM autologin user dnd"
echo "  - pkgs: nautilus xdg-desktop-portal-gnome at-spi2-core python3-pyatspi jq strace lsof"
echo "  - virtio-gpu, qemu-guest-agent, sshd"
echo "  - disable lock/screensaver; cloud-init from nested-gui/guest/cloud-init.yaml"
echo "ISO index: $ISO_URL"
echo "Require: /dev/kvm, qemu-kvm, virt-install, edk2-ovmf"
test -e /dev/kvm && echo "kvm ok" || echo "kvm MISSING"
exit 0
