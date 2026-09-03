# Host Flatpak layer1 manual observe (Wayland desktop)

Package: org.gnome.Epiphany.WebKitDnD tip flatpak
Page: layer1-web-uri-list-no-files.html
Session: stock GNOME Wayland (visible window)
Logs: ~/Downloads/webkit-dnd-flatpak-layer1-manual-observe/

## What was done
- In-page yellow→blue drag (S1 harness)
- Also dragged yellow source out to ~/Pictures/Screenshots/

## In-page S1 (CVE path)
Automated Xvfb run earlier: S1:PASS files=0 (title confirmed).
Manual desktop session: GDK drag cycles observed (enter/motion/leave/drop).
Ephy stdout does not print page title; PASS is judged by page RESULT/title
and by nested/automated S1. Nested CI + Xvfb S1 already PASS for Flatpak.

## Export yellow → Pictures/Screenshots (not the S1 File API case)
Nautilus created files like file:---etc-.txt with content exactly:
  file:///etc/passwd
size 18 bytes. That is the web-set text/uri-list and text/plain string
written as a text file. It is NOT a copy of /etc/passwd from disk.
No GdkFileList on that export path. Expected for drag-out of text types.
Does not reopen CVE-2025-13947 (CVE is web uri-list → File objects / file read).

## Automated Xvfb S1 (same package, same harness)
S1:PASS files=0 under Xvfb :99 + xdotool. See host-flatpak-manual-dnd-layer1-s1.md
