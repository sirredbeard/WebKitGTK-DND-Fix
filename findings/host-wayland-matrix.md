# Host Wayland / full matrix learnings

## Goal
Full AppImage|Flatpak × X11|Wayland e2e including N1 (file input) and F1 (external files). No xrdp. Nested KVM remains authoritative CI bar.

## What works
- S1/S2/S3 on host Wayland with GDK_BACKEND=x11 + xdotool (XWayland clients): solid PASS on tip AppImage and Flatpak.
- Nested CI already green for S1–S3+F1 with Nautilus under guest Xvfb+openbox (run 31351799703).
- Portable xdotool (user rpm extract) works against host DISPLAY=:0 XWayland.
- GTK4 X11 drag source window maps on host (`class=X11_drag_source.py`) when Nautilus is Wayland-only.
- N1 controlled fixture name `n1-picker-nonreg-sample.txt` rejects stray picks (earlier false PASS on a .flatpak).

## What does not / footguns
- Host GNOME Nautilus is pure Wayland: invisible to xdotool. Forcing GDK_BACKEND=x11 segfaults or errors (`Unsupported or missing session type 'wayland'` unless XDG_SESSION_TYPE=x11; still unstable on this host).
- Bare Xvfb without openbox: Nautilus/Epiphany windows may not map for xdotool.
- xdotool `mousemove --sync` under GNOME XWayland can block ~timeout per step; F1 drags looked hung. Fixed: plain mousemove + short sleeps.
- N1 typing into Epiphany URL bar if chooser detection is loose (path becomes window title). Fixed: only drive GtkFileChooserDialog / exact Open titles; never generic "file" match.
- GTK_USE_PORTAL=0 must stay set for the whole N1 case, not only launch.
- Host dual matrix runs can collide on :8765 and steal focus; run one dogfood at a time.
- ImageMagick `import -window root` fails on GNOME Wayland; prefer gnome-screenshot/grim.
- ephemeral-docker still optional Azure ops (not required for DnD bar). xrdp dropped.

## Automation changes
- `automate_manual_qa.py`: N1 required (DND_REQUIRE_N1=1); chooser drive; F1 Nautilus then GTK4 `x11_drag_source.py` fallback; force X11 spawn without WAYLAND_DISPLAY; drag without --sync.
- `scripts/host-matrix-dogfood.sh`: 4-cell host matrix, Xvfb+openbox for x11, learnings.md.
- Nested gate: require N1 PASS with F1 when fail_on_suite.

## Status
Host dogfood still proving F1/N1 after drag/chooser fixes. Nested CI is the ship bar; host is extra confidence under live GNOME Wayland.

## xdotool --sync measurement (host GNOME Wayland / XWayland)

- 20-step plain mousemove drag: ~0.20s
- single `mousemove --sync`: TIMEOUT at 3s (hangs)
- Conclusion: never use --sync for pointer motion on this host; windowactivate --sync still OK with short timeout

## Nested fetch footgun

`set -o pipefail` + `RUN_ID=$(gh ... | while ... grep -q ...)` exited 1 when no live package artifacts, aborting the step before release fallback. Fixed with `|| true`, runner package cache reuse, and pin to validation-20260810-gnome-web-31346489622.


## Nested N1 green path (beacon + drop)

- Drop of controlled fixture onto layer5 fires `/_dnd_result/N1/PASS?name=n1-picker-nonreg-sample.txt&how=drop`.
- Epiphany Xvfb window title often stays `epiphany`; must score N1 from beacon, not xdotool title alone.
- Run 31358641234: N1 PASS appimage-x11 + both flatpak cells; appimage-wayland N1 failed launch (title stuck); S2 appimage-x11 same. Fixed launch_ephy to reload URL and accept live window when fixture HTTP is up.
- Flatpak full matrix already green with N1 on that run.

