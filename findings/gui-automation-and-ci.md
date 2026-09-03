# GUI automation, golden image, and dual-runner CI

How we run non-interactive DnD QA, what we log, how the Fedora 44 golden guest is built and cached, and how the two self-hosted runners share work. Product DnD design lives in engine-fix.md and goal-and-cve.md. AppImage packing traps live in appimage-packaging.md. Money boxes live in budget-and-ops.md.

## 1. What "automated GUI" means here

We are not driving a full GNOME session on the host desktop. We run:

1. **Host full-stack probe** (`scripts/ci-verbose-gui-probe.sh`) on Xvfb: extract AppImage, path/reloc audit, AppRun --version, cold profile launch, canary token check, dbus/portal/proc noise, screenshot if import exists.
2. **Nested guest suite** (qemu-kvm + golden qcow2): real xdotool moves/clicks/drags against the HTML harness, Nautilus for external drop, same stack tracers inside the guest.

Human interactive QA (download AppImage, open HTML, drag by hand) stays authoritative when automation returns INCONCLUSIVE. Automation is for regression signal and for packing/launch failures that used to hide behind "window never appeared".

### Cases (maintainer bar)

| Id | Layer | Intent |
|----|--------|--------|
| S1 | layer1 web uri-list | Must not populate Files from hostile page |
| S2 | layer4 local / IsSource | In-page drag must not grant file access |
| S3 | layer4 export | Export path must not leak file:// as grant |
| F1 | layer2 external drop | Trusted file from Nautilus/Files must work |
| N1 | layer5 file input | Non-reg file picker still works |

S1/S2/S3 FAIL is a security regression. F1 FAIL is a product regression. canary token in page or ephy logs is FAIL. INCONCLUSIVE means the harness did not get a clean verdict (launch abort, missing window, flaky geometry). After a healthy AppImage, CI treats INCONCLUSIVE on S1-S3/F1 as not success when `fail_on_suite` is on.

### HTML harness

Under `html/`:

- Machine-readable `RESULT` lines and document titles for automation.
- layer5 added for file-input non-reg.
- Bundled into the AppImage under `share/webkitgtk-dnd-fix/html` when pack finds it.
- Served in guest/host probe via `python3 -m http.server` on 8765 so we are not fighting file:// quirks alone.

### Stack monitoring (guest and host probe)

`nested-gui/guest/stack-trace-env.sh` exports one channel set. Host probe sources the same file when present.

Covered layers:

- AppImage: `APPIMAGE_EXTRACT_AND_RUN`, `APPIMAGE_DEBUG`, keep extract for post-mortem
- WebKit: `WEBKIT_DEBUG` / `WEBKIT2_DEBUG` / `WEBCORE_DEBUG` (DragAndDrop, Pasteboard, FileAPI, Loading, Network, Process, IPC, ...)
- GTK/GDK: `GTK_DEBUG`, `GDK_DEBUG=dnd,events,misc,portals`, `GDK_BACKEND=x11` under Xvfb
- GLib/GIO: `G_MESSAGES_DEBUG=all`, `GIO_DEBUG`, portal-related chatter
- Mesa: software GL in nested (`LIBGL_ALWAYS_SOFTWARE`), verbose GL logs
- AT-SPI: a11y bus for future richer automation
- D-Bus: `dbus-monitor` session + portal-ish filters; xdg-desktop-portal and portal-gtk verbose if installed
- Proc sampler: epiphany, WebKit*Process, Nautilus, portals, AppRun
- xdotool action trace + screenshots (ImageMagick `import`)
- Per-page ephy logs, leak-watch on canary token, fixtures created for drag files

Artifacts land under the run out dir (`results.json`, `logs/stack/*`, `screenshots/*`, `manual-qa-*.json`). CI uploads `nested-gui-debug-<runid>`.

### Guest automation flow

`automate_manual_qa.py`:

1. Start HTTP server on harness.
2. Launch AppImage with `--profile=<fresh dir>` only (Epiphany rejects `--private-instance` with `--profile`).
3. Wait for visible Epiphany/Web window via xdotool; dump all window names on failure.
4. S1: open layer1, read RESULT / title, assert no file grant.
5. S2/S3: layer4 local and export checks.
6. F1: open layer2, start Nautilus on fixtures dir, xdotool drag toward Epiphany geometry, read RESULT.
7. N1: layer5 file input smoke.
8. Always write `results.json` and stop tracers.

Launch always goes through the AppImage entrypoint (AppRun), never bare `usr/bin/epiphany` after extract. That is mandatory once migrator reloc lives in AppRun.

