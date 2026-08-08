# Testing plan

## Build and test plan (automated where possible)

Goal: prove a future patch restores external file DnD without reopening CVE-2025-13947. Prefer automation EWS can run; document manual gaps honestly.

### Machine setup (reference upstream paths)

From ReadMe.md development path:

```
Tools/gtk/install-dependencies
Tools/Scripts/update-webkitgtk-libs
Tools/Scripts/build-webkit --gtk --debug
```

Production-shaped:

```
cmake -DPORT=GTK -DCMAKE_BUILD_TYPE=RelWithDebInfo -GNinja
ninja
```

Also keep a WPE build available if shared WebCore changes land:

```
Tools/wpe/install-dependencies
Tools/Scripts/update-webkitwpe-libs
Tools/Scripts/build-webkit --wpe --debug
```

Notes:

- Full WebKit GTK debug builds are heavy (CPU, disk, time). Use icecream/local cores if available; do not commit build artifacts.
- Two-depth clone may need more history/blobs when bisecting; for build we only need a complete work tree at the branch tip.
- Never install over system libwebkit by accident if it bricks the desktop session; prefer uninstalled MiniBrowser via `run-minibrowser --gtk` / Tools scripts with the build path.

Wiki reference: trac.webkit.org/wiki/BuildingGtk (linked from ReadMe).

### What to build for this work

- Target port: GTK (primary)
- Secondary compile check: WPE when `DataTransfer.h` / `SelectionData` / shared pasteboard change
- Config: debug for tests, RelWithDebInfo for manual perf sanity optional

### Automated tests to add or extend

LayoutTests / WebKitTestRunner:

- Existing drag-file tests under `LayoutTests/editing/pasteboard/` and `LayoutTests/fast/events/` are mostly written for Cocoa-style eventSender file drags. GTK EventSenderProxy is mouse-heavy; full OS file drag simulation may be missing or incomplete. Audit `Tools/WebKitTestRunner/gtk/EventSenderProxyGtk.cpp` before promising EWS coverage.
- Existing fingerprint of the mitigation: `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt` (and related) showing Files type / path expectations changed to FAIL. After a correct fix, update expectations only with a sentence in the commit message about why.

Security regression tests (must be automated if at all possible):

1. **Web-authored uri-list does not create File objects.** HTML test: on dragstart `setData('text/uri-list', 'file:///etc/passwd')` (or a temp path), drop onto a sink in-page, assert `dataTransfer.files.length === 0` and Files type absent or empty. If same-document drop is required, synthesize via internals if available.
2. **Plain text / non-file uri-list still works** for non-file DnD sites.
3. **Paste path policy explicit.** Either assert Files still hidden on paste if we keep that gate, or assert safe paste behavior if Idea 1 makes paste safe.

API tests:

- Cocoa has rich `TestWebKitAPI` DragAndDropSimulator helpers under Tools/TestWebKitAPI/Helpers/cocoa. GTK does not have a peer simulator of the same depth. Options:
 a. Add a focused GLib unit/API test around SelectionData: setURIList from web write vs setFilenames from trusted path.
 b. TestWebKitAPI GTK test that constructs pasteboard/drag data structures without full GDK drag.

(a) is the highest value per line of code and runs anywhere. Put business logic tests on SelectionData/Pasteboard where possible so EWS GTK/WPE both run them.

### Manual test matrix (MiniBrowser + GNOME Web against built lib)

Use a local build of MiniBrowser first, then system GNOME Web only if we can point it at the built WebKit (often hard on Fedora without prefix installs). Document exact binary path in the bug when claiming manual results.

Cases:

1. External file drop from Nautilus onto a page with a drop sink logging `event.dataTransfer.files[0].name` and size. Expect file present after fix; empty before fix.
2. Same with multiple files.
3. Directory drop: document actual behavior; do not silently expand scope.
4. Drag from page to page of attacker uri-list file://. Expect no File bytes.
5. Drag from page to Nautilus: no surprising file creation (Idea 4).
6. Click `<input type=file>` still works (non-regression).
7. Drag image from page within page (non-file) still works.
8. GTK4 Wayland portal session vs GTK3 X11 if both are realistic for reviewers.
9. WPE MiniBrowser only if WPE exposes a drop surface in our build; otherwise compile-only + unit tests.

Security non-regression checklist (manual or automated):

