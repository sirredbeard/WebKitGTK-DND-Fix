# Opus second opinion and our synthesis

Equal weight with the Grok-side analysis. Opus reviewed only the engine fix (not CI). Full review text is below the synthesis. We do not claim ours is better. We do not throw ours out. We fold hard blockers into commits and tests.

## Status vs Opus (honest scorecard)

Short answer: **hard blockers and the export/async gaps Opus called required are addressed in engine code. Not everything is closed.** Positive direction items we already shared. Several should-haves and residual risks stay open on purpose or wait on E2E proof. **Do not upstream yet.**

Engine tip on `gtk-dnd-file-access-reenable`: `2b70a3d087` (clipboard sanitize + pending drop) on top of `17647b75df` (filenames IPC) and the earlier four-layer stack through `a85db85942`.

### Positive feedback we kept (agree and ship direction)

- Trust split is the right CVE-class fix: web uri-list must not fill `m_filenames`; UIProcess trusted drops may.
- Cocoa untouched; paste Files stay off until clipboard grant design exists.
- Portal-prefer on GTK4 is the right non-widening rule.
- DragSource export sanitize is load-bearing.
- Unit tests necessary, not sufficient; real GTK drops still required.
- Do not re-enable promotion inside `setURIList` as a shortcut.
- Leaving paste disabled for this series is the right call.

### Negative / hard blockers — addressed in tree

- **B1 / H1 IPC filenames omission** — **done** in `17647b75df`. `SelectionData.serialization.in` carries `Vector<String> filenames()`. Decode constructor calls `setFilenames` after uri-list; no promotion on decode. Unit: `IpcConstructorPreservesFilenamesWithoutURIListPromotion`, `TrustedDropShapeAfterIpcRoundTrip`.
- **E1 / H4 clipboard write still exported raw file:// uri-list** — **done** in `2b70a3d087`. GTK3/GTK4 `Clipboard::write` route URIList through `uriListWithoutFilenames`.
- **B5 / H5 GTK4 drop races async load** — **done** in `2b70a3d087`. `m_pendingDrop` defers `drop()` while `m_cancellable` is live; finishes from `didLoadData`.
- **Must-have unit: portal not widened by hostile uri-list** — **done**. `PortalFilenamesNotWidenedByHostileURIList`.
- **Must-have unit: export sanitize / uri-list without filenames** — **done**.
- **Must-have: serialization.in includes filenames** — **done** (compile-time contract + unit mirror).
- **H8 messaging** — we still do not claim "DnD restored" without E2E green and we are not upstreaming yet.

### Gaps still open (not fully addressed)

Product / proof (Opus must-have before upstream):

- **E2E GTK4 file-manager drop → `dataTransfer.files.length >= 1` and readable blob** — automation + nested suite exist; **not green yet** on the Python-reloc AppImage (build `31249460890` still in flight; prior nested run was INCONCLUSIVE on migrator abort).
- **E2E web attack: page sets file:// uri-list → drop → files empty** — same; suite cases exist; need PASS under fixed image + stack logs.
- **Maintainer bar (S1/S2/S3 + F1)** — enforced in CI wiring; not yet proven PASS.

Should-have / polish Opus called out (engine not fully done):