### What worked for GUI automation

- Xvfb + openbox is enough to map a window without a full GNOME login session.
- Fresh `--profile` dirs make migrator and state reproducible.
- RESULT markers in HTML beat brittle OCR.
- Full-stack logs turned "window never appeared" into a concrete migrator abort (`/usr/libexec/epiphany/ephy-profile-migrator` missing or version skew).
- Canary file + grep is a cheap leak net for S1-class mistakes.

### What did not work (yet)

- First nested runs were all INCONCLUSIVE solely because the AppImage died in the migrator before any window. DnD verdicts were noise until packing was fixed.
- xdotool drag geometry is brittle (Nautilus icon layout, HiDPI, timing). Expect F1 flakes until we tighten fixtures and maybe AT-SPI.
- Host probe on short timeout can see "Web process crashed" under pure software GL without that being the engine DnD bug. Record it; do not treat as S1 FAIL by itself.
- Dual session backends are now first-class: nested matrix runs **x11** (Xvfb + openbox + `WEBKIT_DND_FORCE_X11=1`) and **wayland** (weston headless, unset `GDK_BACKEND` so AppRun/wrapper prefer native Wayland). Same S1–S3/F1 bar per cell.
- Dual packages: **AppImage** and **Flatpak** (`org.gnome.Epiphany.WebKitDnD` with slipstreamed WebKit). Flatpak cell runs when a `.flatpak` is staged on the guest in-share.
- Azure nested needs the golden on disk; without it CI fell back to host probe only. Fixed by stamp-cached golden ensure in the workflow. Golden recipe stamp includes weston+flatpak guest packages.

## 2. Golden image build and cache

### Recipe

`nested-gui/host/build-golden-image.sh`:

1. Fetch Fedora 44 Cloud Base qcow2 once into the cache dir.
2. Create a backing qcow2, resize virtual size (default 40G).
3. cloud-init user-data installs a **minimal** DnD lab package set with `dnf --skip-unavailable` (F44 dropped some old package names; one missing name must not abort the whole transaction).
4. Packages include: gnome-shell/session bits, gnome-terminal, nautilus, xdg-desktop-portal{,-gtk,-gnome}, at-spi, python3, xdotool, Xvfb, openbox, dbus, fuse, jq, strace, mesa dri, ImageMagick, xev, qemu-guest-agent. Not a full Workstation spin. No LibreOffice.
5. Write `golden_ok` into the guest when Xvfb/xdotool/openbox are present, then poweroff.
6. Promote work image to `fedora-44-ws-dnd-golden.qcow2`.

Local sizes observed: cloud base ~557M on disk; golden ~2.0-2.1G on disk, 40G virtual.

### Cache policy (do not rebuild every CI run)

Stamp file beside the golden: hash of builder script identity + package list fingerprint + size knob (`golden_recipe_v2`).

- Cache **hit** when stamp matches and `.ok` exists → exit 0 immediately.
- Rebuild only on stamp mismatch or `FORCE_GOLDEN=1`.
- Guest suite scripts and HTML are **not** in the stamp. They are copied into the overlay at suite time.

CI workflow step "Ensure golden image" always calls the builder; the builder no-ops on hit. That keeps Azure and a laptop share the same semantics.

### Suite runtime

`run-guest-suite.sh` uses an overlay qcow2 on the golden, user networking + ssh, copies AppImage + html + guest scripts, runs `run-dnd-suite.sh`, pulls results out. Host cache root is `WEBKIT_DND_CACHE` (CI: `/var/cache/webkit-dnd`, local: e.g. `~/webkit-dnd-cache`).

## 3. Dual-runner CI (Vultr + Azure)

Private repo: `sirredbeard/WebKitGTK-DND-Fix`. Engine fork: `sirredbeard/WebKit` branch `gtk-dnd-file-access-reenable`. Upstream WebKit does not run public GHA for the engine; we run private validation only. Squash to main, no Co-authored-by on this private repo.

### Machines

| | Vultr | Azure |
|--|--------|--------|
| Role | Fast Fedora burn box | Nested KVM capable, budget-watched, wakes on demand |
| Host OS | Fedora 44 Server | Ubuntu 24.04 (marketplace). Work still runs in Fedora 44 containers |
| Runner labels | self-hosted, vultr, webkit-dnd, ... | self-hosted, azure, webkit-dnd, ... |
| Billing | On while the instance exists | Deallocate when idle; $150/mo budget alarms |
| Nested GUI | Possible if KVM exposed | Primary nested target (`/dev/kvm`) |