- Page cannot read `/etc/passwd` via crafted drag data
- Page cannot read a private file path it guessed under `$HOME`
- Drop of a real user-selected file still allowed

### Commands (expected once tree builds)

Style:

```
Tools/Scripts/check-webkit-style -f <touched files>
```

Layout tests (narrow):

```
Tools/Scripts/run-webkit-tests --gtk fast/events/drag-dataTransferItemList-file-handling.html editing/pasteboard/paste-image-does-not-reveal-file-url.html
```

(Adjust list once we know which tests are meaningful on GTK.)

API tests:

```
Tools/Scripts/run-api-tests --gtk <TestNameFilter>
```

Run-minibrowser:

```
Tools/Scripts/run-minibrowser --gtk
```

### EWS expectations

- PR will hit style bots and GTK (and maybe WPE) build/test queues.
- Red GTK EWS blocks credibility. Fix or mark tests correctly; do not ignore.
- We are not committers; no merge-queue self-serve. Reviewer handles land.

### CI we have vs do not have

Have (private repo Actions):

- Fedora 44 builder image with deps landmines preinstalled
- Shallow clone of fix branch, thin GTK build, `SelectionData.*` API tests
- Log artifacts + validation GitHub Releases (`validation-YYYYMMDD`)
- HTML harness under `html/` for manual MiniBrowser/GNOME Web checks

Still do not have:

- Private 271957 test suite access
- Official "drag from Nautilus" on upstream EWS
- So: unit-test the trust boundary hard; manual-test the OS integration; say so in the bug

### Definition of done for the future implementation phase

- Automated: web-originated file:// cannot populate `files()`
- Automated: trusted filename injection path can populate `files()` when `allowsFileAccess` is restored
- Manual: Nautilus → MiniBrowser drop works on the built GTK port
- Manual: attacker page drag does not yield file contents
- WPE: at least compiles; tests shared code
- Style clean; public Bugzilla filed; commit message complete
- Still zero references to personal app repos in WebKit-facing text

---


## Build and test tooling (current)

Tooling for Ideas 1-4 is no longer "install deps on a random laptop and hope."

- **Builder image:** Fedora 44 `WebKitGTK-DND-Fix-builder` / `ghcr.io/sirredbeard/webkitgtk-dnd-fix-builder:<YYYYMMDD>`
- **packages.txt** encodes the landmines we already hit once: `pcre2-devel` (not pcre-devel), `enchant2-devel`, `perl-bignum` (bigint.pm), `xdg-dbus-proxy`, ccache, mold/lld, gtk3/gtk4 stack, `-DUSE_LIBBACKTRACE=OFF`, `-DENABLE_API_TESTS=ON` / DEVELOPER_MODE
- **Workflows:** manual `Build deps container`, then manual `WebKitGTK DnD build and test`
- **Default CI target:** `TestWebCore` + `SelectionData.*` (thin cmake; MiniBrowser opt-in via dispatch inputs)
- **Caches:** ccache 2G + GHA/registry layer cache; GHCR keep 2 tags; Actions artifacts keep 5
- **Upstream still expects:** `check-webkit-style`, GTK/WPE EWS, gtk-wk2 when expectations change, MiniBrowser/GNOME Web manual matrix for real OS drops

Reference upstream build docs remain valid for anyone reproducing outside our CI: `Tools/gtk/install-dependencies`, `Tools/Scripts/update-webkitgtk-libs`, `Tools/Scripts/build-webkit --gtk`, and the WPE twins. Prefer matching our container flags when comparing results.


## Testing strategy (engine PR + this private repo)

WebKit norms for a security-adjacent behavior change: tests travel with the code. Prefer unit/API tests for the trust boundary. LayoutTests when web-visible behavior or platform expectations change. Style clean. EWS green or explained. Manual OS DnD is stated honestly because bots cannot drag from Files.

We need coverage that:

