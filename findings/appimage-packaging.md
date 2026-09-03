# AppImage packaging notes (GNOME Web + patched WebKitGTK)

Private validation image only. Not an upstream GNOME or WebKit release. Not for Flathub.

## What we ship

- Payload: GNOME Web (Epiphany) from gnome epiphany `main`, linked against WebKitGTK built from `sirredbeard/WebKit` branch `gtk-dnd-file-access-reenable`.
- There is no separate WebKitGTK git tree. WebKitGTK is the GTK port of that WebKit checkout, installed to PREFIX then merged into the AppDir.
- Builder: Fedora 44. glibc floor is the builder's glibc (record in release notes and `builder-glibc.txt`). Older hosts fail at load with GLIBC_x.y missing. That is normal AppImage behavior.

## The migrator failure (host and guest)

Symptom on Fedora rawhide host with system GNOME Web installed:

```
Version mismatch, version 40 requested but our version is 39
Failed to run the migrator process, Web will now abort.
```

Symptom on a clean nested guest without epiphany:

```
Failed to execute child process "/usr/libexec/epiphany/ephy-profile-migrator" (No such file or directory)
Failed to run the migrator process, Web will now abort.
```

Root cause is the same class of bug. Epiphany bakes `PKGLIBEXECDIR "/ephy-profile-migrator"` at compile time. In `lib/ephy-profile-utils.c` that becomes an absolute path, currently `/usr/libexec/epiphany/ephy-profile-migrator`, and `g_spawn_sync` runs it. On a host that already has GNOME Web, that path is the *system* migrator. Tip Epiphany may ask for migration version 40 while the system migrator is still 39. On a clean guest the path is simply missing.

This is not a nested-QA-only problem. Anyone running the AppImage next to a distro epiphany package, or on a machine without one, hits it. PATH does not fix it. The spawn uses an absolute path.

## What the AppImage docs actually say

docs.appimage.org packaging guide, "No hard-coded paths":

1. Prefer real relative paths in the application.
2. Or same-length binary rewrite: replace `/usr` with `././` (both four bytes), then run with cwd set to `AppDir/usr` so `././libexec/...` resolves inside the bundle.
3. AppRun sets ordinary relocatable env (`PATH`, `LD_LIBRARY_PATH`, `XDG_DATA_DIRS`, ...) and execs the payload.

They do not recommend bubblewrap bind-mounts over host `/usr` for this.

## Wrong turn: bwrap AppRun

We first shipped an AppRun that bind-mounted the bundled migrator (and pkglibdir) over `/usr/libexec/epiphany` with bwrap, plus a long list of `--setenv` copies because bwrap starts a clean environment. It worked as a workaround. It was the wrong model.

Problems with that approach:

- Fights the AppImage layout instead of fixing hardcoded paths.
- Depends on bubblewrap on every QA host and in smoke.
- Re-exports half the environment by hand. Easy to miss `DISPLAY`, portal sockets, or the next variable a toolkit needs.
- Looks like a sandbox product when we only needed relocatability.

Called out in review. Dropped.

## Current approach (docs-aligned)

1. Build Epiphany with `meson --prefix=/usr` and `DESTDIR=AppDir` so PKGLIBEXECDIR is `/usr/...`, not `/opt/webkitgtk-dnd`.
2. Merge the WebKitGTK PREFIX install into `AppDir/usr` (libs, libexec helpers, injected-bundle).
3. Pack-time same-length rewrites on epiphany and webkit ELF only (Python byte replace; `sed -i` on ELF did not reliably apply in the pack container):
   - `/opt/webkitgtk-dnd` (18) -> `./././././././././` (18)
   - `/usr/libexec/epiphany` (20) -> `././/libexec/epiphany` (20)
   - same idea for `/usr/lib64/epiphany` and `/usr/lib/epiphany`
4. Minimal `AppRun.wrapped`: set PATH, LD_LIBRARY_PATH, XDG_DATA_DIRS, GSETTINGS_SCHEMA_DIR, WEBKIT_EXEC_PATH, WEBKIT_TOP_LEVEL, then `cd "$APPDIR/usr" && exec ./bin/epiphany "$@"`.
5. linuxdeploy keeps the outer AppRun and the gtk plugin hook. We only own the wrapped payload.
6. Smoke runs through AppRun only (never bare `usr/bin/epiphany`), asserts relative migrator strings, rejects leftover `/opt/webkitgtk-dnd`, rejects bwrap in AppRun, fails on Version mismatch / Failed to run the migrator.

