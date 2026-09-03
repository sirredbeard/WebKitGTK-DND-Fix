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

### Commits vs proof (visitor practice)

**In WebKit (upstream-facing):**

- Stacked, reviewable commits on one bug (303434). Message shape: title, bug URL, `Reviewed by NOBODY (OOPS!).`, prose, `* path:` / `(function):`.
- In-tree proof = TestWebKitAPI / layout tests that land with the code.
- No AppImage binaries, nested logs, dual-runner notes, or "E2E PASSED" receipt commits in the engine tree.
- Optional follow-ups (H2 IsSource narrow, H3 API) as later commits or a follow-up bug - not folded into history rewrites.
- Clean the fork series toward 2–4 logical commits before `git webkit pr`; drop Co-authored-by if it is not intentional for upstream.

**Beside WebKit (private CI):**

- AppImage smoke, nested S1/F1, stack traces, golden image: confidence for us and for a maintainer who wants a tarball to try.
- Record tip SHA + Actions run URLs in private `findings/` only.
- PR/Bugzilla may say "also verified on GNOME Web built from this tip" with steps - link artifacts off-tree if asked. Do not make CI theater the lead of the PR.

**Order:** engine tip stable → private E2E green → Bugzilla/PR with house-shaped commits + EWS. Private proof never becomes a layer in their commit stack.

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


---

## Mandatory: commits and proof when we go upstream (follow this)

We are visitors. WebKit process is the product surface. Private CI is how we get confident before asking for reviewer time. Do not confuse the two.

### What lands in sirredbeard/WebKit (and eventually WebKit/WebKit)

1. Bug first: bugs.webkit.org 303434 (public behavior + security property). Link 271957 without private exploit detail.
2. Stacked reviewable commits on one bug. Prefer 2-4 logical commits for the pitch, not WIP micro-commits and not one undifferentiated blob unless a reviewer asks to squash.
3. Commit message is the PR body:

```text
[GTK][WPE] <short title>
https://bugs.webkit.org/show_bug.cgi?id=303434

Reviewed by NOBODY (OOPS!).

Why this keeps the CVE closed and restores trusted drops.

* path/file.cpp:
(Class::method):
```

4. In-tree proof only: TestWebKitAPI (SelectionData etc.), layout expectations if needed. That is what EWS and reviewers treat as proof.
5. No AppImage binaries, nested results.json, dual-runner docs, golden qcow2, or "E2E PASSED" receipt commits in the engine tree.
6. No personal app names, product pitches, or private CI theater in branch names, commits, PR text, or Bugzilla.
7. Clean Co-authored-by / noise before formal PR if not intentional for upstream.
8. Branch via git webkit pr / eng/... when opening the real PR. Do not PR fork main onto upstream main.
9. Style: check-webkit-style on the touch set. Author owns EWS (style, gtk, gtk-wk2, api-gtk, wpe if shared).
10. Leave Cocoa alone. Paste Files stay off until a separate clipboard grant design.
11. H2 IsSource narrow, H3 trusted API, path canonicalization, H7 parallel allowedFiles are optional follow-ons - own commits or own bug after the main series is understood. Do not rewrite the landed trust-split history to insert them.
12. We cannot r+ or merge-queue ourselves. Reviewer approves; committer labels the queue.

### What stays in WebKitGTK-DND-Fix (private)

