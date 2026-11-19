#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-shell-guards.sh — regression test for the SIGPIPE / pipefail trap.
#
# `producer | grep -q PATTERN` is unsafe under `set -o pipefail`. grep exits at
# the first match and closes the pipe; if the producer still has data to write
# (anything over the 64 KiB pipe buffer) it dies on SIGPIPE, the pipeline
# returns 141, and a check that DID match reads as a failure.
#
# That is not hypothetical. build-live-iso.sh used this idiom to decide whether
# a rebuilt initrd contained casper. On the same input it returned "match" in
# one build and "no match" in the next, so a good initrd was silently thrown
# away and the image fell back to Ubuntu's. It is a coin flip, not a bug you
# can see in a log.
#
# The fix is the has()/has_word()/has_re() helpers in the build scripts: they
# match a here-string, which bash backs with a temp file, so there is no
# producer to kill. This test proves both halves and then enforces the rule
# across the repository.
#
#   ./scripts/test-shell-guards.sh
#
# No root, no ISO, no network. Takes under a second.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# Same helpers as the build scripts.
has()      { grep -qF  -- "$1" <<< "$2"; }
has_i()    { grep -qiF -- "$1" <<< "$2"; }
has_re()   { grep -qE  -- "$1" <<< "$2"; }
has_word() { grep -qxF -- "$1" <<< "$2"; }

fail=0
pass() { printf '\033[1;32m PASS\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m FAIL\033[0m %s\n' "$*"; fail=1; }
warn() { printf '\033[1;33m WARN\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# A listing shaped like `lsinitramfs` output, comfortably over the pipe buffer
# (64 KiB) so the producer is forced to block.
# ---------------------------------------------------------------------------
filler="$(for i in $(seq 2000); do
    printf 'lib/modules/7.0.0-31-generic/kernel/drivers/filler-%04d.ko\n' "$i"
done)"
listing="scripts/casper
$filler
scripts/casper-bottom/05mountpoints
conf/conf.d/default-boot-to-casper.conf
plymouth/themes/dct/dct.plymouth"

printf '  input: %s lines, %s bytes (pipe buffer 64 KiB)\n\n' \
    "$(wc -l <<< "$listing")" "${#listing}"

# ---------------------------------------------------------------------------
# 1. The old idiom is genuinely unsafe on this input.
#    If it happens not to fail on this machine, say so — the pattern is still
#    wrong, and the point of this test is to keep it out of the tree.
# ---------------------------------------------------------------------------
old_false_negatives=0
for _ in $(seq 20); do
    if printf '%s\n' "$listing" | grep -q 'scripts/casper'; then
        :
    else
        old_false_negatives=$((old_false_negatives + 1))
    fi
done
if [ "$old_false_negatives" -gt 0 ]; then
    pass "old idiom reproduced the defect ($old_false_negatives/20 false negatives)"
else
    warn "old idiom did not misfire this run (timing-dependent); still unsafe by construction"
fi

# ---------------------------------------------------------------------------
# 2. The helpers match every time, on the same input.
# ---------------------------------------------------------------------------
new_false_negatives=0
for _ in $(seq 200); do
    has 'scripts/casper' "$listing" || new_false_negatives=$((new_false_negatives + 1))
    has 'conf/conf.d/default-boot-to-casper.conf' "$listing" || new_false_negatives=$((new_false_negatives + 1))
    has 'plymouth/themes/dct' "$listing" || new_false_negatives=$((new_false_negatives + 1))
done
[ "$new_false_negatives" -eq 0 ] \
    && pass "has() matched in all 600 attempts" \
    || bad "has() produced $new_false_negatives false negatives"

# ---------------------------------------------------------------------------
# 3. Absent patterns still fail. A guard that always returns true is worse
#    than the bug it replaces.
# ---------------------------------------------------------------------------
has 'scripts/definitely-not-present' "$listing" \
    && bad "has() matched an absent pattern" \
    || pass "has() rejects an absent pattern"
has_i 'SCRIPTS/CASPER' "$listing" \
    && pass "has_i() is case-insensitive" \
    || bad "has_i() failed a case-insensitive match"

# ---------------------------------------------------------------------------
# 4. Exact-line semantics: has_word must not accept a prefix.
# ---------------------------------------------------------------------------
words=$'alpha\nbeta\ngamma'
has_word 'beta' "$words" && pass "has_word() matches a whole line" \
    || bad "has_word() missed a whole line"
has_word 'bet' "$words" && bad "has_word() matched a prefix" \
    || pass "has_word() rejects a prefix"
has_re '^beta$' "$words" && pass "has_re() honours anchors" \
    || bad "has_re() missed an anchored match"

# ---------------------------------------------------------------------------
# 5. Nothing in the repository pipes into grep -q. Static, so it catches the
#    next occurrence before it can cost a build. Two exemptions:
#      - full-line comments discuss the idiom, they do not run it
#      - this file contains it on purpose, to prove it is broken
# ---------------------------------------------------------------------------
hits="$(grep -nE '\|[[:space:]]*grep[[:space:]]+-[^[:space:]]*q' "$HERE"/*.sh \
        --exclude=test-shell-guards.sh 2>/dev/null \
        | grep -vE ':[[:space:]]*#' || true)"
if [ -n "$hits" ]; then
    bad "a script pipes into grep -q (SIGPIPE risk):"
    printf '%s\n' "$hits" | sed 's/^/       /' >&2
else
    pass "no script pipes into grep -q"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "all shell-guard checks passed"
else
    echo "shell-guard checks FAILED" >&2
fi
exit "$fail"