- **H2 IsSource still coarser than Cocoa** — **open**. Still any in-process `gdk_drop_get_drag` / any `gtk_drag_get_source_widget`. Same-app native file widget → WebView still over-denies. Unit documents deny for IsSource; no narrow-to-this-WebView change.
- **H3 single trusted grant API (`setTrustedFilenames` private/friend)** — **open**. Still public `setFilenames` / `setFilenamesFromURIList`. Policy is "only DropTarget should call"; not enforced by API shape.
- **H7 parallel `allowedFiles` on drag IPC instead of SelectionData** — **deferred** deliberately; filenames-on-SelectionData works with codegen; revisit only if upstream prefers clearer boundary.
- **GTK3 external drop E2E** — should-have; nested guest is GTK4/GNOME Web path first.
- **Same-WebView / cross-WebView E2E** — unit covers IsSource deny shape; full browser E2E not closed.
- **Same-app native→WebView product case** — documented over-deny; not fixed (needs H2).
- **Async drop E2E under load** — code path fixed; not yet proven in nested suite timing.
- **`file://127.0.0.1`, `FILE://`, mixed lists** — partial unit coverage via `filenamesFromURIList` / strip helpers; not a full matrix.
- **`getData('text/uri-list')` when files are granted** (path hiding / canExposeURL…) — residual string disclosure path; not fully tested against Chromium-ish hiding.
- **Layout/API `<input type=file>` drop with real paths** — not landed.
- **WPE file-drop parity** — **intentionally not claimed**; shared SelectionData/allowsFileAccess only.
- **Paste restore + editor `readFilePaths` audit** — **intentionally out of series** (Opus F: correct to leave off).
- **Path canonicalization / symlink / realpath** — **open residual**, pre-existing class; we do not pretend this series solves it.
- **Hostile external GdkFileList / portal MIME spoof** — **Med residual**, inherent desktop DnD trust; portal-prefer only stops uri-list *widening*.
- **Navigation / load of dropped `file://` via asURL** — out of File-API scope; not hardened here.
- **Markup/plain text still can carry path strings on export** — residual scrape surface; not File grant inside WebKit.

### Residual risk after current tip (updated)

- Web read local file via script uri-list → `dataTransfer.files`: **Low** (promotion gone; grants only from UIProcess filenames + IPC).
- Trusted drop product path: **code claims fixed (IPC + pending drop)**; **proof still pending E2E** → treat product confidence as **Med until nested/AppImage green**, not High.
- Web exfil via drag-out / clipboard write file://: **Low** after clipboard sanitize parity with DragSource (markup/text strings remain Low scrape).
- Confused deputy / hostile external file list: **Med** (unchanged class).
- Same-app native→WebView: **product gap** until IsSource narrowed.

### What "addressed" does not mean

- Opus did **not** review CI/packaging. Dual-runner, AppImage reloc, golden image, nested GUI are our work beyond the review.
- Unit green ≠ maintainer success. Catanzaro bar needs S1/S2/S3 security PASS and F1 product PASS under real stack.
- Findings `engine-fix.md` still has older narrative sections (pre-IsSource / pre-reenable history). Trust this scorecard + git tip over stale mid-doc snapshots when they disagree.

## What we agree on (both sides)

- Trust split is the right fix for the CVE class: web-authored `text/uri-list` must not fill `m_filenames`; trusted UIProcess drops may.
- Cocoa stays the reference. Leave it alone.
- Paste Files on GTK stays off until clipboard uri-list to path is audited (GTK3 especially).
- Portal-prefer on GTK4 is the right non-widening rule when a portal file list is present.
- DragSource export sanitize (no `file://` / no GdkFileList from web) is load-bearing.
- Unit tests on SelectionData are necessary and not sufficient. IPC and real GTK drops still have to pass.
- Do not re-enable promotion inside `setURIList` as a shortcut.

## Hard blocker Opus found — historical (now fixed in tree)

Was: `SelectionData.serialization.in` omitted `filenames`, so UIProcess grants died on IPC and trusted re-enable was a no-op.

Now: `17647b75df` serializes `Vector<String> filenames()` and decodes via `setFilenames` without uri-list re-promotion. Product still needs E2E proof before "works" messaging.

## Commit plan (updated)

Landed stack on the fork branch:

1. Stop uri-list promotion; trusted `setFilenames*`; DropTarget calls.
2. `allowsFileAccess` → `forFileDrag()` on GTK/WPE only (paste stays off).
3. GTK4 portal list owns filenames over parallel uri-list.
4. IsSource deny + DragSource export sanitize.
5. **IPC filenames** (`17647b75df`).
6. **Clipboard write sanitize + GTK4 pending drop** (`2b70a3d087`) + extra SelectionData units.

