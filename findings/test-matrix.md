# Full test matrix (WebKit norms + our layers)

What "thorough" means for this DnD restore: match how WebKit lands GTK/WPE work (style + API tests + targeted layout where real), plus our CVE-shaped security layers, plus desktop proof on the AppImage.

## A. Upstream-shaped automated (engine fork)

These are what reviewers and EWS expect on a GTK pasteboard/DnD change.

1. Style
   - `Tools/Scripts/check-webkit-style` on touched engine files (python3.12).
   - Our `scripts/lint-local.sh` wraps that plus actionlint + shellcheck.

2. TestWebKitAPI (WebCore glib)
   - File: `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp`
   - Filter: `SelectionData.*`
   - Binary: `TestWebCore` (not stock gtest banners; look for `**PASS**`).
   - Required cases (also enforced by `ci-external-validation.sh`):
     - SetURIListDoesNotPromoteFilenames
     - SetURIListKeepsHttpURLWithoutFilenames
     - TrustedSetFilenamesFromURIList
     - ExplicitSetFilenames
     - FilenamesFromURIListSkipsCommentsAndNonFiles
     - ClearFilenames
     - URIListWithoutFilenamesStripsFileURLs
     - URIListWithoutFilenamesEmptyWhenOnlyFiles
     - IpcConstructorPreservesFilenamesWithoutURIListPromotion
     - DragDataIsSourceDeniesFilenameAccess
     - PortalFilenamesNotWidenedByHostileURIList
     - UriListWithoutFilenamesKeepsHttpOnly
     - TrustedDropShapeAfterIpcRoundTrip
     - TrustedDropPrefersPortalFilenames
     - TrustedDropFallsBackToURIListWhenNoPortalList
     - TrustedDropWithoutFilesGrantsNothing
     - TrustedDropWithOnlyPortalListHasNoURIList
     - TrustedDropReplacesPreviousFilenames
   - CI: `webkit-gtk-dnd.yml` and `webkit-gtk-tests-only.yml`.

2b. TestWebKitAPI (GTK UIProcess drop lifecycle)
   - File: `Tools/TestWebKitAPI/Tests/WebCore/glib/DropTargetState.cpp`
   - Filter: `DropTargetState.*` (GTK lanes only; PlatformWPE.cmake does not build it)
   - Covers the "finish the GdkDrop exactly once" contract and the deferred-drop
     replay that GtkDropTargetAsync makes easy to get wrong:
     - SynchronousDropIsNotDeferred
     - DropDuringLoadIsDeferredAndReplayedOnce
     - DropIsNotDeferredWhenNothingIsLoading
     - LeaveAfterDeferredDropStillOwesFinish
     - LeaveWithoutDropOwesNothing
     - FinishedDropIsNotFinishedAgain
     - DestroyWithDeferredDropOwesFinish
     - AcceptResetsPreviousState
     - LoadingCompletionWithoutDropDoesNotDefer

3. Broader WebKit suites we do **not** claim green yet
   - Full `run-webkit-tests --gtk` is multi-hour and mostly unrelated.
   - File-drag LayoutTests under `LayoutTests/editing/pasteboard/` are Cocoa eventSender-heavy; GTK EventSenderProxy does not fully simulate OS file drops.
   - Useful GTK expectations to re-check when landing upstream:
     - `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url*`
     - any gtk-skipped drag File tests once EventSender gaps are known
   - WPE: `port-compile-matrix.yml` now configures `-DPORT=WPE` and builds
     `TestWebCore WebKit`, so the shared WebCore glib layer and the SelectionData
     suite are compiled and run under `PLATFORM(WPE)`; full WPE layout is still
     not required for private CI.

4. What upstream would still want before a public PR
   - ChangeLog / bugzilla 303434 style commit messages (engine already cites the bug on IPC commit).
   - No Cocoa edits.
   - EWS GTK (+ WPE if shared headers change).

## B. Private CI automated (non-GUI)

1. Unit lane (Azure preferred)
   - Build TestWebCore + run `SelectionData.*` and `DropTargetState.*`
   - External validation: HTML fixture presence + required gtest names + layer-checklist-auto.txt
   - Fail closed on empty log / FAIL markers / missing required names

