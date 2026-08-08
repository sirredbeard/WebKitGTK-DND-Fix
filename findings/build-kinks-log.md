# Build system kinks and postmortems

## Vultr teardown: one snapshot only

Teardown always does a single disk snapshot then deletes the instance. No skip-snapshot branch in the default path. Stable snapshot description `webkit-dnd-gha-final` so a retry (GHA + on-box timer) reuses the same snapshot instead of minting another billable one. Delete is refused until that snapshot is complete. Done stamp prevents a second full run. Must egress from Azure static IP 20.127.61.97.



## AppImage clone failure (root-owned __pycache__)

AppImage lane failed while image pull actually succeeded. Real failure: `rm -rf` of prior WebKit worktree hit permission denied on root-owned `__pycache__` from container bind mounts. Misleading error said GHCR image missing. Fix: wipe CLONE_DIR with sudo before clone; clone-from-mirror.sh wipes stubborn trees; distinct errors for pull vs clone; local image seed fallback if ghcr pull fails.



## Azure Ubuntu host tuning

Azure box already matched most Fedora runner knobs: swappiness 5, dirty ratios, autogroup off, large TCP buffers, nofile 1M, docker overlay2 + log rotation, runner drop-in OOMScoreAdjust -500, ccache env, performance CPU governor, IO scheduler none, tuned present, fstrim enabled, 64G RAM no swap.

Gaps closed:
- THP was Azure default always → madvise (better for compile)
- 600G resource disk at /mnt now used for build-gtk (and optional buildx) via symlink; ccache/mirrors/images stay on OS disk so they survive deallocate
- docker.service.d LimitNOFILE/TasksMax; journald size caps; git manyFiles/pack.threads
- scripts/host-tune-ubuntu-runner.sh is the durable re-apply path (skips docker/runner restart while a job is active)

Docker data-root stays on OS disk by default so images survive deallocate; set DOCKER_ON_EPHEMERAL=1 only when intentionally trading persistence for temp-disk speed.



## Idle dual-runner reboot + self-delete squash

Workflow `reboot-runners-when-idle.yml` (github-hosted, cron every 4h + manual):

1. If any other workflow run is in_progress/queued/pending, exit and try next cron.
2. Wake Azure, reboot Vultr via Azure Run Command + vultr-cli (static IP allowlist).
3. `az vm restart` Azure so kernel/sysctl/docker/runner unit drop-ins load.
4. Delete this workflow file and orphan-squash main to one commit (scripts/gha-squash-main.sh). No Co-authored-by.

So it retries every 4 hours until the burn is idle once, then removes itself.

Vultr teardown, after successful one-snapshot+delete, also deletes `vultr-teardown.yml` and squashes main to one commit the same way.



## Root cause: Azure unit fail + slow wake

Three stacked issues:

1. Zombie Listener - unit active / API online, but broker session dead (SSL cancel, backoff). Diag went quiet. Wake only checked systemctl active, so it trusted a half-dead runner or looped on slow az vm run-command.

2. No passwordless sudo for gha on Azure - container builds leave root-owned __pycache__ under the WebKit worktree. wipe_dir/sudo rm failed with password required, then clone failed. Mirror fetch also hit sudo.

3. Pull+clone parallel - clone failure is fatal even when GHCR pull succeeded; error text can look like an image problem.

Prevention shipped:
- install-gha-sudoers.sh (NOPASSWD for gha)
- azure-runner-health.sh + 2m timer (restart sticky broker / stale diag when no Worker)
- azure-vm-wake.sh single probe: sudoers + health + Listening for Jobs + activity + seeds
- clone wipe_dir: sudo -n then docker alpine root fallback
- activity stamp writes as gha; peer sync never fails the job




## Critical CI findings (clone + remote)

- Unit run 31241709351: build and TestWebCore exit 0, but `selectiondata-tests.log` was **0 bytes** and external validation failed all 9 required cases.
- Root cause 1: branch `gtk-dnd-file-access-reenable` on **sirredbeard/WebKit was still at main tip d5bec83d77** - our four DnD commits lived only in the local clone (`ahead 4`). CI built main. Pushed: remote tip is now **a85db85942**.
- Root cause 2: Azure WebKit bare mirror partially corrupt (`unable to read sha1 file` on many paths). Shallow `--reference --shared` clone failed checkout; fallback left detached HEAD at d5bec without failing the job.
- Root cause 3: AppImage 31242087792 got past epiphany clone, then `rm -rf /workspace/gnome-web-build` hit **Device or resource busy** (docker mountpoint). Fixed to clear contents only.
- Mitigations shipped: clone-from-mirror verifies `git ls-remote` tip vs HEAD and refuses wrong tree; rebuilds bad mirrors; gtest fails closed on empty/no PASSED; external validation flags empty log.