GitHub hands `webkit-dnd` jobs to whichever runner is idle. Heavy unit/AppImage jobs pin or prefer labels as the workflow says (AppImage often Azure wake + build).

### Shared cache layout (`/var/cache/webkit-dnd`)

On each runner (and locally under WEBKIT_DND_CACHE):

- `ccache/` large cap on NVMe
- `build-gtk/` persistent ninja tree when kept
- `prefix/` WebKitGTK install + `.webkitgtk-dnd-sha` stamp
- `mirrors/` bare WebKit + epiphany (per host; see below)
- `tools/` linuxdeploy, appimagetool
- `nested/` golden, cloud base, suite out, in/
- `images/` optional docker seed tarballs
- last-good prefix tarballs for tip seed

### Peer sync: what worked

- **ccache warm from peer** and live-sync during long builds cut cold compile pain on the second machine.
- **Prefix last-good tarballs** with tip-first selection and `EXPECTED_WEBKIT_SHA` / seed pin so a stale shorter SHA cannot wipe a newer tip (d5bec vs branch tip lesson).
- **Size-winner / stamp checks** when choosing peer artifacts.
- **rsync exclude** of huge throwaway trees where needed; docker image layers stay local to each host's docker store when tags match.
- **Azure wake scripts** + activity stamps so deallocate does not strand jobs.
- **Vultr API from Azure** only after static IP allowlist (`20.127.61.97`); key on Azure root only, not in GitHub secrets.
- **Five-day Vultr snapshot+delete** timer from Azure as an exit hatch.
- **Budget guard** on Azure: touch file or script → stop runner + deallocate. Budgets email; they do not hard-kill by themselves.

### Peer sync: what did not work / do not repeat

- **Shared bare git mirrors across peers via rsync** caused corrupt objects and wrong HEAD checkouts (`unable to read sha1 file`, detached at main while branch tip lived only locally). Fix: per-host mirrors, fetch from origin, verify `ls-remote` tip vs HEAD, refuse wrong tree. No peer rsync of git objects.
- **Seed last-good without tip pin** let an older successful main build poison AppImage/unit against the DnD branch.
- **Trusting systemctl active alone on Azure** while the Actions listener was a zombie. Need health script: Listening for Jobs, diag, sudoers, activity.
- **Root-owned `__pycache__` / build dirs** from container binds without passwordless sudo for gha → clone/rm failures that looked like GHCR pull failures. Fix: sudoers + wipe helpers + distinct error text.
- **AppImage smoke calling bare epiphany** skipped AppRun and lied about migrator health.
- **bwrap AppRun** as a packing fix: worked, wrong model (see appimage-packaging.md).
- **sed -i reloc on ELF in the pack container**: no bytes changed, CI fail-closed. Python same-length replace works.
- **GHA-hosted ccache upload** for full WebKit trees: too big / wrong shape. Prefer on-box NVMe ccache + prefix tarballs + optional small build snapshots.
- **Ephemeral docker on Azure** while nested or migrate is busy: defer; HOLD_AWAKE and uptime gates exist for a reason.

### Workflow map (private repo)

- Unit / TestWebCore + external validation
- WebKitGTK prefix build
- GNOME Web AppImage + clean F44 smoke
- Nested GUI probe (dispatch; golden stamp cache; full host probe; guest suite; maintainer bar)
- Parallel burn, runner wake/reboot/teardown helpers, container build

Engine commits stay on the fork branch. Validation repo main is squash-friendly ops git.

## 4. End-to-end path we want every tip through

1. Engine push on `gtk-dnd-file-access-reenable` (IPC filenames, clipboard sanitize, GTK4 pending drop, SelectionData tests).
2. Unit lane: SelectionData.* PASS (TestWebKitAPI prints PASS, not gtest PASSED).
3. AppImage lane: tip prefix seed, pack with Python reloc, smoke AppRun migrator + sha.
4. Host probe: path audit + launch without migrator abort.
5. Nested suite: S1/S2/S3/F1 (and N1) with stack packs.
6. Human download of the same AppImage for interactive confirm.

Do not claim upstream-ready on packaging green alone. Do not claim DnD green on unit alone.

## 5. Related files

- findings/appimage-packaging.md
- findings/nested-gui.md
- findings/manual-qa.md
- findings/test-matrix.md
- findings/ci-federation.md
- findings/budget-and-ops.md
- findings/build-kinks-log.md
- nested-gui/** , scripts/ci-verbose-gui-probe.sh , scripts/ci-smoke-appimage.sh
- .github/workflows/nested-gui-dnd.yml , gnome-web-dnd-fix-appimage.yml
