# Upstream lint and test parity

How WebKit actually gates GTK changes, and what we run to match.

## What WebKit runs (EWS / Buildbot)

Style queue:

- Command: `python3 Tools/Scripts/check-webkit-style`
- Flunks the EWS style bot on any reported error
- Engine is a cpplint fork under `Tools/Scripts/webkitpy/style/`
- Important rule for our patches: `runtime/wtf_move` rejects both `std::move(` and `WTFMove(` and asks for `WTF::move(`
- Modern `Source/WebCore` is almost all `WTF::move` (tens of thousands of uses). Leftover `WTFMove` macros are rare
- IWYU-style include checks exist in the checker but are filtered off by default (`-build/include_what_you_use`)
- No in-tree `.clang-tidy` gate for GTK. Apple SaferCPP / scan-build queues are not the GTK land bar

GTK / WPE queues:

- gtk build: compile WebKitGTK (build-webkit / ninja)
- gtk tests / gtk-wk2: layout tests when relevant; modified-test discovery
- wpe build + wpe tests when shared non-Cocoa headers move
- API tests on GTK/WPE go through `run-gtk-tests` / `run-wpe-tests` (TestWebKitAPI), not layout tests alone

Local scripts upstream documents and EWS wraps:

- `Tools/Scripts/check-webkit-style`
- `Tools/Scripts/build-webkit` (perl) with `--gtk` / release flags
- `Tools/Scripts/run-webkit-tests`
- `Tools/Scripts/run-api-tests`, `run-gtk-tests`, `run-wpe-tests`

Git hooks:

- Optional via webkit-patch install-hooks
- pre-commit sorts Xcode pbxproj only. It does **not** run style
- pre-push is about secure/public remote policy, not compile
- So "I committed" never meant "style or gtk build passed"

## What would have caught our WTFMove mistake

1. `check-webkit-style` on the touch set - flags `WTFMove(` immediately
2. A real gtk / TestWebCore compile - `WTFMove` undeclared if the macro header is not pulled in; `WTF::move` was already visible transitively in SelectionData.cpp neighbors
3. Style alone does **not** prove IPC serialization or drop behavior

We hit (2) in CI before we ran (1) locally. Order should be style then compile then SelectionData gtests.

## Host Python footgun

This Fedora host defaults to Python 3.15. webkitpy still does `import sre_compile`, removed from the stdlib. EWS images and python3.12 still work:

```bash
python3.12 Tools/Scripts/check-webkit-style --diff-files <files>
```

`scripts/lint-local.sh` prefers python3.12 for that reason.

## What we run (private repo + fork)

Local before push:

```bash
bash scripts/lint-local.sh
```

That is:

- actionlint on `.github/workflows` (same bar as our workflow commits)
- shellcheck `-S error` on `scripts/` and `containers/` shell
- check-webkit-style on the DnD touch set (SelectionData, DropTarget, DragSource, DragDataGLib, API test)

Still required after lint-local (upstream gtk bar):

- Configure/build TestWebCore (our unit workflow or local ninja)
- `gtest_filter=SelectionData.*`
- External validation harness when the unit job says so
- AppImage lane only after unit is honest green on the real branch tip

Engine tests we own:

- `Tools/TestWebKitAPI/Tests/WebCore/glib/SelectionData.cpp` (including IPC constructor / filenames preserve case)
- Private HTML layers under `html/`
- Nested GUI later on Azure KVM only after unit + AppImage

## Gaps vs full upstream EWS

We do not run full gtk-wk2 layout on every push. That is deliberate cost control. Before an upstream PR we still need:

- style clean on the final diff
- GTK build of the touched libs
- API tests green
- judgment call on layout if DropTarget behavior shows in WebKitGTK API tests or needs a LayoutTest

We are not inventing a parallel style system. We are running their checker and a thin slice of their gtk API test surface inside private CI.
