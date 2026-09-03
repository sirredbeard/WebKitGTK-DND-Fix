# Bug report draft: restore trusted file drops on GTK and WPE

Prepared for bugs.webkit.org. Not yet filed. Nothing here goes upstream
without explicit authorization.

This file has three parts: the Bugzilla field values, the body to paste as
comment 0, and notes for us that must not be pasted. The notes include
prepared replies for the questions a reviewer is likely to ask, so the
reasoning we cut from comment 0 is ready when it is wanted.

## Part 1: Bugzilla fields

Match the fields [bug 303434](https://bugs.webkit.org/show_bug.cgi?id=303434)
used, since this is its direct follow-up. Both 303434 and
[bug 322068](https://bugs.webkit.org/show_bug.cgi?id=322068) carry no
keywords.

- Product: WebKit
- Component: WebKitGTK
- Version: WebKit Nightly Build
- Hardware: PC
- OS: Linux
- Severity: Normal
- Priority: P2
- Keywords: none
- CC: bugs-noreply@webkitgtk.org
- URL: https://developer.mozilla.org/en-US/docs/Web/API/HTML_Drag_and_Drop_API/File_drag_and_drop
  (the public drop zone 320301 used; a maintainer can try it in
  MiniBrowser without downloading anything)
- See Also: https://bugs.webkit.org/show_bug.cgi?id=303434
- See Also: https://bugs.webkit.org/show_bug.cgi?id=271957 (restricted; 303434
  links it the same way)
- See Also: https://bugs.webkit.org/show_bug.cgi?id=320301
- Attachment: `bug_report_drop.html` from this repo, uploaded as `drop.html`,
  content type text/html, description "Drop target that reports
  dataTransfer.files.length in the title"

Summary line:

```
REGRESSION(303828@main): [GTK][WPE] dataTransfer.files is empty when files are dropped from the file manager
```

The [bug report guidelines](https://webkit.org/bug-report-guidelines/) ask
for exactly this shape: "If you have tested and verified that this is a
regression from a previous version of WebKit, prepend 'REGRESSION: ' to
the summary. If you know the range of revisions in which the regression
occurred, add this to the summary after REGRESSION". Bug 278644 used the
modern form, `REGRESSION(281966@main): [GTK] ...`, and got a diagnosis
from a maintainer the next day. The rest of the title names the symptom,
not our fix, which is how 322068 and most landed WebKitGTK bugs are
written and keeps the bug useful if the fix changes shape in review.

## Part 2: comment 0

Wrapped at 72 columns to match how comments are written on this component.
Paste from the line below the fence to the line above the closing fence.
Bugzilla does not render markdown.

<!-- BUGZILLA-BODY-START -->
```
Since 303828@main, DataTransfer::allowsFileAccess() in
Source/WebCore/dom/DataTransfer.h returns false on every port except
Cocoa. A file dragged from the file manager into a page arrives with
an empty dataTransfer.files, so drop-to-upload does not work on
WebKitGTK or WPE. Bug 320301 reports the same failure against
WebKitGTK 2.52.5 in Epiphany and MiniBrowser.

Steps to reproduce:
1. Open the attached drop.html. It reports dataTransfer.files.length
   in the window title.
2. Drag a file from Files (Nautilus) onto the red box.
3. The title reads files=0. Before 303828@main it read files=1.

Cause: the disable was the workaround for CVE-2025-13947, and comment
0 on bug 303434 says the narrow fix was tried first and failed. The
defect it worked around is in SelectionData. setURIList() promoted
every file:// line into m_filenames, and a page can write
text/uri-list itself through DataTransfer.setData() during a drag it
started, so a page could name file:///etc/passwd, receive its own
drag back, and read it. The uri-list is web-writable text. The
filename list is a filesystem grant. Bug 52094, open since 2011, is
the same conflation from another angle.

Fix: separate the two channels rather than flip the policy back.
setURIList() stops writing m_filenames. Filenames are set by the
UIProcess drop targets from a real GdkDrop or GdkDragContext, travel
in their own SelectionData IPC field, and are cleared by
WebPageProxy::startDrag() on the way up. On GTK4 the portal file list
takes precedence over a parallel uri-list, web drag exports drop
file:// lines, import rejects file URIs naming a foreign host, and
DragData denies filenames when DragApplicationFlags::IsSource is set.
Only then does allowsFileAccess() return forFileDrag() for GTK and
WPE. Paste stays denied, so the expectation 303828@main added for
paste-image-does-not-reveal-file-url is unchanged.

Tests: drag and drop cannot be driven from WebKitTestRunner on GTK
(bug 157179), so the patch adds a GLib API test, TestDragAndDrop,
that feeds the production DropTarget path the inputs a real drop
supplies and asserts dataTransfer.files from JavaScript after the IPC
round trip, plus SelectionData and DropTargetState unit tests in
TestWebCore: 11 API tests and 33 unit tests. The commit message
covers the negative controls and what stays out of scope.

Bug 271957 is not visible to me. I would appreciate a maintainer
checking the change against that reproducer.

HeroDevs is sponsoring this work.

Pull request to follow.
```
<!-- BUGZILLA-BODY-END -->

### Self-review comment on our own pull request, titled "Open questions"

Post once the PR exists, as a review comment, not in the bug. Two
paragraphs, wrapped at 72.

```
Two structural choices here are the maintainers' to make, so I want to
flag them rather than have them found in review.

This is one commit because the layers are not independently safe:
allowsFileAccess() returning forFileDrag() without the SelectionData
split is CVE-2025-13947 again, so a partial backport or a single-commit
revert of a series would reopen it while looking clean. If a series is
preferred anyway, I will split it with the allowsFileAccess() change
last.

The tests drive the production DropTarget path through a test-only
entry on WebKitWebViewBase, because WebKitTestRunner cannot deliver
synthetic drags to GdkDragContext (bug 157179) and beginDragWithFiles
exists only in the legacy DumpRenderTree. If the preference is to solve
157179 first and test through WebKitTestRunner, I would rather know now.
```

### One comment on bug 320301, after ours has a number

```
Filed bug NNNNNN with the cause and a patch: since 303828@main,
DataTransfer::allowsFileAccess() returns false on every non-Cocoa
port, so dropped files never reach dataTransfer.files. I have not
checked whether the page being replaced by the dropped file has the
same cause.
```

## Part 3: notes for us, do not paste

### Why it is shaped this way

We surveyed the Bugzilla REST API on 2026-09-02: the bug report guidelines,
the contributing page, comment 0 of bugs 303434, 322068, 157179, 52094,
and 42194, and 37 WebKitGTK and WPE bugs from 2024 to 2026 that were
RESOLVED FIXED and filed from addresses outside Igalia, Apple, GNOME, and
Red Hat. The full record is in `findings/webkit-norms-and-reviewers.md`.
The numbers that decided the shape:

- Median comment 0 on those 37 outsider bugs is about 70 words. The 75th
  percentile is about 120. Three exceeded 280, and the longest, 824
  words, was a pasted log. Length bought nothing in any of them.
- Zero successful outsider comment 0s contained a list of questions to
  maintainers. The two that asked open questions (278016 and 290446) were
  the two slowest to resolve.
- The ones that went well share five traits: the regressing commit in the
  title, the cause named at function level in two or three sentences, the
  fix mechanism stated once, a repro a maintainer can run, and a pull
  request within minutes of filing. Bug 322068 is the cleanest example:
  196 words, PR twelve minutes later, approved in an hour, landed in
  three.
- Every patch attached to Bugzilla or pasted inline (283246, 278016,
  310235) was redirected to GitHub. The fork branch is not a deliverable.
  The pull request is.
- Design argument belongs in the commit message and the PR thread. Bug
  319275 is the model: 39 words in comment 0, and the reasoning about
  test coverage came in the PR when the reviewer asked for it.

Our comment 0 is about 380 words. That is the high end of the observed
range and deliberately so, because the cause and the fix need a paragraph
each on a change that reopens a CVE-adjacent path, and because the testing
question will be asked on any patch that adds no layout test. It is still
a quarter of the previous draft. The previous draft's four questions, the
testing seam argument, and the single-commit argument were not deleted.
They are the prepared replies below and, where they describe the change,
they are already in the commit message, which is the PR body.

The sponsorship line is one sentence, placed after the substance and before
the pull request line, and it names the company and nothing else. That is
how affiliation shows up on this component when it shows up at all: the
reporter's e-mail domain, or a bare sentence. No product, no link, no
description of what the company does. It stays out of the commit message,
which has no convention for it, and out of the PR thread. Tooling used to
prepare the patch is not mentioned anywhere upstream-facing.

The one request in comment 0 is the 271957 line. It mirrors how bug 299208
refers to that restricted bug, asks for something only a maintainer can
do, and does not speculate about the contents of a report we cannot read.

### Bug 320301

Filed 2026-07-26 by an end user, not a WebKit contributor. WebKitGTK
2.52.5, GTK 4.22.4, Fedora 44 Workstation, GNOME 50.3 Wayland, reproduced
in both Epiphany 50.4 and MiniBrowser, with a video attached. Status NEW,
no maintainer reply in five weeks. Title "[GTK] Cannot drag and drop (DnD)
upload files to a standard HTML file upload drop zone".

We missed it until 2026-09-02 because it mentions neither allowsFileAccess
nor 303434. `findings/upstream-strategy.md` said no downstream user had
filed a report and has been corrected.

We file ours anyway, for three reasons. Ours names the cause and carries a
patch, which a symptom report cannot be retitled into without rewriting
someone else's bug. Ours covers WPE. And two bugs by different reporters,
cross-linked, is the pattern 278644 and 278648 used without friction. Add
320301 to See Also, post the one comment above on it, and let the
maintainers decide which one closes as a duplicate of the other. Either
outcome is fine.

One caution. 320301 describes a second symptom, the page being replaced by
a navigation to the dropped file. That may be the default action running
when the drop is not consumed, or it may be something else. We have not
checked, and the comment on 320301 says so. Do not claim the patch fixes
it.

### Facts checked before writing, not assumed

- 303434 fields, status RESOLVED FIXED, no keywords, and its see_also link
  to 271957, read from the Bugzilla REST API. 322068 also carries no
  keywords.
- 303828@main resolves to 89838b9164a1dd3baa7053539cf93414977fb081, dated
  2025-12-03, two files: `DataTransfer.h` and the GTK expectation for
  paste-image-does-not-reveal-file-url. Checked at commits.webkit.org.
- 271957 returns "not authorized", so it stays a bare number.
- 157179 is REOPENED, in Tools / Tests, titled "[GTK] Drag and drop can't
  be tested with WebKitTestRunner".
- 52094 is NEW, WebKitGTK, creation_time 2011-01-08.
- 320301 as described above, read from the REST API including comment 0.
- EventSenderProxyGtk.cpp is 527 lines with zero drag entry points.
- 42 lines in the GTK TestExpectations cite 157179.
- Test counts: 11 API, 24 SelectionData unit, 9 DropTargetState unit.
- beginDragWithFiles exists only in Tools/DumpRenderTree/mac and
  Tools/DumpRenderTree/DumpRenderTreeFileDraggingSource.h. It is a legacy
  WebKit1 entry point. Tools/WebKitTestRunner/EventSenderProxy.h declares
  no drag entry point for any port, Cocoa included.
- 322 declarations ending in ForTesting appear in headers under
  Source/WebKit/UIProcess on upstream main. Our tree has 323 because ours
  is one of them. An earlier draft said 579, from a looser grep. The
  number a reviewer reproduces on main is the one that ships.
- `setFilenames()` has three production callers, not two: DropTargetGtk3,
  DropTargetGtk4, and the SelectionData IPC decode constructor at
  SelectionData.cpp line 93. Comment 0 no longer counts them. The engine
  commit message was amended on 2026-09-03 and now names all three.
- Negative controls rerun 2026-09-03 with every API test in its own
  process and a fifth revert, `allowsFileAccess()` false again. Each of the
  five reverts turned red only the tests that depend on it, ten of the 11
  API tests went red under at least one revert, and the eleventh
  (`non-file-uri-list-grants-no-files`) is a parser guard that no single
  defence decides. The earlier "and nothing else" reading was an artifact
  of the GLib harness aborting at the first failure. Record and log path in
  `findings/testing-plan.md`. The engine commit message was amended to say
  this and pushed to the fork the same day; the tree hash did not move.
- Style: `check-webkit-style -g a097f4c45e..` reports 0 errors in 24 files
  on the rebased tip `2c6d19d7e4`. The rebase onto current main on
  2026-09-03 has a patch-id identical to the tested tree, and the per-test
  negative control matrix was rerun on the rebased tree with identical
  results.
- Comment 0 carries no environment line of our own. We did not reproduce
  on an unpatched MiniBrowser, so rather than guess, the line was deleted
  on 2026-09-02. 320301 supplies the independent reproduction on 2.52.5
  with GTK 4.22.4, and the mechanism is read from the header.

### Prepared replies

Use these when a reviewer asks. Do not post them unasked. Each is wrapped
at 72 columns so it can be pasted.

If asked why there is no layout test, or why not fix 157179 first:

```
WebKitTestRunner is out for a mechanical reason: synthetic GDK motion
events are not delivered to GdkDragContext, so DRAG_MOTION never fires
and the drag protocol never advances past its first step. That has
been the diagnosis on 157179 since 2016.

Adding beginDragWithFiles for GTK is also not the small step it looks
like. That entry point exists only in
Tools/DumpRenderTree/mac/EventSendingController.mm, the legacy WebKit1
runner. Tools/WebKitTestRunner/EventSenderProxy.h declares no drag
entry point for any port, Cocoa included. So adding it for GTK means
designing a cross-port testing API in a shared header as a
prerequisite to a GTK fix, which is a larger review surface than the
fix and pulls in reviewers with no stake in this bug.

The API test supplies the drop inputs, the uri-list text, the portal
file list, and which of three sources the drop came from, and hands
them to the same DropTarget path a real GdkDrop drives. It supplies
inputs, not conclusions. It does not set a grant, skip a check, or
shortcut allowsFileAccess(). The assertions run in JavaScript in the
web process after a real IPC round trip, because the trust boundary
here is exactly the one between what the UI process granted and what
the page can assert. A test-only entry on WebKitWebViewBase has
precedent: webkitWebViewBaseSnapshotForTesting lives in the same
header, and there are 322 ForTesting declarations under
Source/WebKit/UIProcess on main.

157179 itself is not fixed by this. The 42 expectations behind it
stay as they are. I am happy to drive this through WebKitTestRunner
instead if that is the preference, but it means solving 157179 first.
```

If asked to split the commit:

```
It is one commit because the layers are not independently safe.
Restoring allowsFileAccess() without the SelectionData split is
CVE-2025-13947 again, exactly. Split across a series, a partial
backport or a single-commit revert reintroduces it while looking like
a clean operation. Keeping it atomic means there is no ordering a
distribution can get wrong. If you would still prefer a series, tell
me where to cut and I will split it, with the allowsFileAccess()
change last.
```

If asked about same-application native drags, or why IsSource is coarser
than Cocoa:

```
IsSource does not distinguish a drag that started in web content from
one that started in a native widget of the same application, so both
are denied file access. That is coarser than Cocoa. I left it that
way because the narrow denial is the safe one and because I could not
find an embedder that depends on native to WebView file drags. If one
exists, narrowing it is a follow-up on top of the split, not a change
to the split.
```

If asked about paste, or about the 303828@main expectation:

```
Paste stays denied. allowsFileAccess() returns forFileDrag(), which is
false for a paste, so the GTK expectation 303828@main added for
paste-image-does-not-reveal-file-url still describes current behaviour
and is unchanged. The GTK3 clipboard still maps uri-list to paths and
needs its own audit before it can match the Cocoa paste policy. Ports
other than GTK and WPE keep returning false because they have not
been audited. Cocoa is untouched. The uri-list string itself stays
visible to the page, as on Cocoa. What no longer follows from it is
file contents.
```

### contributors.json

The operator is not in `metadata/contributors.json`. Recent history there is
people giving themselves committer status after approval, with a reviewer
named in the commit, or committers adding new people. It is not something a
first security-adjacent PR should carry as a second change, and WebKit wants
one commit per PR anyway. Leave it out. If EWS or a reviewer wants an entry,
a committer adds it, or it becomes its own one-line PR after this one has a
reviewer. Whether EWS runs at all for an author who is not listed is not
verified; it cannot be tested privately, since EWS only runs on
WebKit/WebKit. If the first EWS bubbles do not appear within an hour of
opening the PR, ask on the PR, not on the bug.

### No names

Do not name individual maintainers anywhere in this document, the bug, the
pull request, or any comment on either. Referring to people by name in a
first contribution, particularly one that reads their commit history and
review habits closely, comes across as tracking them rather than reading
the project. Cite artifacts instead. A bug number, a commit hash, a
canonical link, or "comment 0 on bug 303434" carries the same information
and is what the project actually keys on.

The reviewer routing happens on its own through CODEOWNERS. We do not need
to request anyone by name, and requesting people we have profiled is
exactly the impression to avoid.

The one address in the field list, bugs-noreply@webkitgtk.org, is the
component's list address rather than a person, and it is the same CC that
bug 303434 and bug 320301 carry.

Do not mention validation packaging, nested virtual machines, continuous
integration architecture, or any application project in the bug, the pull
request, or any comment. Impact is described generically and already is
above.

### Sequencing

Do not file this until the operator says so. The survey is clear that the
pull request should follow the bug within minutes, not days, so do not file
until everything below can happen in one sitting.

1. Confirm the fork tip still has tree hash
   `d364838bce86df36cc77eb6d9a8522e49d4de69d`, or that its patch-id against
   its base is still `b3ff539e216f190363fac0926f1ade3268ba3d49`.
2. Amend the engine commit message header URL from 303434 to the new bug
   number once it exists. The callers sentence and the negative control
   paragraph were already amended and pushed on 2026-09-03. Message-only
   amends keep the tree hash `d364838bce86df36cc77eb6d9a8522e49d4de69d`, so
   the recorded results still hold. Push the amended commit to the fork.
3. File the bug through the web form, attach `drop.html`, and note the
   number. The form shows the rendered text before submission, which is
   worth having on a first filing.
4. Post the one comment on 320301.
5. Open the pull request with `Tools/Scripts/git-webkit pull-request` from
   the WebKit checkout. That script posts the "Pull request: <url>" comment
   on the bug under the operator's account, which is the convention on
   this component. The checkout was made ready for it on 2026-09-03: the
   clone was unshallowed with a blobless filter (three minutes, 4.5 GB),
   the remotes were renamed so `origin` is WebKit/WebKit and `fork` is
   ours, a local `main` tracks `origin/main`, `git-webkit setup --defaults`
   ran to completion and installed the three hooks, and the pre-PR style
   checker is pinned to python3.12 because the host `python3` cannot import
   webkitpy. `git-webkit find HEAD` resolves. The whole path was then
   exercised privately on 2026-09-03: a throwaway commit on a branch of our
   fork, `git-webkit pull-request --draft --no-issue` with the target
   mapped to the fork, which rebased, ran the style check, pushed, and
   created draft PR 1 on sirredbeard/WebKit with the commit message as the
   body in the standard `<pre>` block. It was closed and its branch deleted
   inside a minute, and the temporary mapping was removed. Nothing touched
   WebKit/WebKit or Bugzilla. The fallback if it misbehaves
   on the day is `gh pr create --repo WebKit/WebKit --head
   sirredbeard:gtk-dnd-file-access-reenable` with the commit message as the
   body, then "Pull request: <url>" posted on the bug by hand, which is
   what bug 311917 did. The commit message must already carry the new bug
   URL and the reviewer line "Reviewed by NOBODY (OOPS!)", which it does.
   Run it from the `gtk-dnd-file-access-reenable` branch, without
   `--no-issue`, so the script posts the Bugzilla comment itself. Expect
   three prompts on the day: the pre-PR style check result, GitHub
   credentials if the stored ones have expired, and Bugzilla username plus
   API key so it can post the comment. The key lives outside the tree.
   The dry run on 2026-09-03 also showed the tool reading bug URLs out of
   every commit in the branch's range and logging "Failed to fetch" for
   restricted ones; that is noise, not a failure.
6. Post one review comment on our own pull request, titled "Open
   questions", with the two structural decisions we want a maintainer to
   weigh in on: one commit versus a series, and the test-only entry point
   versus waiting on 157179. The PR thread is where this component
   discusses tradeoffs (317322, 319275). Comment 0 on the bug is not.
   Keep it to two short paragraphs; the prepared replies carry the detail
   if anyone asks.
7. Expect EWS style, gtk, gtk-wk2, and wpe. Expect a request for tests or
   a question about the seam; the prepared replies are above.

### Filing mechanics, for when the go ahead comes

The operator has a bugs.webkit.org account and an API key. The key does not
belong in this repository, in a commit, or in a shell history entry. Read it
from the environment or from a file outside the tree.

The web form is the right tool here. This is one bug, filed once, with one
attachment, and the form previews the result. The script below exists to
dry run the body: it extracts the text between the markers, checks the
column width, and prints exactly what Bugzilla would receive, since Bugzilla does not render markdown and a stray
backtick is easy to miss.

```sh
python3 - <<'PY'
import re, sys
src = open('bug_report.md').read()
body = re.search(
    r'<!-- BUGZILLA-BODY-START -->\n```\n(.*?)\n```\n<!-- BUGZILLA-BODY-END -->',
    src, re.S).group(1)
long = [n for n, l in enumerate(body.splitlines(), 1) if len(l) > 72]
if long:
    sys.exit(f'lines over 72 columns: {long}')
print(body)
PY
```

If the REST API is used instead, the fields are: product WebKit, component
WebKitGTK, version "WebKit Nightly Build", op_sys Linux, platform PC,
severity Normal, priority P2, no keywords, cc bugs-noreply@webkitgtk.org,
see_also 303434, 271957, and 320301, url as in Part 1, summary as in
Part 1, description as printed
above. The attachment is a second POST to `/rest/bug/<id>/attachment` with
the file base64 encoded. That is two authenticated calls to get right on a
first filing, which is the argument for the form.

If the summary line is edited, edit it in Part 1 only. Nothing else in this
file repeats it.