## Unit build 31242490849: WTFMove undeclared in SelectionData.cpp

- Correct tip `a85db85942` cloned after mirror recreate. Good.
- ninja failed on `UnifiedSource-platform-26.cpp.o` compiling `SelectionData.cpp`.
- Errors: `WTFMove` was not declared at `setFilenames` and `updateURLFromURIList`.
- Cause: new/moved code paths use `WTFMove` without `#include <wtf/StdLibExtras.h>`. Transitive includes no longer enough.
- Fix on engine branch: add that include. Re-dispatch unit after push.

## AppImage 31242491821: epiphany clone failed WebCore check

- After clone hardening, `clone-from-mirror.sh` always required `Source/WebCore`.
- Epiphany is not WebKit. Clone of gnome epiphany died with "missing Source/WebCore".
- Fix: only require WebCore when REPO_URL looks like WebKit and not epiphany/GNOME. Optional `REQUIRE_MARKER_PATH` for other trees.


## Local lint would have caught WTFMove

Upstream EWS `style` runs `Tools/Scripts/check-webkit-style` and flunks. It rejects `WTFMove(` and `std::move(` in favor of `WTF::move(`. Our SelectionData paths used `WTFMove`; modern WebCore is almost all `WTF::move` (order of 15k vs a handful of leftover macros). That also explains the unit compile: `WTFMove` needed a macro header, `WTF::move` was already visible transitively. Fix: use `WTF::move` only. Run `scripts/lint-local.sh` before push.


## AppImage 31243369724: meson missing iso-codes

- Epiphany clone succeeded after WebCore check fix.
- WebKit HEAD was wrong/old on that job path in one log line (`42356523`) worth watching; unit job on Azure correctly saw `96b0229725`.
- meson failed: `Dependency "iso-codes" not found`.
- Fix: add Fedora package providing iso-codes pkg-config to builder image (`iso-codes` and/or devel as required on F44).


## iso-codes vs iso-codes-devel

Image had RPM `iso-codes` but meson wants pkg-config `iso-codes.pc`, which lives in `iso-codes-devel` on Fedora. Added to packages-webkit.txt. AppImage script also `dnf install`s it if pkg-config is missing so we need not block on a full image rebuild.


## Unit 31244108137: all SelectionData **PASS** but job red on parser

- Tip `17647b75df` correct (IPC filenames + WTF::move).
- TestWebCore built and ran. Log has ten lines like `**PASS** SelectionData.Foo` including the new IpcConstructor case.
- Job still failed: `ci-test-selectiondata.sh` and `ci-external-validation.sh` only looked for gtest `[  PASSED  ]` / `PASSED`.
- TestWebKitAPI does not print stock gtest PASSED lines. It prints `**PASS**` / `**FAIL**`.
- Fix: accept both markers; require FAIL closed; add IpcConstructor to REQUIRED_TESTS. Verified offline against the real log (external validation fail=0).


## Container 31244109917: checkout Post EACCES on root __pycache__

- Build deps container failed after a unit job on the same Azure workspace.
- `actions/checkout` Post could not unlink `WebKit/.../__pycache__/hasher.cpython-314.pyc` (root from docker bind mount).
- Not a Dockerfile bug. Shared self-hosted workspace pollution.
- Fix: `scripts/workspace-fix-root-owned.sh` plus pre-checkout and post-docker reclaim steps on unit, AppImage, prefix, and container workflows. chown to runner uid/gid, drop `__pycache__` / `*.pyc`.


## AppImage 31244108972: meson pwquality missing

- Prefix path reused webkitgtk-6.0 2.53.4 (old last-good, still not tip).
- Epiphany clone OK. iso-codes-devel install OK.
- meson died: `Dependency "pwquality" not found`.
- Fix: add `libpwquality-devel` to packages-webkit/packages.txt; AppImage script dnf-installs missing iso-codes/pwquality/gck/libportal if pkg-config fails so we need not block on image rebuild.


## Unit 31244625519: green on tip 17647b

- Azure tests_only path. HEAD `17647b75df`.
- test_exit=0. All ten SelectionData cases `**PASS**`, including IpcConstructor.
- external-validation fail=0 (parser fix).
- last-good-unit stamped on host. Validation release published.
- Layer 1 unit + Layer 4 unit automated checks closed for this tip.