Legitimate env that stays:

- `WEBKIT_EXEC_PATH` / `WEBKIT_TOP_LEVEL` are supported WebKit overrides, not path hacks.
- Ordinary AppImage library and data path vars.
- linuxdeploy-plugin-gtk may force `GDK_BACKEND=x11`. Note it; override only if Wayland is required and stable.

## Second packing bug: injected-bundle under PREFIX

After migrator reloc alone, profile launch still warned:

```
Error loading the injected bundle (/opt/webkitgtk-dnd/lib64/webkitgtk-6.0/injected-bundle/...)
```

WebKit was built with `PREFIX=/opt/webkitgtk-dnd`. Those strings live in `libwebkitgtk-6.0.so`. Merging PREFIX into AppDir/usr does not rewrite them. The `/opt/...` same-length rewrite covers injected-bundle, libexec helpers, and share paths. Without it the UI may come up and the web process still dies.

## sed -i failure in CI

Run 31248832293 died at:

```
error: reloc patch did not produce ././libexec/epiphany/ephy-profile-migrator in libephymisc
```

Before-audit still showed absolute paths. After-audit unchanged. No `reloc-patch` log lines. The shell `sed -i` loop did not modify the ELF payload under `set -e` in that container the way a local interactive test did. Fix: Python reads each interesting ELF, does in-place same-length `bytes.replace`, writes back, fail-closed if absolute migrator or `/opt/webkitgtk-dnd` remains.

Local proof before the Python packer: patch + minimal AppRun on an extracted tree gave `Web <rev>` with no version mismatch, and cold profile ran migrators 37 through 40 using the bundled migrator.

## Other packing traps we hit

- Never bake `/opt/webkitgtk-dnd` into Epiphany itself. DESTDIR install with prefix=/usr.
- `APPIMAGE_EXTRACT_AND_RUN=1` still uses AppRun. Nested automation must not exec `usr/bin/epiphany` from the extract tree and skip reloc.
- Epiphany rejects `--private-instance` together with `--profile`. Use `--profile` only for isolated QA profiles.
- linuxdeploy misses recursive deps (harfbuzz was one). Extra ldd pass into AppDir; fail closed if harfbuzz missing.
- Builder leaves a DEVELOPER_MODE/build-root string `/workspace/gnome-web-build/src/ephy-profile-migrator` in libephymisc. Production path is PKGLIBEXECDIR; debug builds may prefer BUILD_ROOT. Do not treat the build-root string as the runtime path.
- glibc floor is F44 builder. Document it. Do not claim universal distro portability.
- No long-lived host launcher script. Fix the image; rebuild.

## Success bar for the image (before DnD claims)

CLI / smoke:

- `./AppImage --version` prints Web/Epiphany rev.
- No Version mismatch, no Failed to run the migrator, no missing ephy-profile-migrator.
- Embedded `.webkitgtk-dnd-sha` matches the engine tip we meant to ship.
- Path audit: relative migrator, no `/opt/webkitgtk-dnd` in libwebkitgtk/libephymisc.

GUI (host probe + nested):

- Window maps under Xvfb or nested session.
- Full stack logs collected (see nested-gui.md and testing-plan.md).
- Maintainer DnD bar is separate: S1/S2/S3 must PASS (security), F1 must PASS (product), canary must not leak. Packaging green is necessary but not sufficient.

## Scripts

- `scripts/appimage-apprun.sh` - minimal wrapped runner
- `scripts/ci-build-gnome-web-appimage.sh` - DESTDIR install, merge PREFIX, Python reloc, appimagetool
- `scripts/ci-smoke-appimage.sh` - clean F44 container smoke
- `docs/appimage-release-notes.template.md` - glibc floor and packing notes for humans

## Open

- Confirm CI pack with Python reloc produces a green smoke and a downloadable AppImage.
- Host plain `./AppImage --version` on rawhide without a side launcher.
- Nested suite S1/F1 after migrator-fixed image.

## CI failure: AppRun "still contains bwrap" (31249460890)

