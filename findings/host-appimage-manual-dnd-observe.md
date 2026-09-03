# Host AppImage manual DnD observation (complete)

AppImage: ~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage
Profile: ~/.cache/webkit-dnd-ephy-profile (kept, not wiped)
Session: stock GNOME Wayland (XDG_SESSION_TYPE=wayland, WAYLAND_DISPLAY=wayland-0)
Page: http://127.0.0.1:8765/layer2-external-drop-files.html
Harness HTML: WebKitGTK-DND-Fix/html/layer2-external-drop-files.html
Artifact dir: ~/Downloads/webkit-dnd-manual-observe/

## How it was launched

- Existing Epiphany profile (not a fresh wipe)
- Full verbosity:
  - WEBKIT_DEBUG=DragAndDrop,Pasteboard,FileAPI,Loading,Network,Process,ProcessSuspension,IPC,ViewState,DropTarget,DragController
  - GDK_DEBUG=dnd,events,misc
  - G_MESSAGES_DEBUG=all
  - GIO_DEBUG=all
- Sandbox relaxed for local dogfood (WEBKIT_FORCE_SANDBOX=0 / DISABLE_SANDBOX flag)
- Native Wayland — not GDK_BACKEND=x11
- Side monitors: dbus-monitor session (full + portal filters), proc sampler, dnd log watcher, local http.server :8765 for layer2

## What you did

Manual Nautilus <-> Epiphany dragging (to/from/inside), on the live AppImage window over the layer2 green drop target and related chrome.

## Hard evidence in logs

### GDK / Wayland (ephy-stdout.log)

Counts from the captured session:

- GDK_DRAG_ENTER: 7
- GDK_DRAG_MOTION: 244
- GDK_DRAG_LEAVE: 7
- GDK_DROP_START: 5
- Wayland "data device drop": 5
- Content reads that include GdkFileList + portal types: 3 cycles
- text/uri-list reads: 3
- application/vnd.portal.files reads: 3
- text/plain reads: 3 (Nautilus also offers plain text)

Successful product path (repeated):

1. GDK_DRAG_ENTER
2. GDK content deserializer sees:
   - GdkFileList
   - application/vnd.portal.filetransfer
   - application/vnd.portal.files
   - text/uri-list
3. Explicit reads: portal.files and text/uri-list (and often text/plain)
4. Wayland: data device drop
5. GDK_DROP_START
6. GDK_DRAG_LEAVE

Example lines:

```
read for GdkFileList application/vnd.portal.filetransfer application/vnd.portal.files text/uri-list
read for application/vnd.portal.files
read for text/uri-list
data device drop, data device 0x3f25c30
Allocating a new GdkDNDEvent for event type GDK_DROP_START
```

Some enter/leave cycles had motion + drop without a fresh "read for GdkFileList" line in that cycle (content already negotiated, or drag left the web view / hit chrome). Five full data-device drops still landed.

### xdg-desktop-portal FileTransfer (dbus)

Nautilus (and the drop target side) went through Documents portal FileTransfer:

- StartTransfer
- AddFiles
- RetrieveFiles (drop side)
- TransferClosed

Rough counts in the monitor logs: StartTransfer/AddFiles ~12 each, RetrieveFiles/TransferClosed ~6 each (multiple transfers per gesture is normal).

This is exactly the modern GNOME Wayland file DnD path: not raw host paths alone, but portal-mediated file transfer + GdkFileList, with text/uri-list still present on the content provider.

### WEBKIT_DEBUG channels

WEBKIT_DEBUG was set on the real epiphany PID. The release AppImage still produced little/no classic WTF "DragAndDrop:" channel spam — logging looks build/config thin for those channels. GDK_DEBUG=dnd + portal dbus are the reliable host signals for this binary.

## Cycle breakdown

1. enter + full GdkFileList/portal/uri-list reads + drop
2. enter + full reads + drop
3. enter + motions + drop (no fresh content-read lines)
4. enter + leave without drop (drag cancelled / left target)
5. enter + full reads + drop
6. enter + motions + drop
7. enter + leave without drop

## Files captured

Under ~/Downloads/webkit-dnd-manual-observe/:

- logs/ephy-stdout.log (+ .final.log) — full GTK/GDK/GIO stderr/stdout
- logs/dnd-hits.log — filtered drag/drop lines
- logs/dnd-timeline-compact.txt — motions collapsed timeline
- logs/dnd-analysis.json — machine-readable counts + cycles
- logs/portal-filetransfer-dbus.txt — FileTransfer dbus slice
- logs/env-snapshot.txt, launch.txt, final-pids.txt, artifact-sizes.txt
- stack/dbus-session-full.log, dbus-session-portal.log
- stack/proc-sample.log
- OBSERVED-DND.md (this file)
- ~/Downloads/webkit-dnd-manual-observe-capture.tar.zst — frozen tarball

Also mirrored into WebKitGTK-DND-Fix/findings/host-appimage-manual-dnd-*

## Bottom line

Host Wayland Nautilus -> tip WebKitGTK AppImage file DnD is visible end-to-end in logs: portal FileTransfer + GdkFileList/uri-list offers, Wayland data-device drop, GDK_DROP_START. Matches the intended post-CVE trusted external-file path (portal/GdkFileList), not a web-origin uri-list attack path.
