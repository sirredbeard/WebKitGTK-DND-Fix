# Host Flatpak layer1 (S1) automated Xvfb

Package: org.gnome.Epiphany.WebKitDnD
Harness: layer1-web-uri-list-no-files.html
Method: automate_manual_qa case_s1 under Xvfb :99 + xdotool (GDK x11)
Logging: full WEBKIT_DEBUG + GDK_DEBUG=dnd

## Result
S1: **PASS**
Title: S1:PASS files=0
Meaning: web-authored text/uri-list file:///etc/passwd → files.length === 0.

## GDK during drag
- GDK_DRAG_ENTER: 1
- GDK_DRAG_MOTION: 14
- GDK_DROP_START: 1
- GdkFileList: 0 (attack must not become files)

Artifacts local only under ~/Downloads/webkit-dnd-flatpak-layer1-observe/
Screenshots not in git.
