# Findings index

Canonical research for restoring trusted file drag and drop on WebKitGTK after
CVE-2025-13947. Root `README.md` stays short. Detail lives here.

Nothing in this directory gets deleted. Some of it records an approach we have
since moved away from. That is still evidence, and the portal and GDK
observations in particular are hard to reproduce.

## Start here

- `upstream-strategy.md` - current plan, written 2026-09-02 with fresh eyes.
  Root cause analysis, upstream state, the three phase plan, and corrections to
  stale claims elsewhere in this directory. Read this before anything else.
- `goal-and-cve.md` - the origin CVE, GHSA, WSA, and the threat model.
- `engine-fix.md` - the engine design and the ranked fix ideas. Note that its
  section on SelectionData IPC serialization is stale, and its four-commit
  stack plan predates the squash to one commit; see `upstream-strategy.md`.
- `opus-second-opinion.md` - independent second opinion, treated with equal
  weight. Contains the "do not upstream yet" scorecard and the open H2 and H3
  gaps. Later and more accurate than `engine-fix.md` on IPC status.

## Upstream process and people

- `webkit-norms-and-reviewers.md` - WebKit contribution norms, coding style,
  reviewer profiles for Michael Catanzaro and Adrian Perez de Castro, the
  credibility checklist, and the split between engine commits and private CI
  proof.
- `upstream-lint-and-test.md` - EWS queues, `check-webkit-style`, and local
  lint parity.

## Testing

- `testing-plan.md` - the full test design.
- `test-matrix.md` - case definitions. S1, S2, S3 are security cases. F1 is the
  trusted external file drop. N1 is the file input non regression case.
- `e2e-results.md` - end to end results and the multi-file drop crash fix.
- `manual-qa.md` - manual QA procedure.
- `gui-automation-and-ci.md` - xdotool, Xvfb, and automation design.
- `nested-gui.md` - nested KVM GUI matrix design.

## Infrastructure

- `ci-federation.md` - dual runner federation, caching, and peer sync.
- `budget-and-ops.md` - the $150 Azure budget, the four enforcement layers, and
  the August 2026 overspend postmortem.
- `build-kinks-log.md` - Fedora package landmines and build failures.
- `appimage-packaging.md` - AppImage packer and smoke tests.
- `flatpak-gnome-web.md` - Flatpak bundle and in-SDK WebKit build.

Per `upstream-strategy.md`, the AppImage and Flatpak lanes are no longer the
release gate. The documents stay because the portal path evidence in them is
real and was expensive to obtain.

## Host and nested observation records

These are captures from specific runs. They are evidence, not design. Keep them
for the GDK, portal, and Wayland detail, which is difficult to recreate.

- `host-dnd-observe-combined.md` - combined host observation and bar assessment.
  The best single entry point to this group.
- `host-appimage-manual-dnd-observe.md` - AppImage layer 2 observation under
  stock GNOME Wayland, with full GDK and portal FileTransfer traces.
- `host-flatpak-manual-dnd-observe.md` - the same for the Flatpak bundle.
- `host-flatpak-manual-dnd-layer1-manual.md` - layer 1 manual desktop session.
  Records the important negative result that dragging a web source out to
  Nautilus writes an 18 byte text file containing the string
  `file:///etc/passwd`, not the contents of `/etc/passwd`. That is uri-list
  drip, not a File API grant, and it does not reopen the CVE.
- `host-flatpak-manual-dnd-layer1-s1.md` - automated Xvfb S1 case, PASS with
  `files=0`.
- `host-wayland-matrix.md` - host Wayland and full matrix learnings, including
  the xdotool `mousemove --sync` hang and the N1 chooser footguns.
- `nested-full-matrix-n1-green.md` - the run where all four nested cells passed
  with N1 required.

Raw machine readable captures are no longer carried on `main`. The JSON, TXT,
and JSONL dumps behind the summaries above were moved to the `archive` branch on
2026-09-02, along with the AppImage, Flatpak, and nested GUI tooling that produced
them. Nothing was deleted; `git show archive:findings/<name>` still returns any of
them. They were dropped from `main` because the effort has narrowed to one engine
commit plus its in-tree tests, and the dumps are large, machine written, and fully
summarized by the markdown above.

What those captures established, so the conclusion survives without the bytes:

- The green four cell nested matrix (`nested-results-31350857266.json`) had every
  cell at `rc=0` with S1, S2, F1, and S3 PASS and N1 inconclusive. That is the run
  that met the nested maintainer bar.
- Its failing predecessor (`nested-results-31349215350.json`) is the useful
  contrast. Only `appimage-x11` passed; the other three cells returned `rc=2` with
  every case inconclusive. That pattern is the signature of a dead session backend,
  not a real security failure. Read `rc=2` plus uniform inconclusive as
  infrastructure before you read it as a regression.

## A note on run URLs

Findings across this directory cite GitHub Actions run IDs as proof. All
workflow runs were deleted on 2026-09-01, so those URLs now return 404. The
validation GitHub Releases survived, and their tags embed the same run IDs
along with the built artifacts and a `webkit-head.txt` recording the engine SHA.
Prefer releases as receipts.

Engine SHAs cited in older findings drifted when the fork branch was rebased.
`ae64af0353` and `17647b75df` are orphaned. See `upstream-strategy.md` for the
current mapping.
