# Nested GUI DnD automation

Goal: run the same checklist a human runs on the AppImage, headlessly, with enough stack noise to see WebKit, GTK, portals, Nautilus, D-Bus, and xdotool when something fails. Local first, then the same scripts on the Azure self-hosted runner.

## Layout

- `nested-gui/host/build-golden-image.sh` - Fedora 44 cloud base -> golden qcow2
- `nested-gui/host/run-guest-suite.sh` - qemu-kvm overlay, ssh, copy AppImage + html + guest scripts
- `nested-gui/guest/run-dnd-suite.sh` - Xvfb, openbox, portals, stack tracers, invoke automation
- `nested-gui/guest/automate_manual_qa.py` - xdotool S1/S2/S3/F1/N1 against HTML harness
- `nested-gui/guest/stack-trace-env.sh` - WEBKIT_DEBUG, GDK/GTK, GLib/GIO, portals, Mesa, AT-SPI, AppImage debug
- `scripts/ci-verbose-gui-probe.sh` - host-side full-stack probe (same depth as guest env); path audit + migrator + canary
- `.github/workflows/nested-gui-dnd.yml` - wake Azure, fetch AppImage artifact, ensure golden, probe, nested suite, upload debug pack

## Golden image cache

Golden lives on the VM:

`/var/cache/webkit-dnd/nested/fedora-44-ws-dnd-golden.qcow2` (CI)

Locally we use `$WEBKIT_DND_CACHE/nested/` (for example `~/webkit-dnd-cache/nested/`).

On-disk size here is about 2.0G qcow2, 40G virtual. Cloud base about 557M.

Cache policy:

- Recipe stamp = hash of builder script identity + package list + size knob.
- Hit when `.stamp` matches and `.ok` exists.
- Rebuild only on stamp change or `FORCE_GOLDEN=1`.
- Guest automation Python/shell is copied at suite time. Changing those does **not** rebuild golden.
- Packages are a minimal DnD lab list (shell session bits, nautilus, xdotool, Xvfb, portals, strace, mesa). Not a full Workstation spin. No LibreOffice tax.

F44 note: `gnome-session-xsession` is gone. Install with `dnf --skip-unavailable` so one missing name does not abort cloud-init.

## What "lots of monitoring" means

Per nested run we want on the artifact pack:

- AppImage extract path audit (migrator reloc, no `/opt` leftovers, embedded webkit sha)
- ephy per-page logs with WEBKIT_DEBUG DnD/Pasteboard/FileAPI/IPC/Process
- GDK_DEBUG dnd,events,portals and GTK_DEBUG
- G_MESSAGES_DEBUG / GIO_DEBUG
- dbus-monitor session + portal-related noise
- xdg-desktop-portal and xdg-desktop-portal-gtk logs
- proc sampler (epiphany, WebKitWebProcess, Nautilus, portals)
- xdotool action trace (moves, clicks, drags) and screenshots
- HTML machine RESULT markers and titles
- canary token file and leak report (must not appear in page/logs)

Host probe uses the same stack-trace-env channels. Nested suite owns real drag cases.

## Maintainer success bar (automation)

From manual-qa.md / test-matrix.md:

| Case | Meaning | Bar |
|------|---------|-----|
| S1 | Web uri-list must not become Files | MUST PASS |
| S2 | IsSource / local drag must not grant | MUST PASS |
| S3 | Export sanitize | MUST PASS |
| F1 | Trusted external file drop works | MUST PASS for product |
| N1 | file input non-reg | should pass |
| canary | token never surfaces in page | MUST NOT leak |

CI `fail_on_suite` (default true) fails the job when security cases are not PASS or F1 is not PASS, or canary leaked. INCONCLUSIVE is not success once the AppImage launches cleanly.

Packaging failures (migrator abort, missing window solely because of AppRun) are infrastructure, not DnD verdicts. Fix the image first.

## Local status

- Golden built and stamped; cache hit verified.
- Earlier nested run: all cases INCONCLUSIVE because epiphany aborted on absolute migrator path (pre-reloc AppImage).
- Waiting on reloc-fixed AppImage (Python packer) then re-run local nested with full tracers, then dispatch nested CI with that run id.

## CI status

Workflow is workflow_dispatch. Does not yet gate the AppImage job. After a green AppImage:

1. Dispatch nested-gui-dnd with `appimage_artifact_run_id`.
2. Golden ensure is stamp-cached on Azure.
3. Upload `nested-gui-debug-<runid>` always.

## Longer write-up

Operational detail for automation, golden stamp cache, dual runners, and what worked vs not: **findings/gui-automation-and-ci.md**.


## Nested suite flake after render-fixed AppImage

Run `20260808T103311Z` with AppImage 31252342415: all cases INCONCLUSIVE. Not the host blank-page extension bug.

Causes seen in guest logs:

1. `G_DEBUG=fatal-criticals` plus Gtk-CRITICAL on AT-SPI registry spawn (Permission denied) — aborts tooling paths.
2. Epiphany profile on 9p `/mnt/dndout/ephy-profile` → SQLite "disk I/O error" / cannot open history DB; window title stuck on default "Blank page"; HTTP fixture server only saw GET `/`, never the layer HTML.
3. Most screenshots 313-byte black frames under nested Xvfb before paint.