Still before upstream pitch:

- Green nested/AppImage E2E for F1 + S1 (and S2/S3 canaries).
- Decide whether to land H2 IsSource narrowing in the same series or document as known over-deny.
- Optional H3 API tightening if reviewers want friend/private grants.
- Human interactive QA still authoritative if automation stays INCONCLUSIVE.

## Other Opus points still on the board

- **IsSource is coarser than Cocoa** — still true in code; next engine touch candidate.
- **Path confusion** — pre-existing; document only.
- **WPE** — no DropTarget parity claim.
- **Parallel allowedFiles design** — deferred; filenames-on-SelectionData shipped.
- **Paste project** — separate series.

## Tests status vs Opus must/should list

Must-have:

1. IPC/decode filenames round trip — **unit done**; full process IPC via real drag still needs E2E.
2. E2E external drop files + blob — **pending** nested/AppImage green.
3. E2E web attack empty files — **pending** same.
4. Portal widen attempt — **unit done**; GTK4 runtime E2E nice-to-have.
5. serialization.in filenames — **done**.

Should-have: GTK3 external, same-WebView, native→WebView documented/fixed, export no file:// (unit + DragSource code done; clipboard write done), clipboard DOM paste empty (policy), async drop defined (code done, E2E pending).

Private CI: SelectionData + external validation fast gate. AppImage reloc rebuild in flight. Nested GUI on Azure after AppImage green.

## What we are not doing

- Not discarding the layered stack.
- Not re-opening paste Files in this pass.
- Not claiming WPE parity.
- Not upstreaming until E2E evidence exists on top of IPC.
- Not putting personal app names in engine commits or Bugzilla text.
- Not pretending path canonicalization or hostile native GdkFileList are solved.

---

## Full Opus review (verbatim, scrubbed only for markdown house style)


# Independent second opinion: GTK/WPE DnD file-access re-enable

**Scope:** security/correctness of commits `a7afbb6618`…`a85db85942` on `gtk-dnd-file-access-reenable` 
**Not reviewed:** CI, process, packaging 
**Verdict:** Directionally right trust split; **must not upstream as-is**. One IPC hole nullifies the re-enable and leaves a false sense of product fix. Several gating/export gaps remain.

---

## Architecture (as implemented)

- Channel: `SelectionData::m_uriList` / `m_url`; Role after patch: Web-writable strings (`setData` / drop text)
- Channel: `SelectionData::m_filenames`; Role after patch: Content-grant list for `dataTransfer.files` / `File`
- Channel: `DataTransfer::allowsFileAccess()`; Role after patch: GTK/WPE: only `Type::DragAndDropFiles` (`forFileDrag()`)
- Channel: `DragData::{containsFiles,asFilenames,numberOfFiles}`; Role after patch: Extra deny if `IsSource` or `m_disallowFileAccess`
- Channel: UIProcess DropTarget; Role after patch: Sole intended writer of `setFilenames*`
- Channel: DragSource export; Role after patch: Strip `file://` from uri-list; no `GdkFileList` from web

That split matches the stated policy. Enforcement is incomplete.

---

## A. Does this close the CVE-class hole?

**Mostly yes for the original mechanism; not a full proof of “web cannot get local File via DnD.”**

### Closed path (primary CVE class)

Pre-fix:

1. Script: `dataTransfer.setData("text/uri-list", "file:///etc/passwd")`
2. `PasteboardGLib::writeString` → `SelectionData::setURIList`
3. `setURIList` called `g_filename_from_uri` and filled **`m_filenames`**
4. Drop / same-document drag built `Pasteboard` from that `SelectionData`
5. `containsFiles()==true` → `DataTransfer::createForDrop(..., draggingFiles=true)` → `DragAndDropFiles`
6. `allowsFileAccess()` (after partial re-enable) + `Pasteboard::read(PasteboardFileReader)` → real `File` contents

Post-fix step 3 is gone: `setURIList` only updates uri-list text + primary URL. Unit test `SetURIListDoesNotPromoteFilenames` matches that.

