#!/usr/bin/env bash
#
# Tests for apps/apps.tsv, apps/lib.sh and the portable/lib.sh seam
# (resolve_chezmoi_src). Every test sources the libs in a subshell.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_LIB="$REPO_DIR/apps/lib.sh"
APPS_TSV="$REPO_DIR/apps/apps.tsv"
SHIM="$REPO_DIR/portable/lib.sh"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    export SANDBOX
    unset CHEZMOI_SRC APPS_FILE
    OUTPUT=""
    STATUS=0
}

teardown() {
    rm -rf "$SANDBOX"
}

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_match() { [[ $1 =~ $2 ]] || fail "expected match '$2', got '$1'"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# al CODE: run CODE in a bash with apps/lib.sh sourced under set -u.
al() {
    OUTPUT="$("$BASH_BIN" -c "set -u; source '$APPS_LIB'; $1" 2>&1)"
    STATUS=$?
}

# real CODE: like al, with the real manifest loaded.
real() { al "apps_load '$APPS_TSV' || exit 9; $1"; }

HEADER='# name tier bundle apt pacman dnf brew release file assets build'
RG_ROW='rg core y ripgrep ripgrep ripgrep ripgrep BurntSushi/ripgrep rg musl|gnu crate:ripgrep:rg'

test_real_manifest_loads() {
    al "apps_load '$APPS_TSV'"
    assert_eq "$STATUS" 0
}

test_header_must_name_every_column() {
    printf '%s\n' '# name tier bundle apt pacman dnf brew release file assets' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" 'header'
}

test_short_row_names_line() {
    printf '%s\n\n%s\n' "$HEADER" 'rg core y a b c d e f g' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" "a.tsv:3: 10 fields, expected 11"
}

test_duplicate_name_fails() {
    printf '%s\n%s\n%s\n' "$HEADER" "$RG_ROW" "$RG_ROW" >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" 'duplicate rg'
}

test_columns_read_by_name() {
    printf '%s\n%s\n' '# build tier bundle apt pacman dnf brew release file assets name' \
        'crate:ripgrep:rg core y a b c d e f g rg' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv' && app rg build"
    assert_eq "$OUTPUT" "crate:ripgrep:rg"
}

test_known_tiers() {
    real 'for n in "${APPS_NAMES[@]}"; do
        case $(app "$n" tier) in core|extra|desktop|-) ;; *) echo "$n: bad tier $(app "$n" tier)" ;; esac
    done'
    assert_eq "$OUTPUT" ""
}

test_bundle_rows_have_a_source() {
    real 'for n in $(apps_names --bundle); do
        [[ $(app "$n" release) != - || $(app "$n" build) != - ]] || echo "$n: no release and no build"
    done'
    assert_eq "$OUTPUT" ""
}

test_known_build_sources() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" build) =~ ^(crate:[a-z0-9_-]+(:[A-Za-z0-9_-]+)?(:.*)?|go:[^[:space:]]+|cross:[a-z0-9-]+|-)$ ]] ||
            echo "$n: bad build $(app "$n" build)"
    done'
    assert_eq "$OUTPUT" ""
}

test_cross_rows_have_no_release() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" build) == cross:* && $(app "$n" release) != - ]] && echo "$n: cross row has release"
    done
    app tmux build'
    assert_eq "$OUTPUT" "cross:tmux"
}

test_lock_names_in_manifest() {
    local n=0
    for lock in "$REPO_DIR"/apps/locks/*.lock; do
        n=$((n + 1))
        real "while IFS=\$'\\t' read -r name src ver; do
            [[ \$name == '#'* || -z \$name ]] && continue
            [[ \$(app \"\$name\" bundle) == y ]] || { echo \"\$name: not a bundle row\"; continue; }
            want=\$(app \"\$name\" build); [[ \$want == - ]] && want=release
            [[ \$src == \"\$want\" ]] || echo \"\$name: lock source \$src, manifest \$want\"
        done <'$lock'"
        [[ -z $OUTPUT ]] || fail "$(basename "$lock"): $OUTPUT"
    done
    ((n >= 2)) || fail "expected locks in apps/locks"
}

test_merged_rows() {
    real 'printf "%s|" "$(app rg apt)" "$(app tspin tier)" "$(app nu release)" "$(app atuin build)" "$(app lazydocker tier)" "$(app firacode bundle)"'
    assert_eq "$OUTPUT" "ripgrep|extra|nushell/nushell|-|-|-|"
}

test_apps_names_filters() {
    real 'apps_names --tier core | tr "\n" " "; echo; apps_names --bundle | tr "\n" " "'
    local core=" ${OUTPUT%%$'\n'*}" bundle=" ${OUTPUT#*$'\n'}"
    assert_match "$core" ' curl '
    [[ $core != *lazydocker* ]] || fail "core has lazydocker"
    assert_match "$bundle" 'lazydocker'
    [[ " $bundle" != *' curl '* ]] || fail "bundle has curl"
}

# shim CODE: run CODE after sourcing portable/lib.sh.
shim() {
    OUTPUT="$("$BASH_BIN" -c "source '$SHIM'; $1" 2>&1)"
    STATUS=$?
}

test_resolve_chezmoi_src_order() {
    local a="$SANDBOX/a" b="$SANDBOX/b" c="$SANDBOX/c"
    mkdir -p "$SANDBOX/bin"
    for d in "$a" "$b" "$c"; do mkdir -p "$d/apps"; cp "$APPS_TSV" "$APPS_LIB" "$d/apps/"; done
    git -C "$c" init -q
    printf '#!/bin/sh\necho %s/apps\n' "$c" >"$SANDBOX/bin/chezmoi"
    chmod +x "$SANDBOX/bin/chezmoi"
    export PATH="$SANDBOX/bin:$PATH"
    shim "resolve_chezmoi_src '$a'; echo \$CHEZMOI_SRC" # no env set: explicit wins
    assert_eq "$OUTPUT" "$a"
    CHEZMOI_SRC="$b" shim "resolve_chezmoi_src '$a'; echo \$CHEZMOI_SRC"
    assert_eq "$OUTPUT" "$a"
    CHEZMOI_SRC="$b" shim "resolve_chezmoi_src; echo \$CHEZMOI_SRC"
    assert_eq "$OUTPUT" "$b"
    shim "resolve_chezmoi_src; echo \$CHEZMOI_SRC"
    assert_eq "$OUTPUT" "$c"
    shim "resolve_chezmoi_src '$a'; type -t apps_load"
    assert_eq "$OUTPUT" "function"
}

test_resolve_chezmoi_src_rejects_tree_without_apps() {
    mkdir -p "$SANDBOX/old"
    shim "resolve_chezmoi_src '$SANDBOX/old'"
    assert_eq "$STATUS" 1
    assert_eq "$OUTPUT" "no apps/apps.tsv in $SANDBOX/old (set CHEZMOI_SRC or --chezmoi to a chezmoi checkout)"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
