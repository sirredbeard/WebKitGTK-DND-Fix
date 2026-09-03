# Copilot instructions (WebKitGTK-DND-Fix)

Private research and CI repo for restoring trusted file drag-and-drop on
WebKitGTK after CVE-2025-13947 / the broad workaround on bugs.webkit.org
303434. Engine patches live on the WebKit fork, not in this repo.

## Repositories and branches

- This repo: `sirredbeard/WebKitGTK-DND-Fix` (private). Research notebook,
  HTML harness, container definition, GitHub Actions.
- Engine fork: `sirredbeard/WebKit`, branch `gtk-dnd-file-access-reenable`.
  One squashed commit on top of upstream `main`. See "Engine state" below.
- Upstream: `WebKit/WebKit` via Bugzilla + PR. GitHub is canonical for code;
  bugs.webkit.org still matters for process.

## Research findings (`findings/`)

Canonical research lives in `findings/*.md` (topic files). Brief map:
`findings/README.md`. Root `README.md` stays short.

Write new research, CI postmortems, design decisions, and second-opinion
synthesis into the matching findings file as you learn them. No detail is
insignificant. Prefer append and correct in place. Do not rewrite from
scratch. Do not gut preserved material.

### Preserve these topics always

Never delete or gut findings material on:

- WebKit coding style
- WebKit project norms, process, checklists, participation, engagement
- Michael Catanzaro (role, review bar, blog success criteria, inferred playbook)
- Origin CVE and GHSA (CVE-2025-13947, GHSA-j77f-3hf7-7rvg, WSA, 271957, 303434)
- Adrian Perez de Castro (aperezdc) profile and review expectations
- Ranked fix ideas and threat model
- Opus (or other) second-opinion synthesis and equal-weight treatment

Only remove content that is truly outdated local process noise (wrong host
names, superseded one-off commands). When splitting or moving files, keep
every substantive sentence.

### Findings maintenance (agents) - mandatory

- After any non-trivial discovery (build kink, security review point, CI
  failure root cause, budget change, upstream process fact, lint/test
  parity note, dual-runner health observation), update the relevant
  `findings/*.md` in the **same work session** before calling the task done.
- If no existing file fits, add a new `findings/<topic>.md` with a
  descriptive name (no numbering) and list it in `findings/README.md`.
- Write findings in the same plain voice and markdown rules as the rest of
  this file: short sentences, spaced hyphens not em dashes, no tables, no
  marketing, no badge walls. Keep every substantive detail. Prefer append
  and correct in place over rewrite-from-scratch.
- Cross-link new topics from `findings/README.md` when you add a file.
- Do not recreate a monolithic `webkit-dnd-research.md`.
- Engine fork stays free of research dumps.
- Do not put personal style-guide filenames or paths into repo docs.

### Writing voice for findings and repo docs

Use the operator's personal writing voice for findings, README, and durable
docs (GitHub/docs register):

- Short declarative sentences. Precision over adjectives.
- No em dashes (use a spaced hyphen: ` - `). No decorative emoji.
- No marketing vocabulary, badge walls, or throat-clearing openers.
- Oxford comma. Security honesty. First person plural is fine for this repo.
- Do not name or quote the personal style guide file in repo text.

## Markdown style (all docs in this repo)

Handwritten-basic markdown only:

- Headers, bullets, numbered lists, fenced code, bold, italics are fine
- No tables
- No excessive formatting, badge walls, or nested collapsible chrome
- No em dashes (spaced hyphen instead)
- Short declarative sentences; security honesty over marketing

## Hard rules for anything WebKit-facing

Never link to, name, or allude to personal application validation projects in:

- WebKit branch names meant for upstream
- commit messages on the engine fork
- PR titles or bodies against WebKit/WebKit
- Bugzilla text
- in-tree test names

Describe impact generically: WebKitGTK, Epiphany-style browsers, embedded
WebKitGTK file upload UIs. Product pitches burn trust on a security-adjacent
change.

HeroDevs is named once, in comment 0 of the bug, as one plain sentence of
sponsorship. No product, no link, no description of the company. Not in the
commit message, not in the PR thread. Never mention any AI tooling anywhere
upstream-facing. No Co-authored-by anywhere, ever.