Also:

- Web drag export no longer advertises stripped-empty-only-file uri-list / `_NETSCAPE_URL` file URLs / `GdkFileList` from `m_filenames`.
- In-process drop: `IsSource` forces `containsFiles()==false` even if filenames were somehow set.

So **script-authored uri-list → `m_filenames` → `dataTransfer.files` is closed** on the paths that used automatic promotion.

### Not closed by design (and still real)

- **Paste / clipboard** still intentionally off for `dataTransfer.files`, but GTK3 clipboard still maps uri-list → paths (see F).
- **String path disclosure** via `getData("text/uri-list")` / `URL` still returns `file://…` when those strings are present and `fileContentState` is not “has files” (see below). That is not full file read, but it is still path leakage for external drops and for web-authored strings (attacker already knows them).
- **Navigation / load of `file://`** still uses `DragData::asURL()` (default `ConvertFilenames`) and UIProcess `assumeReadAccessToBaseURL` when `dragData.asURL()` is `file:`. Separate from File API; not hardened here.

### Critical correctness failure (blocks “trusted drop works”)

`SelectionData.serialization.in` still has:

```text
text, markup, url, uriList, image, customData, canSmartReplace
```

**No `filenames`.**

GTK/WPE drag IPC:

```cpp
// WebPageProxy::performDragControllerAction (GTK||WPE)
send(..., *dragData.platformData(), dragData.flags());
// → Messages::WebPage::PerformDragControllerAction(..., SelectionData selection, flags)
```

Decode rebuilds via the constructor, which only calls `setURIList(uriList)` - and **`setURIList` no longer rehydrates filenames**.

- Era: Pre-fix; How web process got filenames: uri-list IPC + **re-promotion inside `setURIList`**
- Era: Post-fix; How web process got filenames: UIProcess sets `m_filenames`, **IPC drops them**, web process always empty

Effects:

1. External file-manager / portal drops: UIProcess may set filenames; **web process never sees them**.
2. `DragData::containsFiles()` in web process → false.
3. `createForDrop(..., draggingFiles=false)` → type `DragAndDropData`, not `DragAndDropFiles`.
4. `allowsFileAccess()` → false even for “trusted” drops.
5. Product goal “re-enable user file drops” **does not work**; only the disable half works.

This is not theoretical: the old security bug *depended* on decode-time re-promotion. Removing promotion without serializing `m_filenames` is an incomplete migration.

**A-summary:** CVE promotion hole is closed; trusted re-enable is currently non-functional over IPC; residual non-File paths remain.

---

## B. Remaining attack / confusion paths

### B1. IPC filenames omission (correctness; security side-effect)

Fail-closed for grants (good for CVE). Bad for apps. Also means tests in UIProcess/unit space can pass while browser DnD files stay dead.

### B2. Paste / clipboard (GTK3 high interest)

Unchanged by this series:

- `ClipboardGtk3::readFilePaths` → `gtk_clipboard_request_uris` → every `g_filename_from_uri` success becomes a path.
- `PasteboardGLib::fileContentState()` / `read(PasteboardFileReader)` still consult clipboard file paths when `m_selectionData` is null.
- **DOM `dataTransfer.files` on paste** gated off: `allowsFileAccess()` is `forFileDrag()` only → paste type is `CopyAndPaste` → false. Good for the File API surface.
- **Other consumers** of `Pasteboard::read(FileReader/WebContentReader)` (editor insert, etc.) are not re-audited here. Leaving paste disabled for DOM files is necessary until that stack is split the same way as DnD.

Clipboard **write** from web still exports raw `uriList()` including `file://` (no `uriListWithoutFilenames`). Drag-out was sanitized; **copy/paste-out was not**. Cross-app “here is a file path” via clipboard remains.

### B3. Same-app / cross-widget `IsSource`

