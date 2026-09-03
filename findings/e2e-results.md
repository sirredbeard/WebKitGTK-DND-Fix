# Nested E2E results (private CI)

## Host AppImage render proof

- Run: GitHub Actions `31252342415` (commit `2087615` pack fix)
- Binary: `~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage`
- sha256: `89894c5b21fcddf9bd4a32037a56043d76982572bf8ef08b8b96e36b36a28d51`
- Engine tip embedded: `2b70a3d087fe`
- Host proof: `AppRun --profile=... 'https://example.com/'` → session_state title **Example Domain**
- Extension reloc + sandbox-off verified in extract; no host GVariant abort

## Nested product + security green (20260809T174813Z)

Guest suite: AppImage above + golden Fedora 44 + Xvfb/openbox + **Nautilus**.

auto_rc=0 status=ok canary_leaked=False

Beacons (`dnd-beacons.jsonl`):

- S1 PASS — web-authored file:// uri-list does not become File objects (CVE class)
- S2 PASS — local/IsSource deny
- F1 PASS — Nautilus multi-select external drop → File objects for
  `sample-drop.txt`, `sample.png`, `sample.html`
  (HTTP: `/_dnd_result/F1/PASS?names=sample-drop.txt,sample.html,sample.png`)
- S3 PASS — no passwd-named export into Nautilus watch dir
- N1 INCONCLUSIVE — file chooser portal still not automated (soft)

Screenshot proof: `findings/screenshots/f1-nautilus-multi-PASS.png` shows RESULT:PASS files=3 and
on-page log of all three types; Nautilus left with 3 items selected.

### F1 automation lessons (Nautilus-only path)

- Never `subprocess.run(nautilus, timeout=…)` — timeout kills the FM. Use Popen.
- Fixtures on guest **local disk** (`~/f1-fixtures`), not 9p.
- Tile Nautilus left / Epiphany right; list view; Ctrl+A multi-select required types only.
- Hit the file **name** row (~y=125), not mid-window (mid-window = rubber-band, not drag).
- Cross-window XDND needs threshold jiggle + dwell on green box before mouseup.
- After a successful drop, do **not** type paths without focusing Nautilus first —
  keys otherwise go to Epiphany and navigate to `file:///…`, wiping the fixture page.
- Force remount of 9p when golden left a stale empty `/mnt/dndin`.

Gate: product bar is now **S1+S2+S3+F1 PASS**. N1 remains soft.

Artifacts: `/home/fedora/webkit-dnd-cache/nested/out/20260809T174813Z/`

## Earlier nested security-only (20260808T110953Z)

S1/S2/S3 PASS; F1 was still INCONCLUSIVE (Nautilus automation gaps above).

## Azure golden

rsync of local `fedora-44-ws-dnd-golden.qcow2` (+ .ok/.stamp + cloud base) to
`azure-webkit-dnd:/var/cache/webkit-dnd/nested/` complete (2.1G golden present).

## Private CI commits (pack + nested)

- `2087615` AppImage render/extension/sandbox
- `cebb78f` findings proof
- `2111f7e` nested env/profile/title wait
- `2408bbd` warm extract
- `a3514c4` result beacons
- `3638d38` Nautilus multi-type F1 + hard gate S1–S3+F1

## Host AppImage Wayland backend

Engine DnD OK on Xvfb (PROBE:PASS:3). Host fail was GDK_BACKEND=x11 vs Wayland Nautilus. AppRun prefers Wayland on Wayland hosts (7cb19e7). Use extracted run-host-wayland.sh until AppImage rebuild.

## Multi-file drop crash fix (engine ae64af0353)

Host multi-file drop aborted Epiphany: gdk_drop_finish got action mask not unique action. DropTargetGtk4 now finishes with dragOperationToSingleGdkDragAction. Prefix rebuild run 31332277598 in flight; AppImage after prefix green.

## drop_finish AppImage verify

Run 31332830900 engine ae64af0353. Xvfb multi-file drop PASS under G_DEBUG=fatal-criticals; process stayed up. Downloads binary sha256 52cc1b4c…70346.

## host dogfood copilot

Nautilus multi-file drop onto copilot.microsoft.com with AppImage 31332830900 (ae64af0353): Copilot recognized attachments, no crash. Wayland session, fixtures under webkit-dnd-cache/appimage-copilot-dnd/fixtures.

## flatpak without runtime rebuild

