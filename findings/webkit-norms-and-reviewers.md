# WebKit norms, coding style, and reviewers

## Markdown style for this notebook

Product naming: say **GNOME Web** in prose, filenames, workflow titles, and release tags. Keep `epiphany` only where it is the upstream project path, binary name, or distro package NEVRA.

Basic handwritten markdown only. Headers, bullets, numbered lists, fenced code, bold, italics. No tables. No decorative horizontal-rule spam beyond section breaks already here. No nested collapsible chrome. Prefer plain sentences over diagram syntax.


---


## WebKit development workflow (relevant bits)

- Canonical development is on [GitHub WebKit/WebKit](https://github.com/WebKit/WebKit). Clone URL in ReadMe is that repo. This is not "Apple internal git with a public mirror" for day-to-day contribution.
- `main` is the integration branch.
- Code review is GitHub PRs plus EWS (Early Warning System) bots spanning Apple ports, GTK, WPE, Windows, PlayStation, etc.
- Canonical commit numbering also published on [commits.webkit.org](https://commits.webkit.org) (`NNN@main`).
- Bugs: [bugs.webkit.org](https://bugs.webkit.org). Security bugs stay restricted. Public workaround bugs can point at private ones via see_also.
- Commit message style (from the disable commit and PR body): title line, bug URL, "Reviewed by ...", prose paragraphs, optional "Canonical link: https://commits.webkit.org/..."
- Tools live under `Tools/Scripts` (`build-webkit`, etc.). Linux/GTK builds use CMake; Apple uses `build-webkit` + Xcode.
- Port-specific code: GTK UIProcess under `Source/WebKit/UIProcess/API/gtk/`, GLib shared bits under `Source/WebCore/platform/glib/`, page bits under `Source/WebCore/page/glib/`.
- LayoutTests have platform overlays under `LayoutTests/platform/gtk/` for expected results and TestExpectations.

Local clone notes:

- Started as a depth-2 shallow clone; commit `89838b9164a1` was missing until `git fetch --depth=1 origin 89838b9164a1...`
- `origin` → https://github.com/WebKit/WebKit/
- `fork` → https://github.com/sirredbeard/WebKit.git
- Branch `gtk-dnd-file-access-reenable` created from `main` and pushed to fork

---


## Building credibility
---


## Building credibility as a first-time WebKit contributor

I am not a WebKit committer or reviewer. I am not a web engine developer by trade. That is fine. WebKit explicitly has a "Contributor" tier that includes anyone who files a bug or sends a patch. Committer and Reviewer are earned statuses.

What will get a security-adjacent GTK fix taken seriously:

1. Correct process (bug, commit message shape, EWS green, reviewer approval).
2. Small, surgical diff that matches house style.
3. A security story that is tighter than the workaround, not looser. Catanzaro will read for "does this reopen 271957."
4. Proof: tests and a manual repro someone can run in MiniBrowser/GNOME Web.
5. Humility in the PR text. State what we verified, what we could not see (private bug 271957), and what we want reviewed hardest.
6. Do not argue the CVE. Treat the workaround as correct under time pressure. Offer the narrower fix he said he did not have time to finish.

Do not lead with a product pitch. Lead with "external file drops no longer populate `dataTransfer.files` on non-Cocoa after 303828@main; here is why, here is a port-local trust boundary, here are tests."

---


## WebKit contribution norms

Primary sources:

- [WebKit/WebKit ReadMe](https://github.com/WebKit/WebKit/blob/main/ReadMe.md)
- [Contributing wiki](https://github.com/WebKit/WebKit/wiki/Contributing)
- [Pull Requests wiki](https://github.com/WebKit/WebKit/wiki/Pull-Requests)
- [Introduction.md](https://github.com/WebKit/WebKit/blob/main/Introduction.md) in-tree
- [webkit.org contributing-code](https://webkit.org/contributing-code/) (linked from wiki; covers build/test/style/testing policy)
- [Commit and Review Policy](https://webkit.org/commit-and-review-policy/)
- [Security Policy](https://webkit.org/security-policy/)
- [Safer C++ Guidelines](https://github.com/WebKit/WebKit/wiki/Safer-CPP-Guidelines)
- In-tree PR template: `.github/pull_request_template.md`
- In-tree style guide source used on the site: `Websites/webkit.org/code-style.md`
- Style linter: `Tools/Scripts/check-webkit-style`
- Preferred PR tooling: `Tools/Scripts/git-webkit` (`git webkit setup`, `git webkit pr`)

### Roles

- Contributor: anyone (bugs, patches, reviews comments).
- Committer: write access / can run merge queues. Rough bar in policy: on the order of 10-20 good patches, judgment, collaboration, known to more than one reviewer. Needs three reviewers supporting nomination.
- Reviewer: can r+ in a way merge-queue honors. Much higher bar (policy cites on the order of 80 good patches plus judgment). Unofficial review before that is encouraged; do not put r+/r- if you are not a reviewer.

Catanzaro is listed in `metadata/contributors.json` as status `reviewer`, expertise "WebKitGTK, Epiphany", GitHub `mcatanzaro`, emails include redhat.com, gnome.org, igalia.com.

### Bug first

Every landed commit is expected to tie back to a bugs.webkit.org bug. Multiple commits may share one bug. PR template says file a bug, mention the PR on the bug, apply labels matching component/version, assign PR to author.

For this work: public bug should describe the UX regression and the security property we must keep. Link [303434](https://bugs.webkit.org/show_bug.cgi?id=303434). Reference [271957](https://bugs.webkit.org/show_bug.cgi?id=271957) without dumping private details. Do not file the security repro as a public how-to exploit. Prefer a fix description: "web-originated file:// in drag data must not grant `dataTransfer.files`; external/OS file drags may."

Security component rules from Introduction.md: do not post patches or detailed exploit writeups on non-security bugs. Our follow-up is a behavior restore with a security constraint, so keep the public bug in the ordinary WebKitGTK / WebCore drag-and-drop area unless security team says otherwise.

### Branch naming

`git-webkit pr` uses `eng/` prefixed branches derived from bug title. Wiki also accepts `dev/`. EWS cannot apply a PR whose head branch is the same name as the base (do not PR from fork `main` onto upstream `main`). Our existing `gtk-dnd-file-access-reenable` is fine as a working name; before formal PR, aligning to `eng/...` via `git webkit pr` is the path of least friction.

### Commit message is the PR description

WebKit treats the commit message as a first-class review artifact. PR description should be the commit message. Required shape (from Pull Requests wiki + PR template):

```text
<bug title>
https://bugs.webkit.org/show_bug.cgi?id=#####

Reviewed by NOBODY (OOPS!).

Why this fixes the bug (prose).

* path/changed.ext:
(function):
(class.function):
```

Notes:

- Title line often carries port tags when relevant: `[GTK]`, `[WPE][GTK]`, etc.
- `Reviewed by NOBODY (OOPS!).` is the placeholder. Merge queue fills real reviewer names from GitHub approvals.
- File list with `(function):` entries is the traditional ChangeLog-style body. Catanzaro still writes this form on non-trivial patches.
- Unreviewed is allowed only in narrow cases (gardening, build fix, infra). Say `Unreviewed.` and why. Our fix is not unreviewed.
- Canonical link `https://commits.webkit.org/NNN@main` is added when landed; do not invent it.

Examples of Catanzaro commit tone (pattern, not to copy wording blindly):

- Short honest constraint: "This isn't implemented properly for WebKitGTK... My initial attempts to fix things have failed, so let's just completely disable it for now."
- Credit and mechanism: "Milan pointed out that if we break out of a g_variant_iter_loop() loop, then it cannot free the key or value for us... The easiest solution is to just not use g_variant_iter_loop() in these cases..."
- User-visible why: media query PR walks GNOME settings → CSS media queries → API renames, and admits scope growth and a prior revert for WPE build break.
- Security callout when relevant: PDF.js update notes a CVE fixed upstream.

### Review and land

- Need approval from a WebKit reviewer (GitHub "Approved"). Non-reviewer thumbs up does not satisfy merge-queue.
- Author is responsible for EWS health. Wiki says this is not automatically enforced for every queue, but in practice green EWS is how you get landed without drama.
- Land via labels: `safe-merge-queue` (waits for EWS), `merge-queue` (macOS build + WK2 layout), `unsafe-merge-queue` (minimal validation; build fixes / gardening / urgency only). Only committers' labels count for queues.
- We cannot land ourselves without committer status. A committer (often the reviewer or another GTK person) applies the queue label after r+.

### EWS that matters for this patch

From the disable PR bubble and general Linux bots:

- style (check-webkit-style)
- gtk / gtk-wk2 / api-gtk
- wpe / wpe-wk2 / api-wpe (if we touch shared GLib or non-Cocoa DataTransfer)
- bindings, webkitperl as applicable
- Apple/Win bots still run on shared WebCore headers; keep the Cocoa path behavior identical

Catanzaro on 54735 literally waited on gtk-wk2 before trusting the layout expectation change. Expect the same bar.

### Tools to run locally before asking for review

- `Tools/Scripts/check-webkit-style` on touched paths
- Prefer `git webkit setup` once so commit template and hooks match project norms
- Build GTK port and run a focused LayoutTest / TestWebKitAPI set rather than boiling the ocean on first push
- Safer C++: GLib side uses `GRefPtr`; WebCore side uses `Ref` / `RefPtr` / `CheckedPtr` patterns. Do not introduce raw owning pointers in new code.

### CODEOWNERS / who gets pinged

`.github/CODEOWNERS` routes a lot of GTK/WPE/GLib paths to `@WebKit/glib-reviewers`. Catanzaro is also named directly on:

- `Source/cmake/OptionsCommon.cmake`
- `Source/cmake/WebKitCompilerFlags.cmake`
- `Source/cmake/OptionsGTK.cmake` (with glib-reviewers)

Layout test platform trees for glib/gtk are under glib-reviewers ownership patterns in that file.

Our likely touch list (`DataTransfer.h`, `SelectionData.*`, `PasteboardGLib.cpp`, `DropTargetGtk*.cpp`, maybe tests under `LayoutTests/platform/gtk`) will draw glib-reviewers and anyone following WebCore drag-and-drop.

Reviewers who already appeared next to this problem or adjacent GTK work:

- Michael Catanzaro (`mcatanzaro`) - author of the workaround, WebKitGTK/Epiphany, Red Hat, reviewer
- Adrian Perez de Castro (`aperezdc`) - reviewed 54735, common GTK/WPE reviewer
- Carlos Garcia Campos (`carlosgcampos` / carlosgc) - long-time WebKitGTK
- Patrick Griffis (`TingPing`) - GLib/security-adjacent reviews (e.g. g_variant leak PR)

Slack: WebKit Slack exists (join link in Introduction.md). Useful after a bug/PR exists, not as a substitute for the paper trail.

---


## WebKit C++ coding style (what reviewers actually flag)

Canonical guide: [Code Style Guidelines](https://webkit.org/code-style-guidelines/) / in-tree `Websites/webkit.org/code-style.md`. Linter: `check-webkit-style` (educates; does not claim completeness).

Hard habits for a small C++ patch:

### Indentation and layout

- Spaces only, 4-space indent. No tabs (except Makefiles etc.).
- Namespace contents are not indented.
- `case` labels align with `switch`; case body indented.
- Boolean break operators go at the start of the continuation line (`||` / `&&` on the left).

### Braces

- Function braces: each brace on its own line (Allman for functions).
- Other braces (classes, control blocks): opening brace on the same line as the declaration/control head (with the usual WebKit examples in the guide).
- Single-statement `if`/`else`/`for`/`while`: no braces unless there is a comment or the statement wraps multiple lines.

### Spacing

- Space around binary/ternary operators. No space around unary.
- Space after `if` / `while` / `for` / `switch` before `(`.
- No space between function name and `(`.
- No space inside `f(a, b)` parens.
- Range-for: space around `:`.
- Braced init: `Foo foo { bar };`
- `template<typename T>` with no space after `template`.

### Line breaking

- One statement per line. No `if (x) y();` on one line.
- No chained assignment.

### Naming

- Class data members: `m_foo`. Static data members: `s_foo`. Private by default.
- Bools: `is` / `did` / `has` style prefixes (`isValid`, not `valid`).
- Getters: bare noun matching the member (`count()`). Setters: `setCount`. Out-param getters: `get...`.
- Prefer full words over cute abbreviations (`characterSize` not `charSize`), but not swampy names.
- Omit useless parameter names in declarations when the type already says it; keep names for bool/string/number params.

### Includes

- `.cpp`: `#include "config.h"` first, then the primary header for that cpp, then other headers sorted (case-sensitive sort), then system headers in `<>`.
- Headers never include `config.h`.
- Primary header include guarantees the header compiles alone.

### Null and conditions

- C++: `nullptr`. C: `NULL`. Obj-C objects: `nil`.
- Prefer `if (ptr)` / `if (!ptr)` over `== nullptr` comparisons in the style guide's zero-comparison rules.

### Comments

- Explain why when non-obvious. The workaround comment pointing at bug 271957 is the model for security breadcrumbs.
- Do not leave noisy commentary on obvious code.
- Port-specific `#if PLATFORM(GTK)` / `PLATFORM(WPE)` / `PLATFORM(COCOA)` should be tight. Prefer shared GLib code under existing glib paths over scattering GTK-only hacks into generic WebCore if the bug is shared.

### Safer C++ (reviewers care)

- Prefer smart pointers on the stack when calling non-trivial methods (`Ref` / `RefPtr` / `CheckedPtr` / `GRefPtr` for GLib).
- Do not invent new raw owning members.
- Follow surrounding file patterns rather than rewriting lifetime style while fixing DnD.

### Tests

- LayoutTests for web-visible behavior. Platform expected files under `LayoutTests/platform/gtk/` when GTK diverges.
- TestWebKitAPI under GTK/GLib folders for API-level tests (`Tools/TestWebKitAPI/Tests/WebKitGtk`, `WebKitGLib`).
- When behavior changes an existing expected result, say so in the commit body. Catanzaro waited on gtk-wk2 for exactly that class of change on 54735.
- Do not land a security-sensitive behavior change with zero tests if a layout or API test can express it.

### Scope discipline

- Prefer the smallest diff that restores the security property + legitimate external file drops.
- Do not drive-by reformat. Do not expand into unrelated DnD cleanups unless required for the fix.
- If WPE shares the bug via SelectionData, either include WPE in the same rationale or explicitly document why GTK-only is safe. Shared non-Cocoa `allowsFileAccess` means a blind Cocoa-style re-enable hits WPE too.

---


## Michael Catanzaro: role, style, priorities

### Who he is in this project

- WebKit reviewer focused on WebKitGTK and Epiphany.
- Red Hat (Fedora/RHEL packaging and security shipping for WebKitGTK).
- Writes publicly about WebKitGTK API versions, security incidents, Flatpak, GNOME security process.
- Authored the CVE-2025-13947 workaround (PR 54735 / 303828@main / bug 303434).
- CODEOWNER on core GTK CMake bits and compiler flag cmake.

If this PR is going to land, he is the person most likely to care whether we got the threat model right. Adrian Perez de Castro and other glib-reviewers may r+ mechanics; Catanzaro will r+ or block on security judgment.

### How he writes patches (voice and structure)

From his landed commit messages and PR threads:

- Plain spoken. Contractions. First person when explaining decisions ("I failed to find...", "Let's stop using that...", "I decided not to try changing this").
- States the failed or rejected approaches briefly, then the chosen one. That is exactly how 54735 is framed.
- Prefers the smallest correct fix under time pressure over a perfect incomplete one. Disabling all file access was explicit triage, not confusion.
- Separates Apple/Cocoa when Apple has confirmed something ("Apple has confirmed that Safari is OK").
- Port tags in titles when the change is port-scoped: `[WPE][GTK]`, or untagged when truly shared WebCore one-liners.
- Still uses the file/function bullet changelog section on real fixes.
- Reverts and relands openly when EWS or bots show a break (media query PR: first attempt reverted for WPE build; second attempt documented that).
- Owns mistakes in thread ("Looks like I broke JS execution." / "Should be fixed.").
- Waits on relevant EWS (gtk-wk2) before trusting expectation-only changes.

### How he reviews others

Samples from recent PR review comments:

- Challenges assumptions with a short technical question rather than a lecture ("I don't think niceness levels can cause another process to get starved?").
- Refuses to rubber-stamp code outside his expertise even under urgency ("I'm hesitant to approve a patch in code that I do not understand. Would be better for a rendering reviewer... @smfr does this look OK now? We really need to land this to fix GitLab.").
- Nits that match project API docs house style: `explicit` constructors, gtk-doc phrasing ("Returns" / "Gets"), naming disambiguation (`webkit_navigation_action_get_source_frame_info` vs overloaded "frame" words).
- Points at existing convention instead of inventing new process ("I'm afraid you just have to duplicate the documentation. That's what we do everywhere else. Move it to the header file and use unifdef.").
- On his own PRs, engages ownership questions (`outPtr` reset safety) until satisfied.

Implications for us:

- Be ready for "does this reopen the confidential bug?" as the first question.
- Be ready for naming/doc nits if we touch GLib API. Prefer not to touch public GLib API at all for this fix.
- If the diff sprawls into WebCore drag machinery Apple owns, expect him to pull in an Apple/WebCore reviewer rather than bless it alone.
- Keep the patch in GTK/GLib trust-boundary code plus the narrow `allowsFileAccess` policy change if possible.

### Priorities visible from his public writing

Blog: [blogs.gnome.org/mcatanzaro](https://blogs.gnome.org/mcatanzaro/)

Themes that matter to our PR:

1. **Security over convenience, but honesty about blunt workarounds.** The DnD post is the template: explain the bug in plain language, ship a broad mitigation, admit it is overly broad, leave a trail for the proper fix.
2. **Downstream shipability.** He thinks in terms of Fedora/RHEL/Epiphany/Flatpak runtimes and stable branch backports (`webkitglib/2.50`, `2.52` backport comments on PRs). A fix that is correct on main but impossible to backport will get questions. Prefer a small cherry-pick-friendly diff.
3. **Good upstream defaults and not surprising packagers.** Build-options post: upstream should make the safe/common path the default. For us: restored file drop should work for normal GNOME Web/MiniBrowser users without special build flags.
4. **API stability awareness.** WebKitGTK API versions post: knows the history of painful breaks; will not want drive-by public API churn for this.
5. **GLib correctness.** Posts and commits about `G_GNUC_CONST` on `get_type()`, variant iter ownership, compiler warnings, `-Werror` pitfalls. If we write GObject/GTK code, match modern GLib hygiene and surrounding file style.
6. **Pragmatism about AI-assisted reports.** He publicly argued GNOME projects should not ban AI-assisted *issue reports* and static analysis findings, while not defending sloppy AI code dumps. Separately he tightened GNOME security tracking because AI vulnerability volume went up (shorter disclosure window, different handling for projects that ban AI content). Practical reading for us: quality and verifiability matter more than whether a tool helped. A vague AI-smelling PR with no repro will burn trust. A tight patch with tests and a clear threat model will be judged on the patch.
7. **Flatpak/sandbox reality.** He writes about sandbox escapes and portal stacks. He already knows portal file transfer is part of the GTK4 drop path (and reviewed in the era of bug 212079 work). Our fix should not ignore portal vs uri-list distinctions; it should use them.

### What he will likely demand on a restore-file-DnD PR

- Threat model restated in the commit message: web content must not choose arbitrary filesystem paths via drag data; user-initiated external file drags may grant file contents.
- Evidence the GTK/GLib path no longer promotes script-written `file://` uri-list entries into content-granting filenames (or equivalent control).
- Evidence external drops (portal/GdkFileList and, if claimed, classic uri-list from file managers) still produce `dataTransfer.files`.
- No behavior change for Cocoa (`PLATFORM(COCOA)` branch stays as-is unless an Apple reviewer is involved on purpose).
- LayoutTest/API coverage; update or remove the GTK expected FAIL that 54735 added if paste/`Files` typing is restored intentionally.
- Explicit note that private bug 271957 was considered to the extent publicly knowable; invite correction from people with access.
- EWS green on GTK and WPE if shared code moves.
- Minimal diff. No framework rewrite.

### What will lose his trust quickly

- Flipping `allowsFileAccess` to always-true or to the Cocoa expression without fixing SelectionData filename promotion.
- Public exploit polish without a fix.
- Huge drive-by refactors in `DragController` / Apple pasteboard code.
- "LGTM" with no tests.
- Ignoring WPE if the kill switch change affects all non-Cocoa.
- Fighting about whether the CVE was serious. It was. CVSS 7.4 Important. The workaround was correct triage.

---


## PR strategy notes

When we move from research to patch:

1. File public bugs.webkit.org bug (WebKitGTK / DnD). Link 303434 and 271957 by number. Describe user impact (GNOME Web, embedded WebKitGTK, file upload UIs). Describe non-goals (not weakening confidentiality).
2. Optional: short heads-up on the bug CC'ing mcatanzaro if Bugzilla allows, or wait for CODEOWNERS on the PR.
3. Implement smallest fix on `eng/...` or keep `gtk-dnd-file-access-reenable` until `git webkit pr` renames.
4. Commit message in full WebKit form; PR body = commit message. No marketing. No product pitch in the subject line. A single sentence of real-world impact is enough.
5. Run style + GTK build + targeted tests.
6. Request review from glib-reviewers / mcatanzaro / aperezdc as appropriate. Do not self-apply merge labels.
7. Expect at least one round of security questions. Answer with mechanism and tests, not adjectives.
8. After land, downstream (Fedora, GNOME runtime) is Catanzaro's world; we can smoke-test GNOME Web once packages move.

Credibility checklist before "please review":

- [ ] Public bug filed and linked
- [ ] Commit message explains why + file/function list
- [ ] Cocoa path unchanged
- [ ] Web-originated file:// cannot populate files
- [ ] External file drop can populate files (portal and/or uri-list story documented)
- [ ] Tests added or expectations updated with rationale
- [ ] `check-webkit-style` clean on touch set
- [ ] GTK (and WPE if shared) build smoke-tested
- [ ] PR text invites scrutiny on 271957 overlap
- [ ] Diff is boring

---


## Extra people and channels

- bugs.webkit.org for durable decisions
- GitHub PR for code review
- WebKit Slack for informal "who should look at this" after the bug exists
- GNOME Web upstream only if we need an application-level repro companion; the engine fix is WebKit
- Red Hat Bugzilla 2418576 is the CVE ship tracker, not the design forum

---


## Standing rule for anything that touches WebKit/WebKit

Never link to, name, or allude to any personal app validation repo in:

- branch names meant for upstream eyes
- commit messages
- PR titles or bodies
- Bugzilla bugs or comments
- GitHub issue comments on WebKit/WebKit
- test names or fixture paths
- mailing list posts
- review replies

Reason is simple. Upstream does not need our product pitch. They need a correct engine fix and a clean threat model. Real-world impact can be described generically: "WebKitGTK embedded widgets and GNOME Web-style browsers cannot receive file drops for upload UIs." That is enough. Product marketing in a security-adjacent PR looks like noise and burns credibility.

Local research may still mention validation apps. That stays in this file and in private notes only.

---


## Adrian Perez de Castro (aperezdc) profile

Same depth goal as Catanzaro. He is not a side character. He reviewed PR 54735 (the disable). He will likely see the restore.

### Identity and role

- GitHub: aperezdc
- WebKit contributors.json: reviewer, email aperez@igalia.com
- Employer context: Igalia (long-time WebKitGTK/WPE contributor ecosystem)
- Blog: blogs.igalia.com/aperez (historical WPE/GTK multi-process and release writing)
- CODEOWNERS / glib reviewer orbit: shows up across WebKitGTK and WPE UIProcess, CMake/options, third-party updates, stable branch backports

### What he actually works on (public PR sample)

Recent and representative themes:

- WPE API surface (color chooser, clipboard permission request, damage propagation defaults)
- MiniBrowser / tooling flags
- CMake and build-system correctness for WPE/GTK (including CMake version friction)
- Third-party and web-facing component bumps (example: PDF.js update PR approved)
- GLib/GTK API docs and deprecation notes for GTK3 vs GTK4
- Stable branch hygiene: explicit "Backported into webkitglib/2.50" / "2.54" comments on PRs, including on 54735 itself

He is a release-and-platform engineer as much as a feature reviewer. Expect questions about:

- Does this compile on GTK3 and GTK4?
- Does WPE need a mirror change or an ifdef?
- Is the diff safe to cherry-pick to webkitglib/N?
- Did CMake/options or public GIR API shift by accident?

### Review posture (from public comments and approvals)

- Approves focused PRs cleanly when the change is tight (empty APPROVED bodies on straightforward bumps are normal).
- When he comments in substance, it is often precise platform knowledge: gi-docgen limits, GTK3 vs GTK4 doc duplication, build requirements, backport SHAs.
- On 54735 he did not leave a long public design essay; he approved and later recorded the stable backport SHA. Reading that charitably: he agreed the blunt disable was acceptable mitigation for the security branch situation, not that the end state was ideal forever.
- Historical writing on multi-process WebKitGTK and WPE releases shows long-term care about process boundaries and shipping discipline. File access across UIProcess/WebProcess is exactly the kind of boundary he has lived with for years.

### Priorities that affect our patch

1. **Correctness on both GTK and WPE.** Shared WebCore kill switch means shared responsibility.
2. **Stable-branch backports.** He actively drives and documents cherry-picks. A restore fix that only works with brand-new GTK4 APIs and cannot backport will get a harder look than a SelectionData trust split that applies to 2.50-era code.
3. **Build and tooling cleanliness.** Do not break `-DPORT=WPE` or dependency probes.
4. **API docs and deprecations.** If we touch WebKitGTK public API (we should try not to), doc and introspectable signatures must stay right on GTK3 and GTK4.
5. **Low drama security fixes.** Prefer small, reviewable diffs with tests over clever architecture tours.

### How he differs from Michael Catanzaro

- Catanzaro: Fedora/RHEL/Epiphany product security voice, blunt public blog triage, downstream user impact, GNOME security process opinions. Author of the disable. Will argue threat model in plain language.
- aperezdc: Igalia platform/WPE/GTK engine voice, backport mechanic, CMake/API details, quieter public security commentary, high volume of port maintenance. Reviewer of the disable. Will argue mechanism, port matrix, and shipability.
- Overlap: both care that WebKitGTK does not ship fantasy fixes; both live in stable branches; both will reject "just return true" on `allowsFileAccess`.
- Practical consequence: write the commit message for Catanzaro's threat model and aperezdc's port matrix at the same time. One paragraph on what web content still cannot do. One paragraph on GTK3/GTK4/WPE impact. One on backport intent.

### What will earn aperezdc's trust

- Explicit GTK3 and GTK4 consideration in DropTarget paths if touched
- WPE noted even if "no behavior change" with reason
- Cherry-pick note after land (or a clean commit that is already cherry-pick shaped)
- No unexplained public API additions
- Tests that do not depend on a developer laptop portal setup nobody can run on EWS, or clear documentation when a test is manual-only

### What will lose it

- GTK4-only assumptions silently breaking GTK3
- Forgetting WPE in a shared WebCore change
- Huge unrelated refactors in UIProcess drag code
- Commit message that reads like an app blog post
- Fighting the original CVE severity

---


## Other sources, resources, personas, and oracles

Use these while designing and when writing the bug/PR. Still never paste personal app project links into WebKit surfaces.

### Primary technical oracles (in-tree)

- `Source/WebCore/dom/DataTransfer.h` - kill switch and Cocoa reference policy
- `Source/WebCore/dom/DataTransfer.cpp` - `createForDrop`, `files()`, type hiding
- `Source/WebCore/platform/glib/SelectionData.{h,cpp}` - uri-list → `m_filenames` promotion (poison well)
- `Source/WebCore/platform/glib/PasteboardGLib.cpp` - `writeString` → `setURIList`; `fileContentState`
- `Source/WebCore/platform/glib/DragDataGLib.cpp` - `containsFiles` + `m_disallowFileAccess`
- `Source/WebKit/UIProcess/API/gtk/DropTargetGtk4.cpp` - portal MIME types, GdkFileList, uri-list merge rules
- `Source/WebKit/UIProcess/API/gtk/DropTargetGtk3.cpp` - classic GtkSelectionData path
- `Source/WebKit/UIProcess/API/gtk/DragSourceGtk4.cpp` (and Gtk3) - what WebKit exports on drag start
- `Source/WebCore/page/DragController.cpp` - when draggingFiles becomes true
- Cocoa mirrors: `PasteboardMac.mm`, `DragDataCocoa.mm`, `PasteboardCocoa.mm` - filenames/file-promise types vs script custom data; how a safe port separates channels
- LayoutTests under `editing/pasteboard/*file*` and `fast/events/drag-*file*` - behavior oracles (many Cocoa-oriented)
- `LayoutTests/platform/gtk/.../paste-image-does-not-reveal-file-url-expected.txt` - fingerprint of 54735 collateral
- Tools: `check-webkit-style`, `build-webkit`, `run-webkit-tests`, `run-api-tests`, `run-minibrowser`
- `.github/pull_request_template.md`, `Websites/webkit.org/code-style.md`, `metadata/contributors.json`, `.github/CODEOWNERS`

### Primary process and security oracles

- bugs.webkit.org 303434 (public mitigation), 271957 (private; no access; reference by number only)
- WSA-2025-0009 (WebKitGTK and WPE advisory text)
- GHSA-j77f-3hf7-7rvg, CVE-2025-13947, CWE-346
- Red Hat BZ 2418576, Ubuntu USN-7941-1, Debian security-tracker webkit2gtk/wpewebkit
- WebKit security policy: `Websites/webkit.org/security-policy.md`, security@webkit.org
- commits.webkit.org/303828@main canonical link style
- webkitglib/2.50 (and later stables) backport practice

### Human personas and what to take from each

- **Michael Catanzaro (mcatanzaro)** - author of workaround; threat-model English; downstream ship; gtk-wk2 expectations; blog success criteria. Primary reviewer to satisfy.
- **Adrian Perez de Castro (aperezdc)** - approved 54735; backport SHAs; WPE/GTK/CMake matrix; quiet precise platform comments.
- **Janet Black** - credited reporter on WSA. We do not contact via weird channels; respect responsible disclosure norms. No need to involve reporter in a restore fix unless security team says so.
- **Apple WebKit security / Cocoa DnD owners** - already confirmed Safari OK. Do not draft them unless a Cocoa touch sneaks in (it should not).
- **Igalia WebKitGTK/WPE engineers broadly** - buildbots, EWS, stable tarballs, Matrix/IRC support culture.
- **Fedora/RHEL packagers** (often overlapping Catanzaro) - cherry-pick cost.
- **GNOME Epiphany maintainers** - end-to-end manual verification allies; not the engine design forum.
- **xdg-desktop-portal / GTK DnD maintainers** - reality of `application/vnd.portal.filetransfer`, GdkFileList; read their docs when Idea 2 is implemented.
- **HTML DnD spec / browser interop folks** - what `DataTransfer.files` vs `getData('text/uri-list')` means; useful for commit wording ("URLs may remain visible; contents must not").

### Other WebKit ports and "same bug" handling

- **Cocoa (macOS/iOS):** not affected. Filenames and file promises are OS pasteboard types; script `writeString` is not the same channel. `allowsFileAccess` stays `!forDrag() || forFileDrag()`. Reference model, not copy-paste.
- **WPE:** same advisory, same non-Cocoa false. Shared WebCore fix must compile; UIProcess drop surface may be thinner. Include WPE in EWS mental model.
- **Windows port:** separate DragDataWin/PasteboardWin. Also hit by non-Cocoa `allowsFileAccess` false even if the original report was GTK-shaped. Mention in analysis: restoring the getter affects all non-Cocoa; either keep the `#else` nuanced per-port or ensure GLib-only data fixes make a shared Cocoa-like condition safe everywhere. Catanzaro wrote "most likely also not for other ports." A GTK-only `#if PLATFORM(GTK)` restore might be the conservative first land if Win/PlayStation are unknown; a shared restore needs evidence. **Open design fork:** (i) restore allowsFileAccess only for PLATFORM(GTK) || PLATFORM(WPE) after GLib SelectionData fix; (ii) restore for all non-Cocoa after per-port audit. Catanzaro-shaped first PR likely (i) or GLib-guarded.
- **PlayStation / embedded:** little public DnD UX; still compile under shared headers.
- **QtWebKit / old forks:** noise on CVE pages; not upstream WebKit/WebKit. Ignore for patch design.
- **Epiphany, Geary, Evolution, elementary mail, etc.:** consumers. Engine fix is the response. File dialogs OK per Catanzaro comments.

No other port shipped a public narrower fix we can cherry-pick. Cocoa is the positive reference. GLib is the broken channel.

### Specs and external docs worth reading at implementation time

- HTML Living Standard: DnD, DataTransfer, drag data store modes
- MDN: DataTransfer.files, setData, getData (for wording, not for security guarantees)
- GTK4 docs: GdkDrop, GdkFileList, content formats
- xdg-desktop-portal FileTransfer / document portal overview
- WebKit wiki BuildingGtk / contributing pages linked from ReadMe
- Catanzaro: Common GLib Programming Errors; Best Practices for Build Options (style of rigor, not DnD-specific)
- Bug 212079 / PR 25575 era notes already in tree comments on portal vs uri-list

### Channels when we are ready to engage (not yet)

- File bugs.webkit.org first (public component WebKitGTK / Drag and drop)
- Optional security@webkit.org if we believe the restore needs private review against 271957 before public patch detail (judgment call; a careful Idea 1 may be fine fully public because the CVE is already disclosed and workaround shipped)
- GitHub PR against WebKit/WebKit with commit message as body
- Matrix #webkitgtk:matrix.org for build pain, not for security debate in public without a bug number
- Do not drive-by Epiphany issues claiming engine CVE details incorrectly

### Test oracles beyond WebKit

- Manual: Nautilus/Files → MiniBrowser page with drop listener
- Manual: page self-drag with setData file:// → must not yield File contents
- Distro WebKitGTK 2.50.3 package as "before" baseline on the same machine
- Portal on vs off (Flatpak vs host) once build runs in both environments

---