Also scrub personal app project names from findings and from these
instructions when editing them. Generic embedder language only.

## WebKit contribution norms (always apply)

Mirror findings and upstream practice:

- Bug first on bugs.webkit.org for durable decisions; PR follows the bug
  within minutes, opened with `Tools/Scripts/git-webkit pull-request` so the
  "Pull request:" comment lands under the operator's account
- Comment 0 is short: symptom, numbered repro with an attached reduction,
  "Cause:", "Fix:", "Tests:", at most one request. Median outsider comment 0
  on this component is about 70 words and none that landed carried a list
  of questions. Design argument goes in the commit message and the PR
  thread. Survey in `findings/webkit-norms-and-reviewers.md`.
- Title regressions as `REGRESSION(NNNNNN@main): [GTK][WPE] <symptom>`
- GitHub `WebKit/WebKit` is where code lands; commit message is the PR body
- WebKit changelog-style commit messages (why, bug, files/functions as needed)
- Reviewer-gated land; do not self-merge or play committer
- EWS matters: style, GTK, gtk-wk2 when expectations change, WPE if shared code
- `Tools/Scripts/check-webkit-style -g <base>..` clean on the diff before
  review ask. Diff scope, not whole files.
- Small, boring, backport-friendly diffs over clever rewrites
- Leave Cocoa alone unless Apple is actually wrong (they are the reference here)
- Tests or expectation updates with a one-line why
- Answer security review with mechanism and tests, not adjectives
- Credibility checklist lives in `findings/webkit-norms-and-reviewers.md`; use it before
  "please review"

### Commits vs proof (mandatory - visitors)

Full playbook: `findings/webkit-norms-and-reviewers.md` section
"Mandatory: commits and proof when we go upstream".

Hard splits agents must not blur:

- **Engine commits** = security code plus in-tree tests only. House message
  shape. No CI receipts, run logs, or "E2E PASSED" commits in WebKit.
- **Private proof** = build and test output from the container builder, with
  SHA and run URLs recorded in findings. Confidence before a review ask, not
  a layer in the upstream commit stack.
- **Order:** stable engine tip that builds and passes `TestWebCore`
  `SelectionData.*` plus `TestDragAndDrop`, then findings updated, then
  Bugzilla and PR on the user's explicit go.
- Lead PR and bug text with the trust boundary and the tests, not CI
  architecture and not product pitches. No personal app names on anything
  WebKit-facing.

See `findings/webkit-norms-and-reviewers.md` for more detail. This is a private repo, but the norms are the same as for public WebKit contributions. Findings are the source of truth here.

## WebKit C++ coding style (always apply on engine patches)

Follow WebKit style as documented in findings and the upstream guide:

- Indentation, braces, spacing, line breaking, naming per WebKit norms
- Include order and header discipline per style guide
- Early return; prefer clear condition structure; careful `auto`
- No drive-by reformat of untouched code
- Comments only when they earn their keep; threat-model English for security
- Safer C++ patterns reviewers already expect in neighboring GLib/WebKitGTK code
- GRefPtr / modern GLib patterns consistent with DropTarget/SelectionData neighbors
- New tests next to behavior (`TestWebKitAPI` / LayoutTests as appropriate)
- Prefer `WTF::move` over `WTFMove` or `std::move`. The EWS style queue
  enforces this (`runtime/wtf_move`), and modern WebCore is almost entirely
  `WTF::move` already.

Run the upstream style checker on the diff before asking for review, from
the WebKit checkout:

```
python3.12 Tools/Scripts/check-webkit-style -g <upstream base>..
```

Scope it to the diff, never to whole files. `--diff-files` checks entire
files and reports 26 pre-existing errors in neighbours we did not touch. The
diff-scoped run on the current tip reports 0 errors in 24 files.

Use python3.12 explicitly. Fedora hosts with python 3.15 break webkitpy,
which still imports `sre_compile`, and EWS runs a 3.12-class interpreter.
Style does not catch missing symbols, so a real GTK compile and test run is
still required on top of it.

See `findings/webkit-norms-and-reviewers.md` for C++ style detail. Apply the same code style as for public WebKit contributions.

## Security and design bar (Catanzaro success definition)

