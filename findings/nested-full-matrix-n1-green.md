# Nested full matrix green (N1 required)

Run: https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31359848716
Tip commit: 9e88bc1 (private CI main)
Packages: validation-20260810-gnome-web-31346489622 / run 31346489622
Engine: ae64af0353 (gtk-dnd-file-access-reenable)

## Result

All four cells PASS S1 S2 F1 S3 N1; canary_leaked=false; maintainer bar green.

- appimage-x11: all PASS
- appimage-wayland: all PASS
- flatpak-x11: all PASS
- flatpak-wayland: all PASS

N1 how=drop (OS file drag of n1-picker-nonreg-sample.txt onto layer5) with beacon
`/_dnd_result/N1/PASS?name=n1-picker-nonreg-sample.txt&how=drop`.

## What unlocked it

1. N1 required in DND_REQUIRE_N1 + maintainer bar
2. Drop fallback when GtkFileChooser not xdotool-visible
3. Score N1 from beacon (Epiphany title often stays "epiphany")
4. launch_ephy reload + accept live window when fixture HTTP up
5. Wipe nested/out each run so last-results is never stale
6. Package fetch pipefail + release pin
7. No mousemove --sync under XWayland
8. Openbox on wayland-x11 nested lane

## Still true

- Nested "wayland" = weston + X11 GDK + xdotool (not pure wl_data_device)
- Host GNOME Wayland Nautilus still supplemental (GTK4 drag source)
- No Bugzilla / upstream PR until asked
- CVE model unchanged (no web uri-list filenames; trusted setFilenames path)

