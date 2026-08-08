# Copilot instructions (WebKitGTK-DND-Fix)

Private research and CI repo for restoring trusted file drag-and-drop on
WebKitGTK after CVE-2025-13947 / the broad workaround on bugs.webkit.org
303434. Engine patches live on the WebKit fork, not in this repo.

## Repositories and branches

- This repo: `sirredbeard/WebKitGTK-DND-Fix` (private). Research notebook,
  HTML harness, container definition, GitHub Actions.
- Engine fork: `sirredbeard/WebKit`, branch `gtk-dnd-file-access-reenable`
  (stacked commits for the four security layers).
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

Also scrub personal app project names from findings and from these
instructions when editing them. Generic embedder language only.

## WebKit contribution norms (always apply)

Mirror findings and upstream practice:

- Bug first on bugs.webkit.org for durable decisions; PR follows the bug
- GitHub `WebKit/WebKit` is where code lands; commit message is the PR body
- WebKit changelog-style commit messages (why, bug, files/functions as needed)
- Reviewer-gated land; do not self-merge or play committer
- EWS matters: style, GTK, gtk-wk2 when expectations change, WPE if shared code
- `Tools/Scripts/check-webkit-style` clean on the touch set before review ask
- Small, boring, backport-friendly diffs over clever rewrites
- Leave Cocoa alone unless Apple is actually wrong (they are the reference here)
- Tests or expectation updates with a one-line why
- Answer security review with mechanism and tests, not adjectives
- Credibility checklist lives in `findings/webkit-norms-and-reviewers.md`; use it before
  "please review"

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

## Engine layers (fork branch `gtk-dnd-file-access-reenable`)

1. Stop promoting web-authored uri-list into `m_filenames`; DropTarget sets
   filenames only on trusted paths. API tests in
   `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp`.
2. Restore `allowsFileAccess` for `forFileDrag()` on GTK/WPE only.
3. GTK4: portal / GdkFileList owns the filename grant over parallel uri-list.
4. IsSource denies local drag file access; DragSource strips `file://` export.
5. **Required next (Opus equal-weight):** serialize `filenames` on
   `SelectionData.serialization.in` and decode via `setFilenames` only.
   Without this, UIProcess grants never reach the web process. See
   `findings/opus-second-opinion.md`.

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
- Thin cmake, default `TestWebCore` + `SelectionData.*`, ccache 2G, small logs
- validation GitHub Releases: `validation-YYYYMMDD`
- Lint workflows with `actionlint` before push
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

- Opening the upstream WebKit PR
- Filing Bugzilla (draft OK if asked)
- Re-enabling paste Files on GTK without a clipboard audit

## GNOME Web AppImage validation

- Separate workflow: `validation GNOME Web AppImage` (dispatch only, long timeout).
- Script: `scripts/ci-build-gnome-web-appimage.sh` (full WebKitGTK install + Epiphany + linuxdeploy/appimagetool).
- Release tag pattern: `validation-YYYYMMDD-gnome-web` with the `.AppImage` attached.
- Target: Fedora 44+ x86_64. Private validation only. Not Flathub. Not the upstream PR vehicle.
- Builder image must include Epiphany deps (libadwaita, gcr, libportal, meson, desktop-file-utils, appstream) and FUSE helpers for AppImage tools.
- Never put personal app product names in AppImage desktop metadata.


## CI step order (unit path)

1. Configure/build (`ci-build.sh`) and test (`ci-test-selectiondata.sh`) are **separate** steps; shared ccache + build tree mounts.
2. On success: pack logs, **publish validation GitHub Release first**, then upload Actions artifacts, then prune old artifacts.
3. Prefer product name **GNOME Web** in filenames, workflow titles, release tags. Keep upstream `epiphany` only for git path / binary / RPM NEVRA.


## Naming

- Do not use pet-food metaphors for validation or QA in this repo.
- Prefer **GNOME Web** in prose and workflow titles. Keep upstream `epiphany` only for git path, binary, or RPM NEVRA.
- Private releases: `validation-YYYYMMDD` (unit) and `validation-YYYYMMDD-gnome-web` (AppImage).
- Workflow file: `gnome-web-dnd-fix-appimage.yml`.

