# GNOME Web Flatpak with slipstreamed WebKitGTK

Private validation only. Not Flathub. Not Copilot Desktop.

## Upstream model

Flathub `org.gnome.Epiphany` on `org.gnome.Platform//50` does **not** build WebKit. WebKit comes from the runtime. Modules: elementary icons/stylesheet, granite, libportal, epiphany 50.x.

GNOME upstream Canary (`org.gnome.Epiphany.Canary`) is the first-party pattern for a custom engine: build or install WebKit into `/app`, launch via wrapper setting `WEBKIT_EXEC_PATH` and `WEBKIT_INJECTED_BUNDLE_PATH`.

## Our recipe

- Manifest: `flatpak/org.gnome.Epiphany.WebKitDnD.yml`
- App-id: `org.gnome.Epiphany.WebKitDnD` branch `dnd-fix`
- Module `webkitgtk`: **cmake-ninja build of sirredbeard/WebKit `gtk-dnd-file-access-reenable` inside org.gnome.Sdk//50** (Canary pattern)
- granite + libportal + epiphany 50.4 like Flathub (elementary icons dropped from the default manifest to save time; not required for DnD)
- Wrapper `epiphany-dnd`: Canary-style `WEBKIT_EXEC_PATH` / `WEBKIT_INJECTED_BUNDLE_PATH` + same GDK backend policy as AppImage AppRun
- Bundle: `GNOME_Web-WebKitGTK-DnD.flatpak`

### Why not copy the Fedora prefix into /app?

Platform 50 ships **glibc 2.42**. Our AppImage/prefix WebKit is built on Fedora 44/45 against **glibc 2.43** (`asinf@GLIBC_2.43` etc.). Linking or loading that `.so` inside the Flatpak fails. In-SDK WebKit build matches runtime libc.

`scripts/stage-webkit-flatpak-prefix.sh` remains for experiments on matching-libc hosts only.

Build: `scripts/ci-build-gnome-web-flatpak.sh` (long: full WebKit). Wired into `gnome-web-dnd-fix-appimage.yml` so release artifacts include AppImage **and** Flatpak.

## E2E matrix

Nested guest suite runs package × session backend:

- packages: `appimage`, `flatpak` (when bundle staged)
- backends: `x11` (Xvfb + openbox + WEBKIT_DND_FORCE_X11), `wayland` (weston headless, unset GDK_BACKEND)

Same cases S1 S2 S3 F1 (N1 soft) per cell. Results in `results.json` under `cells` / `cases_matrix`.

## Install (manual)

```
flatpak install --user GNOME_Web-WebKitGTK-DnD.flatpak
flatpak run org.gnome.Epiphany.WebKitDnD
```

## Build environment (consistent with AppImage)

Flatpak builds run in the **same Fedora 44** `webkitgtk-dnd-fix-builder` container as prefix/AppImage. Never `apt install flatpak` on the Ubuntu Azure host — that path failed CI (`flatpak: command not found`).

Container needs: `flatpak`, `flatpak-builder`, `ostree`, `python3-pyparsing` (packages-webkit.txt). Docker run uses `--privileged` + `/dev/fuse` for nested bwrap.

## Last-good in-SDK WebKit (AppImage prefix parallel)

Fedora host prefix cannot be slipstreamed (glibc 2.43 vs Platform 50 / 2.42). Instead we cache the **Sdk//50** WebKit install tree:

- Tarball: `webkitgtk-flatpak-sdk50-<sha12>.tar.zst` (+ `.sha` sidecar, stamp file inside)
- Cache dirs: `/var/cache/webkit-dnd/flatpak-webkit/`, `flatpak-builder-state/`, `flatpak-user/`
- Seed: `scripts/seed-flatpak-webkit-from-last-good.sh` (SHA-pinned like prefix seed)
- Build: `scripts/ci-build-gnome-web-flatpak.sh`
  - phase1: `flatpak-builder --stop-at=epiphany` (libportal+granite+webkit), pack last-good
  - phase2: assemble epiphany+wrapper from prebuilt tarball (fast packaging debug)
  - On seed hit: skip phase1 entirely — no WebKit compile
- Input: `force_rebuild_flatpak_webkit` on the AppImage workflow
- Prefer `WEBKIT_SRC_DIR` / clone as `type: dir` (no multi-GB git fetch inside builder)

Artifacts: `webkitgtk-flatpak-sdk50-*` + bundle on the release next to the AppImage.

## Independent AppImage vs Flatpak lanes

Workflow inputs (default both true):

- `build_appimage` — Fedora prefix + AppImage only
- `build_flatpak` — in-SDK WebKit Flatpak only (does not need the Fedora prefix)
- Both share the same WebKit clone/SHA pin when run together
- Flatpak runs with `always() && !cancelled()` so an AppImage failure does not skip Flatpak
- Rebuild only Flatpak packaging: `build_appimage=false`, `build_flatpak=true`, leave force_rebuild_flatpak_webkit=false to reuse last-good sdk50 tarball
- Rebuild only AppImage: opposite flags; prefix last-good still applies

## CI footgun: flatpak as root

