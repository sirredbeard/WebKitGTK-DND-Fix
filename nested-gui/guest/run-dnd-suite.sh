#!/usr/bin/env bash
# Inside guest: mount in/out, run AppImage against html layers, write results.json.
set -euo pipefail
IN="${DND_IN:-/mnt/dndin}"
OUT="${DND_OUT:-/mnt/dndout}"
export OUT_DIR="$OUT"
mkdir -p "$OUT/logs" "$OUT/screenshots"
exec > >(tee -a "$OUT/logs/suite.log") 2>&1
echo "guest suite $(date -u -Iseconds)"

# mounts (host 9p)
sudo mkdir -p /mnt/dndin /mnt/dndout
mountpoint -q /mnt/dndin || sudo mount -t 9p -o trans=virtio,version=9p2000.L dndin /mnt/dndin || true
mountpoint -q /mnt/dndout || sudo mount -t 9p -o trans=virtio,version=9p2000.L dndout /mnt/dndout || true

bash "$(dirname "$0")/canary-setup.sh"
bash "$(dirname "$0")/leak-watch.sh" pre

APP=$(ls -1 "$IN"/*.AppImage 2>/dev/null | head -1 || true)
[[ -n "$APP" ]] || { echo "no AppImage in $IN"; exit 1; }
chmod +x "$APP"
export APPIMAGE_EXTRACT_AND_RUN=1
export WEBKIT_DEBUG="${WEBKIT_DEBUG:-DragDrop}"
export GTK_DEBUG="${GTK_DEBUG:-}"

# TODO: start GNOME session / ensure WAYLAND_DISPLAY
# TODO: launch AppImage with html/layer1..4
# TODO: dogtail/pyatspi or wtype automation for L1/L4; L2 nautilus drop
# TODO: screenshots via grim/gnome-screenshot

bash "$(dirname "$0")/leak-watch.sh" post

cat >"$OUT/results.json" <<JSON
{
  "status": "stub",
  "appimage": "$(basename "$APP")",
  "layers": {"L1": "todo", "L2": "todo", "L4": "todo"},
  "note": "implement automation after AppImage CI green"
}
JSON
echo "stub guest suite done"