## WebKitGTK prefix reuse

- Build install prefix with `ci-build-webkitgtk-prefix.sh` (emits `webkitgtk-prefix-<sha>.tar.zst`).
- GNOME Web pack sets `SKIP_WEBKIT_BUILD=1` when PREFIX already has webkitgtk-6.0.
- AppImage workflow input `webkit_prefix_artifact_run_id` downloads a prior run's prefix artifact to avoid a second full engine compile.
- Thin TestWebCore builds are not install prefixes; do not wire them as GNOME Web inputs without an install step.

## Artifact resilience

- Pack and upload steps are best-effort (`continue-on-error`, `if-no-files-found: warn`).
- Always upload every log that exists; missing files on incomplete runs must not fail the upload step.
- Publish validation Release before artifact prune.


## Build caching (mandatory on CI changes)

- WebKit upstream CI is Buildbot/EWS, not public GHA workflows. Mirror their **ccache** ideas from `WebKitCCache.cmake`, not nonexistent Actions YAML.
- Always set `CCACHE_BASEDIR` to the WebKit source root and `CCACHE_NOHASHDIR=true` inside containers.
- ccache max ~5G; keys versioned (`-v2-`); save even on failure when possible; restore-keys fall back broadly.
- Optional ninja build-dir snapshot for TestWebCore only, size-gated; never assume multi-GB debug trees fit cache.
- GNOME Web must reuse `webkitgtk-prefix-*` artifacts by default (auto-find or run id); only rebuild prefix when missing or forced.
- Unit TestWebCore build is not an install prefix; sharing is via ccache + explicit prefix tarball.


## Self-hosted runner

- Heavy workflows MUST use `runs-on: [self-hosted, linux, x64, webkit-dnd]`.
- Never send multi-hour WebKit builds to `ubuntu-latest` while the Vultr runner is online.
- Persist ccache/build/prefix under `/var/cache/webkit-dnd/` on the runner host.
- Do not put Vultr API keys in GitHub secrets for this repo.

## Builder image layers

- Edit `containers/packages-core.txt` or `packages-webkit.txt`, not a single mixed RUN when possible.
- Keep CI scripts as the last Dockerfile layer.
- Runner keeps a bare WebKit mirror under `/var/cache/webkit-dnd/mirrors/WebKit.git`.


## Dual-runner federation (hard rules)

- Runs-on: `[self-hosted, linux, x64, webkit-dnd]`. Azure + Vultr labels as needed.
- Peer-sync **ccache**, **prefix tarballs**, **builder images**, **build snapshots**.
- Do **not** rsync live `*.git` mirrors between hosts. Each host `git fetch`es
  its own mirrors. `SYNC_MIRRORS` defaults off.
- Clone with `--reference` and dissociate. Never `--shared`.
- Fail closed if WebKit checkout lacks `Source/WebCore` or HEAD != expected tip.
- Lint workflow YAML with `actionlint` before commit.
- Single squash commit on `main`. Never `Co-authored-by` on this repo.
- Nested GUI on Azure KVM only after unit + AppImage green. See `nested-gui/`
  and `findings/nested-gui.md`.



## Local lint (mirror upstream + this repo)

Before committing engine or CI changes, run:

```bash
bash scripts/lint-local.sh
```

That runs:

- `actionlint` on `.github/workflows` (required before every workflow commit)
- `shellcheck -S error` on `scripts/` and `containers/` shell
- `check-webkit-style` on the DnD engine touch set via **python3.12**
  (Fedora hosts with python 3.15 break webkitpy `sre_compile`; EWS uses 3.12-class)

Upstream EWS still expects a real **gtk compile** and **TestWebCore /
SelectionData.*** run. Style does not catch missing symbols by itself.

Engine C++ habits that match WebKit style bots:

- Prefer `WTF::move` over `WTFMove` or `std::move` (`runtime/wtf_move`)
- Run style on the touch set before push; do not wait for CI to teach style

Set `WEBKIT_SRC` if the fork checkout is not `../WebKit`.

See `findings/upstream-lint-and-test.md` for EWS queue detail.

