# WebKitGTK-DND-Fix

Private CI and research for restoring **trusted** file drag-and-drop on WebKitGTK after CVE-2025-13947 / bugs.webkit.org 303434.

Engine patches: `sirredbeard/WebKit` branch `gtk-dnd-file-access-reenable`.  
This repo: Fedora 44 builder image, dual-runner Actions, HTML harness, GNOME Web AppImage lane, nested GUI stubs.

## Docs

- Agent rules: `.github/copilot-instructions.md`
- Research by topic: [`findings/`](findings/)
- Nested GUI sketch: `nested-gui/`

## Status (short)

- Four engine layers on the fork (trust split, allowsFileAccess for file drags, portal-prefer, IsSource + export sanitize).
- Open hard blocker: serialize `SelectionData` filenames over IPC (see `findings/opus-second-opinion.md`).
- CI: self-hosted Azure + Vultr, ccache/prefix/image peer sync, per-host git mirrors (not rsynced).

Dispatch workflows manually. Lint with actionlint before workflow commits. Single squash commit on `main`, no Co-authored-by.
