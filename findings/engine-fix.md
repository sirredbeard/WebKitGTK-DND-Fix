# Engine fix design and status

## What the tree does today

### The kill switch

Entire non-Cocoa policy is in `Source/WebCore/dom/DataTransfer.h`:

```cpp
bool allowsFileAccess() const
{
#if PLATFORM(COCOA)
 return !forDrag() || forFileDrag();
#else
 // Check https://webkit.org/b/271957 before allowing file access for your port.
 return false;
#endif
}
```

Cocoa keeps the origin-aware path (`forFileDrag()`). Everyone else, including WebKitGTK and WPE, hard-returns `false`. The comment is a breadcrumb, not a roadmap.

`forDrag()` is true when type is `DragAndDropData` or `DragAndDropFiles`. `forFileDrag()` is true only for `DragAndDropFiles`.

So Cocoa policy in plain language:

- Copy/paste (not a drag): allow file access
- Drag that is not a file drag: deny file access
- File drag: allow file access

Non-Cocoa after the workaround: always deny, including copy/paste paths that go through the same helper.

### Who calls allowsFileAccess

In `Source/WebCore/dom/DataTransfer.cpp`:

- `types()`: can hide the `"Files"` type when `!allowsFileAccess()`
- `filesFromPasteboardAndItemList()`: only reads pasteboard files into `File` objects when `allowsFileAccess()` is true

So with the hard `return false`, the page does not get `dataTransfer.files` populated from pasteboard file paths, and may not even see `"Files"` in `types` depending on mode.

### How createForDrop decides file vs data drag

```cpp
// DataTransfer.cpp
createForDrop(..., bool draggingFiles)
// uses draggingFiles ? Type::DragAndDropFiles : Type::DragAndDropData
```

`draggingFiles` comes from `DragData::containsFiles()` in `DragController` when performing / updating drops.

### GTK DragData::containsFiles

`Source/WebCore/platform/glib/DragDataGLib.cpp`:

```cpp
bool DragData::containsFiles() const
{
 return !m_disallowFileAccess && m_platformDragData->hasFilenames();
}
```

Filenames live on `SelectionData` (`m_filenames`). `disallowFileAccess()` can clear the effective file view. `DragController::disallowFileAccessIfNeeded` only calls that when `!canDropCurrentlyDraggedImageAsFile()` (cross-origin image drag restriction). It is not a general "this drag was started by web content" gate.

### The actual GTK bug shape (why Cocoa is fine and we are not)

`SelectionData::setURIList()` in `Source/WebCore/platform/glib/SelectionData.cpp` parses every line of a uri-list. For each valid URL it runs `g_filename_from_uri`. If that succeeds, it appends to `m_filenames`.

So any `file://` URI that lands in a uri-list becomes a "filename" and therefore a candidate for `containsFiles()` / `forFileDrag()` / pasteboard file reads.

Web content can put those URIs there. `Pasteboard::writeString` for `text/uri-list` (and `Files` mapped the same) calls `m_selectionData->setURIList(data)` (`PasteboardGLib.cpp`). That is the JS `dataTransfer.setData("text/uri-list", "file:///...")` path on dragstart.

DropTarget also ends up calling `setURIList` for external drops. Legitimate Files/Nautilus drops and malicious page-synthesized file URLs share the same promotion path from URI string to filename list.

Cocoa does not work that way. Real file access rides OS pasteboard file types / file promises (`NSFilenamesPboardType`, legacy files promise, etc.), not "any file:// string in text/uri-list." There is even a Cocoa-oriented layout test `LayoutTests/http/tests/security/dataTransfer-set-data-file-url.html` that checks `setData('URL', 'file:///etc/passwd')` does not put `NSFilenamesPboardType` on the drag pasteboard for non-local pages.

GTK DragSource (`DragSourceGtk4.cpp`) exports web selection data as `text/html`, `text/uri-list`, `_NETSCAPE_URL`, pixbuf, string, smartpaste, and custom pasteboard data. It does not export `GDK_TYPE_FILE_LIST`. That is useful: a web-originated drag is not a GdkFileList provider. External file managers often are (and portal transfer uses that path).

### Drop path on GTK4 (DropTargetGtk4.cpp)

