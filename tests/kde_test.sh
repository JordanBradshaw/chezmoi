#!/usr/bin/env bash
#
# Tests for the kde data flag: how .chezmoi.toml.tmpl sets it on init, and
# the kde template every KDE-only file reads it through. PATH is a sandbox
# dir, so a real plasmashell never leaks in.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHEZMOI="$(command -v chezmoi)"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    STUBS="$SANDBOX/stubs"
    mkdir -p "$STUBS" "$SANDBOX/home"
    OUTPUT=""
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
assert_line() { grep -qxF -- "$2" <<<"$1" || fail "no line '$2' in: $1"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

stub_plasmashell() {
    printf '#!%s\nexit 0\n' "$BASH_BIN" >"$STUBS/plasmashell"
    chmod +x "$STUBS/plasmashell"
}

# config DATA_LINES...: a saved config with the given [data] lines.
config() {
    { printf '[data]\n    hasSecrets = false\n'; printf '    %s\n' "$@"; } >"$SANDBOX/c.toml"
}

# cz ARGS...: chezmoi on the repo with the sandbox config and PATH.
cz() {
    PATH="$STUBS" "$CHEZMOI" --source="$REPO_DIR" --config="$SANDBOX/c.toml" \
        --persistent-state="$SANDBOX/s.db" --destination="$SANDBOX/home" "$@" 2>/dev/null
}

init_config() { cz execute-template --init <"$REPO_DIR/home/.chezmoi.toml.tmpl"; }
helper() { cz execute-template '{{ includeTemplate "kde" . }}'; }

# ---------------------------------------------------------------------------

test_plasmashell_sets_kde() {
    stub_plasmashell
    config 'machine = "desktop"'
    assert_line "$(init_config)" "    kde = true"
}

test_desktop_without_plasmashell_non_tty_is_false() {
    config 'machine = "desktop"'
    assert_line "$(init_config)" "    kde = false"
}

# script(1) gives chezmoi a terminal on stdin, so the question is asked;
# --promptBool answers it.
test_desktop_without_plasmashell_tty_asks() {
    local script_bin
    script_bin="$(command -v script)" || { echo "  skip $CURRENT: no script(1)"; return 0; }
    ln -s "$(command -v cat)" "$STUBS/cat"
    config 'machine = "desktop"' 'appsBuild = "prebuilt"'
    local out
    out="$(PATH="$STUBS" "$script_bin" -qec "'$CHEZMOI' --source='$REPO_DIR' --config='$SANDBOX/c.toml' \
        --persistent-state='$SANDBOX/s.db' --destination='$SANDBOX/home' execute-template --init \
        --promptBool 'Is this machine using KDE=true' \"\$(cat '$REPO_DIR/home/.chezmoi.toml.tmpl')\"" \
        /dev/null </dev/null 2>/dev/null | tr -d '\r')"
    assert_line "$out" "    kde = true"
}

test_server_is_false_even_with_plasmashell() {
    stub_plasmashell
    config 'machine = "server"'
    assert_line "$(init_config)" "    kde = false"
}

test_saved_kde_false_wins_over_plasmashell() {
    stub_plasmashell
    config 'machine = "desktop"' 'kde = false'
    assert_line "$(init_config)" "    kde = false"
}

test_helper_falls_back_to_machine_without_key() {
    config 'machine = "desktop"'
    assert_eq "$(helper)" "true"
    config 'machine = "server"'
    assert_eq "$(helper)" "false"
}

test_helper_uses_kde_key() {
    config 'machine = "desktop"' 'kde = false'
    assert_eq "$(helper)" "false"
    config 'machine = "server"' 'kde = true'
    assert_eq "$(helper)" "true"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