Yes: app-bundle or override patched WebKit on stock org.gnome.Platform//50. Full Platform rebuild not required for Copilot DnD validation.

## gnome web flatpak + dual backend e2e

Added Flathub-style org.gnome.Epiphany.WebKitDnD Flatpak with slipstreamed WebKit prefix; CI publishes .flatpak next to AppImage. Nested suite matrix: appimage|flatpak x x11|wayland with full S1-S3/F1 bar per cell.

## Stale AppImage on Flatpak-only releases

Release notes for 31345746885 claimed webkit ae64af and shipped an AppImage,
but the AppImage embedded usr/.webkitgtk-dnd-sha was still d5bec (Aug 8).
Self-hosted OUT kept the old binary; Flatpak-only jobs re-uploaded it.

Fix: clear OUT AppImages when build_appimage=false; publish AppImage only if
this run's build step succeeded; refuse publish when embedded sha != tip pin.

## unit SelectionData tip (run 31347639203)

tests_only=false rebuild TestWebCore on ae64af branch. All 13 SelectionData.* PASS including PortalFilenamesNotWidenedByHostileURIList, UriListWithoutFilenamesKeepsHttpOnly, TrustedDropShapeAfterIpcRoundTrip. External validation fail=0. Earlier tests_only runs only had 10 cases from stale binary.

URL: https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31347639203

## Nested matrix 31349215350 (DISPLAY-fixed host path, still multi-cell footgun)

Packages tip ae64af. Units 13/13 SelectionData already green on tests_only=false.

Cell results (from guest-printed results.json; host tar pull did not land files this run):

- appimage-x11: S1 PASS, S2 PASS, S3 PASS, F1 PASS, N1 INCONCLUSIVE (file chooser portal / dogtail). Product bar green. canary_leaked false.
- appimage-wayland: all INCONCLUSIVE — epiphany failed to show window. Session left DISPLAY=:99 pointing at Xvfb killed by prior cell stop. Wayland headless + xdotool cannot see pure Wayland surfaces either.
- flatpak-x11: all INCONCLUSIVE — Gtk "Failed to open display" / import "unable to open X server :99". Same dead DISPLAY after session_backend_stop killed Xvfb but left DISPLAY exported.
- flatpak-wayland: same class of failure.

Root cause: session_backend_stop killed Xvfb/weston pids but did not unset DISPLAY. session_backend_start x11 only starts Xvfb when DISPLAY is empty, so cell 2+ reused a dead :99.

Also: host pull of /home/dnd/dnd-out was silent-failure (no results.json on OUT_HOST); suite log still had the full JSON dump. Fixed pull to log errors and fall back to parsing ssh-suite.log.

Fix landed in scripts/session-backend-start.sh + guest fallback: stop clears DISPLAY/WAYLAND; start always (re)starts Xvfb and checks xdpyinfo; wayland lane defaults to GDK_BACKEND=x11 for xdotool; flatpak run gets explicit --socket=x11 and --env=DISPLAY.

## Nested matrix 31350857266 — full dual package × dual backend green

After DISPLAY lifecycle fix (08de52b):

- appimage-x11: S1/S2/S3/F1 PASS (N1 soft portal)
- appimage-wayland: S1/S2/S3/F1 PASS (GDK x11 automation on live Xvfb + weston)
- flatpak-x11: S1/S2/S3/F1 PASS — stock-shaped GNOME Web Flatpak with slipstreamed tip WebKit
- flatpak-wayland: S1/S2/S3/F1 PASS
- matrix auto_rc=0, canary_leaked false, status ok
- Enforce maintainer success bar: success
- Job conclusion failure was only Stage slim debug pack: find|head SIGPIPE under pipefail. Cosmetic; fixed.

This is the overnight bar: tip packages, nested GUI proof both AppImage and Flathub-shaped Flatpak, CVE cases S1-S3 not FAIL, F1 external Nautilus multi-type PASS, no canary leak.

## Nested matrix 31351799703 — confirmation job green

Same tip packages 31346489622. Workflow conclusion success after slim-pack pipefail fix (0ed6870).

matrix_rc=0 canary_leaked false
- appimage-x11 / wayland: S1 S2 S3 F1 PASS, N1 INCONCLUSIVE (portal)
- flatpak-x11 / wayland: S1 S2 S3 F1 PASS, N1 INCONCLUSIVE (portal)