- Registers formats: `G_TYPE_STRING`, `GDK_TYPE_FILE_LIST`, `text/html`, `text/uri-list`, `_NETSCAPE_URL`, smartpaste, custom pasteboard type.
- Accepts COPY | MOVE | LINK.
- On accept, async-reads matching types.
- Portal MIME types: `application/vnd.portal.filetransfer`, legacy `application/vnd.portal.files`. When present, reads `GDK_TYPE_FILE_LIST` and builds URIs from `GFile`s into `m_uriListBuilder`. Also skips bare `file://` lines from `text/uri-list` when portal transfer already happened (sandbox-friendly).
- When all reads finish, `setURIList` on the built string (which promotes file:// to filenames again).
- Builds `DragData(&selectionData, ...)` and calls `page->dragEntered` / `dragUpdated` / `dragExited` / `performDragOperation`.
- Does not set `DragApplicationFlags::IsSource`.
- Does not call `gdk_drop_get_drag()` to detect in-app / local drags (GTK can return the local `GdkDrag` when the drag is in-process).

### Drop path on GTK3 (DropTargetGtk3.cpp)

- Classic `gtk_drag_dest_*` + `gtk_drag_get_data`.
- Targets include text, html, uri-list, netscape url, smartpaste, custom.
- URI list received via `setURIList` directly (filename promotion included).
- On drop, may set `DragApplicationFlags::IsCopyKeyDown` if selected action is COPY. Still no `IsSource`.

### Drag start path on GTK4 (DragSourceGtk4.cpp)

- `gdk_drag_begin` with a union of content providers from current `SelectionData`.
- Exports uri-list bytes if `hasURIList()`.
- No file-list provider, as noted above.

### Paste is collateral damage

The GTK expected result added by the disable commit, `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt`, shows:

```text
FAIL event.clipboardData.types.includes("Files") should be true. Was false.
```

Other asserts (no file URL leakage via getData) still PASS. So the broad `allowsFileAccess() == false` also strips `"Files"` from paste clipboardData types on GTK. File picker paths are separate and fine. Paste-of-files / paste-image Files typing is not.

`PasteboardGLib::fileContentState()` returns `MayContainFilePaths` when selection filenames are non-empty, or when clipboard types include `text/uri-list` with file paths from the strategy, or when an image MIME type is present. Without `allowsFileAccess()`, that state does not turn into `dataTransfer.files`.

### Cocoa signals we do not set on GTK

macOS UIProcess sets `DragApplicationFlags::IsSource` when the drag originated in the same view (`applicationFlagsForDrag` in `WebViewImpl.mm` / legacy WebView). That flag is used at least when deciding how to handle file promises vs web archive self-drags.

GTK DropTarget almost never populates `DragApplicationFlags` beyond optional copy-key on GTK3. There is no IsSource plumbing on the GTK drop path today.

`disallowFileAccessIfNeeded` is about dragged image origin vs drop document origin (`canDropCurrentlyDraggedImageAsFile`), not "was this drag started by script with file URLs."

### Related WPE work (not the fix)

There is WPE work to route drag-and-drop through the same GLib SelectionData IPC path as GTK (bug 319275, PR traffic around WebKit/WebKit#69280 / #69326). That shares the SelectionData model. It does not restore `allowsFileAccess`. Any real fix should keep WPE in mind because the kill switch is all non-Cocoa, and WPE is on the same SelectionData/filename machinery.

### Layout tests that matter for a fix

Security / behavior references in tree:

- `LayoutTests/http/tests/security/dataTransfer-set-data-file-url.html` (Cocoa pasteboard filenames must not appear from setData of file URL on non-local pages)
- `LayoutTests/http/tests/security/drag-drop-local-file.html` (drag file:// link into iframe)
- `LayoutTests/http/tests/security/pasteboard-file-url.html`
- `LayoutTests/http/tests/security/file-system-access-via-dataTransfer.html`
- `LayoutTests/editing/pasteboard/drag-drop-href-as-url.html` (file:// href should not round-trip as usable uri-list the way https does)
- GTK expected FAIL for Files on paste-image after the workaround (see above)

A proper fix needs automated coverage that:

1. Page-synthesized `file://` in drag data does not yield readable `dataTransfer.files` contents
2. External / trusted file list drops do yield `dataTransfer.files`
3. Paste image / Files typing is not left broken if we only meant to lock down drags

---


## Fix direction (design)

Do not just flip `allowsFileAccess()` back to the Cocoa expression for all ports. That reopens the CVE on GTK because filename promotion from web-written uri-lists is still wrong.

Need origin-aware file grants on the GLib port, then restore access.

### Trust boundary that matches Cocoa's idea

"Filenames that grant content access" must only come from user/OS file drag surfaces, not from script-writable string types.

Concrete GTK4-shaped approach:

1. Stop treating every `file://` in any uri-list as a content-granting filename when the uri-list was written by web content.
 - `Pasteboard::writeString` / drag-start SelectionData path: set URI list text without calling the filename extraction side of `setURIList`, or add an explicit API like `setURIListWithoutFilenames` vs `setURIListFromExternalFileDrop`.
2. DropTarget external path: still populate filenames from trusted sources:
 - Prefer `GDK_TYPE_FILE_LIST` / portal transfer (already implemented).
 - For non-portal environments where the file manager only sends `text/uri-list`, still allow filename extraction on the DropTarget receive path (user is dragging in from outside). That is the X11 / classic host case.
3. Defense in depth on DragSource export: web-originated drags should not export a content provider that other WebKit instances will treat as a trusted file list. Today they export `text/uri-list` only, not GdkFileList. If receivers only trust GdkFileList + DropTarget-side uri-list from non-web sources, cross-process web→web file theft gets harder. Sanitizing `file://` out of exported uri-list from web content matches HTML/security test expectations around file URL drag data.
4. Optional: set `DragApplicationFlags::IsSource` when `gdk_drop_get_drag()` is non-null and belongs to our DragSource (local in-app drag). Use as an extra deny on filenames if any slipped through. Not sufficient alone (cross-process web→web would not look local).
5. After the GLib SelectionData/filename trust boundary is fixed, restore `allowsFileAccess()` for GTK (and likely WPE) to the Cocoa logic: `return !forDrag() || forFileDrag();` or an equivalent that still allows non-drag paste file access.
6. Re-read private bug 271957 before landing. The code comment is not ceremonial. If we cannot see 271957, coordinate with mcatanzaro / WebKit security rather than guessing from the blog alone.
7. Tests: MiniBrowser/GNOME Web manual repro for Files → page upload; layout/API tests for web-synthesized file URL drag must not populate files; external drop must; paste Files typing regression from the workaround expected.txt should be revisited.

### What not to do

- Do not invent a new permission dialog for ordinary external file drops. Match the HTML DnD contract and Cocoa's trust idea.
- Do not re-enable `allowsFileAccess` with a one-line `#else` flip and call it done.
- Do not try to paper over the engine gap with JS injection or fake SelectFiles in an embedder.
- Do not chase Flatpak finish-args for this symptom.
- Do not claim Apple/Safari is broken; they are the reference for the safe policy.
- Do not file a noisy upstream bug that re-argues the CVE. File (or patch toward) "restore external file DnD on GTK/WPE without reintroducing 271957."

### Pre-PR posture

WebKit is review-heavy and committer-gated. For a security-adjacent behavior change on a port, the right shape is:

- Public bug on bugs.webkit.org describing the UX regression and the intended security property (link 303434 and reference 271957 without demanding private details in public)
- Or a GitHub PR against WebKit/WebKit with a clear commit message in WebKit style (bug URL, reviewer line, why)
- Talk to GTK port people (Catanzaro, Igalia reviewers who touched DropTarget/portal) before insisting on a design
- Expect EWS on gtk / gtk-wk2 / api-gtk / wpe bots

---


## Key file index (engine tree)

Kill switch and DataTransfer:

- `Source/WebCore/dom/DataTransfer.h` (`allowsFileAccess`, `forDrag`, `forFileDrag`, types)
- `Source/WebCore/dom/DataTransfer.cpp` (`createForDrop`, `filesFromPasteboardAndItemList`, `types`, `shouldSuppressGetAndSetDataToAvoidExposingFilePaths`)

Drag orchestration:

- `Source/WebCore/page/DragController.cpp` (`performDragOperation`, `dragEnteredOrUpdated`, `disallowFileAccessIfNeeded`, uses `dragData.containsFiles()`)
- `Source/WebCore/page/EventHandler.cpp` (`performDragAndDrop`, `canDropCurrentlyDraggedImageAsFile`)
- `Source/WebCore/platform/DragData.h` / `DragData.cpp` (`m_disallowFileAccess`, `DragApplicationFlags`)

GLib / GTK selection and pasteboard:

- `Source/WebCore/platform/glib/SelectionData.h`
- `Source/WebCore/platform/glib/SelectionData.cpp` (`setURIList` filename promotion via `g_filename_from_uri`)
- `Source/WebCore/platform/glib/PasteboardGLib.cpp` (`writeString` → setURIList, `fileContentState`, drag pasteboard create)
- `Source/WebCore/platform/glib/DragDataGLib.cpp` (`containsFiles`, `asFilenames`, URL file-protocol scrubbing in `asURL` when not converting filenames)

GTK UIProcess DnD:

- `Source/WebKit/UIProcess/API/gtk/DropTargetGtk4.cpp`
- `Source/WebKit/UIProcess/API/gtk/DropTargetGtk3.cpp`
- `Source/WebKit/UIProcess/API/gtk/DragSourceGtk4.cpp`
- `Source/WebKit/UIProcess/API/gtk/DragSourceGtk3.cpp`
- `Source/WebKit/WebProcess/WebCoreSupport/gtk/WebDragClientGtk.cpp`

Cocoa reference (safe policy / IsSource):

- `Source/WebKit/UIProcess/mac/WebViewImpl.mm` (`applicationFlagsForDrag`, `performDragOperation`, IsSource + file promises)
- Cocoa `allowsFileAccess` branch in `DataTransfer.h`

Workaround commit artifacts:

- PR https://github.com/WebKit/WebKit/pull/54735
- Commit `89838b9164a1dd3baa7053539cf93414977fb081` / 303828@main
- `LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt`

Portal / Flatpak history:

- Bug 212079, PR https://github.com/WebKit/WebKit/pull/25575

---


## Fix ideas (multiple), ranked

Constraint reminder: flipping `allowsFileAccess` without fixing the trust boundary reopens CVE-2025-13947. Every serious idea either keeps a gate or makes the gate safe to open.

Ranking key:

- Security confidence (does this re-close CWE-346?)
- Functional restore (external file drop works in Epiphany/MiniBrowser)
- Complexity / reviewability
- Backport friendliness
- GTK3/GTK4/WPE coverage

### Idea 0: Rejected non-fix

**Just make `allowsFileAccess()` return true on GTK, or copy the Cocoa condition blindly.**

- Complexity: trivial
- Security: fails. Reopens the CVE as soon as web-written `file://` uri-list promotes into filenames again.
- Rank: disqualified. Do not propose. Do not "try it locally" as a PR candidate.

### Idea 1 (recommended baseline): Split trusted filenames from web-written uri-list

**Core idea:** `SelectionData::setURIList` (or its callers) must not treat script-supplied URI strings as content-granting filesystem paths. Only UIProcess drop paths that received files from the OS/compositor/portal may populate the filenames vector used for `containsFiles` / `files()`.

Concrete shape (design level):

1. Add a way to set uri-list text for clipboard/drag interoperability without calling `g_filename_from_uri` into `m_filenames`, used by `PasteboardGLib::writeString` and any web-originated write.
2. Keep or add an explicit API path used by `DropTargetGtk3` / `DropTargetGtk4` when the drop provides real files (`GdkFileList`, portal files, or verified external uri-list from a non-local drag) that populates `m_filenames`.
3. Optionally strip or refuse filename promotion when the drag is local/web-originated (see Idea 3) as defense in depth.
4. Once filenames cannot be web-authored, restore non-Cocoa `allowsFileAccess()` to something Cocoa-like: allow when `forFileDrag()` (and paste if paste is proven safe under the same split).

Why this is the best default:

- Matches the actual bug class (origin validation on the data, not "all file drops are evil")
- Smallest conceptual change reviewers already hinted at ("isn't implemented properly")
- Backportable
- Works for GTK3 uri-list file managers and GTK4 portal lists if both DropTarget paths set filenames explicitly
- WPE can adopt the same SelectionData rules even if its UIProcess drop code differs

Risks / work:

- Must audit every `setURIList` caller
- Must not break plain uri-list navigation drags that are not file content grants
- Paste path needs an explicit decision: restore Files on paste only if paste cannot be fed attacker-chosen `file://` the same way
- Needs tests that web setData cannot create files; external drop can

Complexity: medium. Security confidence: high if the audit is complete. Rank: **1 / primary recommendation.**

### Idea 2: Grant files only from GdkFileList / portal (GTK4-hard line)

**Core idea:** Ignore uri-list `file://` for filename grants entirely. Only `GdkFileList` (and portal file transfers) populate filenames. Web uri-list writes become inert for `files()`.

Pros:

- Very clear trust boundary on modern GNOME
- Aligns with bug 212079 direction (portal-aware drops)
- Easy to explain in a commit message

Cons:

- GTK3 and classic X11 file managers that only offer text/uri-list may stay broken
- WPE/other may not have GdkFileList
- Might be too narrow for Catanzaro's "good default for normal users" if many still live on uri-list-only paths
- Still need Idea 1's write-side fix if any uri-list promotion remains elsewhere

Complexity: medium-low for GTK4-only, high if we still need GTK3 parity via a second path. Security confidence: high on the GTK4 portal path. Rank: **2 / strong hardening layer**, best combined with Idea 1 rather than alone if we care about GTK3/file-manager uri-list.

### Idea 3: Drag source origin flags (IsSource / local drag detection)

**Core idea:** Thread `DragData::IsSource` (or GDK local-drag checks: drop has a source drag in-process) so same-WebView or same-process web drags never get `allowsFileAccess`, while external drags do.

Pros:

- Matches CWE-346 wording ("origin validation") literally
- Cocoa already has IsSource in the enum space
- Good defense in depth

Cons:

- GTK almost never sets IsSource today; needs careful UIProcess plumbing on GTK3 and GTK4
- Alone it is insufficient if an external-looking path can still be poisoned (depending on compositor) or if paste is in scope
- Easy to get wrong with nested web views, middle-button paste, or synthetic events in tests
- Reviewers may not trust origin flags without the SelectionData split

Complexity: medium-high. Security confidence: medium alone, high as belt-and-suspenders on Idea 1. Rank: **3 / secondary control**, implement with or immediately after Idea 1, not instead of it.

### Idea 4: Sanitize web drag exports (DragSource path)

**Core idea:** When WebKit is the drag source, never export filenames / file content offers derived from page-supplied uri-list. Export text/uri-list as text only, or drop file targets from the source side.

Pros:

- Stops the page from presenting a fake file drag to other apps too (host integrity / confused deputy outward)
- Defense in depth relative to drop-side CVE

Cons:

- Does not by itself restore inbound external file drops
- Does not justify opening `allowsFileAccess` without Idea 1
- Outbound behavior change may affect niche site→file-manager flows

Complexity: low-medium. Security confidence: helpful but incomplete. Rank: **4 / complementary hardening**, nice follow-up commit or same PR if tiny.

### Idea 5: Per-path sandbox extensions / UIProcess allowlist

**Core idea:** UIProcess decides exactly which paths are readable for a given drop, mints something like Cocoa sandbox extensions or a WebKitGTK-internal allowlist, WebProcess can only materialize `File` for those inodes/paths.

Pros:

- Architecturally closest to "real" browser file grants
- Good long-term story

Cons:

- Large design, multi-process IPC, permission lifetime, revoke on drag end
- Not backport friendly
- Far more than needed to fix 13947's specific GLib promotion bug
- Will not land as a first PR from an outside contributor

Complexity: very high. Security confidence: high if finished. Rank: **5 / long-term architecture**, not the first patch.

### Idea 6: Site-bound user gesture + picker fallback

**Core idea:** If drag files are unavailable, show a file chooser or only accept drops after an explicit permission prompt.

Pros:

- Product-level mitigation for apps we control

Cons:

- Not an upstream WebKit fix for DataTransfer parity
- Against "do not put app workarounds in the engine PR"
- Does not restore HTML5 drop semantics

Complexity: app-side medium. Rank: **rejected for upstream**, emergency app UX only if engine fix stalls.

### Recommended stack to propose when we implement

Primary: **Idea 1** (stop web-authored filename promotion; trusted DropTarget sets filenames; then restore gated `allowsFileAccess` for file drags).

Add if cheap in the same diff: **Idea 4** outbound sanitize + **Idea 3** local-drag/IsSource deny.

Use **Idea 2** as the GTK4 DropTarget implementation detail inside Idea 1 (portal/GdkFileList is already the preferred trusted source; uri-list promotion only when the drop is external and portal list absent, if we still support that).

Do not lead with Idea 5.

### Ordering of work inside the primary fix

1. Write failing tests (web setData file:// must not yield `dataTransfer.files`; if automation cannot do real OS drop, split API test vs manual).
2. SelectionData / PasteboardGLib write path stop promoting.
3. DropTarget GTK3/GTK4 explicit trusted filename set.
4. DragSource sanitize if needed.
5. Flip non-Cocoa `allowsFileAccess` to the narrow safe condition.
6. Update GTK expected results that 54735 marked FAIL if behavior returns.
7. WPE build + smoke reasoning.
8. Style, commit message, public bug.

---


### Implementation status on `gtk-dnd-file-access-reenable`

The recommended stack is landed as four stacked commits (bottom to tip):

1. **Idea 1 core** - Stop promoting web-authored uri-list into drag filenames; DropTarget trusted setFilenames*; API tests; `allowsFileAccess` still false in that commit alone.
2. **Idea 1 restore** - `allowsFileAccess` -> `forFileDrag()` on GTK/WPE only; paste stays gated.
3. **Idea 2 polish** - Prefer portal GdkFileList over uri-list for drop filenames on GTK4.
4. **Ideas 3+4** - IsSource deny + DragSource export sanitize.

In-tree tests: `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp`.

Still true: never flip the restore without the trust split. Paste Files on GTK stays gated until clipboard uri-list→path is audited. Cocoa untouched. No personal app names in engine commits. Public bug reference while iterating: 303434; file a dedicated restore bug before upstream PR if reviewers want a clean number.



## How Catanzaro would approach a real fix (inferred playbook)

This is inference labeled as inference, grounded in blog + commit + PR habits + his other security posts (Flatpak/Yelp escape, Evince single-click, GNOME security tracking).

### Timebox and triage pattern

1. Confirm severity and user impact in plain language (blog style).
2. Check whether Apple/Cocoa is already safe (he did; leave Cocoa alone).
3. Attempt a proper origin-aware fix quickly.
4. If the proper fix is not obviously correct under time pressure, ship a broad safe disable + public honesty that it is overly broad.
5. Backport to stable. Move on. Leave a Bugzilla trail (271957 / 303434) for later.

We are living in step "later." He will not be offended by a proper fix. He will be offended by a proper-looking fix that is wrong.

### What he likely tried in those two afternoons (hypothesis ranked)

Not claims of private knowledge. Best-fit guesses for what a GLib/WebKitGTK security engineer tries first when the bug is "web drag source gets file contents":

**Attempt A: Gate `allowsFileAccess` or `files()` on "this drag is a file drag from outside."**

- Flip or specialize the non-Cocoa branch toward Cocoa's `!forDrag() || forFileDrag()`.
- Discover that on GTK, `forFileDrag()` / `createForDrop(draggingFiles=true)` is driven by `containsFiles()` which is driven by `m_filenames` which is driven by **any** `setURIList` with `file://`, including web `setData`.
- Result: either external drops still work and the CVE still reproduces, or you break something subtle and still do not have a clean origin bit. Matches "attempts failed."

**Attempt B: Stop promoting `file://` to filenames in `SelectionData::setURIList` entirely.**

- One-line conceptual fix at the poison well.
- Immediately collides with DropTarget paths that rely on uri-list → filenames for classic file manager drops (especially GTK3, and GTK4 when portal list is absent).
- Portal path (GdkFileList) might still work on new GNOME; older paths break. Two-afternoon testing matrix (Wayland portal, X11, GTK3, GTK4, Nautilus, Files) is exactly where this dies without a second trusted entry point for filenames.

**Attempt C: UIProcess local-drag / `gdk_drop_get_drag` / IsSource.**

- Deny file access when the drop's source drag is in-process (web-initiated).
- Sound against same-WebView self-drags.
- Weaker or awkward for: synthetic tests, cross-widget cases, paste, or any path where filenames were already baked into SelectionData before the drop flag is consulted.
- GTK plumbing for IsSource is sparse today; two afternoons may not finish UIProcess threading + tests.

**Attempt D: DragSource export sanitization only.**

- Stop offering file contents on the way out.
- Does not fully match his stated bug (drop target reading contents for attacker-chosen paths on the **page's** dataTransfer), and does not restore inbound external drops if you still leave `allowsFileAccess` false.
- Incomplete alone.

**Attempt E: Something Cocoa-like with separate pasteboard types for filenames.**

- Right long-term architecture (Idea 5 family).
- Far too large for two afternoons and for a stable backport during an embargo/advisory cycle.

Most likely outcome of A-D under timebox: each either reopens the hole, breaks external DnD, or needs more port matrix than the advisory calendar allows. Hence blunt `return false` plus blog apology.

### How he would want the eventual fix to look

Match his blog success criteria literally in the commit message:

- "Websites may attach file URLs to drag sources" → still possible as strings if required by HTML, but
- "should not receive file access" → `files()` / File blobs stay empty for that case
- "only the user... dragging the file from an external application" → DropTarget-trusted paths populate filenames and `allowsFileAccess` allows contents

Coding style he will accept:

- Small, boring C++ in existing files (`SelectionData`, `PasteboardGLib`, DropTarget, maybe DragSource, then `DataTransfer.h`)
- No new public WebKitGTK API unless unavoidable
- GRefPtr / modern GLib patterns consistent with neighbors
- Test expectation updates with a one-line why (he waited on gtk-wk2 for exactly that class of change)
- Prefer cherry-pick-shaped commits for webkitglib stables
- English that sounds like his blog, not a vendor whitepaper

Coding style he will bounce:

- Clever framework rewrite
- "Trust the site with a permission prompt" as the engine fix
- Touching Cocoa "for consistency"
- Re-enabling contents without proving web setData cannot populate filenames
- Giant mixed commit that also reformats DragController

### Catanzaro review of our Ideas 1-4 (predicted)

**Idea 1 (split web uri-list from trusted filenames; then restore gated allowsFileAccess):** 
This is the fix he described in the blog. He will like it if the audit of `setURIList` callers is complete and DropTarget still grants real user files. He will ask: paste? GTK3 uri-list-only? WPE?

**Idea 2 (GdkFileList/portal-only grants on GTK4):** 
He already lives in portal/Flatpak reality (Yelp escape posts, runtime fixes). He will like portal as the **preferred** trusted channel. He will push back if GTK3/classic uri-list external drops stay broken without a story, because Epiphany on older paths still matters for downstream. Best as implementation detail inside Idea 1, not as "GTK4 only forever."

**Idea 3 (IsSource / local drag deny):** 
Aligns with CWE-346 and his "drag sources created by websites" framing. He will treat it as good defense in depth, maybe insufficient alone (he may have tried something like it). Wanted if cheap and tested; not a substitute for Idea 1.

**Idea 4 (DragSource export sanitize):** 
Matches "websites should not receive file access" from the other direction (do not offer fake file drags to the world). Small and on-brand. Secondary.

**Ideas 0 and 5:** reject / later, as already ranked.

### What if we do Ideas 1 through 4 together?

That is the full defense-in-depth package:

- **Idea 1:** Remove the poison well; restore contents only when filenames are trustworthy
- **Idea 2:** Prefer OS/portal file lists as the trusted filename source on GTK4
- **Idea 3:** Deny content grant when drag origin is in-process web source
- **Idea 4:** Do not export attacker-shaped file offers from WebKit-as-drag-source

**Pros of doing all four**

- Matches his stated model from multiple angles (data path, GTK4 host path, origin flag, export path)
- Survives a reviewer asking "what if setURIList is called from a path you missed?"
- Survives portal-present and portal-absent drops if Idea 1 keeps a careful external uri-list path
- Better story for "did you reopen 271957?" because the answer is layered controls, not one boolean
- Closer to Cocoa's separation of script strings vs OS filename types, without copying Cocoa APIs

**Cons of doing all four in one blob**

- Diff size and cognitive load up; Catanzaro prefers boring minimal security diffs for land/backport
- Harder to bisect which layer fixed or broke gtk-wk2
- Easier for a reviewer to stall on the most controversial sub-piece (often IsSource plumbing)
- Four behaviors need four test stories

**Recommended packaging if we do 1-4**

Not one unstructured dump. Prefer a **stacked sequence** on one branch / one Bugzilla, reviewable as:

1. **Commit A - Idea 1 core:** SelectionData/Pasteboard write does not promote web uri-list to filenames; DropTarget trusted path sets filenames explicitly; unit tests for promotion rules. Keep `allowsFileAccess` false still. (Safe intermediate: no CVE reopen, DnD still broken for contents.)
2. **Commit B - Idea 1 restore:** non-Cocoa `allowsFileAccess` → Cocoa-like `!forDrag() || forFileDrag()` (or equivalent); update GTK expectations; manual external drop now works.
3. **Commit C - Idea 2 polish:** GTK4 DropTarget prioritizes GdkFileList/portal; document uri-list fallback rules.
4. **Commit D - Idea 3 + 4:** IsSource/local-drag deny + DragSource export sanitize.

Commits A then B are the minimum viable restore. C and D can be same PR if still small, or a fast follow. Selling point to Catanzaro: A is the fix he ran out of time to finish; B is safe only because of A; C/D are belts.

Alternative he might accept: single commit that is still small if Idea 3/4 are tiny helpers next to A+B. Decision after we see line counts. Default bias: **two commits minimum (gate fix, then re-enable)** so revert of B without revert of A remains possible on stable.

**Risk if we only ship B without A:** CVE returns. Never.

**Risk if we ship A without B:** security good, feature still dead. Good emergency intermediate; not our end goal.

**Risk if we ship 1-4 half-tested:** he waits on gtk-wk2, finds expectation rot, loses confidence. Test plan below must cover each layer.

---


## Updated recommendation snapshot

- Catanzaro already defined success: web drag sources do not get file access; user external file drags do; URL lists may remain; dialogs never were the bug.
- He timeboxed, failed to land the narrow fix, shipped broad disable, documented honesty.
- Our Idea 1 is his intended fix. Ideas 2-4 are how serious GTK ports keep it true under portal and origin edge cases.
- Prefer stacked commits if we do 1-4; never re-enable without the data-path split.
- Consider PLATFORM(GTK)/WPE-scoped allowsFileAccess restore first if Win is unknown.
- Tooling: stock Tools/gtk/install-dependencies → update-webkitgtk-libs → build-webkit --gtk --debug → MiniBrowser + targeted tests.
- Sources: his blog, WSA, in-tree GLib/Cocoa drag code, security policy, downstream trackers, portal/GTK docs.

Research status: deeper Catanzaro intent, resource map, combined 1-4 plan, and tooling install runbook appended. Still no code fix and no PR.


---






## Status snapshot

- CVE/GHSA/WSA public surface documented without 271957 access
- Downstream matrix: shipped 2.50.3 broad disable; no public surgical restore found before our work
- Catanzaro and aperezdc fully profiled (role, review habits, blog success criteria, inferred attempt playbook labeled as inference)
- WebKit process, coding style, credibility checklists, engagement channels preserved above
- Fix ideas ranked; Ideas 1-4 implemented as stacked commits on `gtk-dnd-file-access-reenable` branch on fork right now
- Private CI, builder image, cost controls, validation Releases: this repo
- GNOME Web AppImage validation path: planned in CI (full install + GNOME Web pack); unit TestWebCore path remains the cheap gate
- Public Bugzilla + upstream WebKit PR: not filed yet

---


## Open questions (answered with current evidence)

These were parked earlier. Answers below are research-backed defaults for the restore work. Alternatives noted where a reviewer might push.

### GTK4 portal-only filenames vs classic uri-list too

**Answer:** Keep both. Prefer GdkFileList/portal when present (Idea 2). When portal list is absent, allow DropTarget to set trusted filenames from an **external** uri-list file drop (Idea 1 DropTarget path), never from web-authored `setURIList` / pasteboard write.

**Why:** Catanzaro ships and validations across Fedora/Epiphany paths that are not portal-only forever. GTK3 and some X11/file-manager combos still offer `text/uri-list` without `GdkFileList`. A GTK4-hard-line-only restore would strand those users and invite a "works on my GNOME" review stall.

**Alternative:** GTK4-portal-only as a first land on main with GTK3 follow-up. Faster story on modern GNOME, weaker backport narrative for classic uri-list hosts. Only take this if a reviewer demands a smaller first diff.

### Must WPE ship in the same change?

**Answer:** Yes for shared WebCore/GLib bits (`SelectionData`, non-Cocoa `allowsFileAccess`, DragDataGLib). The kill switch is all non-Cocoa. aperezdc and WPE bots will compile the shared headers anyway.

**UIProcess:** WPE may not have the same GDK DropTarget/DragSource surfaces. Compile shared code; do not invent fake WPE DnD UX in the first PR. Note compile-only WPE coverage in the commit message when UIProcess is GTK-only.

**Alternative:** GTK-only ifdef maze to avoid WPE. Rejected. That fights the existing non-Cocoa layout and annoys the WPE maintainer who already reviewed 54735.

### Public Bugzilla now vs draft PR first?

**Answer:** File a public bugs.webkit.org bug **before** the upstream PR. WebKit norms are bug-first for durable decisions. Link 303434 and 271957 by number. Describe restore of external file DnD without reopening the CVE. Then open the PR with `Bugzilla: NNNNNN` / full commit message.

**Alternative:** Draft PR on the fork only to get early smoke. Fine as private prep; not a substitute for the public bug when asking mcatanzaro/aperezdc for review.

### Minimal manual repro page

**Answer:** Already covered by `html/` in this repo (layer pages logging types/files). For Bugzilla, link a minimal single-file HTML drop sink (types, `files.length`, file name/size) that MiniBrowser can open. Do not attach exploit polish.

### Exact paste scope of 271957

**Answer:** Unknown without 271957 access. **Default:** leave paste Files gated on GTK/WPE (`allowsFileAccess` only for `forFileDrag()`). Clipboard uri-list→path on GTK3 is a second poison well.

**Alternative:** Restore paste too if a security reviewer with 271957 access confirms paste was out of scope and our write-side split makes paste safe. Do not guess that in the first land.

### Can GTK EWS run real file drops?

**Answer:** Treat EWS as **SelectionData/API + layout expectation** coverage, not Nautilus. GTK EventSenderProxy is mouse-heavy; no official "drag from Files" on bots. That is why Idea 1 put business logic tests on `SelectionData` unit tests. Manual MiniBrowser/GNOME Web matrix stays required and should be stated honestly in the bug.

**Alternative:** Invest in a GTK DragAndDropSimulator peer to Cocoa helpers. Valuable long-term; too large to block the restore.

### Pointing Epiphany at a prefix WebKitGTK

**Answer:** For reviewers and local spikes, MiniBrowser from the build tree is still the cheapest engine validation. System Epiphany against a prefix is awkward (rpath/loader, Flatpak vs RPM).

**validation path we are building:** a self-contained **GNOME Web (Epiphany) AppImage** for Fedora 44+, linked against our patched WebKitGTK install prefix, published on validation Releases alongside logs and the HTML harness. That gives a real browser shell without asking anyone to jhbuild. See Validation / AppImage section below.

**Alternative:** jhbuild/prefix install documented in the bug for reviewers who want a system-layout tree specifically.

### One commit vs stacked commits

**Answer:** Prefer the **stacked sequence already on the branch** (trust split → allowsFileAccess restore → portal preference → IsSource/export). Matches Catanzaro backport/bisect habits: restore commit can revert without reverting the gate. Four commits is OK if each is small; minimum two (gate fix, then re-enable).

**Alternative:** Single commit if the final diff is tiny and a reviewer asks to squash. Do not squash away the ability to revert B without A on stable unless they insist.

---



## IPC filenames hole (from Opus second opinion, equal weight)

`SelectionData.serialization.in` does not carry `filenames`. UIProcess grants die on the hop to the web process. CVE path stays closed; trusted drop re-enable does not work until we serialize `Vector<String> filenames()` and decode via `setFilenames` only.

See `findings/opus-second-opinion.md` for the full synthesis and required tests.

## Build fix: WTFMove include

`SelectionData.cpp` needs `#include <wtf/StdLibExtras.h>` so `WTFMove` in `setFilenames` / URI list helpers compiles under the unified sources build. Landed on the fork after unit run 31242490849 failed on that error.


## Engine tip notes

- `17647b75df` - serialize `filenames` over IPC; `WTF::move` style; IPC constructor API test
- Prior `96b0229725` StdLibExtras include is superseded in spirit by `WTF::move` (left in history)
