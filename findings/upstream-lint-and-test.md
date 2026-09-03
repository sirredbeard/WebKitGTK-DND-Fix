# Upstream lint and test parity

How WebKit actually gates GTK changes, and what we run to match.

## What WebKit runs (EWS / Buildbot)

Style queue:

- Command: `python3 Tools/Scripts/check-webkit-style`
- Flunks the EWS style bot on any reported error
- Engine is a cpplint fork under `Tools/Scripts/webkitpy/style/`
- Important rule for our patches: `runtime/wtf_move` rejects both `std::move(` and `WTFMove(` and asks for `WTF::move(`
- Modern `Source/WebCore` is almost all `WTF::move` (tens of thousands of uses). Leftover `WTFMove` macros are rare
- IWYU-style include checks exist in the checker but are filtered off by default (`-build/include_what_you_use`)
- No in-tree `.clang-tidy` gate for GTK. Apple SaferCPP / scan-build queues are not the GTK land bar

GTK / WPE queues:

- gtk build: compile WebKitGTK (build-webkit / ninja)
- gtk tests / gtk-wk2: layout tests when relevant; modified-test discovery
- wpe build + wpe tests when shared non-Cocoa headers move
- API tests on GTK/WPE go through `run-gtk-tests` / `run-wpe-tests` (TestWebKitAPI), not layout tests alone

Local scripts upstream documents and EWS wraps:

- `Tools/Scripts/check-webkit-style`
- `Tools/Scripts/build-webkit` (perl) with `--gtk` / release flags
- `Tools/Scripts/run-webkit-tests`
- `Tools/Scripts/run-api-tests`, `run-gtk-tests`, `run-wpe-tests`

Git hooks:

- Optional via webkit-patch install-hooks
- pre-commit sorts Xcode pbxproj only. It does **not** run style
- pre-push is about secure/public remote policy, not compile
- So "I committed" never meant "style or gtk build passed"

## What would have caught our WTFMove mistake

1. `check-webkit-style` on the touch set - flags `WTFMove(` immediately
2. A real gtk / TestWebCore compile - `WTFMove` undeclared if the macro header is not pulled in; `WTF::move` was already visible transitively in SelectionData.cpp neighbors
3. Style alone does **not** prove IPC serialization or drop behavior

We hit (2) in CI before we ran (1) locally. Order should be style then compile then SelectionData gtests.

## Host Python footgun

This Fedora host defaults to Python 3.15. webkitpy still does `import sre_compile`, removed from the stdlib. EWS images and python3.12 still work:

```bash
python3.12 Tools/Scripts/check-webkit-style --diff-files <files>
```

`scripts/lint-local.sh` prefers python3.12 for that reason.

## What we run (private repo + fork)

Local before push:

```bash
bash scripts/lint-local.sh
```

That is:

- actionlint on `.github/workflows` (same bar as our workflow commits)
- shellcheck `-S error` on `scripts/` and `containers/` shell
- check-webkit-style on the DnD touch set (SelectionData, DropTarget, DragSource, DragDataGLib, API test)

Still required after lint-local (upstream gtk bar):

- Configure/build TestWebCore (our unit workflow or local ninja)
- `gtest_filter=SelectionData.*`
- External validation harness when the unit job says so
- AppImage lane only after unit is honest green on the real branch tip

Engine tests we own:

- `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp` (including IPC constructor / filenames preserve case)
- Private HTML layers under `html/`
- Nested GUI later on Azure KVM only after unit + AppImage

## Gaps vs full upstream EWS

We do not run full gtk-wk2 layout on every push. That is deliberate cost control. Before an upstream PR we still need:

- style clean on the final diff
- GTK build of the touched libs
- API tests green
- judgment call on layout if DropTarget behavior shows in WebKitGTK API tests or needs a LayoutTest

We are not inventing a parallel style system. We are running their checker and a thin slice of their gtk API test surface inside private CI.

## Correction: lint-local.sh removed (2026-09)

`scripts/lint-local.sh` and `containers/lint-local.sh` were deleted from `main`
during the scope narrowing that also removed the AppImage, Flatpak, and nested
GUI apparatus. Both files are preserved on the `archive` branch and can be
recovered with `git show archive:scripts/lint-local.sh`.

Everything above about the wrapper still describes what it did. What changed is
only how we invoke the part that still matters. The actionlint and shellcheck
passes went away with the workflows and scripts they covered. The
`check-webkit-style` pass did not, because that one is an upstream EWS
requirement rather than local CI housekeeping. Run it directly from the WebKit
checkout:

```
python3.12 Tools/Scripts/check-webkit-style --diff-files <touched files>
```

The python3.12 pin is still required for the reason given earlier in this file:
webkitpy imports `sre_compile`, which Fedora hosts running python 3.15 no
longer provide, and stable EWS images are 3.12-class.