Python reloc itself was fine (`reloc_files_patched=13`, `reloc_patch=ok`). Fail-closed audit did:

```bash
grep -q bwrap AppRun.wrapped || grep -q bwrap AppRun
```

Our minimal AppRun had the word "bwrap" only in a **comment** explaining why we do not use bubblewrap binds. That tripped the audit after a successful reloc pass. Lesson: comment text is not code; audit must ignore `#` lines (or never put the forbidden token in comments).

Fix: scrub the comment; audit with `grep -v '^[[:space:]]*#' | grep bwrap` so real `exec bwrap ...` still fails closed. Smoke script lives inside a single-quoted `bash -lc '...'` payload — do not nest single-quoted regexes there.

## CI failure: smoke after green pack (31249843494)

Pack and reloc succeeded. AppRun `--version` printed `Web 42356523f` (migrator path OK). Smoke still failed:

1. **Bare migrator exec** from AppDir root without `LD_LIBRARY_PATH` / without `cwd=usr` → exit 127 (`libephymisc.so` not found). Not a supported launch mode. Epiphany spawns migrator after AppRun `cd usr`.
2. **DT_RUNPATH corruption:** reloc replaced `/usr/lib64/epiphany` inside RUNPATH with `././/lib64/epiphany` (cwd-relative). Also `/opt/webkitgtk-dnd` inside rpath strings became `./././...//lib64`.
3. **Cold profile** in clean `fedora:44` hit libportal CRITICAL: missing `/etc/machine-id` → core (rc 134). Not a migrator abort.

Fixes:

- Reloc only spawn strings (`/usr/libexec/epiphany`, `/opt/webkitgtk-dnd`), not libdir prefixes used as rpath.
- After reloc, `patchelf --set-rpath '$ORIGIN/...'` on epiphany, migrator, webkit helpers.
- Smoke: seed machine-id; test migrator from `usr/` with AppDir lib path; soft-warn if `$ORIGIN`-only fails.

## CI failure: ORIGIN unbound (31250357224)

After `reloc_patch=ok`, packer died:

```text
ci-build-gnome-web-appimage.sh: line 701: ORIGIN: unbound variable
```

Cause: `set -u` plus `log "patchelf $ORIGIN rpaths ..."`. Shell expanded `$ORIGIN` as a variable. Fix: single-quote the log string so `$ORIGIN` is literal text. Rpath arguments to patchelf were already single-quoted and fine.

## Host blank page / "won't resolve" (render path, green AppImage 31250829176)

Symptom: AppImage starts, --version OK, but pages look broken / blank. First guess was networking. Wrong.

What we proved:

1. HTTPS works. WebKit disk cache stored `https://example.com/` as `text/html` with Cloudflare headers. Not DNS/TLS as the primary failure once sandbox is off and CA path is set.
2. Default launch still used **host bwrap** for WebKitWebProcess/NetworkProcess (`execve /usr/sbin/bwrap`). AppDir layout is not visible the way a normal install is. Portable image must set `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` / `WEBKIT_FORCE_SANDBOX=0` in AppRun.
3. **Hard crash (SIGABRT):** coredump stack was `g_variant_get` → `ephy_web_process_extension_user_message_received_cb` in **host** `/usr/lib64/epiphany/web-process-extensions/libephywebprocessextension.so`. GLib-CRITICAL: format `@a(ss)` vs value `a(ssb)`. Bundled extension was present under AppDir but `libephymain.so` still had absolute `/usr/lib64/epiphany/web-process-extensions` (we had intentionally skipped libdir reloc earlier because it mangled DT_RUNPATH). UI process loaded the **distro** extension against tip Epiphany IPC → abort → "Web process crashed."
4. MiniBrowser from the same AppDir stayed up clean (no ephy extension). Confirms WebKit payload can run when extension skew is out of the path.
5. Hot-patch proof on extracted AppDir:
   - same-length reloc `/usr/lib64/epiphany/web-process-extensions` → `././/lib64/epiphany/web-process-extensions` (and sibling `/usr/lib64/epiphany` → `././/lib64/epiphany`) in libephy*.so
   - AppRun sandbox off + Fedora CA path + host `LIBGL_DRIVERS_PATH`
   - strace: opens `././/lib64/epiphany/web-process-extensions/libephywebprocessextension.so` (bundled), not host
   - session_state.xml: `url="https://example.com/" title="Example Domain"` after ~40s live run, no Web process crashed line

