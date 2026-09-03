# Combined host DnD observe + bar assessment

Ship bar (CI): nested run 31359848716 — AppImage|Flatpak × X11|Wayland, S1–S3+F1+N1 all PASS.

No screenshots in git (removed findings/screenshots/; gitignore png/screenshots/out).

## Packages tested locally

- AppImage: ~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage
- Flatpak: ~/Downloads/GNOME_Web-WebKitGTK-DnD.flatpak → org.gnome.Epiphany.WebKitDnD

## Local manual results

### Usability / product — layer2 Nautilus → browser (Wayland)

AppImage: PASS path. portal FileTransfer + GdkFileList + uri-list + data device drop + GDK_DROP_START across multiple cycles. See host-appimage-manual-dnd-observe.md.

Flatpak: PASS path. Same stack; portal Receiving files under /run/user/1000/doc/... (2 cycles). See host-flatpak-manual-dnd-observe.md.

### Security — layer1 web uri-list must not become Files

Flatpak automated Xvfb S1: PASS, title S1:PASS files=0.

Flatpak manual Wayland desktop: layer1 harness; GDK enter/motion/drop cycles logged. Page title is not mirrored to ephy stdout; Xvfb + nested already lock S1.

Nested CI: S1 PASS on all four cells for both packages.

### Yellow drag out to ~/Pictures/Screenshots/

Created text files like file:---etc-.txt whose entire content is the 18-byte string:

  file:///etc/passwd

That is text/plain + text/uri-list drip to the desktop. It is not a copy of /etc/passwd from disk and not a File API grant. Does not fail CVE-2025-13947 (CVE is web uri-list minting File objects / file contents inside the page).

### Regression — file input N1

Nested CI N1 PASS on all four cells (controlled fixture + beacon). Host pure-Wayland Nautilus N1 automation is weaker; ship bar is nested.

## Does local manual AppImage+Flatpak pass the bar?

Yes, for the goals we set:

1. Usability: Nautilus → tip WebKitGTK file drop works on both packages under stock GNOME Wayland (portal/GdkFileList path).
2. Security: S1 PASS (no File objects from web file:// uri-list) on Flatpak host automated + full nested matrix both packages. Manual export-to-folder only wrote the uri string as text.
3. Regression: N1+F1+S2+S3 green in nested CI for both packages × both session backends.

Caveats:

- Host manual did not re-run full S2/S3/N1 by hand on every package; nested CI is the complete automated bar.
- Nested "wayland" cell is weston + X11 GDK + xdotool, not pure Mutter wl_data_device. Host manual Wayland fills that gap for layer2 product path.
- WEBKIT_DEBUG channels stay quiet on release packages; GDK_DEBUG + portal dbus carry host evidence.

## Does automated CI have the same granularity?

Mostly yes on cases, not identical on environment.

CI nested (automate_manual_qa.py) runs with beacons + titles:

- S1 layer1 web uri-list → files.length 0
- S2 local drag deny
- S3 export/watch
- F1 external multi-file product drop
- N1 file-input non-reg with controlled fixture name

CI does not currently:

- Drive real host Mutter Nautilus pure-Wayland drops (host manual does)
- Assert portal FileTransfer dbus sequences as first-class checks
- Score web→desktop text export side effects (the Pictures txt files)

So CI granularity on security/product cases is at least as strict (and more complete on S2/S3/N1). Host manual is finer on real GNOME Wayland portal UX. Together they meet the bar; neither alone is a perfect clone of the other.

## Artifact index (local Downloads, not git blobs)

- webkit-dnd-manual-observe/ — AppImage L2
- webkit-dnd-flatpak-manual-observe/ — Flatpak L2
- webkit-dnd-flatpak-layer1-observe/ — Flatpak S1 Xvfb
- webkit-dnd-flatpak-layer1-manual-observe/ — Flatpak S1 manual desktop

## Bottom line

Local manual AppImage + Flatpak dogfood passes usability and security intent for layer2 + S1, aligned with nested green. Keep nested CI as the release gate; keep host Wayland observe as supplemental proof of the real Nautilus path.