- Web-authored drag sources must not get filesystem file contents
- User external file drops may grant `dataTransfer.files`
- URL list strings may still be visible; contents must not follow from
  attacker-chosen `file://` paths
- File picker / `<input type=file>` was never the CVE path
- Do not flip `allowsFileAccess` without the SelectionData trust split
- Prefer small, backport-friendly diffs
- GTK and WPE share non-Cocoa headers; reason about both
- Paste file access on GTK stays gated until clipboard uri-list→path is
  audited (GTK3 especially)

## Engine state (fork branch `gtk-dnd-file-access-reenable`)

Filed and public since 2026-09-03: bug
https://bugs.webkit.org/show_bug.cgi?id=323277 (attachment 481279 is
`drop.html`) and pull request 73114 on WebKit/WebKit (do not write the PR
reference in linkable form anywhere in this repo; the repo is public and must
not create backlinks on the PR).
One comment posted on 320301. The "Open questions" self-review comment is on
the PR. See `findings/upstream-strategy.md` section "Filed" for the
deviations (271957 rejected from See Also by the API; `--no-issue` because
webkitbugspy has no api_key support, Bugzilla comments posted via REST).

Tip is `2fd5c6cb7ea7`, one commit on upstream base `ae96e9b10b9d`, carrying
the first review round fixes pushed 2026-09-03. Tree hash is
`bc272e2a5ebe08e3027b1968d4995c60530acdc5`. Check the tree hash, not the
commit hash. The review fixes changed the patch-id, so the old patch-id
`b3ff539e216f` no longer describes the diff. The builder baseline is green on
this exact tree (reviewcheck, 05:37 to 05:57 UTC: GTK4 and WPE builds, 11 API
tests one per process, 33 GTK and 24 WPE unit tests) and EWS is green on
every queue that ran. The per-test negative control matrix in
`findings/testing-plan.md` was last run on tree `d364838bce86` (tip
`2c6d19d7e4`); a rerun on the current tree is owed before citing per-test
controls as being of this tip, and the revert patches in
`/var/cache/webkit-dnd/reverts` need regenerating first. Every pre-squash SHA
in older findings (`9d2732f8c`, `62c2aeca1`, `adc3c73d4`, `ae64af0353`,
`17647b75df`) and the earlier tips `30f09212e3`, `108eb10b76`, `2c6d19d7e4`,
`77c35c575c`, and `a9e2b8faf054` are orphaned. The ten-commit history
survives as local branches `backup-ten-commits` and `backup-premerge-b66d907`
in the WebKit checkout.

The defences in the commit, by name. `findings/testing-plan.md` labels the
first, third, fourth, and fifth of these L1, L3, L4, and L5 in its negative
control matrix. `engine-fix.md` numbered them differently while they were
separate commits, so cite the name, not the number.

- uri-list promotion: `setURIList()` no longer writes `m_filenames`. Filenames
  come only from `setFilenames()`, `setFilenamesFromURIList()`, and
  `setTrustedDrop()`. Production callers are the two UIProcess drop targets
  and the IPC decode constructor in `SelectionData.cpp`.
- `allowsFileAccess()` returns `forFileDrag()` on GTK and WPE only.
- portal precedence: on GTK4 the GdkFileList wins over a parallel uri-list.
- IsSource denial and export sanitize: `DragData` denies filenames when
  `DragApplicationFlags::IsSource` is set; web drag exports drop `file://`
  lines and never export a GdkFileList.
- file URI authority: import rejects `file://host/path` unless the host is
  empty or `localhost`. Found by our own tests.
- IPC: `filenames` is its own field in `SelectionData.serialization.in`,
  applied after `setURIList()` on decode; `WebPageProxy::startDrag()` clears
  it on the way up.
- clipboard uri-list export sanitize and the deferred GTK4 drop.

Tests: `TestDragAndDrop` (11 GLib API tests, GTK), `TestWebCore`
`SelectionData.*` (24) and `DropTargetState.*` (9). Five defences have a
recorded per-test negative control, run 2026-09-03 with every API test in its
own process: L1 promotion, L3 portal, L4 IsSource, L5 host check, and L2
`allowsFileAccess()` itself. Ten of the 11 API tests go red under at least one
revert; `non-file-uri-list-grants-no-files` is a parser guard no single defence
decides. Say exactly that upstream, nothing stronger. The GLib harness aborts a
binary at its first failed assertion, so always run API tests one process per
test when reading a negative control. Record in `findings/testing-plan.md`.