Pack fixes landed:

- Reloc table: longer keys first (`web-process-extensions` before bare `.../epiphany`), then migrator; patchelf `$ORIGIN` still runs after so RUNPATH is not left cwd-relative.
- Fail-closed if absolute web-process-extensions remains in libephymain.
- AppRun: sandbox disable by default, multi-distro CA search (ca-trust first), optional bundled/host DRI path.
- Smoke: assert bundled extension .so exists, relative extension string in libephymain, AppRun exports sandbox kill-switch.

AppDir still has no `usr/lib64/dri` (linuxdeploy did not pull Mesa DRI). Host DRI via `LIBGL_DRIVERS_PATH` is the interim; bundling mesa dri is a follow-up if a host without usable dri fails.

## Who else ships GNOME Web as AppImage

Not GNOME upstream (they push Flatpak). Community:

- **pkgforge-dev/Gnome-Web-AppImage** — real maintained recipe. Uses **sharun / quick-sharun**, not linuxdeploy. Build host is Arch (`pacman -S epiphany` + gstreamer plugins), then `quick-sharun /usr/bin/epiphany ...` and `--make-appimage`. README/FAQ tell people not to use docs.appimage linuxdeploy recipes for this class of app. quick-sharun forces `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` during deploy/test and is built to pull OpenGL stacks when needed. uruntime so FUSE is optional. Self-updater hooks optional.

We stay on linuxdeploy for now because the private CI image is already wired that way. Lessons we took: disable WebKit sandbox for portable runs; do not leave absolute `/usr/lib64/epiphany/...` data paths; graphics stack is part of "it opens web pages," not optional polish. Longer-term option if linuxdeploy keeps hurting: evaluate sharun packaging of our PREFIX-built epiphany+webkit tree.

## Reloc policy (updated)

Do rewrite (data/spawn strings, longer first):

- `/opt/webkitgtk-dnd` → same-length `././...`
- `/usr/lib64/epiphany/web-process-extensions` and `/usr/lib/epiphany/web-process-extensions`
- `/usr/libexec/epiphany` (migrator)
- bare `/usr/lib64/epiphany` and `/usr/lib/epiphany` (module roots)

Then always `patchelf --set-rpath '$ORIGIN/...'` on binaries so DT_RUNPATH is never left as cwd-relative junk from the libdir rewrites.

Do not use bwrap AppRun binds. Do not exec bare `usr/bin/epiphany` in smoke or nested without AppRun.

## Rebuild status (render fix)

Landed on private CI `main` as commit `2087615` ("Fix AppImage page load: reloc ephy extension path, disable WebKit sandbox").

Workflow run **31252342415** (GNOME Web DnD fix AppImage) completed success. Artifact AppImage copied to `~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage` (sha256 `89894c5b21fcddf9bd4a32037a56043d76982572bf8ef08b8b96e36b36a28d51`, ~266M). Embedded WebKit tip `2b70a3d087fe`. Smoke log shows `extension_reloc=ok` and `SMOKE_OK`.

Local host proof without further hot-patch (extracted AppDir from that binary, DISPLAY=:0, profile-only launch):

```
./AppRun --profile=$PROF 'https://example.com/'
```

After ~30s timeout stop:

- `session_state.xml~` embed: `url="https://example.com/" title="Example Domain"`
- WebKit disk cache has `<title>Example Domain</title>` for the example.com resource
- No GVariant / host-extension CRITICAL in the UI log
- Final `Web process crashed` line is from SIGTERM on the timeout stop (session_state.xml then marks crashed=true). The good title is in the `~` snapshot written while the page was live.

Notes from false starts while proving:

- Xvfb alone hit `gdk_display_prepare_gl` abort on this host; real `:0` works for manual proof
- `--private-instance` cannot combine with `--profile`
- Passing `--new-window https://example.com` once steered Epiphany into Bing search for the string; positional URL with trailing slash is the reliable form

Still open packaging follow-ups: bundle Mesa `dri` into AppDir (no `usr/lib64/dri` yet), optional sharun evaluation, Azure golden was still missing before rsync of the local golden qcow.