The closing point from the original section is unchanged and worth repeating.
Style is not a substitute for a compile. It does not catch missing symbols, and
it has no opinion about whether the tests pass.

## Base currency check, 2026-09-02

Verified rather than assumed, because the branch had been sitting.

Base `f374cf141b` is a clean ancestor of upstream `main` (`ee629dabaf`), 34
commits behind, about 14 hours old. Of the 300 files upstream touched in that
window, exactly one overlaps our 24: `Source/WebKit/UIProcess/WebPageProxy.cpp`.
The upstream hunks there are in `didCommitLoadForFrame`,
`commitProvisionalPage`, `decidePolicyForNavigationAction`, and the message
check macros near line 502. Ours is in `startDrag()`. Different regions of a
very large file.

Confirmed with a real trial rebase in a throwaway worktree rather than by
reading the diff. It rebased clean, and `git patch-id --stable` on the result
is identical to the patch-id on the current base, so the rebase is semantically
a no-op.

Left the branch on the tested base on purpose. The negative control matrix and
the 33 unit tests ran against that tree. Moving to a newer base to gain nothing
would mean the tested artifact and the published artifact are no longer the
same thing. A PR that is a day behind main is normal and EWS handles it.

Superseded on 2026-09-03: the branch was rebased onto `a097f4c45e` after all,
because the operator asked for it and because the matrix could be rerun on the
result the same night. Patch-id identical, style clean, matrix identical. The
reasoning above about not moving a tested tree without retesting still holds;
it was honoured by retesting.

Method worth reusing: `gh api repos/WebKit/WebKit/compare/<base>...main` gives
`behind_by`, `ahead_by`, and the changed file list without fetching anything.
Intersect that file list against `git diff --name-only <base>..HEAD` to find
conflict candidates in one step.

## What the green matrix did not build

Asked the plain question of whether we had built the thing we tested, and the
answer turned out to be "one configuration of it."

Everything green so far ran in a single build tree, `WebKitBuild/Release`, whose
`CMakeCache.txt` says `PORT=GTK` and `USE_GTK4:BOOL=ON`. The touch set is 24
files. Four of them cannot be reached by that configuration:

- `Source/WebKit/UIProcess/API/gtk/DragSourceGtk3.cpp`
- `Source/WebKit/UIProcess/API/gtk/DropTargetGtk3.cpp`
- `Source/WebKit/UIProcess/gtk/ClipboardGtk3.cpp`
- `Tools/TestWebKitAPI/PlatformWPE.cmake`

The first three open with `#if ENABLE(DRAG_SUPPORT) && !USE(GTK4)` or
`#if !USE(GTK4)`. In a GTK4 build they are empty translation units.

The trap is that the object files exist and look convincing:

```
WebKitBuild/Release/Source/WebKit/CMakeFiles/WebKit.dir/UIProcess/gtk/ClipboardGtk3.cpp.o
WebKitBuild/Release/Source/WebKit/CMakeFiles/WebKit.dir/UIProcess/API/gtk/DragSourceGtk3.cpp.o
WebKitBuild/Release/Source/WebKit/CMakeFiles/WebKit.dir/UIProcess/API/gtk/DropTargetGtk3.cpp.o
```

Checking for the presence of a `.o` is not evidence the code inside it
compiled. The preprocessor got there first. Grep the guard, do not trust the
artifact.

The GTK3 changes are not cosmetic either, so this is not a formality. They
sanitize the drag and clipboard export paths: `DragSourceGtk3` strips file
lines from the exported uri-list, drops the `_NETSCAPE_URL` target when the URL
is a file, and withholds both targets from the target list when there is
nothing left to export. `ClipboardGtk3` does the same for copy out. Those call
`SelectionData::uriListWithoutFilenames()` as a static and use
`URL::protocolIsFile()`. Both are declared correctly, and the call sites read
fine, but reading is not compiling.

This is exactly what GTK EWS would have caught, in public, on a
security-adjacent patch, in front of the maintainer we most need to convince.
Cheaper to find it ourselves.

Method for next time: intersect the touch set against the build configuration
before claiming a build is proof.

```
grep -E "^(USE_GTK4|PORT):" WebKitBuild/<dir>/CMakeCache.txt
head -32 <each touched source> | grep -n "#if"
```

Any touched file whose guard excludes the configured port is untested, no
matter how green the suite is.

## Compiling the GTK3 files, and how we proved they really compiled

Fixing the gap above meant configuring a second tree with `-DUSE_GTK4=OFF` and
building the three objects there. All three compiled, exit status 0, no
warnings we introduced. That is the headline, but the exit status is the weaker
half of the evidence. A build system that skipped the work would also report
success.

The stronger check is to compare the objects against their GTK4 counterparts in
the tree we had been calling green:

