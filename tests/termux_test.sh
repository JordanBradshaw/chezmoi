#!/usr/bin/env bash
#
# Tests for Termux support in the chezmoi source: how .chezmoi.toml.tmpl
# detects it, the termux template other files read it through, and the
# Termux-only font. TERMUX_VERSION stands in for Termux; PATH is a sandbox
# dir so a real plasmashell never leaks in.

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
    unset TERMUX_VERSION
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
helper() { cz execute-template '{{ includeTemplate "termux" . }}'; }

# ---------------------------------------------------------------------------

test_termux_init_is_desktop_without_kde() {
    config
    OUTPUT="$(TERMUX_VERSION=0.118.1 init_config)"
    assert_line "$OUTPUT" '    machine = "desktop"'
    assert_line "$OUTPUT" "    termux = true"
    assert_line "$OUTPUT" "    kde = false"
}

test_saved_machine_wins_on_termux() {
    config 'machine = "server"'
    OUTPUT="$(TERMUX_VERSION=0.118.1 init_config)"
    assert_line "$OUTPUT" '    machine = "server"'
    assert_line "$OUTPUT" "    termux = true"
}

test_not_termux_elsewhere() {
    config 'machine = "desktop"'
    assert_line "$(init_config)" "    termux = false"
}

test_helper_reads_termux_key() {
    config 'machine = "desktop"' 'termux = true'
    assert_eq "$(helper)" "true"
    config 'machine = "desktop"' 'termux = false'
    assert_eq "$(helper)" "false"
}

test_helper_false_without_key() {
    config 'machine = "desktop"'
    assert_eq "$(helper)" "false"
}

# A get.chezmoi.io (linux) chezmoi can't resolve DNS on Android, so its
# archive externals would fail; Termux's package is built for Android.
test_install_sh_uses_pkg_chezmoi_on_termux() {
    local tool log="$SANDBOX/calls.log"
    for tool in dirname mkdir chmod; do ln -s "$(command -v "$tool")" "$STUBS/$tool"; done
    {
        printf '#!%s\n' "$BASH_BIN"
        printf 'echo "pkg $*" >>"%s"\n' "$log"
        printf 'printf "#!%s\\necho \\"chezmoi \\$*\\" >>%s\\n" >"%s"\n' "$BASH_BIN" "$log" "$STUBS/chezmoi"
        printf 'chmod +x "%s"\n' "$STUBS/chezmoi"
    } >"$STUBS/pkg"
    printf '#!%s\necho "curl $*" >>"%s"\nexit 1\n' "$BASH_BIN" "$log" >"$STUBS/curl"
    chmod +x "$STUBS/pkg" "$STUBS/curl"
    OUTPUT="$(HOME="$SANDBOX/home" TERMUX_VERSION=0.118.1 PATH="$STUBS" "$BASH_BIN" "$REPO_DIR/install.sh" 2>&1)"
    local calls
    calls="$(cat "$log" 2>/dev/null)"
    assert_line "$calls" "pkg install -y chezmoi"
    ! grep -q '^curl' <<<"$calls" || fail "fetched get.chezmoi.io: $calls"
    assert_line "$calls" "chezmoi apply"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
