# Goal, CVE, and threat model

# WebKitGTK file drag-and-drop research

Working notes on why file drop into web content is broken on WebKitGTK, how that shows up in embedders and GNOME Web-style browsers, and what a real upstream fix has to look like. Long form of the investigation plus everything learned in the WebKit tree.

Personal app names stay in this private notebook only. They never go on WebKit/WebKit surfaces.


## Where things live now

- Engine work: local `WebKit/` checkout, remote `sirredbeard/WebKit`, branch `gtk-dnd-file-access-reenable`.
- Private CI and harness: `sirredbeard/WebKitGTK-DND-Fix` (this repo).
- Research: `findings/` in this repo (topic files). Brief map: `README.md`.
- Standing agent rules: `.github/copilot-instructions.md`.
- Nested GUI stubs: `nested-gui/`.
- Do not put research dumps in the engine fork.


## The user-visible bug (private validation context)

Dragging a file from Files (for example a path under Pictures/Screenshots) onto a web upload surface does not attach it. Click-to-upload via the file chooser works.

First read on this was "WebKitGTK + Flatpak + Wayland stack limitation." That was directionally right about the layer and wrong about Flatpak being required. It is not a regression from embedder sandbox finish-arg tweaks, and it is not something an embedder can cleanly fix on its own.

### What we checked in the app

Permissions are not the blocker. After dropping `--device=all`, `org.freedesktop.secrets`, and bare `org.freedesktop.DBus` talk-name, the sandbox still has:

- `xdg-pictures:ro` (covers `~/Pictures/Screenshots`)
- other XDG dirs kept for drag-drop convenience
- FileChooser / Documents portals

Inside the tightened Flatpak the sample path is readable:

```text
~/Pictures/Screenshots/<file>.png -> readable
```

So the app process can see the path. The drop still does not land in the page.

Same failure in GNOME Web Flatpak. That rules out our shell code and the specific finish-args cut as the root cause.

Later validation: same class of failure in GNOME Web from the Fedora RPM, not only Flatpak. That was the important data point. If GNOME Web RPM and GNOME Web Flatpak and this app all fail the same way, Flatpak finish-args are not the story. Neither is our shell.

Click upload is already wired. `OnRunFileChooser` opens a portal-backed `Gtk.FileDialog` and calls `FileChooserRequest.SelectFiles`. That path works for attaching files in a typical SPA upload UI.

### Why a native drop handler in the app is not enough

Nautilus/Files offers a file list over Wayland DND. For that to become a page attachment, WebKit has to deliver it into the web content as a real web `File` / `DataTransfer` (or into an `<input type="file">` the SPA owns).

Receiving paths in our process with `Gtk.DropTarget` only gets native-side paths. It does not put a `File` into the page. The SPA only sees what WebKit gives it, or what the chooser / `SelectFiles` path provides.

Approaches that look attractive on paper and why we are not doing them:

- `Gtk.DropTarget` on the window: easy; does not fill the page file input.
- Read file, base64/blob, inject via JS: fragile against SPA UI/CSP changes; high maintenance.
- Drop opens chooser or fakes `SelectFiles`: only helps if a chooser request is already active; the page may ignore it.
- Rely on WebKit built-in file DND: correct layer; currently broken in this stack.

### App-side determination

- Proper fix: upstream WebKitGTK (and Wayland/portal DND only if that is part of a different break). Cross-check already done: host RPM GNOME Web fails too.
- This app: keep click-to-upload. Do not implement native drop reception just to look busy. Do not build a site-specific inject hack unless the pain is high enough to own the breakage every UI change.
- Not a README item for the app. Tracked in issue 2 so validation does not re-litigate finish-args every time.

Workaround for users: use the attach / file picker control in the page (click to upload). That goes through the portal file chooser.

### validation environment

- Fedora host, GNOME, Wayland
- Private embedder Flatpak on GNOME Platform runtime (post-permissions tighten)
- Runtime `org.gnome.Platform//50`
- Source path: `~/Pictures/Screenshots/`
- Host packages noted while researching: `webkitgtk6.0-2.53.4-2.fc45` (well past the 2.50.3 security floor), `epiphany-51~alpha-4.fc45`, `gtk4-4.23.3-1.fc45`
- GNOME Platform Flatpak runtimes ship their own WebKitGTK; post-2.50.3 lineage still shows the contents gap