```cpp
// GTK4: any local GdkDrag
if (gdk_drop_get_drag(drop)) flags.add(IsSource);
// GTK3: any source widget in this app
if (gtk_drag_get_source_widget(context)) flags.add(IsSource);
```

Cocoa sets `IsSource` only when `draggingSource == view` (same view), not every same-app source.

GTK meaning = “drag originated in this process/app”. Consequences:

- Scenario: WebView → same WebView; Result: Deny files (intended)
- Scenario: WebView A → WebView B, same process; Result: Deny files (usually intended)
- Scenario: Native file list widget → WebView, **same app**; Result: **Deny files** (product break; over-broad vs Cocoa)
- Scenario: Other process file manager → WebView; Result: Allow if filenames present (intended external trust)
- Scenario: Other process malicious native app advertising paths; Result: Treated as user grant (inherent DnD trust; portal path helps on GTK4 sandboxed)

`IsSource` is a useful second line after export sanitize, not a complete identity of “web origin.”

### B4. Portal vs hostile parallel uri-list (GTK4)

Intent is sound:

- Portal MIME scheduled first; `m_transferredFilesFromPortal = true` **synchronously** before async completes (avoids TOCTOU on the flag).
- uri-list handler skips `file://` lines when portal flag set.
- `didLoadData`: if `m_portalFilenames` non-empty, **only those** become filenames; else classic uri-list promotion.

Gaps:

- **GTK3:** no portal preference; any external uri-list file:// is a grant (classic X11/Wayland file managers). Acceptable for non-portal hosts; weak in sandboxed GTK3 if such builds exist.
- **Portal MIME spoof by external app:** a native app can offer portal-like types + `GdkFileList` with arbitrary native paths. That is “external drop trust,” not web script. Residual confused-deputy risk if compositor/portal doesn’t bind the list to a real user chooser.
- **Portal empty + uri-list stripped:** fail-closed (no files). Good.
- **No path canonicalization** (`g_filename_from_uri` only): symlinks, `/proc/self/root/…`, `file://127.0.0.1/etc/passwd` → `/etc/passwd` all become grants if trusted path runs. Pre-existing class of issues.

### B5. Async drop race (GTK4)

`enter`/`update` wait on `m_cancellable`; **`drop()` does not**. Early drop can run with partial `SelectionData`.

Security: fail-closed (often no filenames yet). 
Correctness: intermittent empty `dataTransfer.files` on fast drops. Pre-existing pattern; worse UX once filenames actually IPC.

### B6. Non-file schemes / custom MIME / buffers

- `filenamesFromURIList` only accepts `g_filename_from_uri` success → http(s), blob, data, smb, etc. do not become Files. Good.
- Custom pasteboard / `m_buffers` are not filename grants.
- Mapping `"Files"` type to uri-list in `selectionDataTypeFromHTMLClipboardType` is old weirdness; with no promotion, `setData("Files", fileURL)` cannot fill `m_filenames` anymore. Good.

### B7. Web → web drag without going through system DnD

In-process: `IsSource` + empty filenames after sanitize. 
Cross-process WebKit: source export must strip `file://`; destination treats as external. Export sanitize is load-bearing for cross-app web.

### B8. `setURL(file://…)`

Still sets `m_url` / may seed uri-list; does **not** set filenames. OK for File API. Still affects `asURL()` / possible load and string reads.

### B9. WPE

`allowsFileAccess` / `SelectionData` / `DragDataGLib` apply; no WPE DropTarget equivalent in this series. WPE stays “no file DnD grants” in practice. Fine if WPE has no UI drop path; don’t claim WPE file-drop parity.

---

## C. `IsSource` / `forFileDrag` gating

### `forFileDrag` / `allowsFileAccess`

```cpp
// GTK||WPE
return forFileDrag(); // Type::DragAndDropFiles only
```

- Paste: off. Correct given clipboard audit debt.
- Drop: on only when `draggingFiles == dragData.containsFiles()` at event creation.
- Because of **B1**, `containsFiles()` is false in web process → **gate never opens for real drops**.

