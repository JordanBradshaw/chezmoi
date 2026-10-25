#!/usr/bin/env bash
#
# Tests for scripts/merge-zsh-history.py.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MERGE="$REPO_DIR/scripts/merge-zsh-history.py"
PASS=0
FAIL=0

setup() { SANDBOX="$(mktemp -d)"; OUTPUT=""; }
teardown() { rm -rf "$SANDBOX"; }

CURRENT=""
fail() { echo "  FAIL [$CURRENT]: $*"; FAIL=$((FAIL + 1)); return 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

merge() { python3 "$MERGE" "$@"; }

# ---------------------------------------------------------------------------

test_entries_sorted_by_timestamp() {
    printf ': 100:0;a\n: 300:0;c\n' >"$SANDBOX/one"
    printf ': 200:0;b\n: 400:0;d\n' >"$SANDBOX/two"
    merge "$SANDBOX/out" "$SANDBOX/one" "$SANDBOX/two" || fail "merge failed"
    assert_eq "$(cat "$SANDBOX/out")" ": 100:0;a
: 200:0;b
: 300:0;c
: 400:0;d"
}

test_multiline_entries_stay_whole() {
    printf ': 100:0;for x in 1 2; do\\\n  echo $x\\\ndone\n: 300:0;c\n' >"$SANDBOX/one"
    printf ': 200:0;b\n' >"$SANDBOX/two"
    merge "$SANDBOX/out" "$SANDBOX/one" "$SANDBOX/two"
    assert_eq "$(cat "$SANDBOX/out")" ": 100:0;for x in 1 2; do\\
  echo \$x\\
done
: 200:0;b
: 300:0;c"
}

test_exact_duplicates_removed_once() {
    printf ': 100:0;a\n: 200:0;b\n' >"$SANDBOX/one"
    printf ': 200:0;b\n: 200:0;b2\n' >"$SANDBOX/two"
    merge "$SANDBOX/out" "$SANDBOX/one" "$SANDBOX/two"
    assert_eq "$(cat "$SANDBOX/out")" ": 100:0;a
: 200:0;b
: 200:0;b2"
}

# Lines from before EXTENDED_HISTORY have no timestamp: they keep their place
# after the entry before them (or at the top).
test_plain_lines_keep_their_place() {
    printf 'old1\nold2\n: 300:0;c\nlate-plain\n' >"$SANDBOX/one"
    printf ': 200:0;b\n: 400:0;d\n' >"$SANDBOX/two"
    merge "$SANDBOX/out" "$SANDBOX/one" "$SANDBOX/two"
    assert_eq "$(cat "$SANDBOX/out")" "old1
old2
: 200:0;b
: 300:0;c
late-plain
: 400:0;d"
}

test_bytes_kept_and_private_mode() {
    printf ': 100:0;echo caf\xc3\xa9 \x83\x80\n' >"$SANDBOX/one"
    merge "$SANDBOX/out" "$SANDBOX/one"
    cmp -s "$SANDBOX/one" "$SANDBOX/out" || fail "bytes changed"
    assert_eq "$(stat -c %a "$SANDBOX/out")" 600
}

test_missing_input_skipped_and_output_may_be_an_input() {
    printf ': 200:0;b\n' >"$SANDBOX/out"
    printf ': 100:0;a\n' >"$SANDBOX/one"
    merge "$SANDBOX/out" "$SANDBOX/out" "$SANDBOX/one" "$SANDBOX/missing" || fail "merge failed"
    assert_eq "$(cat "$SANDBOX/out")" ": 100:0;a
: 200:0;b"
}

test_usage_error() {
    merge 2>/dev/null && fail "ran without arguments"
    return 0
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