1b. Port compile matrix (`port-compile-matrix.yml`)
   - `WEBKIT_CONFIG=gtk3` -> `-DPORT=GTK -DUSE_GTK4=OFF`, `WEBKIT_CONFIG=wpe` -> `-DPORT=WPE`
   - Builds `TestWebCore WebKit` so `DropTargetGtk3.cpp` is actually compiled
   - Asserts the expected `DropTarget*.cpp.o` exists and the other port's does not
   - Own build dir + ccache per config so the warm GTK4 lane is never evicted

1c. Harness unit lane (`harness-unit-tests.yml`, GitHub-hosted, seconds)
   - `tests/test_nested_harness.py`: eighteen cases over the maintainer bar
     (`scripts/nested-maintainer-bar.py`) and the nested chooser detection
   - Locks in that an N1 PASS via `how=drop` is rejected, that a missing
     results.json fails the gate instead of passing it, that every matrix cell
     is judged, and that the GTK4 chooser (application WM_CLASS, title
     "Select File") is recognised while known browser windows never are
   - Also `bash -n` over all 107 harness shell scripts: a syntax error in a
     guest script otherwise appears forty minutes into a nested run as a cell
     that never starts
   - Runs on every push touching the harness, so nested-only regressions stop
     costing a forty minute VM run to discover

2. Prefix + AppImage lane (Vultr preferred)
   - PREFIX stamp must equal WebKit HEAD (fail closed)
   - Migrator path under usr/libexec (no /opt baked into epiphany)
   - Clean Fedora 44 container smoke: version/help, migrator spawn, embedded sha, no /opt strings
   - glibc floor recorded (F44 = 2.43)

3. Seed / federation guards (not product tests, but gate wrong-engine false greens)
   - EXPECTED_WEBKIT_SHA on seed
   - tip-named tarball preference
   - peer last-good size/sha winner

## C. External validation layers (product meaning)

| Layer | Meaning | Automated today | Needs GUI |
|-------|---------|-----------------|-----------|
| L1 | web uri-list must not grant File | SelectionData unit + HTML marker check | Manual/nested for real drag |
| L2 | real external file drop grants File | none in unit | Manual + nested |
| L3 | portal / GdkFileList trusted path | code review + notes HTML | Optional portal session |
| L4 | IsSource deny + export sanitize | DragData + uriListWithoutFilenames unit | Manual export to Nautilus |
| NEG | canary path never leaks | nested leak-watch (stub→real) | nested |
| NR | input type=file still works | not automated | Manual |

HTML fixtures: `html/layer1` … `html/layer4` + `html/index.html`.

## D. Non-interactive GUI (nested KVM, Azure only)

Target: Fedora 44 Workstation guest under qemu-kvm on Azure (`/dev/kvm` present).

Flow:
1. Unit + AppImage green on tip SHA
2. Host places AppImage + html + guest scripts on 9p
3. Guest boots golden qcow2 overlay, starts session, runs `guest/run-dnd-suite.sh`
4. Suite drives L1/L4 with AT-SPI/wtype where possible; L2 with a real file drop helper; writes results.json + leak-report
5. Does not gate compile lanes until stable

Status: host/guest scripts were stubs; we are fleshing boot + AppImage launch + result contract. Golden image build is rare and cached under `/var/cache/webkit-dnd/nested/`.

## E. Interactive manual QA (you)

1. Copy tip AppImage to `~/Downloads` only after smoke embedded sha matches tip
2. Open `html/index.html` via the AppImage (file:// or simple http server)
3. Run the checklist in `docs/manual-qa.md`
4. Security focus: L1/L4 must never surface `/etc/passwd` as a File; L2 must work for a file you own
5. Report results back into findings or the issue tracker

## F. Order of confidence

1. lint-local + SelectionData.**PASS** + external validation fail=0
2. AppImage smoke tip sha + migrator path
3. Manual L1/L2/L4 on host with that AppImage
4. Nested non-interactive suite on Azure
5. Only then talk upstream EWS / full layout garden

## G. Gaps still open

- Nested suite not yet a green CI workflow
- No GTK LayoutTest rebaseline run in private CI
- No automated L2 file drop outside nested/manual
- Manual QA not yet signed off on tip AppImage