Cocoa: `!forDrag() || forFileDrag()` (paste can see files). GTK deliberately stricter.

### `allowsFilenameAccess` / `IsSource`

Applied only in `DragDataGLib::{containsFiles,numberOfFiles,asFilenames}`. Good choke point **if** filenames exist in that process.

Missing:

- Does not distinguish “web SelectionData” vs “native same-app file widget.”
- Does not run in UIProcess before IPC (UIProcess isn’t where DOM File is built).
- No mirror check on pasteboard clipboard path (relies on `allowsFileAccess` false).

### Layering (defense in depth - intended vs actual)

- Layer: No promote in `setURIList`; Intended: Block web write→grant; Actual: **Works**
- Layer: Filenames only from DropTarget; Intended: Trust boundary; Actual: UIProcess only; **lost on IPC**
- Layer: `containsFiles` + `IsSource`; Intended: Deny in-app web recycle; Actual: Works when filenames present
- Layer: `allowsFileAccess` / `forFileDrag`; Intended: DOM File gate; Actual: Works in principle; **starved of containsFiles**
- Layer: Export sanitize; Intended: Stop cross-app web file bait; Actual: **DnD yes; clipboard no**

---

## D. Portal-prefer vs classic uri-list

**Sound design for GTK4** once filenames IPC exists:

1. Portal `GdkFileList` = grant set. 
2. Parallel uri-list cannot widen grants. 
3. Non-file uri-list lines can still appear as strings (OK). 
4. No portal → classic file manager uri-list promotion (needed for Nautilus etc.).

Suggested hardening (not blockers for the idea):

- Treat grant list as **ordered unique real paths**; optional `realpath`/existence check is policy-heavy - document “no symlink resolution” if you skip it.
- If portal MIME present but list empty, **do not** fall back to uri-list file:// (current code already avoids fallback when flag set and files stripped). Keep that invariant in a test.
- Consider requiring `g_file_is_native` (clipboard GTK4 readFilePaths already skips non-native; drop portal path uses `g_file_get_uri` + `g_filename_from_uri` and drops failures - OK).

GTK3 classic-only is an explicit platform limitation; document it.

---

## E. Export sanitize gaps

**Done well (DragSource GTK3/4):**

- uri-list run through `uriListWithoutFilenames`
- skip advertising uri targets if sanitize empty
- `_NETSCAPE_URL` skipped when `protocolIsFile()`
- no export of `SelectionData` filenames as `GdkFileList`

**Gaps:**

1. **Clipboard write** (`ClipboardGtk3/4::write`) still pushes full `uriList()` including `file://`. Same CVE *class* toward other apps / later paste stacks.
2. **`uriListWithoutFilenames` vs WebCore `URL`:** lines that parse as URL but fail `g_filename_from_uri` are **kept**. Odd `file:` forms may still exit as text (usually not a local File grant).
3. **`g_filename_from_uri` accepts** `file://127.0.0.1/...`, `FILE://`, `file:/path` - stripped/promoted consistently; good alignment for strip vs grant.
4. **Markup / plain text** can still contain path strings (`setURL` writes text + `<a href="file://...">`). Other apps may scrape; not File grant inside WebKit.
5. **Custom data** buffer not filename export; OK.
6. Image-only drags OK.

---

## F. Paste left disabled - right call?

**Yes, for this series.**

Reasons:

- GTK3 `readFilePaths` = uri-list→paths with no separate trust bit (same shape as the old DnD bug).
- GTK4 clipboard file read uses `GDK_TYPE_FILE_LIST` (better) but write path still accepts web uri-list with `file://`.
- DOM paste uses `CopyAndPaste` type; turning on Cocoa-like `!forDrag() || forFileDrag()` without clipboard trust split would re-open File API on paste.

**Safe paste restore would need (minimum):**