Docker default user is root. `flatpak install --user` then fails with
`Refusing to operate on a user installation as root`.

Fix: run the Flatpak container as `--user $(id -u):$(id -g)` with
`HOME`/`FLATPAK_USER_DIR` on `/var/cache/webkit-dnd/…`. Script falls back to
system install under `$CACHE/flatpak-system` only if still root.

## granite needs sassc

CI failed on granite meson: `Program 'sassc' not found`. Flathub builds libsass+sassc
(under elementary-stylesheet) before granite. We ship standalone libsass+sassc modules
(cleanup: '*') before granite in the manifest and prebuilt assembler.

## Upstream alignment (WebKit / WebKitGTK / GNOME Web)

Flathub `org.gnome.Epiphany` (Platform//50): **no WebKit module**. Engine is the
runtime's WebKit. Modules: elementary icons/stylesheet (+ nested libsass/sassc),
granite, libportal, epiphany. Finish-args are the short set (dri, xdg-download,
ipc, network, fallback-x11, pulse, wayland). We mirror modules + sockets; we add
portal talk-names and xdg docs/pictures for DnD QA.

GNOME Web **Canary** (Igalia / base-art, 2021+): does **not** compile WebKit
inside `org.gnome.Sdk`. WebKit Buildbot builds with the **WebKit Flatpak SDK**;
Canary CI installs those artifacts into a sandbox on the WebKit SDK runtime and
wraps Epiphany (`WEBKIT_EXEC_PATH` / injected bundle). Nightly.gnome.org +
`webkit-sdk.flatpakrepo`. Different runtime ABI story than shipping on GNOME 50.

Upstream **build-webkit** (Tools/Scripts/webkitdirs.pm): always
`-DPORT=…` and **`-DDEVELOPER_MODE=ON`** for cmake ports. GTK OptionsGTK.cmake:
when `DEVELOPER_MODE`, sets **`CMAKE_DISABLE_PRECOMPILE_HEADERS ON`**.

Fedora rawhide `webkitgtk.spec`: `-DPORT=GTK -DCMAKE_BUILD_TYPE=Release
-DUSE_GTK4=ON -DUSE_LIBBACKTRACE=OFF` (and docs toggle). No DEVELOPER_MODE line
(default OFF). Arch similar. Distro builds are release tarballs + system toolchain.

Our **AppImage prefix** script: DEVELOPER_MODE=ON, FATAL_WARNINGS=OFF, tests off —
same shape as build-webkit, proven green.

Our **Flatpak** must compile WebKit **inside org.gnome.Sdk//50** so glibc matches
Platform 50 (Fedora prefix is 2.43+ and cannot load). That is intentional drift
from Canary's prebuilt-artifact model, but cmake flags should still track
Fedora + our prefix.

## GraphicsTypesGL.h miss (WebKit PCH + private-header symlinks)

Runs **31338874103** (and same path if ICE hadn't stopped 31337055281 earlier):

```
GStreamerCommon.h:39:10: fatal error: GraphicsTypesGL.h: No such file or directory
```
at WebKit `cmake_pch.hxx.gch` (~8550/8924), after WebCore finished.

Facts on the Azure state-dir (`webkitgtk-2`):

- `GraphicsTypesGL.h` **exists** under
  `_flatpak_build/WebCore/PrivateHeaders/WebCore/` as a **symlink** to
  `Source/WebCore/platform/graphics/GraphicsTypesGL.h`
- `GStreamerCommon.h` likewise → `…/platform/graphics/gstreamer/GStreamerCommon.h`
- Upstream stages private headers with **`WEBKIT_SYMLINK_FILES`** (flattened), not copy
  (`Source/WebCore/CMakeLists.txt` → `WebCore_CopyPrivateHeaders`)
- WebKit PCH includes only `-I…/WebCore/PrivateHeaders` (parent), not
  `…/PrivateHeaders/WebCore` and not `Source/WebCore/platform/graphics`
- Include chain: `WebKitPrefix` → `<WebCore/SharedBuffer.h>` →
  `#include "GStreamerCommon.h"` (USE(GSTREAMER)) →
  `#include "GraphicsTypesGL.h"` (USE(GSTREAMER_GL))
- GCC diagnostics show the **realpath** under `…/gstreamer/` for
  GStreamerCommon.h; quote-include then searches that directory first, so
  sibling `GraphicsTypesGL.h` in PrivateHeaders is not seen

Why AppImage/prefix never hit this:

- Prefix uses **`DEVELOPER_MODE=ON`** → OptionsGTK disables **PCH**
- Flatpak had **`DEVELOPER_MODE=OFF`** → PCH on → WebKit PCH fails

Fix: set Flatpak cmake to **`DEVELOPER_MODE=ON`** + `DEVELOPER_MODE_FATAL_WARNINGS=OFF`
and keep API/layout tests off (same as prefix). Equivalent minimal fix is
`-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON` alone; DEVELOPER_MODE matches
build-webkit + our green prefix.

Also confirmed `USE_GSTREAMER_GL=ON`, `ENABLE_WEBGL=ON` in cache (defaults).
Not a missing Sdk GL package for this particular error (header path, not
pkg-config).

## Other gaps vs upstream (checklist)

- Canary runtime = WebKit SDK; we stay on org.gnome.Platform//50 for user install
  next to normal GNOME Web (correct for validation dogfood).
- Flathub finish-args lack our portal talk-names / extra xdg mounts — keep ours for DnD.
- We skip elementary-icons (time); granite still needs sassc (we ship libsass+sassc).
- Bubblewrap sandbox OFF inside Flatpak (nested bwrap pain); OK for private app-id.
- JOBS capped at 12 (ICE at 16 on Sdk gcc); Fedora uses memory-weighted `%limit_build`.

## Sdk gcc ICE at high -j (run 31337055281)

In-SDK WebKit got to WebCore ~8210/8924 then:

`ScrollAnimationMomentum.cpp: internal compiler error: in expand_debug_locations, at cfgexpand.cc:6042`

Not the OOM killer (62 GiB free after fail, no swap). Sdk gcc + large unified TUs +
flatpak-builder `--jobs=$(nproc)` (=16) is enough to trip the ICE.

Mitigations now in tree:

- Cap Flatpak WebKit `JOBS=12` in the workflow (script default also caps at 12; was 8 first retry after ICE at 16)
- webkitgtk `build-options` `cflags`/`cxxflags`: `-g1 -fno-var-tracking-assignments`
- phase1 retry once at half jobs; state-dir + `--keep-build-dirs` resumes ninja objects
- Do not wipe `flatpak-builder-state` on retry

After green, last-good `webkitgtk-flatpak-sdk50-<sha>.tar.zst` makes packaging-only
rebuilds skip this compile entirely.

## Runner pool (any default)

Package workflow runner_label default is **any** (not azure). Labels for any are only self-hosted,linux,x64,webkit-dnd so the first free peer takes the job. Azure wake when any is a parallel non-blocking job; build does not wait on it. Pin azure|vultr only when needed.

Azure run on old SHA that hits GraphicsTypesGL continues because phase1 retries once at half jobs (ICE dodge). Same PCH miss will fail the second attempt — not a silent pass.

### Unifdef miss (Vultr 31341325458 @ 7a63920)

After DEVELOPER_MODE=ON, cmake failed immediately: Could NOT find Unifdef. org.gnome.Sdk//50 has no unifdef binary; Fedora prefix image installs unifdef from packages-core. GTK default USE_SYSTEM_UNIFDEF=ON. Fix: -DUSE_SYSTEM_UNIFDEF=OFF (bundled ThirdParty/unifdef). Azure 8148dd9 got past cmake via older module hash / state before this config change.

## Focus
Flatpak-only right now (in-SDK WebKit). No separate Fedora WebKitGTK prefix/AppImage rebuild needed unless AppImage path regresses. Cancelled Azure 31338874103 (pre DEVELOPER_MODE / unifdef; guaranteed PCH fail after retry). Dual flatpak shots: Vultr + Azure on fixed tip.


## Green path verified

- Full: 31341571803 success Vultr, in-SDK WebKit ae64af0353, bundle + last-good artifacts
- Peer sync flatpak-webkit: both hosts 354M last-good
- Packaging-only: 31343549390 success ~4m seed=hit
- Nested dual appimage|flatpak x x11|wayland dispatched after

## Launch DBus ServiceUnknown (renamed app-id)

Symptom: `flatpak run org.gnome.Epiphany.WebKitDnD` →
`Failed to register: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown`.

Cause: Epiphany binary still registers GApplication as `org.gnome.Epiphany`.
Our Flatpak app-id is `org.gnome.Epiphany.WebKitDnD`, so the sandbox only
owns that name by default. `--help`/`--version` work (no bus register);
normal GUI launch fails.

Fix: finish-args `--own-name=org.gnome.Epiphany` (+ SearchProvider /
WebAppProvider). Local workaround without rebuild:
`flatpak override --user --own-name=org.gnome.Epiphany org.gnome.Epiphany.WebKitDnD`
Verified: after override, WebKitNetworkProcess/WebKitWebProcess start from
`/app/libexec/webkitgtk-6.0` (slipstreamed engine).

## login.live.com Oops / WebKitWebProcess SIGSEGV (dav1d)

Symptom: UI loads chrome then "Oops! Something went wrong while displaying
this page" on login.live.com (and similar media-heavy pages).

Cause: WebKitWebProcess SIGSEGV in thread comm=dav1d-worker inside
org.gnome.Platform//50 `libdav1d.so.7` (GStreamer dav1ddec). Not DnD.

Mitigation in epiphany-dnd-wrapper.sh:
`GST_PLUGIN_FEATURE_RANK=dav1ddec:NONE` (default). Local override same env
until rebuilt bundle is installed. example.com unaffected either way.

## Nested e2e green

flatpak-x11 and flatpak-wayland both S1-S3+F1 PASS on nested 31351799703 with
bundle from packages 31346489622 (ae64af). Guest installs org.gnome.Platform//50
from flathub then the private bundle. own-name / wrapper path held under nested
automation.