Open decisions, both flagged by the second opinion: H2 (`IsSource` denial is
coarser than Cocoa and also denies same-application native to WebView drags)
and H3 (a single trusted grant API). Both are follow-ups, not in this commit.
The bug draft now says so in its out-of-scope list.

The testing seam that used to be listed here as required next is done.
`webkitWebViewBaseSynthesizeFileDropForTesting()` feeds the production
`DropTarget` path a synthesized `SelectionData`, and the assertions run in
JavaScript after a real IPC round trip. Bug 157179 itself is not fixed, and
the bug draft says so. See `findings/upstream-strategy.md`.

The filing sequence is done: bug 323277, comment on 320301, commit header
amended to the new bug URL, PR 73114 opened, "Open questions" posted. What
remains is review: watch EWS (style, gtk, gtk-wk2, wpe), answer reviewers
with mechanism and tests using the prepared replies in `bug_report.md`
Part 3, and rerun the test matrix if the diff changes (patch-id is the
tripwire). Do not post the prepared replies unasked.

Paste Files stays off. Do not re-enable uri-list promotion.

## Reviewers

Primary: Michael Catanzaro (workaround author, WebKitGTK/Fedora security voice).
Also: Adrian Perez de Castro (reviewed the disable, backports, WPE/GTK/CMake).
Full profiles stay in `findings/webkit-norms-and-reviewers.md`.

## Private bug

Assume no access to Bugzilla 271957. Design from public code, WSA-2025-0009,
GHSA-j77f-3hf7-7rvg, and the public mitigation commit. Reference 271957 by
number only.

## CI and container

- Base image OS: Fedora 44
- Builder image title: WebKitGTK-DND-Fix-builder
- GHCR package (lowercase): `ghcr.io/<owner>/webkitgtk-dnd-fix-builder`
- **Image tags are UTC date only** (`YYYYMMDD`). No `fedora44` tag, no `sha-*`
  floating tags on the image. Optional `tag_extra` input only when explicitly set.
- Build/test resolves the newest date tag when `image_tag` input is empty
- Manual `Build deps container` then prune GHCR to newest two **date** tags;
  prune Actions artifacts keep 5
- `WebKitGTK DnD build and test` is workflow_dispatch only
- Thin cmake, default `TestWebCore` + `SelectionData.*`, ccache 2G for the
  unit job (the host cap below is 5G), small logs
- validation GitHub Releases: `validation-YYYYMMDD`
- Private minutes and storage are scarce. Fail fast. No build-tree uploads
- Do not cancel in-flight Actions runs unless the user says so

### Fedora package landmines

- `pcre-devel` → `pcre2-devel`
- `enchant2-devel`
- `perl-bignum` for `bigint.pm`
- `xdg-dbus-proxy` (bubblewrap sandbox configure check)
- libwpe may be missing; GTK-only OK
- `-DUSE_LIBBACKTRACE=OFF`
- `-DENABLE_API_TESTS=ON` / DEVELOPER_MODE

## Git practice for this private repo

- Always squash to a single commit on `main`
- Never `Co-authored-by` on this repository
- Fold editor hand-edits into the next squash
- Do not commit secrets or private security bug contents

## Out of scope until the user directs

- Re-enabling paste Files on GTK without a clipboard audit

## Build caching and the builder

- Base image is the GHCR builder; heavy work runs in it, not on the host.
- Always set `CCACHE_BASEDIR` to the WebKit source root and
  `CCACHE_NOHASHDIR=true` inside containers. A warm ccache is the single
  biggest lever on turnaround time; protect it.
- ccache max ~5G. Keys versioned. Save even on failure where possible.
- Persist ccache, build tree, and source mirror under `/var/cache/webkit-dnd/`
  on the builder host.
- Runner keeps a bare WebKit mirror at
  `/var/cache/webkit-dnd/mirrors/WebKit.git`. Clone with `--reference` and
  dissociate. Never `--shared`.