1. Separate clipboard filename channel (never fill from web `setData` / `writeString` uri-list).
2. UIProcess: populate filenames only from `GdkFileList` / portal / explicit file clipboard targets; GTK3 needs an explicit trust story (harder).
3. Serialize that channel if pasteboard reads cross process (already via proxy APIs - fix `readFilePaths` callers, not SelectionData drag IPC).
4. Sanitize clipboard **write** uri-list (`uriListWithoutFilenames`) symmetric to drag.
5. Keep `allowsFileAccess` false until (1 - 4) + tests; then consider matching Cocoa paste policy.
6. Audit editor `readFilePaths` / content insertion, not only `DataTransfer::files`.

---

## G. Test gaps before upstreaming

### Must-have (blockers)

1. **IPC round-trip:** UIProcess `SelectionData` with filenames only → encode/decode → web process `hasFilenames()` / `DragData::containsFiles()` true, uri-list-only → false. 
2. **End-to-end GTK4:** drop from file manager → `drop` event `dataTransfer.files.length >= 1` and readable blob. 
3. **End-to-end web attack:** page sets uri-list `file:///…` on dragstart → drop on self/other page → `files.length === 0`, no content read. 
4. **Portal widen attempt (GTK4):** portal list `{/tmp/a}` + uri-list `file:///etc/passwd` → filenames == `{/tmp/a}` only. 
5. **Serialization.in includes filenames** (compile-time contract test or decoder unit test).

### Should-have

6. GTK3 external uri-list drop files. 
7. Same-WebView and cross-WebView same-process: no files. 
8. Same-app **native widget → WebView** file drop (documents current IsSource over-deny). 
9. Export: web drag offers no `file://` uri-list / no file list content-type. 
10. Clipboard: web copy `file://` does not yield DOM files on paste (and after sanitize, other apps don’t get file targets if that’s the policy). 
11. `drop` before async load finishes: no crash; define files empty or deferred. 
12. `file://127.0.0.1/…`, `FILE://`, comments, mixed http+file uri-lists. 
13. `getData('text/uri-list')` when files **are** granted: non-file URLs only (`canExposeURLToDOMWhenPasteboardContainsFiles`) - today this only arms when `forFileDrag()` and fileContentState set. 
14. WPE: `allowsFileAccess` stays inert without UI grants. 
15. Layout/API test for `<input type=file>` drop using real paths once IPC fixed.

Current `Tools/TestWebKitAPI/.../SelectionData.cpp` tests are necessary but **unit-only**; they never exercise IPC or GTK drop controllers.

---

## H. Concrete improvements / alternatives

### H1. Fix filenames IPC (required)

In `SelectionData.serialization.in`:

```text
Vector<String> filenames()
```

Wire encode/decode to `filenames()` / `setFilenames`. 
**Do not** re-enable promotion in `setURIList` as a shortcut.

Constructor today ignores filenames; generated decode must call `setFilenames` after or extend constructor carefully so web-authored uri-list still cannot populate grants.

### H2. Narrow `IsSource` (product + security clarity)

Prefer Cocoa-like “source is **this web view**,” not “any widget in process”:

- GTK3: `gtk_drag_get_source_widget(context) == m_webView` (or walk to WebKitWebViewBase). 
- GTK4: compare `gdk_drop_get_drag` to **this** view’s active `DragSource` drag, not any local drag.

Keep export sanitize regardless.

### H3. Single “grant” API on SelectionData

```cpp
// Trusted only - assert or make private + friend DropTarget
void setTrustedFilenames(Vector<String>&&);
```

Avoid public `setFilenames` callable from any WebCore code that later gets confused with web paths.

### H4. Clipboard export parity

```cpp
// ClipboardGtk*::write
auto sanitized = SelectionData::uriListWithoutFilenames(selectionData.uriList());
```

### H5. Fail-closed drop if data incomplete (GTK4)

If `m_cancellable` still active in `drop()`, cancel or defer `performDragOperation` until `didLoadData` (or finish with empty grant). Prevents flaky empty files and races.

### H6. Optional: stop putting `file://` in primary URL for web-written uri-list when building drag for DOM string reads under file-ish content - low priority vs Files.