## AppImage 31244771020: prefix tip green, meson blueprint-compiler

- Force prefix rebuild on Vultr finished for engine tip `17647b75df`. Stamp `.webkitgtk-dnd-sha` and tarball `webkitgtk-prefix-17647b75dff4.tar.zst` (~96M stripped).
- Older `d5bec83` stamp/tarball were leftovers only; live clone was already tip.
- pwquality dnf hook worked (YES 1.4.5). Next fail: `Program 'blueprint-compiler' not found` in epiphany/src/meson.build.
- Fix: package `blueprint-compiler` (+ desktop-file-utils/itstool common helpers) in packages lists and AppImage host-dep install with fail-closed checks.


## Builder image package batch (bake next container)

Runtime dnf hooks caught epiphany host deps the F44 image lacked. Next `Build deps container` should bake these so AppImage skips dnf:

- iso-codes, iso-codes-devel (pkg-config iso-codes)
- libpwquality-devel (pkg-config pwquality)
- blueprint-compiler (epiphany UI templates)
- already expected: desktop-file-utils, itstool, libportal-gtk4-devel, libadwaita-devel, gcr-devel, libsecret-devel, libsoup3-devel, appstream(-devel)

Keep the AppImage fail-closed host-dep install as a safety net when the image lags the script. Do not block AppImage on image rebuild once the hook can install the RPM.


## Epiphany SRPM BuildRequires mapped into builder packages

Source of truth: Fedora `epiphany` SRPM BuildRequires (`dnf download --source epiphany` on F45 rawhide), then `dnf provides` for each `pkgconfig(...)` and binary path.

Leaf RPMs (no distro `webkitgtk*-devel`; PREFIX provides those):

- tools: blueprint-compiler, desktop-file-utils, itstool, gettext-devel, meson, python3-docutils (rst2man), gcc
- pc: iso-codes-devel (+ iso-codes), libpwquality-devel, gcr-devel, libportal-gtk4-devel, libadwaita-devel, libsecret-devel, libsoup3-devel, json-glib-devel, libarchive-devel, nettle-devel, sqlite-devel, cairo-devel, gdk-pixbuf2-devel, gsettings-desktop-schemas-devel, gstreamer1-devel, gtk4-devel, libxml2-devel, libappstream-glib-devel
- dnf dry-run also pulls deps: libappstream-glib, libportal-devel, vala, libvala, python3-gobject-devel

AppImage host-dep installer checks the same set and dnf-installs only misses. Next container bake should make that a no-op.


## AppImage migrator path and clean-F44 smoke

Host run of the first green AppImage:

- `--version` prints `Web 42356523f` (works; does not exercise migrator)
- GUI aborts: `Failed to execute child process /opt/webkitgtk-dnd/libexec/epiphany/ephy-profile-migrator`

Cause: epiphany was meson-installed with `--prefix=/opt/webkitgtk-dnd` (same as WebKit PREFIX), so `PKGLIBEXECDIR` is baked to that absolute path. Staging into AppDir does not rewrite the binary.

Fix: meson `--prefix=/usr` + `DESTDIR=AppDir` ninja install; merge WebKit PREFIX into AppDir; rewrite text metadata; keep AppRun.wrapped env; CI smoke in clean `fedora:44` checks no `/opt/webkitgtk-dnd` in epiphany, migrator present under `usr/libexec/epiphany`, and `--version` with bundled `LD_LIBRARY_PATH`.

F44 package name check (docker fedora:44 on Azure): all packages-webkit.txt names resolve (`missing_count=0`). F45 rawhide names match F44; only NVR differs.

## libephymain.so and linuxdeploy

After DESTDIR=/AppDir prefix=/usr install, epiphany private libs land in `usr/lib64/epiphany` (pkglibdir). linuxdeploy only searches standard lib paths and fails with `Could not find dependency: libephymain.so`. Fix: stage `*.so` from pkglibdir into `usr/lib64`, put pkglibdir on `LD_LIBRARY_PATH`, pass `--library .../libephymain.so`, and keep pkglibdir first on AppRun LD_LIBRARY_PATH.


## AppImage target: Fedora 44 glibc floor

Cross-distro AppImage breakage is usually the **glibc** version the binary was linked against, not missing GTK libs (those we bundle). Builder is Fedora 44; measured glibc **2.43**. Host is Fedora 45 rawhide for agent work only. Runtime target is Fedora 44+ (latest stable), not 43.

Release notes template now records builder glibc and the GLIBC_x.y not found failure mode. `builder-glibc.txt` is stamped during pack.

