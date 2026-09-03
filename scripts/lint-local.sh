#!/usr/bin/env bash
# Local lint gate. Run before every push that touches workflows, shell, or the
# engine touch set. Mirrors what upstream EWS and this repo's conventions check.
#
#   bash scripts/lint-local.sh
#
# WEBKIT_SRC   path to the WebKit fork checkout (default ../WebKit)
# WEBKIT_BASE  upstream base commit the branch sits on (default auto-detect)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

rc=0
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; rc=1; }

section "actionlint on .github/workflows"
if have actionlint; then
    # actionlint runs shellcheck on run: blocks at info level by default, which
    # is noisier than this repo's -S warning policy for shell. Align them.
    if SHELLCHECK_OPTS="${SHELLCHECK_OPTS:--S warning}" actionlint; then
        echo "ok"
    else
        fail "actionlint reported problems"
    fi
else
    echo "SKIP: actionlint not installed"
fi

section "shellcheck on scripts/ and containers/"
if have shellcheck; then
    mapfile -t sh_files < <(find scripts containers -name '*.sh' -type f 2>/dev/null | sort)
    if [ "${#sh_files[@]}" -eq 0 ]; then
        echo "no shell files found"
    else
        for f in "${sh_files[@]}"; do
            bash -n "$f" || fail "bash -n: $f"
        done
        if shellcheck -x -S error "${sh_files[@]}"; then
            echo "ok (${#sh_files[@]} files)"
        else
            fail "shellcheck reported errors"
        fi
    fi
else
    echo "SKIP: shellcheck not installed"
fi

section "check-webkit-style on the engine diff"
webkit_src="${WEBKIT_SRC:-$repo_root/../WebKit}"
if [ ! -d "$webkit_src/Tools/Scripts" ]; then
    echo "SKIP: no WebKit checkout at $webkit_src (set WEBKIT_SRC)"
else
    # webkitpy needs a 3.12-class interpreter. Fedora's python3 may be 3.15,
    # where sre_compile is gone and webkitpy import fails.
    py=""
    for cand in python3.12 python3.11 python3; do
        have "$cand" || continue
        if "$cand" -c 'import sre_compile' >/dev/null 2>&1; then py="$cand"; break; fi
    done
    if [ -z "$py" ]; then
        fail "no interpreter with sre_compile; install python3.12"
    else
        base="${WEBKIT_BASE:-}"
        if [ -z "$base" ]; then
            base="$(git -C "$webkit_src" merge-base HEAD upstream/main 2>/dev/null \
                 || git -C "$webkit_src" rev-parse HEAD~1 2>/dev/null)"
        fi
        if [ -z "$base" ]; then
            fail "could not determine base commit; set WEBKIT_BASE"
        else
            echo "interpreter $py, base $base"
            # Scope to the diff. Whole-file mode reports pre-existing errors in
            # untouched code, which EWS does not flag and we must not "fix".
            out="$(cd "$webkit_src" && "$py" Tools/Scripts/check-webkit-style -g "${base}.." 2>&1 \
                | grep -vE "perl:|LC_[A-Z]+|LANGUAGE|LANG =|are supported|Can't locate|BEGIN failed|Compilation failed")"
            echo "$out" | grep -vE '^\s*$' || true
            if echo "$out" | grep -q "Total errors found: 0"; then
                echo "ok"
            else
                fail "check-webkit-style reported errors on the diff"
            fi
        fi
    fi
fi

section "result"
if [ "$rc" -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL - do not push"
fi
exit "$rc"
