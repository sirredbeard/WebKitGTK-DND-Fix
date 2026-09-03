# Host Flatpak manual DnD observation (layer2)

Package: ~/Downloads/GNOME_Web-WebKitGTK-DnD.flatpak
App ID: org.gnome.Epiphany.WebKitDnD (branch dnd-fix)
Profile: ~/.cache/webkit-dnd-ephy-profile-flatpak-observe
Session: stock GNOME Wayland
Page: http://127.0.0.1:8765/layer2-external-drop-files.html (layer2 only, not layer1)
Artifacts: ~/Downloads/webkit-dnd-flatpak-manual-observe/
No screenshots stored in git.

## Env
- WEBKIT_DEBUG DnD/Pasteboard/FileAPI/...
- GDK_DEBUG=dnd,events,misc,portals,settings
- G_MESSAGES_DEBUG=all, GIO_DEBUG=all
- Native Wayland (flatpak allowed wayland socket; wl_data_device_manager + xdg_toplevel_drag_manager_v1)
- Extra --filesystem for fixtures + Downloads (read-only) so drops from those trees work under sandbox

## Layer2 results (Nautilus -> Flatpak Epiphany)

Two full drop cycles captured:

- GDK_DRAG_ENTER: 2
- GDK_DRAG_MOTION: 51
- GDK_DRAG_LEAVE: 2
- GDK_DROP_START: 2
- Wayland data device drop: 2
- GdkFileList / portal.files / text/uri-list reads: 2 each
- Portal FileTransfer: StartTransfer/AddFiles + RetrieveFiles/TransferClosed (4 retrieves)

Path each cycle:
1. GDK_DRAG_ENTER
2. read GdkFileList + application/vnd.portal.filetransfer + application/vnd.portal.files + text/uri-list
3. read application/vnd.portal.files and text/uri-list
4. file transfer portal: Receiving files: /run/user/1000/doc/.../<name>
5. data device drop
6. GDK_DROP_START
7. GDK_DRAG_LEAVE

Same product path as AppImage observe: portal-mediated GdkFileList on Wayland into tip WebKitGTK, not a web-origin uri-list attack path.

## Note
User confirmed layer2 testing only (not layer1 security harness in this session).