Related app notes: permissions PR #1 (DND failure reproduced after tighten; sandbox still reads Pictures). Audio works under tightened finish-args. DND does not in this app or GNOME Web Flatpak or GNOME Web RPM.

---


## Short answer

The break is in WebKitGTK. Specifically a deliberate, overly-broad security workaround for CVE-2025-13947 that disables file *contents* on drag-and-drop for every drag, including legitimate drags from Files into a page. The page may still see URLs. It does not get the bytes. Any web upload UI needs the bytes.

GTK, Wayland, and Flatpak have their own historical DnD scars. They are not what explains this particular failure on current Fedora.

---


## Layer by layer

### 1. Flatpak - ruled out as the root cause

Older WebKit bug [212079](https://bugs.webkit.org/show_bug.cgi?id=212079) ("Drag-and-drop does not work under flatpak") is real history. Portal/path issues for `GdkFileList` in sandboxes are also real (GNOME Discourse threads on FileList + Flatpak).

PR that fixed portal receive on GTK4: [WebKit/WebKit#25575](https://github.com/WebKit/WebKit/pull/25575) / bug 212079, landed as commits.webkit.org/275908@main. That work added `GDK_TYPE_FILE_LIST` to DropTarget formats so GTK can deserialize `application/vnd.portal.filetransfer` (and the legacy `application/vnd.portal.files`). When portal transfer is present, file:// URIs from `text/uri-list` are ignored because sandbox paths from the host uri-list are often meaningless; portal file list is trusted instead.

But GNOME Web from the RPM fails too. Same host, no sandbox. So "grant more filesystem permissions" or "we tightened finish-args in #1" does not explain the current behavior. Permissions can still make a separate mess in other apps. They are not this mess.

### 2. Wayland / GTK4 DnD plumbing - real, but secondary here

GTK4 + Wayland still have sharp edges: action negotiation (Nautilus often offers move; targets that only accept copy silently fail), compositor involvement, incomplete ASK menus. Ghostty hit the copy-vs-move case hard ([ghostty-org/ghostty#11175](https://github.com/ghostty-org/ghostty/issues/11175)).

That class of bug usually means the drop never arrives. Our situation is different in kind: WebKitGTK is still in the picture, and the security workaround explicitly says the site gets URLs without file contents. Even a perfect Wayland drop into WebKit leaves the page without a usable `File` for upload.

### 3. WebKit core (Apple) - not the Linux bug

Catanzaro's write-up is blunt: Apple platforms are not affected. This is a WebKitGTK / GTK port problem in how drag origin and file access were handled on Linux.

### 4. WebKitGTK - this is the layer

CVE-2025-13947 (Important / CVSS 7.4 per Red Hat): WebKitGTK did not properly verify that a drag carrying file access came from outside the browser. A page could attach file URLs to a drag source; on drop, the page could read those files. User-assisted, but trivial to induce. Confidentiality impact is the point.

Red Hat: [bugzilla.redhat.com/2418576](https://bugzilla.redhat.com/show_bug.cgi?id=2418576). CVE record: [CVE-2025-13947](https://www.cve.org/CVERecord?id=CVE-2025-13947).

Michael Catanzaro (blog: [Significant Drag and Drop Vulnerability in WebKitGTK](https://blogs.gnome.org/mcatanzaro/2025/12/09/significant-drag-and-drop-vulnerability-in-webkitgtk/)):

> Websites may attach file URLs to drag sources. When the drag source is dropped onto a drop target, the website can read the file data for its chosen files, without any restrictions. ... only the user is supposed to be able to make that choice, by dragging the file from an external application.

And the line that matches what we see:

> I failed to find the correct way to fix this bug in the two afternoons I allowed myself to work on this issue, so instead my overly-broad solution was to disable file access for all drags. With this workaround, the website will only receive the list of file URLs rather than the file contents.

Workaround shipped in WebKitGTK 2.50.3. Canonical commit: [303828@main](https://commits.webkit.org/303828@main) / `89838b9164a1dd3baa7053539cf93414977fb081`.

Intended model:

- Drag from Files (external) = page may read file contents (user chose the file)
- Drag synthesized by the page = page must not read arbitrary paths

The shipped workaround collapses both cases to: no file contents for any drag. URLs only. Upload UIs that need a real blob/file break. File picker is unaffected, which is exactly our working path (`OnRunFileChooser` → portal dialog → `SelectFiles`).

Blog comments worth keeping: Catanzaro said this only affects drag and drop, not select dialogs. GNOME 48 and 49 Flatpak runtimes got the 2.50.3-class fix. He doubted Geary would care much because mail bodies are not running random page JS the same way.

Older WebKitGTK DnD bugs in the archive (context, not this CVE): [265857](https://bugs.webkit.org/show_bug.cgi?id=265857), [215373](https://bugs.webkit.org/show_bug.cgi?id=215373), ancient [23642](https://bugs.webkit.org/show_bug.cgi?id=23642).

### Where a fix is fixable

- This app: no, not cleanly. Native `Gtk.DropTarget` gets paths in our process. It does not create a web `File` inside the page SPA. JS inject is fragile and not worth owning.
- Flatpak manifest: no. Already readable; RPM fails too.
- GTK / Mutter: unlikely alone. Fixing action negotiation helps apps that never see the drop. It does not re-enable WebKitGTK file contents after the CVE workaround.
- WebKitGTK: yes, only real fix. Need a proper distinction: allow file contents for external drags, deny for web-originated drags. That is exactly the fix Catanzaro did not have time to get right in two afternoons. Until then the broad disable stays.
- WebKit Apple port: N/A, not affected.
- Hosted web app: N/A. Behaving like any site that expects standard HTML file DnD.

---


## Upstream paper trail

Three artifacts matter. Only one is a code change.

1. Security bug [bugs.webkit.org/271957](https://bugs.webkit.org/show_bug.cgi?id=271957). Still access-restricted. Login does not help without the right group. This is the CVE bug. It is the one the code comments tell ports to re-read before flipping file access back on.

2. Public workaround bug [bugs.webkit.org/303434](https://bugs.webkit.org/show_bug.cgi?id=303434). Title: "Disable file access in data transfer operations, except for Cocoa ports." Status: RESOLVED FIXED. Reporter/assignee: Michael Catanzaro. `see_also` points at 271957. There is no separate open public bug filed for "restore external file DnD on GTK/WPE."

3. PR / commit:
 - [WebKit/WebKit#54735](https://github.com/WebKit/WebKit/pull/54735) (merged)
 - [303828@main](https://commits.webkit.org/303828@main) / `89838b9164a1dd3baa7053539cf93414977fb081`
 - Author: Michael Catanzaro (`mcatanzaro@redhat.com`)
 - Reviewed by Adrian Perez de Castro
 - Essentially no discussion on the PR
 - Files touched: `Source/WebCore/dom/DataTransfer.h` and a GTK layout test expected file `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt`

Commit message (same substance as the bug):

> This isn't implemented properly for WebKitGTK and most likely also not for other ports. My initial attempts to fix things have failed, so let's just completely disable it for now. However, Apple has confirmed that Safari is OK, so let's leave file access enabled there.

### What I searched and did not find (public)

- Open WebKit PRs restoring file access for external drags, or retargeting `allowsFileAccess` / `forFileDrag` for GTK/WPE
- Open public bugs.webkit.org issues whose job is "finish the real fix" rather than "ship the disable"
- Branches or follow-up commits from mcatanzaro (or anyone else) continuing the two-afternoon attempt from the blog
- Red Hat BZ 2418576 tracking anything beyond shipping 2.50.3 (CLOSED ERRATA for Fedora/EPEL streams). That is a CVE ship tracker, not a regression tracker for file drop UX
- GitLab GNOME / WPE side patches that carry a tailored solution

Other Linux WebKit embeds hit the same wall (paste/attach paths that need file contents). That is collateral from the same switch. It is not evidence of a recovery effort.

Reading: Catanzaro did the responsible thing under time pressure. Close the confidentiality hole, leave Cocoa alone because Apple confirmed it, document that non-Cocoa ports must not casually flip the bit without understanding 271957. The temporary switch is still the permanent policy in `main`. The security bug is still private. There is no public phase-2 bug, PR, or branch.

---


## Attack vs legitimate drop (mechanism)

Threat model (for bug/PR English):

- Assets: file contents and path-backed File objects available to web content.
- Attacker: malicious web origin, JS, ability to start a drag the user completes (UI:R).
- Bad outcome: page obtains File/contents for a path the user did not intentionally drag from the host file manager or portal.
- Good outcome: page obtains File/contents only for files the host DnD system delivered as real files for that drop.
- Non-goals: inventing a new user permission prompt; changing Cocoa; fixing unrelated clipboard bugs unless the same promotion bug forces it.

Attack (CVE class):

1. Malicious page on dragstart: `dataTransfer.setData("text/uri-list", "file:///home/user/.ssh/id_rsa")` (or equivalent URL / Files typing that hits the uri-list writer)
2. `Pasteboard::writeString` → `SelectionData::setURIList` → `g_filename_from_uri` → `m_filenames` gets a real path
3. User is induced to drop (same page, another drop target, etc.)
4. `containsFiles()` true → `createForDrop(..., draggingFiles=true)` → `forFileDrag()` true
5. Pre-workaround `allowsFileAccess()` on a Cocoa-like policy would return true for that file drag
6. `files()` reads path bytes into web `File` objects. Page exfiltrates.

Legitimate external drop:

1. User drags from Files/Nautilus
2. GTK4 often offers portal file transfer + GdkFileList, and/or text/uri-list with file://
3. DropTarget loads portal file list and/or uri-list into SelectionData
4. filenames present because user chose those files in another app
5. Page should get `dataTransfer.files` with contents (or blob-backed Files). This is the HTML DnD contract upload UIs rely on.

Workaround: step 5 always denied at `allowsFileAccess()`, so legitimate and attack both die. URLs may still be visible; bytes are not.

---


## Origin CVE and GHSA

We assume no access to private Bugzilla 271957. Everything below is from public trackers, the mitigation commit, and packaging notes. Treat 271957 as the authoritative security bug that we cannot read; design as if a security reviewer with access will compare our patch to that bug's root cause.

### Identifiers

- CVE-2025-13947
- GHSA-j77f-3hf7-7rvg (GitHub Advisory Database, reviewed)
- WebKit Bugzilla private: 271957 (security bug; closed; not readable without access)
- WebKit Bugzilla public companion for the mitigation: 303434
- Upstream mitigation: commit 89838b9164a1 / 303828@main / PR 54735
- Stable backport: cherry-pick onto webkitglib/2.50 as f4c8d71fc57b (and shipped in 2.50.3)
- Official product advisory: WSA-2025-0009 on webkitgtk.org (covers WebKitGTK and WPE WebKit together)
- CWE: CWE-346 Origin Validation Error
- CVSS 3.1 (from NVD/GHSA/Red Hat aligned public text): AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:N/A:N score 7.4 High
- Red Hat severity: Important
- Credit (WSA): Janet Black
- Affected products per WSA: WebKitGTK and WPE WebKit before 2.50.3 for this CVE specifically
- Fixed version line: 2.50.3 (and later stables that contain the cherry-pick)

### Public vulnerability statement (what defenders are allowed to say)

Paraphrase of the consistent public wording across GHSA, NVD-style mirrors, Red Hat, and Ubuntu:

WebKitGTK (and WPE, per WSA) does not adequately verify that a drag operation originates from outside the browser before granting access to file paths / file contents through the drag-and-drop dataTransfer path. A malicious page, with user interaction (the drag), can cause sensitive local file information to be exposed to web content. Scope is changed (S:C) because the confidentiality impact crosses out of the web origin into the host filesystem view the engine should not have handed over.

WSA-2025-0009 impact line for this CVE is deliberately short:

"A website may be able to exfiltrate sensitive system information."

WSA description line:

"The issue was addressed through improved state checks."

That is advisory-speak for the blunt `allowsFileAccess()` false path, not a detailed root-cause essay. Catanzaro's public blog post and the PR 54735 commit message are more honest about the engineering shape: file access in data transfer is not implemented safely for GTK, so disable it except on Cocoa.

### What the public text does not give us

- Exact PoC HTML
- Whether paste-only paths were in-scope for the original report or only drag
- Whether WPE had a separate repro or was closed out as same code
- Any agreed long-term design beyond "fix properly later"
- Whether 271957 also tracks follow-up work or is purely the incident bug

We do not need the PoC to reason. The code path is enough.

### Attack shape reconstructed from public code (not from 271957)

This is engineering reconstruction, labeled as such:

1. Page handles dragstart (or related) and calls `dataTransfer.setData('text/uri-list', 'file:///etc/passwd')` or another `file://` URL the user can be tricked into dragging over a sink.
2. On GLib pasteboard write, `PasteboardGLib` `writeString` for URI types funnels into `SelectionData::setURIList`.
3. `setURIList` walks lines and for each `file://` URI calls `g_filename_from_uri`, then appends to `m_filenames`.
4. `m_filenames` non-empty makes `containsFiles()` true on the drag data.
5. Drop path builds `DataTransfer::createForDrop(..., draggingFiles=true, ...)`.
6. Pre-mitigation, `files()` / item list paths could surface real `File` objects backed by those paths, i.e. web content read the bytes or at least metadata/contents the page should not get from a self-supplied path.
7. Cocoa does not take this route for real files. Script-writable URI strings are not the same channel as OS filenames / file promises. GTK/WPE largely collapsed those channels in SelectionData.

The CWE-346 label matches: the engine treated "uri-list claims file://" as "origin is a real external file drag" without a trustworthy origin signal.

### Why the mitigation is `allowsFileAccess() { return false; }` on non-Cocoa

`DataTransfer.h`:

- Cocoa: allow file access when not a drag, or when it is a file drag (`!forDrag() || forFileDrag()`).
- Else: always false, with a comment pointing at webkit.org/b/271957.

So every non-Cocoa consumer of `files()` and the Files type plumbing is gated off, including:

- GTK external file drops (collateral damage; our target to restore carefully)
- WPE whatever drop path exists
- Paste paths that would expose Files typing (GTK layout test expected FAIL for paste-image-does-not-reveal-file-url is a fingerprint of that collateral)

It is a correct emergency control. It is not a correct end state.

### GHSA / ecosystem packaging notes

- GitHub advisory GHSA-j77f-3hf7-7rvg marks the issue reviewed and ties fixed packages to the 2.50.3 line.
- OSV and distro CVE pages mirror the same description.
- No public GHSA for a "file drop broken" regression. Downstream treated this as ship the security update, accept functional fallout.

### Related bugs to keep straight

- 271957: private security incident bug (do not claim contents)
- 303434: public bug for the disable commit
- 212079 / PR 25575 era: GTK4 drop path and portal / GdkFileList work; relevant because external trusted file lists already have a better channel than raw uri-list on modern GTK4
- Cocoa drag/file promise bugs and LayoutTests under editing/pasteboard/*file* are reference behavior, not copy-paste targets

---


## Downstream and sibling-project response matrix

Question we care about: after CVE-2025-13947, did anyone ship a narrower fix that restores external file DnD, or did the world just absorb 2.50.3's broad disable?

### WebKitGTK upstream

- Shipped mitigation on main (89838b9164a1).
- Backported to webkitglib/2.50 (f4c8d71fc57b) for the 2.50.3 stable tarball.
- Documented in WSA-2025-0009 alongside other CVEs fixed in that cycle.
- No public follow-up commit found that re-enables non-Cocoa `allowsFileAccess` or splits SelectionData trust. As of this research, we would be the ones proposing that follow-up.

### WPE WebKit

- Same advisory WSA-2025-0009 lists WPE WebKit before 2.50.3 as affected for CVE-2025-13947.
- Same non-Cocoa `#else return false` applies to WPE builds.
- Debian/Ubuntu package lines for wpewebkit vary by suite; security trackers list wpewebkit next to webkit2gtk for the CVE.
- Any shared WebCore fix must be reasoned about for WPE, even if our manual validation is GTK. Catanzaro and aperezdc both touch WPE packaging and will notice if WPE is forgotten.

### GNOME Web

- GNOME Web does not vendor a fork of the DnD stack. It links WebKitGTK from the system or runtime.
- No GNOME Web application-level workaround showed up in a search for this CVE. There is nothing useful for Epiphany to patch except "require WebKitGTK >= 2.50.3" for security, which distros already did.
- Functional regression (no file drop into web content) is therefore an engine problem. Filing only a GNOME Web issue would be the wrong upstream.
- GNOME Web remains the best end-to-end manual repro browser on Fedora/GNOME once we have a patched libwebkitgtk.

### Fedora / RHEL

- Red Hat Bugzilla 2418576 tracks the CVE for product security.
- Fix posture: upgrade WebKitGTK to the fixed upstream stable (2.50.3+), not a downstream-only rewrite of DataTransfer.
- Catanzaro's dual role (upstream reviewer + Fedora/RHEL WebKitGTK reality) means a mainline fix that is hard to backport will get explicit questions. Prefer something cherry-pickable onto webkitglib stables.

### Debian

- security-tracker lists webkit2gtk fixed at 2.50.3.
- wpewebkit entries exist per suite; some suites lag or differ. Read the tracker before claiming every Debian user is healed.
- No Debian-specific patch re-enabling DnD on top of 2.50.3 found.

### Ubuntu

- USN-7941-1: WebKitGTK vulnerabilities; updates webkit2gtk/webkitgtk packages to 2.50.3-0ubuntu0.* on the active releases named in that notice.
- Guidance to users: standard update, restart apps that use WebKitGTK (Epiphany called out generically).
- Same story: ship upstream mitigation, no Ubuntu-only DnD restore.

### SUSE / other RPM ecos

- Public CVE mirrors follow the same 2.50.3 fixed version. No evidence of a distro carrying a reverse patch to turn file access back on.

### Flatpak / GNOME runtime

- Runtimes pick up WebKitGTK from the runtime branch. Once the runtime has 2.50.3+, sandboxed apps get the mitigation automatically.
- Portal-based file choosers (click to upload) still work; that path never depended on drag filenames the same way. That matches validation: click-to-upload OK, drag-file broken.
- A correct engine fix should keep working under xdg-desktop-portal file transfers used by GTK4 DropTarget.

### Apple / Cocoa WebKit

- Not affected by this WebKitGTK/WPE advisory line.
- Cocoa keeps the stricter pasteboard type model and the existing `allowsFileAccess` logic.
- Our patch must leave `PLATFORM(COCOA)` behavior untouched unless Apple people are deliberately in the thread.

### Other "WebKit" consumers (embedded, Qt wrappers, etc.)

- Old qtwebkit source packages still appear on some CVE pages as tracking noise; they are not modern WebKitGTK and are not our patch target.
- Embedded apps using system WebKitGTK inherit whatever the distro shipped. They are silent victims of the functional regression and beneficiaries of a correct restore.

### Bottom line on responses

Everyone responsible shipped the broad disable via 2.50.3 and moved on. Nobody public has restored external file DnD with a surgical trust-boundary fix. That is opportunity and burden: we are not competing with an existing patch series, and we will own the security argument.

---


## Catanzaro blog: the intended correct fix in his own words

Primary public source beyond the commit message:

https://blogs.gnome.org/mcatanzaro/2025/12/09/significant-drag-and-drop-vulnerability-in-webkitgtk/

(Title: Significant Drag and Drop Vulnerability in WebKitGTK. Do not put calendar dates in our own prose elsewhere; the URL is the stable handle.)

What he states as the bug, plain language:

- Websites may attach file URLs to drag sources.
- When that drag is dropped on a drop target, the website can read file data for the paths it chose, with no real restriction.
- That is not how DnD is supposed to work. Websites must not choose which filesystem paths they may read. Only the user may make that choice, by dragging a file from an external application.
- Punch line: **drag sources created by websites should not receive file access.**

What he states about the shipped workaround:

- He failed to find the correct fix in the **two afternoons** he allowed himself for the issue.
- Overly broad solution: disable file access for **all** drags.
- After the workaround, the website still receives the **list of file URLs**, not the **file contents**.
- Apple platforms not affected.
- Comment replies: only drag-and-drop is affected, not file select dialogs; GNOME Flatpak runtimes already fixed; Geary not really in scope because mail bodies do not run page JS the same way.

This is gold for our design and our commit message voice.

His definition of correct behavior is not "DnD is unsafe forever." It is:

1. Web-originated drag source → no file content access.
2. User external file drag → file content access OK.
3. URL list strings may still be visible; contents must not follow from attacker-chosen paths.
4. `<input type=file>` / dialogs are a different trust path and were never the CVE.

That maps almost one-to-one onto Idea 1 (and the threat model bullets under Attack vs legitimate drop). Ideas 2-4 are how you make (1) hold on real GTK stacks.

### "My initial attempts to fix things have failed"

From commit 89838b9164a1 / PR 54735 body:

"This isn't implemented properly for WebKitGTK and most likely also not for other ports. My initial attempts to fix things have failed, so let's just completely disable it for now. However, Apple has confirmed that Safari is OK, so let's leave file access enabled there."

Public git does **not** show those attempts as landed commits or open PRs. They were almost certainly local spikes, private security-branch experiments, or discarded diffs during the two-afternoon window. We must not invent a fake git history of his failures. We **can** reverse-engineer what a Catanzaro-shaped attempt looks like from his habits, the code shape, and the blog's success criteria.

PR 54735 process tells:

- aperezdc APPROVED with empty body (trusted blunt security patch).
- mcatanzaro waited on gtk-wk2 EWS specifically to validate the **test expectation** change before land.
- aperezdc recorded webkitglib/2.50 backport SHA after land.
- EWS matrix was green across GTK/WPE/mac/ios style bots; he cares about test delta correctness, not only compile.

So any restore PR should expect the same: gtk-wk2 expectation scrutiny, WPE compile, tiny diff, clear security English.

---


## Practical stance (embedders)

1. Click-to-upload remains the working path on WebKitGTK after 2.50.3. Do not wait on DnD for app UX.
2. Do not build an in-app drop bridge. It cannot feed the page a web `File` cleanly, and it would not outrank `return false` in `allowsFileAccess`.
3. Do not chase finish-args or portal tweaks for this symptom.
4. Upstream work belongs on WebKitGTK: origin-aware file access for external drags, deny web-originated file URL grants, without reopening CVE-2025-13947.
5. Until that lands in Fedora and in `org.gnome.Platform` runtimes, retesting embedder packaging tweaks for this symptom is noise.

---



## Maintainer bar we are driving to

Same problem Catanzaro described: trusted external file drops must work again
without reopening the web uri-list file theft hole. Our branch stacks that as
separate commits (deny web promotion, trusted setFilenames, IsSource deny,
portal GdkFileList preference, IPC filenames, GTK4 drop finish).

### Private CI proof status (overnight bar)

Met on tip ae64af0353:

- SelectionData unit green: run 31347639203 (13/13 + external fail=0)
- AppImage + Flatpak same tip SHA: packages run 31346489622
- Nested AppImage+Flatpak x X11+Wayland: S1-S3 PASS, F1 PASS, canary false
  on 31351799703 (confirmation) and product-identical 31350857266
- N1 file chooser remains soft (portal / dogtail) — not a product-bar blocker
- No canary leak on nested export sanitize path

Still not "upstream landed": Bugzilla 303434 / WebKit PR review, gtk-wk2 EWS,
stable cherry-pick discussion. Private CI is the proof pack for that next step.

Stock alignment held: Flatpak Flathub-shaped modules + Canary /app WebKit.
AppImage Fedora prefix pack of the same engine. Nested drives real
Nautilus multi-type drops, not only unit tests.
