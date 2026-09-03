# WebKitGTK-DND-Fix

Research and CI notebook for restoring **trusted** file drag-and-drop on
WebKitGTK and WPE after CVE-2025-13947.

## The issue

CVE-2025-13947 (WSA-2025-0009, GHSA-j77f-3hf7-7rvg) let web content read
local file contents through drag-and-drop on WebKitGTK. The upstream fix,
bugs.webkit.org 303434, was a broad disable: `allowsFileAccess()` returns
`false` on all non-Cocoa ports, so `dataTransfer.files` is empty for every
drop, including a user dragging their own file from the file manager onto an
upload target. Epiphany-style browsers and embedded WebKitGTK upload UIs
lost the feature. Bug 320301 is an end-user report of the same regression.

## Proposed solution

Split trust at the platform boundary instead of disabling the feature. One
commit on the engine fork, `sirredbeard/WebKit` branch
`gtk-dnd-file-access-reenable`:

- `SelectionData::setURIList()` no longer promotes uri-list lines to
  filenames. File grants come only from the explicit setters used by the
  two UIProcess drop targets and IPC decode.
- `allowsFileAccess()` returns true only for actual file drags on GTK and WPE.
- On GTK4 the portal-provided `GdkFileList` wins over a parallel uri-list,
  with the same file URI host check applied to both paths.
- Drags whose source is the same application are denied filenames, and web
  drag exports strip `file://` lines and never export a `GdkFileList`.
- `file://host/path` is rejected unless the host is empty or `localhost`.
- `filenames` crosses IPC as its own field and the web process copy is
  cleared on drag start.

Web-authored drag sources get no file contents. User drops of external
files grant `dataTransfer.files`. Paste stays disabled pending a clipboard
audit.

## Status

Filed upstream on 2026-09-03.

- Bug: https://bugs.webkit.org/show_bug.cgi?id=323277
- Change: PR 73114 on WebKit/WebKit, awaiting human review
- First automated review round addressed: two fixes taken, one taken with a
  stated test limit, one declined with a GLib source citation
- Tip `2fd5c6cb7ea7`, tree `bc272e2a5ebe`, on current upstream `main`
- Builder baseline green: GTK4 and WPE builds, 11 GLib API tests, 33 GTK and
  24 WPE unit tests
- EWS green on every queue that ran, including gtk, gtk3-gcc, and wpe
- Per-test negative controls (revert a defence, watch its tests fail) are
  recorded for tree `d364838bce86`; a rerun on the current tree is owed

## Docs

- Research by topic: [`findings/`](findings/)
- Plan of record: [`findings/upstream-strategy.md`](findings/upstream-strategy.md)
- Coverage audit against the CVE mechanism: [`findings/testing-plan.md`](findings/testing-plan.md)
- Filed bug text and prepared replies: [`bug_report.md`](bug_report.md)
- Agent rules: [`.github/copilot-instructions.md`](.github/copilot-instructions.md)

## Repo practice

Single squashed commit on `main`, no other branches. The packaging and GUI
validation machinery that preceded the engine-only approach was removed;
`findings/` keeps the conclusions in prose.