```
DragSourceGtk3   gtk4 1432 bytes    2 syms  0 uriref | gtk3 37440 bytes  101 syms  1 uriref
DropTargetGtk3   gtk4 1432 bytes    2 syms  0 uriref | gtk3 45048 bytes  125 syms  0 uriref
ClipboardGtk3    gtk4  960 bytes    0 syms  0 uriref | gtk3 34528 bytes   84 syms  1 uriref
```

`uriref` counts undefined references to `SelectionData::uriListWithoutFilenames`
in `nm -uC` output. Two of the three carry one. `DropTargetGtk3` carries none,
and that is correct rather than a miss - it is the import side, and
`uriListWithoutFilenames()` is an export helper. `DragSourceGtk3` and
`ClipboardGtk3` are the two paths that hand data out, so they are the two that
have to strip.

The symbol counts are the part worth keeping. An empty translation unit
produces 0 to 2 symbols. These produce 84 to 125. The GTK4 objects were not
small because the code is small; they were small because there was no code in
them at all.

Method, stated so it survives: to prove a guarded file compiled, do not check
that the object exists. Check that a symbol only that file's new code could
reference is present in it.

One caveat we did not leave dangling: compiling is not linking. We built the
three objects, not a whole GTK3 WebKit, so an unresolved
`SelectionData::uriListWithoutFilenames` would still have been invisible. That
is answerable without another multi-hour build. The definition sits in
`Source/WebCore/platform/glib/SelectionData.cpp`, which contains no
preprocessor conditionals at all, and that file is listed in
`Source/WebCore/platform/SourcesGLib.txt`, which both `PlatformGTK.cmake` and
`PlatformWPE.cmake` include unconditionally. The symbol is therefore present
for GTK3, GTK4, and WPE alike, and the undefined references in the three
objects resolve. Reading the build lists was cheaper than linking and answered
the same question.

## The WPE include-directory asymmetry, and why it is not a bug

Our patch adds a `TestWebCore_PRIVATE_INCLUDE_DIRECTORIES` block with
`${CMAKE_SOURCE_DIR}/Source` to `PlatformGTK.cmake` and adds no matching block
to `PlatformWPE.cmake`, which has none for that target at all. That asymmetry
looks like an oversight that WPE EWS would find for us in public, so we settled
it before asking for review.

We settled it by deleting the block from `PlatformGTK.cmake`, reconfiguring,
and rebuilding. It failed, and the failure named the reason exactly:

```
Tests/WebCore/glib/DropTargetState.cpp:32:10: fatal error:
WebKit/UIProcess/API/gtk/DropTargetState.h: No such file or directory
```

One file needs it. `DropTargetState.cpp` includes
`<WebKit/UIProcess/API/gtk/DropTargetState.h>`, which is a path into the source
tree rather than an installed private header, so it only resolves with
`Source` on the include path. That file is GTK-only and is deliberately not
listed in `PlatformWPE.cmake`, because `DropTargetState.h` is a GTK type.

The file WPE does share is `SelectionData.cpp`, and its includes are
`<WebCore/DragData.h>`, `<WebCore/SelectionData.h>`, and `<wtf/...>`. Those
resolve out of `WebCore/PrivateHeaders/WebCore/` with no help, which is exactly
how its existing neighbour `Damage.cpp` resolves `<WebCore/Damage.h>` on WPE
today.

So the asymmetry is correct. The include directory is not missing from WPE, it
is unnecessary there, because the only consumer never reaches WPE. No CMake
change. The block also matches the surrounding style: `${CMAKE_SOURCE_DIR}/Source`
is already used for `TestWebKit`, `TestWebKitAPIBase`, and
`TestWebKitAPIInjectedBundle` in the same file, quoted the same way, and
`PlatformWPE.cmake` uses it for three targets of its own.

The answer to a reviewer who asks is one sentence: the include is for
`DropTargetState.cpp`, which is GTK-only, and the shared test needs nothing.

## Lint gate: scripts/lint-local.sh now exists

Our own instructions said to run `bash scripts/lint-local.sh` before every push
that touches workflows, shell, or the engine touch set. The script did not
exist. Every "lint before push" instruction had been silently doing nothing,
which explains the recurring basic shell and YAML bugs.

It exists now and does three things:

- `actionlint` over `.github/workflows`, with `SHELLCHECK_OPTS=-S warning` so
  its embedded shellcheck matches this repo's severity policy instead of
  reporting `info` noise
- `bash -n` then `shellcheck -x -S error` over `scripts/` and `containers/`
- `check-webkit-style -g <base>..` on the engine diff, using an interpreter
  that still has `sre_compile`