Fixes in guest scripts: drop fatal-criticals default, NO_AT_BRIDGE=1, GTK_A11Y=none, GSK_RENDERER=cairo, profile on `~/.cache/webkit-dnd-ephy-profile`, wait for non-Blank Layer title before DnD.

Host-side Example Domain proof for the AppImage remains valid; nested is automation environment, not engine regression.

## Azure host probe failure (no Xvfb)

Nested run 31344043919 died in Full-stack host GUI probe with empty DISPLAY and exit 1 before Xvfb start. Root cause: Azure self-hosted runner is Ubuntu 24.04, but Host prep only ran `dnf install` (no-op / missing) with `|| true`. Probe then hit `command -v Xvfb` under `set -e` while dumping environment.txt and aborted.

Fix: `scripts/ci-install-nested-host-deps.sh` (apt on Debian/Ubuntu, dnf on Fedora), call from nested Host prep + host probe; harden tool checks in `ci-verbose-gui-probe.sh`; default packages matrix `appimage flatpak`.

## Host probe hang on tee pipe

After path-audit die(), nested step stayed in_progress: workflow ran
bash ci-verbose-gui-probe.sh piped to tee, and Xvfb only redirected stderr,
so it kept pipe stdout open and tee never got EOF. Fix: redirect Xvfb
stdout, EXIT trap cleans helpers, probe writes console via redirect not
pipe; host probe continue-on-error plus 15m timeout.

Stale AppImage in packages artifact (embedded sha d5bec, pre-reloc) fails
path audit. Flatpak matrix should still run.

## nested self-clobber (run 31346813976)

Fetch staged tip AppImage+Flatpak into `/var/cache/webkit-dnd/nested/in/` (171M + 42M listed). Guest suite then did `rm -rf "$CACHE/in"` and `cp -af "$APPIMAGE_PATH" "$CACHE/in/"` with APPIMAGE_PATH already under CACHE/in. Source gone, cp fails, suite dead before QEMU.

Fix: snapshot packages (and html) into mktemp stage under CACHE, then wipe/rebuild `in/`. Guest also gets `suite-env.sh` for DND_PACKAGES/backends (SSH does not inherit host env). AppImage optional when flatpak-only. Debug artifact slimmed (no squashfs-root) so local download does not blow disk quota.

Host probe still continue-on-error; workflow now always cats probe-console on failure.

## nested ssh_timeout (run 31347148297)

Clobber fix worked (staged appimage+flatpak). Guest booted Fedora Cloud on golden overlay; cloud-init finished; serial showed login. Host never got SSH:

- qemu.log: `ci-info: no authorized SSH keys fingerprints found for user dnd`
- Host had no sshpass; BatchMode pubkey auth only
- Fedora Cloud often PasswordAuthentication no even with ssh_pwauth in user-data
- instance-id was static `webkit-dnd-gui` (risk of cloud-init skip on reuse)

Fix: per-boot instance-id; generate CACHE/guest-ssh-key and inject ssh_authorized_keys + runcmd authorized_keys; install sshpass in nested host deps; prefer key SSH with password fallback. Host probe: stop FAIL on mere bwrap string in AppRun (only FAIL if exec path).

Host probe path audit on tip AppImage: migrator ok, ae64af sha, no /opt residual; only bwrap string false-fail before soften.

## nested 9p dndout permission (run 31347877892)

SSH key path green (try=3). Guest then failed mkdir /mnt/dndout/* Permission denied. 9p security_model=none exposes host dir modes; OUT_HOST was 755 gha-owned. Fix: chmod 777 OUT_HOST + seed subdirs on host; guest mkdir after mount with sudo fallback.
Host probe PASS on tip AppImage (migrator_ok).

## nested 9p write + Platform 50 (runs 313480–313484)

Guest SSH green. 9p dndout not reliably writable for uid 1000 (permission denied on create despite 777). Switched suite OUT to /home/dnd/dnd-out local disk; host tars it back over SSH after suite.

Flatpak install failed: org.gnome.Platform//50 missing on golden. Guest now remote-adds flathub and installs Platform//50 before the bundle (needs guest net — usernet already on).

## DISPLAY lost via pipe (run 31348679486)

session_backend_start was piped to tee → subshell → Xvfb DISPLAY never reached automate. Cells ran with empty DISPLAY; xdotool failed. Fixed: append logs to file, no pipe. Also unit SelectionData 13/13 green on 31347639203.

## Dead DISPLAY across matrix cells

After appimage-x11 went green (S1-S3+F1), every later cell died with a dead X socket. Stop must unset DISPLAY. Start must not trust a leftover DISPLAY value — verify with xdpyinfo or always spawn a fresh Xvfb.

Wayland note: xdotool only drives X11. Default wayland cell now keeps a live Xvfb and forces GDK x11 for automation unless DND_WAYLAND_NATIVE=1. That is an honest nested compromise so we still exercise the package under a weston host without blocking the maintainer bar on missing ydotool.

Results harvest: prefer SSH tar of /home/dnd/dnd-out with visible logs; if empty, scrape the printed results.json from ssh-suite.log via auto_rc/cases_matrix markers.

## Bar closed: 31351799703

Full dual matrix green end-to-end (workflow success). Product bar = S1-S3+F1 PASS
on every cell. N1 soft. Rebuild-if-stale: packages not rebuilt for this proof;
used 31346489622 tip artifacts.

Remaining nested polish only if desired: bake Platform 50 into golden, native
Wayland input without GDK x11, dogtail N1. None required for maintainer bar.