- Fail closed if a WebKit checkout lacks `Source/WebCore` or HEAD is not the
  expected tip.
- Edit `containers/packages-core.txt` or `packages-webkit.txt` rather than one
  mixed RUN. Keep CI scripts as the last Dockerfile layer.

## Builder landmines

- The builder ships GCC 16. Its `-Wsfinae-incomplete` fires inside WTF's own
  headers, and `DEVELOPER_MODE` makes warnings fatal. Configure with
  `-DDEVELOPER_MODE_FATAL_WARNINGS=OFF`. Passing `-Wno-error` through
  `CMAKE_CXX_FLAGS` does not work, because WebKit prepends its own flags.
- Azure access from this host is `az vm run-command invoke`; there is no SSH
  key here and the NSG pins source IPs that rotate. The VM ships `sh`, not
  `bash`, for run-command wrappers, so `[[` is unavailable. Pass long scripts
  with `--scripts @file` rather than inline quoting.
- Deallocate the VM when idle. Keep the disks; the ccache and mirror live there.
- After `az vm start`, run `/usr/local/sbin/docker-seed-load.sh` on the VM or
  the builder image is missing; it lives on the ephemeral disk. The wake
  script does this, a bare start does not. GHCR pulls are denied from the VM.
- Builds run inside the builder container, not on the Ubuntu host. The build
  directories were configured in the container (`/usr/sbin/cmake`, GCC 16).
- The VM had a DevTest Labs auto-shutdown at 0300 UTC that killed a build on
  2026-09-03. It is disabled. Do not re-enable a wall-clock stop; the idle
  watchdog and budget guards are the stops. See `findings/budget-and-ops.md`.
- Manual jobs must run a keepalive that touches `/etc/webkit-dnd/HOLD_AWAKE`
  and both activity stamps while the job container lives, or the idle
  watchdog and anything reading the stamp will consider the machine idle.
- The GLib test harness aborts a test binary at its first failed assertion.
  Run API tests one process per test (`-p /webkit/<Suite>/<name>`) whenever
  the per-test result matters.

## Overnight / maintainer bar (agents)

When the operator is away, keep driving toward this bar without waiting:

1. Priority is the upstream patch. Packaging is not a deliverable and no
   reviewer sees it. The AppImage, Flatpak, and nested GUI apparatus has been
   removed from `main` and preserved on the `archive` branch. Do not
   reintroduce it, and do not spend time debugging it.
2. The gate is the in-tree test, which runs on EWS for free. Today that is
   `TestWebCore` `SelectionData.*` and `DropTargetState.*` plus the
   `TestDragAndDrop` API tests. A green build plus green tests on a tip that is
   rebased on current upstream main is the bar.
3. A passing test is not the same as a proving test. Before claiming a layer is
   covered, revert that layer in a scratch tree, rebuild, and confirm the test
   actually fails. A test that passes with the hole open is worse than no test,
   because it buys false confidence. Record every negative control result in
   findings, including the ones that embarrass us.
4. Rebuild only what is stale. Never rebuild a green tip for sport. Restore
   ccache first; a full rebuild is a last resort.
5. Update findings in the same work session as the discovery. Write them in the
   operator voice rules above.

Success means: the engine branch is rebased on current upstream main, builds
clean, the tests pass, each test is backed by a negative control that shows it
fails when its layer is reverted, findings record the SHAs and results, and a
new Bugzilla bug plus PR are drafted and ready for review.

Do not open the PR or file the bug without explicit authorization.

Do not file against 303434. It is RESOLVED FIXED and closed since 2025-12-03.
Restoration needs its own bug. Reference 303434, 271957, 157179, 52094, and
320301, the unanswered end-user report of the same regression filed
2026-07-26. Do not hijack 320301; file ours, See Also it, comment there once.

Every pre-squash proof SHA is orphaned, including `adc3c73d4` and `62c2aeca1`,
which earlier notes called current. The tree hash under "Engine state" is the
receipt now. The cited run IDs return 404 because all workflow runs were
deleted on 2026-09-01; the validation Releases survived and carry the engine
SHA. Plan of record is `findings/upstream-strategy.md`.