### H7. Alternative design (equal weight)

**Cocoa-like separate file list on `DragData`**, not inside web-writable `SelectionData`:

- IPC: `Vector<String> allowedFiles` parallel to selection payload on `PerformDragControllerAction`. 
- Web process attaches grants only from that vector. 
- `SelectionData` remains pure clipboard strings. 

Clearer trust boundary; more plumbing.

### H8. Keep global kill-switch?

Until H1+E2E green, shipping “re-enable” commits without IPC fix is worse messaging than leaving `allowsFileAccess()==false`. Prefer: land selection split + export sanitize first; land `allowsFileAccess`/`forFileDrag` true only with IPC+E2E.

---

## I. Residual risk ratings

- Risk: **(1) Web read local file via DnD (`dataTransfer.files` / File)**; Rating: **Low** for the classic uri-list promotion CVE; **Low - Med** overall until paste/editor paths audited. IPC bug currently fail-closes grants (Low exploitability, High product false confidence).
- Risk: **(2) Web exfil via drag-out**; Rating: **Low - Med**; Notes: DnD export sanitize helps; **clipboard write still emits `file://` uri-list**; markup/text path strings remain. Other apps may treat uri-list as files.
- Risk: **(3) Confused deputy with portal**; Rating: **Med** (GTK4 improved vs pure uri-list; not eliminated); Notes: Portal-prefer prevents uri-list *widening* when portal list present. Hostile external `GdkFileList`, GTK3 classic uri-list, and symlink/path confusion remain. Same-app native→WebView over-denied by `IsSource`.

---

## HTML5 / app compatibility mismatches

- Expectation: User drops files from Nautilus onto page; After this series (with IPC bug): **Broken** (no files in web process); After IPC fix only: Should work (GTK4 portal / GTK3 uri-list)
- Expectation: Page `setData('text/uri-list', fileURL)` → `files`; After this series (with IPC bug): Empty (spec-wise browsers differ; WebKit security choice); After IPC fix only: Same - intentional
- Expectation: In-page drag of “virtual files” via uri-list; After this series (with IPC bug): Empty files; After IPC fix only: Same
- Expectation: Paste files from OS → `clipboardData.files`; After this series (with IPC bug): Empty (intentional); After IPC fix only: Same until paste project
- Expectation: Same-app native file widget → WebView; After this series (with IPC bug): Denied by broad `IsSource`; After IPC fix only: Still denied until H2
- Expectation: `getData('text/uri-list')` on file drops; After this series (with IPC bug): May still show raw file URLs while files empty (IPC); with working files + `forFileDrag`, suppression path filters to http(s)/blob/data; After IPC fix only: Aligns better with Chromium-ish path hiding when Files present
- Expectation: Drag-out of http(s) links; After this series (with IPC bug): Works; After IPC fix only: Works
- Expectation: Drag-out of file links from web; After this series (with IPC bug): Stripped from uri-list targets; After IPC fix only: Same - sites cannot drag real files out via uri-list alone (use download / native APIs)

Sites that relied on the **bug** (synthetic file:// uri-list → File) break permanently by design. Sites that need real user file drops need the IPC fix.

---

## Bottom line

1. **Trust split (`uri-list` vs `filenames`) is the right fix for CVE-2025-13947-class bugs** on GTK/WPE. 
2. **Incomplete:** filenames never cross UIProcess→WebProcess; re-enable is currently a no-op for real drops. 
3. **Export sanitize on DragSource is good; clipboard write is not paired.** 
4. **`IsSource` is coarser than Cocoa and over-denies same-app native sources.** 
5. **Portal-prefer on GTK4 is sound** as a non-widening rule. 
6. **Paste disabled is correct** until a dedicated clipboard grant design exists. 
7. **Do not upstream** until: serialize filenames (or parallel grant vector), E2E drop tests pass, and clipboard export policy is explicit.

I’m not signing off on this as a complete security+product fix; I’m signing off on the *direction* with hard blockers called out above.