Authoritative private-CI proof for overnight bar:
- packages: https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31346489622
- units: https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31347639203
- nested: https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31351799703
- engine: sirredbeard/WebKit gtk-dnd-file-access-reenable @ ae64af0353

Wayland cells: automation uses live Xvfb + GDK_BACKEND=x11 so xdotool can drive surfaces; weston still up. Not a pure Wayland input path. N1 remains soft under headless portals.

## Correction: nested run 31359848716 N1 "PASS" was not a file-chooser pass

31359848716 reported N1 PASS in all four cells after the harness gained an
external-drop fallback: when xdotool could not find the GTK file chooser it
dragged a host file onto layer5 instead, and layer5's drop handler fires the
same `/_dnd_result/N1/PASS` beacon (with `how=drop`). That is the S2 path, so
the run proved external drop twice and proved nothing about `<input type=file>`.
The honest reading of every nested run to date is the one recorded above:
**N1 INCONCLUSIVE**.

Fixed in `Nested: make N1 prove the file chooser, not the drop path`:

- the drop fallback is off unless `N1_ALLOW_DROP_FALLBACK=1`;
- the verdict is taken from layer5's own `how` field — `change` (chooser) counts,
  `drop` is recorded INCONCLUSIVE;
- the maintainer bar independently rejects an N1 PASS whose `how` is not
  `change`/`chooser`/`atspi`, so the gate does not rely on the harness alone;
- the chooser is now opened by keyboard first (layer5 autofocuses its only
  focusable element, so click dead space → Tab → space), with the old blind
  pixel-fraction clicking demoted to a fallback, and the portal chooser window
  classes are matched for the flatpak cells.

## Port compile coverage (new)

`scripts/ci-build.sh` only ever configured `-DPORT=GTK` with the default
`USE_GTK4=ON`, and only built `TestWebCore`, which links WebCore. So neither
`DropTargetGtk3.cpp` nor any `PLATFORM(WPE)` configuration had ever been
compiled by CI, despite four commits tagged `[GTK][WPE]`.

`WEBKIT_CONFIG=gtk4|gtk3|wpe` now selects port and `USE_GTK4`, each with its own
build dir and ccache, and `.github/workflows/port-compile-matrix.yml` runs the
gtk3 and wpe lanes over `TestWebCore WebKit` so the UIProcess drop targets are
really compiled. Each lane asserts afterwards that the expected
`DropTarget*.cpp.o` exists and the other port's does not, so a mis-configured
lane cannot pass by building GTK4 twice.

`ci-external-validation.sh` is config-aware: GTK lanes require the nine
`DropTargetState.*` cases (PlatformGTK.cmake only), all lanes require the
eighteen `SelectionData.*` cases including the five new `TrustedDrop*` ones.

### Port compile matrix results

Engine `sirredbeard/WebKit gtk-dnd-file-access-reenable @ 9d2732f8c1`.

| lane | run | evidence |
| --- | --- | --- |
| gtk4 units | [31395989712](https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31395989712) | 27/27 `**PASS**`, external validation `fail=0` |
| gtk3 build + units | [31400164838](https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31400164838) | `DropTargetGtk3.cpp.o=45056` vs `DropTargetGtk4.cpp.o=1432`, `USE_GTK4=OFF`, 27/27 `**PASS**`, `fail=0` |
| wpe build + units | [31400910574](https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31400910574) | `webkit_port=WPE`, no `DropTargetGtk*.cpp.o`, 18/18 `**PASS**`, `fail=0` |

Two build-environment fixes were needed before the WPE lane could configure at
all, and both are recorded because they are properties of the image, not of the
patch: the builder image has no usable `libwpe`/`wpebackend-fdo`, so the lane
uses `-DENABLE_WPE_LEGACY_API=OFF` with WPEPlatform headless; and
`ENABLE_WPE_QT_API` defaults to `ENABLE_DEVELOPER_MODE`, which pulled in a
`find_package(Qt6 REQUIRED)` the image cannot satisfy, so the lane sets
`-DENABLE_WPE_QT_API=OFF -DENABLE_COG=OFF`.

The object-size assertion, not an object-presence assertion, is the correct
check: `SourcesGTK.txt` lists `DropTargetGtk3.cpp` and `DropTargetGtk4.cpp`
unconditionally with `@no-unify`, and each file wraps its whole body in
`#if ENABLE(DRAG_SUPPORT) && [!]USE(GTK4)`, so both `.cpp.o` files exist in
every GTK build and only the configured one has content.

