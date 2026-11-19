#!/usr/bin/env bash
#
# Tests for scripts/set-login-shell.sh and its chezmoi run_onchange script.
# zsh, getent and chsh are stubs on a PATH without the real ones; nothing
# changes the real login shell.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/set-login-shell.sh"
TEMPLATE="$REPO_DIR/home/.chezmoiscripts/run_onchange_after_15-login-shell.sh.tmpl"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    STUBS="$SANDBOX/stubs"
    export STUB_LOG="$SANDBOX/calls.log" SHELLS_FILE="$SANDBOX/shells"
    export STUB_LOGIN_SHELL=/bin/bash
    unset STUB_CHSH_FAIL
    mkdir -p "$STUBS"
    : >"$STUB_LOG"
    local tool
    for tool in id cut grep; do
        ln -s "$(command -v "$tool")" "$STUBS/$tool"
    done
    printf '#!%s\nexit 0\n' "$BASH_BIN" >"$STUBS/zsh"
    printf '#!%s\necho "me:x:1000:1000::/home/me:$STUB_LOGIN_SHELL"\n' "$BASH_BIN" >"$STUBS/getent"
    printf '#!%s\necho "chsh $*" >>"$STUB_LOG"\n[[ -z ${STUB_CHSH_FAIL:-} ]]\n' "$BASH_BIN" >"$STUBS/chsh"
    chmod +x "$STUBS/zsh" "$STUBS/getent" "$STUBS/chsh"
    printf '/bin/bash\n%s\n' "$STUBS/zsh" >"$SHELLS_FILE"
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
assert_status() { [[ $STATUS -eq $1 ]] || fail "exit status $STATUS, expected $1: $OUTPUT"; }
assert_match() { [[ $1 =~ $2 ]] || fail "'$1' does not match '$2'"; }
calls() { cat "$STUB_LOG"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

run_script() {
    OUTPUT="$(PATH="$STUBS" "$BASH_BIN" "$SCRIPT" 2>&1)"
    STATUS=$?
}

# render MACHINE: the login-shell template for MACHINE, stdin not a tty.
render() {
    printf '[data]\n    machine = "%s"\n    hasSecrets = false\n' "$1" >"$SANDBOX/c.toml"
    chezmoi --source="$REPO_DIR" --config="$SANDBOX/c.toml" --persistent-state="$SANDBOX/s.db" \
        --destination="$SANDBOX/home" execute-template <"$TEMPLATE" 2>/dev/null
}

# render_tty MACHINE: the template rendered with a terminal on stdin.
# script(1) provides it; the template is an argument so stdin stays the
# terminal. Callers skip with no_script first.
no_script() {
    command -v script >/dev/null 2>&1 && return 1
    echo "  skip $CURRENT: no script(1)"
}

render_tty() {
    printf '[data]\n    machine = "%s"\n    hasSecrets = false\n' "$1" >"$SANDBOX/c.toml"
    script -qec "chezmoi --source='$REPO_DIR' --config='$SANDBOX/c.toml' \
        --persistent-state='$SANDBOX/s.db' --destination='$SANDBOX/home' \
        execute-template \"\$(cat '$TEMPLATE')\"" /dev/null </dev/null 2>/dev/null | tr -d '\r'
}

# ---------------------------------------------------------------------------

test_already_zsh_no_chsh() {
    STUB_LOGIN_SHELL=/usr/bin/zsh run_script
    assert_status 0
    assert_eq "$(calls)" ""
}

test_bash_runs_chsh() {
    run_script
    assert_status 0
    assert_eq "$(calls)" "chsh -s $STUBS/zsh"
}

# stub_sudo STATUS: sudo that logs its arguments and exits STATUS.
stub_sudo() {
    printf '#!%s\necho "sudo $*" >>"$STUB_LOG"\nexit %s\n' "$BASH_BIN" "$1" >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
}

# Cloud VM users often have passwordless sudo but no password for chsh.
test_passwordless_sudo_runs_chsh() {
    stub_sudo 0
    run_script
    assert_status 0
    assert_eq "$(calls)" "sudo -n chsh -s $STUBS/zsh $(id -un)"
}

test_sudo_needing_password_falls_back_to_chsh() {
    stub_sudo 1
    run_script
    assert_status 0
    assert_eq "$(calls)" "sudo -n chsh -s $STUBS/zsh $(id -un)"$'\n'"chsh -s $STUBS/zsh"
}

test_zsh_not_in_shells_warns_no_chsh() {
    printf '/bin/bash\n' >"$SHELLS_FILE"
    run_script
    assert_status 0
    assert_eq "$(calls)" ""
    assert_match "$OUTPUT" "not in $SHELLS_FILE"
}

test_chsh_failure_exits_0() {
    STUB_CHSH_FAIL=1 run_script
    assert_status 0
    assert_eq "$(calls)" "chsh -s $STUBS/zsh"
    assert_match "$OUTPUT" "warning"
}

test_no_zsh_warns_exits_0() {
    rm "$STUBS/zsh"
    run_script
    assert_status 0
    assert_eq "$(calls)" ""
    assert_match "$OUTPUT" "zsh not found"
}

test_template_empty_for_container() {
    local out
    no_script && return 0
    out="$(render_tty container)" || fail "chezmoi failed: $out"
    [[ $out != *set-login-shell* ]] || fail "container runs set-login-shell: $out"
}

test_template_empty_without_tty() {
    local out
    out="$(render server)"
    assert_eq "${out//[[:space:]]/}" ""
}

test_template_runs_script_on_tty() {
    local out
    no_script && return 0
    out="$(render_tty server)" || fail "chezmoi failed: $out"
    assert_match "$out" "set-login-shell.sh hash: [0-9a-f]{64}"
    assert_match "$out" "exec \"$REPO_DIR/scripts/set-login-shell.sh\""
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