That last point is a footgun worth naming. Fedora's `python3` is 3.14 or newer,
where `sre_compile` is gone and webkitpy fails to import. The script probes
`python3.12`, `python3.11`, then `python3` and picks the first that can import
it. Set `WEBKIT_SRC` if the fork is not at `../WebKit`, and `WEBKIT_BASE` to
pin the upstream base.

Scope the style check to the diff, never to whole files. See the readiness
review in `webkit-norms-and-reviewers.md` for why the whole-file number is
misleading.

### What it caught on its first real run

Two live bugs, both in workflows we thought were fine.

**`webkit-gtk-dnd.yml` could not be dispatched at all.** It declared 13
`workflow_dispatch` inputs. GitHub caps that at 10. The workflow had zero runs
in its history, which we had read as "we prefer the tests-only workflow" rather
than "this thing is broken". `workflow_call` has no such cap, so the fix was to
drop three inputs from the dispatch block and keep all 13 on `workflow_call`.

The three chosen were `warm_from_peer`, `skip_wake`, and `snapshot_on_failure`,
because every reference to them is already a null-safe comparison:

```
if: ${{ inputs.skip_wake != true }}
if: ${{ inputs.snapshot_on_failure != false }}
if: ${{ inputs.warm_from_peer != false }}
```

On a manual dispatch those inputs are undefined, and `null != true` is true
while `null != false` is also true, so each falls back to the default it had
declared. No behaviour change on dispatch, full control retained for the parent
workflow. A comment in the file records the cap so nobody re-adds a fourth.

**`build-container.yml` had a `sudo` redirect that never ran as root.**

```
sudo nohup /usr/local/sbin/webkit-dnd-peer-sync.sh >>/var/cache/webkit-dnd/out/peer-sync.log 2>&1
```

The redirect is performed by the calling shell, not by `sudo`, so the log is
opened as the runner user. When that log is root-owned the fallback fails
exactly when it is needed, which is after `systemd-run` already failed. Fixed by
moving the redirect inside the privileged shell with `sudo -n nohup sh -c '...'`.

Neither of these is exotic. Both are what a lint gate exists to catch, and both
survived because the gate was a sentence in a document rather than a file on
disk.

## Making the local checkout usable by git-webkit, 2026-09-03

`git-webkit` is the sanctioned way to open a WebKit pull request. It posts the
"Pull request:" comment on the bug itself and shapes the PR body. Our checkout
at `~/WebKit` could not run it, for four reasons, each fixed in place:

- It was a shallow, single-branch clone. `git-webkit find HEAD` failed with
  "Failed to retrieve revision count for main..". Fixed with a blobless
  unshallow: set `remote.origin.promisor true` and
  `remote.origin.partialclonefilter blob:none`, then `git fetch --unshallow`.
  Three minutes, 4.5 GB, 320k commits, no blobs beyond what we touch.
- The remotes were named for us, not for the tool. `git-webkit` wants `origin`
  to be WebKit/WebKit and the personal fork to be `fork`. Renamed both. The
  fork remote's fetch refspec was also single-branch; `git remote set-branches
  fork '*'` widened it so `fork/main` exists, which the tool needs to match
  the base.
- There was no local `main`. Created it tracking `origin/main`.
- `git-webkit setup --defaults` prompts for GitHub credentials through
  `/dev/tty` and refuses without one. Ran it under a Python pty driver that
  answers the username and token prompts, declines keyring storage, and takes
  defaults elsewhere. The driver has to make the child a session leader with
  the pty as controlling terminal, or the pre-push hook, which opens
  `/dev/tty` itself, fails with ENXIO. Setup installed pre-commit, pre-push,
  and prepare-commit-msg hooks and set `webkitscmpy.*` config.
- The pre-PR style checker is configured as `python3 Tools/Scripts/check-webkit-style`.
  Host `python3` is 3.15 and webkitpy still imports `sre_compile`, so it was
  repinned: `git config webkitscmpy.pre-pr.style-checker "python3.12
  Tools/Scripts/check-webkit-style"`.

Two things the dry run taught that the docs do not say. `--remote` names a
webkitscmpy remote (origin, security, apple), not a git remote, so pointing a
PR at our own fork needed a temporary `webkitscmpy.remotes.fork.url` plus a
git remote called `fork-fork`, both removed afterwards. And the tool walks
every commit in the branch's range and tries to read the bug behind each
commit message; restricted bugs log "Failed to fetch" repeatedly. Noise, not
failure. On the real run it will also ask for Bugzilla credentials to post the
comment.

The dry run itself: draft PR 1 on sirredbeard/WebKit from a throwaway commit,
body in the standard hash header plus `<pre>` commit message shape, closed and
branch deleted inside a minute. `git-webkit` also rebased the branch onto the
freshly fetched main before pushing, so expect the real run to move our tip
again by a message-preserving rebase if main has advanced.