## Resolution: N1 now proves the file chooser

N1 had never produced a genuine `how=change` pass. Three separate harness bugs
hid one environment bug; each was found only after the run artifacts were made
to survive a failing suite.

1. **The harness could not see the chooser.** Detection rejected any window
   whose class looked like Epiphany, but under GTK4 an in-process
   `gtk_file_chooser_native_new()` dialog is an ordinary application toplevel
   and carries the application's own `WM_CLASS`. Detection also matched only the
   title `Select Files`, while `WebKitWebViewGtk.cpp:115` titles a single-file
   chooser `Select File`. Fixed by identifying the chooser as a toplevel that
   did not exist before the request, keyed by window id.
2. **The harness closed the chooser while opening it.** The open phase pressed
   `Return` 0.6 s after `space`; run 31410600059 shows the Epiphany log adding
   the `response.activate` action (the chooser really was built) and the blind
   `Return` immediately activating the default response. Fixed by never pressing
   `Return` while opening, and by raising the detection window to
   `CHOOSER_OPEN_TIMEOUT` (12 s) for a cold dialog under Xvfb.
3. **The gate and the log pull failed open.** The suite step ran under
   `pipefail` and aborted before copying `results.json`; the bar then printed
   `warn: no nested results.json` and exited 0. `run-guest-suite.sh` likewise
   died before pulling `/home/dnd/dnd-out`. Fixed in
   `scripts/nested-maintainer-bar.py` (missing/unreadable results is a failure)
   and by capturing the rc around the ssh pipeline.

The real cause was environmental, and only visible once the logs were being
collected. Run 31412442483 shows **17** `org.freedesktop.portal.FileChooser`
`OpenFile` calls — every click did open a chooser — each answered with:

    Backend call failed: Could not activate remote peer
    'org.freedesktop.impl.portal.desktop.gnome': startup job failed

`XDG_CURRENT_DESKTOP=GNOME` made the portal frontend select the gnome backend,
which needs a GNOME session. The gtk backend was started, but before Xvfb, so it
exited at once with `cannot open display` and never claimed the bus name. So the
chooser was requested, never rendered, and nothing was on screen to drive.

`stack-trace-env.sh` now writes a `portals.conf` pinning
`org.freedesktop.impl.portal.FileChooser=gtk` before the frontend starts, and
`portal_backend_start` (re)starts the gtk backend per cell once `DISPLAY` is
live — D-Bus activation cannot do this, because the activation environment has
no `DISPLAY`.

Result, nested run
[31414509123](https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31414509123)
(appimage/x11, `fail_on_suite=true`), the first genuine N1 pass:

    N1: chooser opened after key space (class=Xdg-desktop-portal-gtk)
    N1: driving chooser window 8388611 (class=Xdg-desktop-portal-gtk)
    CASE N1=PASS ... 'chooser_driven': True, 'how': 'change'

S1, S2, S3, F1 and N1 all PASS, `canary_leaked=False`, and the maintainer bar
passed with N1 held to `how=change`. N1 is no longer a soft cell.

### Full nested matrix, all cells green

Nested run
[31415929043](https://github.com/sirredbeard/WebKitGTK-DND-Fix/actions/runs/31415929043)
— `fail_on_suite=true`, AppImage from 31399106610, Flatpak bundle from
31402215302 — is the first run in which every cell passes every case:

| cell | S1 | S2 | S3 | F1 | N1 |
| --- | --- | --- | --- | --- | --- |
| appimage-x11 | PASS | PASS | PASS | PASS | PASS (`how=change`) |
| appimage-wayland | PASS | PASS | PASS | PASS | PASS (`how=change`) |
| flatpak-x11 | PASS | PASS | PASS | PASS | PASS (`how=change`) |
| flatpak-wayland | PASS | PASS | PASS | PASS | PASS (`how=change`) |

`canary_leaked=False`, every `cell_rc=0`, and each cell logs
`chooser opened after key space (class=Xdg-desktop-portal-gtk)`, so the pass is
the file-chooser path in a separate process, not the drop path. The flatpak
cells were expected to stay INCONCLUSIVE because the portal is mandatory inside
the sandbox; pinning the gtk backend fixed them too, which confirms the failure
was always the portal backend and never the sandbox.