1. AppImage pack + smoke, nested GUI S1/F1, full stack logs, golden image stamp cache, dual-runner federation.
2. findings/* postmortems and scorecards (including Opus).
3. Optional findings/e2e-results.md with tip SHA + Actions run URLs + PASS table - a receipt for us, not an engine commit.
4. Squash-to-main workflow and no Co-authored-by on this private repo stay as local policy.

### Order of operations (do not skip)

1. Hold engine tip at the security stack through clipboard sanitize + pending drop (currently 2b70a3d087 lineage). No H2/H3/path/H7 required for proof cut.
2. Green private AppImage on that SHA (migrator reloc, host plain ./AppImage --version).
3. Nested suite: S1/S2/S3 security must PASS; F1 product must PASS; canary must not leak. Golden is stamp-cached; rebuild only on recipe change.
4. Record private E2E receipt in findings (SHA, run ids). Human QA if automation is INCONCLUSIVE.
5. Only then: Bugzilla update + WebKit PR with house-shaped commits and in-tree tests. PR "How we tested" may mention GNOME Web built from tip and point off-tree if asked - lead with mechanism and tests, not CI architecture.
6. Fix EWS; answer security review with mechanism; land via reviewer/committer.

### Explicit non-goals for the upstream pack

- Do not attach E2E proof as a WebKit commit layer.
- Do not lead the PR with dual-runner, AppImage reloc, or golden image design.
- Do not claim WPE file-drop parity.
- Do not reopen paste Files in this series.
- Do not pretend path realpath / hostile native GdkFileList are solved.

When an agent prepares the upstream PR or rewrites engine history, re-read this section and findings/opus-second-opinion.md scorecard first.

---


## Readiness review against maintainer expectations, 2026-09-02

Picked the patch back up and audited it against what Catanzaro and aperezdc
actually do, using their commit histories rather than our notes about them.
Five findings, three of them things we had wrong.

### Style is clean, but only when you scope it the way EWS does

`check-webkit-style` on the touched *files* reports 26 errors. Scoped to the
diff it reports 0.

```
python3.12 Tools/Scripts/check-webkit-style Source/... Tools/...   # 26 errors
python3.12 Tools/Scripts/check-webkit-style -g f374cf141b..        # 0 errors
```

All 26 live in code we did not touch: `using namespace` at file scope in
`WebKitWebViewBase.cpp`, `runtime/log` and `whitespace/indent` in the
seventeen-thousand-line `WebPageProxy.cpp`, `auto_with_adopt` in
`ClipboardGtk4.cpp`. EWS checks the diff, so these are not ours and fixing them
would be exactly the drive-by reformat the style guide tells us not to do.

Use `-g <base>..` always. Whole-file mode on a large file will either panic you
into cleaning someone else's code or train you to ignore a real error in the
noise.

### The commit message was an outlier, and outliers get read as AI slop

Measured against the 199 upstream commits preceding our base:

- median 98 words
- p75 192
- p90 364
- p95 591
- max 1465, which is a mechanical Skia dependency roll

Ours was 1042 words, 911 of them prose. Only three of 199 exceeded it, and one
of those is a generated dependency list. Catanzaro's own last 60 commits: median
35 words, p90 137. His 303828@main disable is 63 words of prose.

Length alone is not fatal on a security change that genuinely needs a threat
model. What is fatal is *what* the extra words were doing. A block of ours
narrated our own debugging journey - that the tests took a second pass, that the
first version measured the wrong thing, that a defect was found by a test
failing for an unpredicted reason. That is a good story and it is true, but
upstream commit messages describe the change, not the author's process. On a
first contribution to a security-adjacent area, from someone with no track
record, verbose self-narration is precisely the texture that reads as machine
generated. Catanzaro has publicly argued *against* banning AI-assisted
contributions while tightening GNOME security handling because AI volume rose.
He will judge the patch, not the tooling - but only if the patch does not
announce itself as padding.

Trimmed the narration to the one sentence a reviewer needs, which is that each
test isolates one defence and each was verified by reverting that layer and
confirming the suite goes red. That is a claim about test quality. The rest was
autobiography. Prose is now 877 words, still long, and deliberately so, because
every remaining paragraph answers a question a reviewer will ask.

Keep the debugging story. It belongs in `findings/testing-plan.md`, where it
already is, and it is fair game in PR conversation if someone asks how the
tests were validated.

### We now answer the expectations question before it is asked

303828@main touched exactly two files. One was `DataTransfer.h`. The other was
a new layout test expectation:

```
LayoutTests/platform/gtk/editing/pasteboard/paste-image-does-not-reveal-file-url-expected.txt
```

It records `FAIL event.clipboardData.types.includes("Files") should be true.`
That expectation is the visible scar of the disable, and a reviewer will ask
what happens to it. We do not touch it, and that is correct: `allowsFileAccess()`
now returns `forFileDrag()`, `forFileDrag()` is `m_type == DragAndDropFiles`,
and a paste is not a drag, so it still returns false and the expectation still
describes reality. Verified in the header rather than assumed. The commit
message now says this in two lines instead of leaving it to be discovered.

### The "why no layout test" answer is already in their tree

We ship API tests and no LayoutTests, on a web-visible behaviour change. That
looks like a gap until you read `LayoutTests/platform/gtk/TestExpectations`:

```
680: # 'beginDragWithFiles' is only implemented in Mac. All other platforms skip this test.
720: # [GTK] Drag and drop can't be tested with WebKitTestRunner
724-727: webkit.org/b/157179 ... [ Failure Timeout ]
```

Upstream already documents that GTK cannot drive drag and drop through
WebKitTestRunner, cites 157179 for it, and that is the same bug our commit
message cites. So the answer to "why not a layout test" is not our argument, it
is their existing annotation. Quote the line numbers if challenged.

Also confirms our `...ForTesting()` hook is normal rather than novel. There are
579 `ForTesting` declarations under `Source/WebKit/UIProcess/` headers, and
`webkitWebViewBaseSnapshotForTesting` sits in the very same
`WebKitWebViewBaseInternal.h` we added ours to, with
`webkitWebViewBaseBeginBackSwipeForTesting` and its completion partner next
door in `WebKitWebViewBasePrivate.h`. Same naming, same placement, same export
macro. This is house practice, not a special pleading.

### Diff shape

24 files, 1417 insertions, 66 deletions. Production code is 508 insertions
across 16 files; the rest is tests. More test than code is the right ratio for
this reviewer, and the deletion count being small is the point - this adds a
trust boundary, it does not rewrite drag machinery.

### Still open, and honestly so

The commit message header still points at 303434, which is RESOLVED/FIXED. A
restore needs a new bug, and until that bug exists the URL cannot be corrected.
That is the one item blocking "please review", and it is procedural, not
technical.

## Comparable bug survey, 2026-09-02

Before reshaping comment 0 we read the bug report guidelines, the contributing
page, and, through the Bugzilla REST API, comment 0 and the early thread of
bugs 303434, 322068, 157179, 52094, and 42194, plus 37 WebKitGTK and WPE bugs
from 2024 to 2026 that were RESOLVED FIXED and filed from addresses outside
Igalia, Apple, GNOME, and Red Hat. Bug 271957 confirmed restricted: the API
returns "You are not authorized to access bug #271957". The result changed the
draft from about 1460 words with four numbered questions to about 380 words
with one request (now about 380). This section records why, so the next draft does not drift
back.

### What the guidelines say, verbatim where it matters

- Summary: "If you have tested and verified that this is a regression from a
  previous version of WebKit, prepend 'REGRESSION: ' to the summary. If you
  know the range of revisions in which the regression occurred, add this to
  the summary after REGRESSION". Modern form is `REGRESSION(NNNNNN@main):`
  (278644, 291194, 301985).
- Reductions: "If you have created a test case reduction for the bug, please
  add it to the bug report as an attachment rather than putting it on a web
  server". Hence `bug_report_drop.html` as an attachment.
- Priority: "the bug submitter can leave this at the default value". Every
  regression sampled (278644, 291194, 268479) stayed at P2 and let the prefix
  carry the signal.
- Keywords: the `Gtk` keyword appeared on 8 of about 150 outsider GTK bugs.
  `InRadar` and `DoNotImportToRadar` are set by Apple's importer and by
  maintainers, never by the filer. `Regression` as a keyword is uncommon; the
  summary prefix is the norm. 303434 and 322068 carry no keywords.
- Contributing: "If your change may be controversial, you may want to check
  in advance with the webkit-dev mailing list." Design pre-clearance is
  routed there, not into comment 0.
- Tests: "If no layout test can be (or needs to be) constructed for the fix,
  you must explain why a new test isn't necessary to the reviewer." The
  "No new tests. (OOPS!)" line gets a patch rejected by Merge-Queue.
- PR linkage: `Tools/Scripts/git-webkit pull-request` posts the comment
  "Pull request: https://github.com/WebKit/WebKit/pull/NNNNN" under the
  author's Bugzilla account. ews-feeder later posts "Committed NNNNNN@main"
  and resolves the bug. One reporter (311917) wrote "Proposed fix : <url>"
  by hand and it still worked.

### The numbers

- Median comment 0 across the 37 outsider FIXED bugs: about 70 words. 75th
  percentile about 120. Three above 280. Longest 824 (275680), a pasted GPU
  dump whose reply addressed only its first two lines.
- 322068, the closest model: 196 words, symptom, three numbered steps,
  "Cause:" paragraph naming the libsoup function, a spec quote, a cross-port
  comparison, one sentence on the fix. PR 12 minutes later, approved in 75
  minutes with one nit, landed in under 3 hours, backported to 2.54 and 2.52
  within 2 days.
- 303434 itself: 45 words, PR 3 minutes later, approved by the second GTK
  reviewer in 25 minutes, landed in 14 hours. The reviewer waited on gtk-wk2
  EWS because the change touched expectations.
- Zero successful outsider comment 0s contained a list of questions. The
  ones that asked (278016 "Any insights ... welcome", 290446 "Please check
  the findings and confirm", 306430 "please review and advise", 42194
  comment 2 "Does it make sense?") got a redirect, a request for data, or
  silence. 291194's "I'm willing to work on a fix for this" got no reply to
  the offer; Igalia landed a fix in 3 days.
- When comment 0 carried a bisect or a named function, first maintainer
  reply came in 0.1 to 2 days (278644, 322068, 291194, 305401). Without one,
  5 to 40 days (273876, 271477, 270516, 285167).
- Every patch attached to Bugzilla or pasted inline was redirected to GitHub
  (283246, 278016, 310235). 283246 only landed because a maintainer rewrote
  seven attachments into one PR three weeks later.

### Same-area bugs

- 320301: our regression as a user sees it. See `upstream-strategy.md` for
  the details. NEW, unanswered.
- 278644 and 278648 (2024): a file-drop regression caused by a UI-process
  file-access security change (`REGRESSION(281966@main): [GTK] can't drag
  and drop files to a gitlab issue`), 38 words plus a bisect line. Diagnosed
  next day, fixed in two. The commit argued file-access semantics: "make
  sure we only grant access to files when the operation is going to be
  performed, not for enter, update or exit operations." Closest precedent
  for ours.
- 319275 (2026-07): "[WPE] Route drag-and-drop through the GLib SelectionData
  IPC path". 39 words. The reviewer's first comment asked for tests and for
  skipped WPE layout tests to be unskipped in the same change. Landed in 3
  days. Same code area as ours, so expect the same first question.
- 299208 (2025, FIXED): DropTargetGtk4 assertion during file drags, fixed
  using the 271957 reproducer. Comment 9 says "the reproducer in bug #271957
  triggers this crash even outside Flatpak", comment 10 "what I'm doing is
  dragging a file or folder from nautilus." That is how a restricted bug is
  referred to on this component: by number, with no speculation.
- 317322 (2026): new public API from an outsider. Reviewer asked for API
  tests by pointing at TestWebKitWebView.cpp and noted new public API needs
  a second GTK/WPE reviewer. All discussion happened on the PR; comment 0
  was left alone.
- 265857, 204281, 198915, 234850: symptom-only file-drop reports, all NEW.
- quicksearch `allowsFileAccess`: zero hits. Nobody has filed on the
  function by name.

### What we changed because of this

- Title now `REGRESSION(303828@main): [GTK][WPE] ...` naming the symptom.
- Comment 0 is about 380 words: symptom with 320301 cited, three steps with
  an attached reduction, an environment line, "Cause:", "Fix:", "Tests:", one
  request about 271957, "Pull request to follow." No question list.
- The previous four questions, the test seam argument, and the one-commit
  argument moved to prepared replies in `bug_report.md` Part 3, and the two
  structural questions get posted as a self-review comment on our own PR,
  which is where 317322 and 319275 show this component weighing tradeoffs.
- Keywords none. See Also 303434, 271957, 320301. URL field carries the MDN
  drop zone 320301 used.
- The PR opens with `git-webkit pull-request` within minutes of filing. If
  that cannot happen in the same sitting, do not file yet.
- The 380 words are above the observed median by a factor of five. Accepted
  because the change reopens a CVE-adjacent path and adds no layout test, so
  the cause, the fix, and the test plan each need a paragraph. Anything
  beyond that is the PR's job.