## webkit-sha.txt poisoned by epiphany clone

`clone-from-mirror.sh` always wrote `webkit-sha.txt` / `webkit-head.txt`. Epiphany clone reused it and overwrote the engine pin with gnome-web HEAD (`42356523f`). Smoke then expected the wrong SHA. Fix: only stamp webkit-* files for WebKit URLs; AppImage script re-stamps from PREFIX `.webkitgtk-dnd-sha` or WEBKIT_DIR; smoke prefers PREFIX stamp and rejects collision with gnome-web-head.

## Migrator path regression guard

Epiphany must meson `--prefix=/usr` + `DESTDIR=AppDir`. Fail closed:

1. migrator exists at `usr/libexec/epiphany/ephy-profile-migrator` after DESTDIR install
2. again after linuxdeploy/ldd
3. `strings epiphany` must not contain `/opt/webkitgtk-dnd`
4. CI smoke in clean F44 enforces the same

Never meson-install epiphany into `/opt/webkitgtk-dnd` (WebKit PREFIX). Merge PREFIX into AppDir after epiphany.

## SRPM dep audit (F43/F44)

epiphany + gtk4 BR identical across F43/F44 except gtk4 glib floor (2.80 vs 2.84). webkitgtk SRPM is named `webkitgtk` (not webkitgtk6.0). Added missing -devel packages from webkit/gtk/epiphany pc map: harfbuzz, icu, woff2, pango, graphene, fontconfig, freetype, X11 composite stack, vulkan-loader, tinysparql, colord, avahi-gobject, librsvg2, clang, etc. Distro webkitgtk*-devel still omitted.


## AppImage packed wrong engine (d5bec) while tip was 17647b

Green smoke on 31246260394 still embedded PREFIX stamp d5bec83: host last-good/prefix tree lagged the tip tarball. Fail closed: if WEBKIT_DIR HEAD and PREFIX `.webkitgtk-dnd-sha` both exist and differ, refuse to pack. Smoke must use PREFIX/tree pin, not epiphany. Reseed tip last-good from `webkitgtk-prefix-17647b75dff4.tar.zst` before next pack.


## Why AppImage green-packed d5bec (stale last-good)

Run 31246260394 was green and smoke matched expected only because expected was taken from the PREFIX stamp. That stamp was d5bec. Tip tree was 17647b. So smoke proved "pack equals PREFIX," not "PREFIX equals engine tip."

Chain that caused it:

1. Force prefix rebuild on Vultr wrote tip tarball `webkitgtk-prefix-17647b75dff4.tar.zst` (~96M) and a tip tree under PREFIX_HOST.
2. `seed-prefix-from-last-good.sh` preferred `webkitgtk-prefix-last-good.tar.zst` first. That file was still the old 48M d5bec handoff from 05:21.
3. Seed did `rsync --delete` from last-good into PREFIX_HOST, wiping the tip tree.
4. Worse: seed treated DEST as disposable. DEST is `/var/cache/webkit-dnd/prefix`, which holds **both** the install tree **and** the tip/last-good tarballs. Moving or replacing the whole DEST deleted the tip tarball path the next run needed.
5. Peer warm + bidirectional peer-sync re-spread whichever last-good was smaller/stale without comparing size or stamp. Azure could hand Vultr d5bec again after a tip reseed.
6. AppImage pack trusted PREFIX. clone-from-mirror also used to write `webkit-sha.txt` for every clone, so an epiphany clone could poison the expected sha with `42356523f`.

What we changed so it cannot silently happen again:

- Seed takes `EXPECTED_WEBKIT_SHA` (clone HEAD). Only extract a tarball whose stamp matches. Prefer tip-named OUT tarballs over last-good.
- Seed rsyncs the tree into DEST with excludes for `webkitgtk-prefix-*.tar.zst` and the stamp file. Never mv/rm the whole DEST.
- Seed refreshes last-good only from a matching tip tarball.
- Pack fails closed if PREFIX stamp and WebKit HEAD disagree (short/long prefix match allowed).
- Smoke expected sha prefers PREFIX stamp, then webkit-sha.txt, then clone HEAD; rejects if that equals gnome-web HEAD.
- clone-from-mirror only writes webkit-sha when the URL is WebKit.
- warm-ccache and peer-sync refuse to overwrite a larger local last-good with a smaller peer copy; winner-by-size then push the winner.

Manual reseed after the bug: Vultr last-good is now the 96M tip tarball, stamp 17647b75dff4324f5a15f6eb32087a0a26b3837c.