1. Each stacked commit stage still works in isolation and together
2. The security property holds (no content grant from web-authored file://)
3. Legitimate external file drops work again after the restore
4. We are not reintroducing CVE-2025-13947 or inventing a sibling hole (export, IsSource bypass, portal/uri-list confusion, paste regression)
5. Shared GTK/WPE code does not leave WPE uncompilable

Automate everything that does not need a real compositor and file manager. Put the rest on the GNOME Web AppImage + HTML harness.

### A. In-tree automated tests (what the WebKit PR commits)

#### Unit / API: TestWebKitAPI `SelectionData.*` (primary gate)

File on branch `gtk-dnd-file-access-reenable`:

- `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp`
- Listed in `PlatformGTK.cmake` and `PlatformWPE.cmake`

Binary: `TestWebCore`. Filter: `SelectionData.*`.

- `SetURIListDoesNotPromoteFilenames` - stage 1 / CVE non-regression core
- `SetURIListKeepsHttpURLWithoutFilenames` - no collateral damage to URL drags
- `TrustedSetFilenamesFromURIList` - stage 1 trusted grant still possible
- `ExplicitSetFilenames` - DropTarget-shaped grant
- `FilenamesFromURIListSkipsCommentsAndNonFiles` - parser hygiene
- `ClearFilenames` - state cleanup
- `URIListWithoutFilenamesStripsFileURLs` - stage 4 export sanitize
- `URIListWithoutFilenamesEmptyWhenOnlyFiles` - stage 4 edge
- `DragDataIsSourceDeniesFilenameAccess` - stage 4 IsSource deny

Still worth adding before or with the upstream PR (automated, headless):

- API-level check that non-Cocoa `allowsFileAccess` is true only for `forFileDrag()` after stage 2 (and false for plain drag / paste-shaped construction if we can build DragData without a full page)
- Round-trip: setURIList(file) + setFilenamesFromURIList only after trusted call; never via writeString path unit if we can call the same helpers Pasteboard uses
- Export: uriListWithoutFilenames never reintroduces a file path that DropTarget would treat as trusted without going through setFilenames*
- Regression: paste Files typing still gated on GTK until clipboard audit (expectation-aware)

How reviewers run:

```
ninja -C WebKitBuild/GTK TestWebCore
WebKitBuild/GTK/bin/TestWebCore --gtest_filter='SelectionData.*'
```

#### LayoutTests / expectation hygiene (regression)

- Mitigation fingerprint: `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt` from PR 54735. Revisit only with a why in the commit message.
- Security cousins (intent docs; Cocoa-heavy EventSender):
 - `LayoutTests/http/tests/security/dataTransfer-set-data-file-url.html`
 - `LayoutTests/http/tests/security/drag-drop-local-file.html`
 - `LayoutTests/http/tests/security/pasteboard-file-url.html`
 - `LayoutTests/http/tests/security/file-system-access-via-dataTransfer.html`
 - `LayoutTests/editing/pasteboard/drag-drop-href-as-url.html`
- Do not promise EWS "drag from Files." GTK EventSenderProxy is mouse-heavy.
- Before PR: `Tools/Scripts/check-webkit-style` on the touch set; narrow `run-webkit-tests --gtk` for any expectation we actually edit.

#### Security properties under test (map)

CVE-class (must stay closed):

- Web page setData/uri-list/file:// must not yield readable File bytes
- Web drag export must not hand another WebKit instance a trusted filename list from attacker paths
- Local in-app drag (IsSource) must not grant file contents via the filename channel

Restore-class (must stay open for users):

- External file manager drop may populate dataTransfer.files after stages 1-2
- Portal/GdkFileList preferred when present (stage 3); classic external uri-list still trusted on DropTarget only
- File picker / input type=file never part of the CVE; must keep working

Leak / new hole checks:

- No grant from parallel hostile uri-list when portal list is the real source (manual + code review; hard in unit tests)
- No paste regression that silently re-enables Files on GTK3 clipboard uri-list without audit
- WPE shares SelectionData tests so we do not ship a GTK-only ifdef maze that leaves WPE wrong

### B. Automated validation in this private repo (GitHub Actions)

Yes. CI is real and already runs automated validation.

Workflow **WebKitGTK DnD build and test** (`workflow_dispatch`):

1. Free disk; resolve date-tagged builder image
2. Parallel docker pull + shallow clone of the fix branch
3. ccache restore (2G)
4. **Build step** - `scripts/ci-build.sh` (thin GTK, `ninja TestWebCore`)
5. **Test step** - `scripts/ci-test-selectiondata.sh` (`SelectionData.*`)
6. ccache save (best effort)
7. Pack log bundle (best effort; never fails the job if files missing)
8. **Publish validation Release** on success (`validation-YYYYMMDD`) before artifact upload
9. Upload **all available** logs/artifacts with `if-no-files-found: warn` and `continue-on-error` so incomplete runs still leave evidence
10. Prune old artifacts (best effort)

What CI proves: clean Fedora 44 configure/link, SelectionData suite green, log trail + private Release.

What CI does not prove: Nautilus drop, live portal session, full LayoutTests/EWS, GNOME Web chrome.

Resilience rules:

- Never fail the pack/upload steps solely because a log from a later phase is missing
- Prefer uploading every path listed in the bundle plus loose `*.log` / `*.tail.log`
- Release before prune so a green run is not empty if storage cleanup hiccups

### C. Manual QA with GNOME Web AppImage + HTML harness

Automated unit tests cannot drag from Files. Manual matrix lives here.

#### HTML harness (`html/`)

- `index.html` - layer index
- `layer1-web-uri-list-no-files.html` - attacker uri-list; expect no file contents
- `layer2-external-drop-files.html` - external drop; expect files after fix
- `layer3-portal-notes.html` - portal / GdkFileList checklist
- `layer4-local-drag-and-export.html` - IsSource / export checks

#### GNOME Web AppImage

- Workflow: **GNOME Web DnD fix AppImage** (`.github/workflows/gnome-web-dnd-fix-appimage.yml`)
- Scripts: `ci-build-webkitgtk-prefix.sh` then `ci-build-gnome-web-appimage.sh`
- Binary name: `GNOME_Web-WebKitGTK-DnD-x86_64.AppImage` (unchanged)
- Release tag: `validation-YYYYMMDD-gnome-web`
- Bundles HTML harness when present for offline manual QA
- Target: Fedora 44+ x86_64. Private validation only. Not Flathub. Not the upstream PR vehicle.

##### Reusing a WebKitGTK build (yes)

Full WebKitGTK install is the expensive part. GNOME Web link + AppImage pack should not force a second engine compile when we already have a good prefix.

How:

1. `ci-build-webkitgtk-prefix.sh` installs into `PREFIX` and writes `webkitgtk-prefix-<sha>.tar.zst` plus a SHA stamp file
2. That tarball is uploaded as an Actions artifact from the AppImage workflow (and can be produced once per WebKit SHA)
3. Workflow input `webkit_prefix_artifact_run_id`: download that run's prefix tarball, extract to host PREFIX, set `SKIP_WEBKIT_BUILD=1`
4. `ci-build-gnome-web-appimage.sh` detects `webkitgtk-6.0` via pkg-config and **skips** engine rebuild
5. ccache still warms any compile that does run (GNOME Web is cheap next to WebKit)

Thin `TestWebCore` CI builds are **not** a drop-in install prefix (different cmake flags, no full install). Reuse is prefix-artifact to prefix-artifact, or same PREFIX directory inside one workflow after the prefix step. Do not expect the unit-test job's build tree to feed GNOME Web without an install step.

Manual matrix:

1. External file(s) from Files onto layer2 / upload UI → files populate
2. Layer1 attacker page → no file bytes
3. Layer4 local drag/export → no surprise grant; no file:// trusted export
4. File picker still works
5. Non-file page drags still work
6. Optional Wayland portal vs X11 classic uri-list

### D. PR testing checklist

- [ ] `SelectionData.*` green in private CI and locally
- [ ] Per-stage tests still map to commits 1-4 (or combined stack)
- [ ] CVE non-regression cases green (no filename promotion from web uri-list; IsSource deny; export sanitize)
- [ ] `check-webkit-style` clean on touch set
- [ ] LayoutTest expectations updated only with rationale
- [ ] WPE compiles shared tests
- [ ] One full manual pass on MiniBrowser or GNOME Web AppImage before review ask
- [ ] Bugzilla text separates automated vs manual proof
- [ ] Zero personal app product names in WebKit-facing tests or PR text


## Validation, CI, and validation releases

Former standalone FIX_VALIDATION.md content lives here. Automated proof is GitHub Actions. HTML under `html/` is manual desktop validation only. No checked-in results file.

### Four layers to prove

1. **Trust split** - web `setData('text/uri-list', 'file://...')` must not yield `dataTransfer.files` contents.
2. **allowsFileAccess restore** - external user file drop may yield files.
3. **Portal preference** - with portal/GdkFileList, filename grant comes from the portal list, not a parallel hostile uri-list.
4. **IsSource + export sanitize** - in-page file:// drag must not grant files; dragging out must not export file:// as a file offer.

Automated unit coverage for 1 and 4: `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp` via `TestWebCore --gtest_filter='SelectionData.*'`.

### Builder image (WebKitGTK-DND-Fix-builder)

- GHCR (lowercase required): `ghcr.io/sirredbeard/webkitgtk-dnd-fix-builder:<YYYYMMDD>`
- Base: **Fedora 44**
- `containers/Dockerfile` + `containers/packages.txt`
- Landmines encoded: `pcre2-devel`, `enchant2-devel`, `perl-bignum`, ccache, mold/lld, gtk3/gtk4 stack
- Also required at configure time when bubblewrap sandbox is on: `xdg-dbus-proxy` (and `bubblewrap`). First CI configure failed without it.
- No full `dnf upgrade` on every image build (layer cache + private minutes)
- Optional WPE packages best-effort
- CI scripts baked under `/opt/webkitgtk-dnd-fix/bin/`; workflows still mount `scripts/` so entrypoint fixes do not force an image rebuild
- After push: GHCR prune keep newest **2** date-tagged versions; Actions artifact prune keep **5**
- Registry buildcache tag used for Buildx layer cache

### Workflows (all manual `workflow_dispatch`)

1. **Build deps container** - free-disk, Buildx, GHA + registry `:buildcache`, push ghcr date tag, prune keep 2.
2. **WebKitGTK DnD build and test** - separate build/test steps, ccache 2G, `SelectionData.*`, pack logs best-effort, **publish `validation-YYYYMMDD` Release first**, then upload all available logs (warn if missing, never fail upload solely for gaps), prune keep 5.
3. **GNOME Web DnD fix AppImage** (`gnome-web-dnd-fix-appimage.yml`) - optional reuse of `webkitgtk-prefix-*.tar.zst` via `webkit_prefix_artifact_run_id`; else build prefix once, then GNOME Web + AppImage with `SKIP_WEBKIT_BUILD=1`. Release `validation-YYYYMMDD-gnome-web` before artifact upload. ccache on.

Private minutes are scarce: no push/PR auto-trigger on multi-hour compiles. Fail fast if the builder image is missing.


### Thin cmake defaults in `scripts/ci-build.sh`

```
-DDEVELOPER_MODE=ON
-DDEVELOPER_MODE_FATAL_WARNINGS=OFF
-DENABLE_API_TESTS=ON
-DENABLE_LAYOUT_TESTS=OFF
-DENABLE_MINIBROWSER=OFF
-DENABLE_DOCUMENTATION=OFF
-DENABLE_WEBDRIVER=OFF
-DENABLE_SPEECH_SYNTHESIS=OFF
-DENABLE_GAMEPAD=OFF
-DENABLE_PDFJS=OFF
-DENABLE_JOURNALD_LOG=OFF
-DUSE_LIBBACKTRACE=OFF
```

plus ccache launchers and mold (or lld). Override `ninja_targets` on dispatch when MiniBrowser validation is required.

### validation GitHub Releases

On successful unit build/test:

- Tag: `validation-YYYYMMDD` (UTC). If the tag exists that day, suffix `-<run_id>`.
- Name: `validation YYYY-MM-DD`
- Assets: CI log bundle, `selectiondata-tests.log`, `summary.log`, zip of `html/` harness
- Body: engine branch SHA, image ref, gtest filter, pass/fail
- Not a WebKitGTK redistribution and not an upstream release

### GNOME Web AppImage (Fedora 44+)

Goal: ship a runnable **GNOME Web** AppImage that embeds our patched WebKitGTK so humans can validation external file drop without a system WebKit install.

Plan:

1. Builder image gains Epiphany build deps (libadwaita, gcr, libportal, meson, desktop-file-utils, appstream) plus AppImage tooling fetch (linuxdeploy, linuxdeploy-plugin-gtk, appimagetool).
2. Separate expensive workflow `validation Epiphany AppImage` (`workflow_dispatch` only). Does not run on every unit-test dispatch. Private minutes.
3. Inside the builder container:
 - Shallow clone `sirredbeard/WebKit@gtk-dnd-file-access-reenable`
 - Configure GTK port **installable** Release build (`CMAKE_INSTALL_PREFIX=/opt/webkitgtk-dnd`, API tests optional off for speed, MiniBrowser optional on as fallback shell)
 - `ninja install` WebKitGTK into the prefix (full libraries, not TestWebCore-only)
 - Shallow clone GNOME Web sources from GNOME (`https://gitlab.gnome.org/GNOME/epiphany.git`, default branch)
 - Meson/ninja GNOME Web with `PKG_CONFIG_PATH` / `LDFLAGS` pointed at the prefix so it links `webkitgtk-6.0` from us
 - Stage AppDir: GNOME Web + prefix libs + critical GStreamer/GTK stack via linuxdeploy + gtk plugin
 - `AppRun` sets `LD_LIBRARY_PATH` / `WEBKIT_*` as needed and execs the `epiphany` binary
 - `appimagetool` → `GNOME_Web-WebKitGTK-DnD-x86_64.AppImage` (name may include date)
4. Publish on a validation Release (same day tag or `validation-YYYYMMDD-epiphany` if unit release already exists): attach the AppImage + short SHA notes. Keep retention honest; AppImages are large, prune old epiphany assets when storage hurts.
5. Target runtime: **Fedora 44+** x86_64 (latest stable Fedora). Host rawhide/F45 is for agent tooling only. Builder image and AppImage pack are Fedora 44.
6. **glibc floor:** AppImage links against builder glibc (F44 measured **2.43**). Older hosts fail with `GLIBC_x.y not found`. That is the usual cross-distro AppImage limit; document it on every validation Release. Not a Flatpak. Not for Flathub. Private validation only.
6. Manual check with the AppImage: open `html/` layer pages (or any https upload UI), drag a real file from Files into the page, confirm `files` populate; run the web uri-list attack page and confirm no contents.

Hard constraints:

- Still never name personal app products in AppImage metadata aimed at WebKit reviewers
- AppImage is **not** the upstream PR vehicle. Upstream stays MiniBrowser + SelectionData tests + Bugzilla
- Full WebKit install is multi-hour. Keep it dispatch-only and concurrency-grouped so it cannot stack with itself
- If disk dies on the runner, free-disk + build in `/mnt` or trim GStreamer plugins to a workable set

Script entrypoint: `scripts/ci-build-gnome-web-appimage.sh`. Workflow: `.github/workflows/validation-gnome-web-appimage.yml`.

### Manual HTML harness

```
Tools/Scripts/run-minibrowser --gtk file://$PWD/html/index.html
```

Or Epiphany against a prefix-built WebKitGTK when available. Prefer noting outcomes on the GitHub Release.

### Scripts in this repo

- `scripts/ci-build.sh` + `scripts/ci-test-selectiondata.sh` - separate build/test; `ci-build-and-test.sh` wrapper
- `scripts/ci-build-gnome-web-appimage.sh` - full WebKitGTK install + GNOME Web + AppImage pack
- `scripts/run-api-selectiondata.sh` - wrapper when a build tree exists
- `scripts/print-layer-checklist.sh`
- `scripts/sync-container-scripts.sh` - copy entrypoints into `containers/` for image bake
- `scripts/prune-ghcr-container.sh`
- `scripts/prune-actions-artifacts.sh`




## Gate order after Opus synthesis

1. SelectionData unit tests green on real branch tip (not main).
2. External validation parses PASSED lines for all required cases.
3. IPC / filenames serialization fix landed and tested.
4. Prefix + GNOME Web AppImage builds and runs.
5. Manual host HTML layers (human sign-off).
6. Optional Azure nested Fedora GUI suite (after 1-4 green).

Do not start nested GUI as a gate until 1-4 look good.


## Local lint and test parity with upstream

What WebKit actually gates (EWS):

- **style** queue: `python3 Tools/Scripts/check-webkit-style` (flunk on failure)
- **gtk** build: `build-webkit --gtk` / ninja compile
- **gtk-wk2** / layout tests when expectations change
- **API tests** via `run-gtk-tests` / TestWebCore for TestWebKitAPI sources
- No default pre-commit style hook; no clang-tidy gate for GTK; IWYU filter off in style

What we run:

- Private CI: actionlint on workflow commits; unit job builds TestWebCore + `SelectionData.*` + external validation
- Local: `scripts/lint-local.sh` (actionlint + shellcheck -S error + check-webkit-style on the DnD touch set with python3.12)
- Still must compile and run SelectionData tests (style does not replace gtk build)


## Parser must match TestWebKitAPI markers

When grepping SelectionData results, match `**PASS** Name` and `**FAIL** Name` first. Stock gtest `[  PASSED  ]` is optional compatibility only. External validation REQUIRED_TESTS must include `SelectionData.IpcConstructorPreservesFilenamesWithoutURIListPromotion` after the IPC serialization fix.
