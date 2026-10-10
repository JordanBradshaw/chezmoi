#!/usr/bin/env bash
#
# Tests for `bootstrap.sh apps`.
#
# Package managers, sudo and eget are replaced by stubs on a sandboxed PATH
# that only log their arguments, so nothing is really installed.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$REPO_DIR/bootstrap.sh"
BASH_BIN="$(command -v bash)"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Sandbox helpers
# ---------------------------------------------------------------------------

setup() {
    SANDBOX="$(mktemp -d)"
    STUBS="$SANDBOX/stubs"
    export HOME="$SANDBOX/home"
    export STUB_LOG="$SANDBOX/calls.log"
    mkdir -p "$STUBS" "$HOME"
    : >"$STUB_LOG"

    # Real tools the script may need, without exposing real package managers.
    local tool
    for tool in mkdir; do
        ln -s "$(command -v "$tool")" "$STUBS/$tool"
    done

    unset REMOTE_CONTAINERS CODESPACES APPS_FORCE_EXTRA DRY_RUN STUB_FAIL_PKGS
    stub sudo
}

teardown() {
    rm -rf "$SANDBOX"
}

# stub NAME: create a fake command that logs "NAME args..." and fails if any
# argument appears in $STUB_FAIL_PKGS. `sudo` logs and runs its arguments.
stub() {
    local name="$1"
    if [[ $name == sudo ]]; then
        cat >"$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $1" >>"$STUB_LOG"
exec "$@"
EOF
    else
        cat >"$STUBS/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >>"\$STUB_LOG"
for arg in "\$@"; do
    for bad in \${STUB_FAIL_PKGS:-}; do
        [[ \$arg == "\$bad" ]] && exit 1
    done
done
exit 0
EOF
    fi
    chmod +x "$STUBS/$name"
}

# Shebangs use /usr/bin/env, so stubs need env and bash on PATH as well.
link_runtime() {
    ln -s "$(command -v env)" "$STUBS/env"
    ln -s "$BASH_BIN" "$STUBS/bash"
}

run_apps() {
    OUTPUT="$(PATH="$STUBS" "$BASH_BIN" "$BOOTSTRAP" apps "$@" 2>&1)"
    STATUS=$?
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    echo "    --- output ---"
    sed 's/^/    /' <<<"$OUTPUT"
    echo "    --- calls ---"
    sed 's/^/    /' "$STUB_LOG"
    FAIL=$((FAIL + 1))
    return 1
}

assert_status() {
    [[ $STATUS -eq $1 ]] || fail "expected exit $1, got $STATUS"
}

assert_call() {
    grep -qxF -- "$1" "$STUB_LOG" || fail "missing call: $1"
}

assert_call_matches() {
    grep -qE -- "$1" "$STUB_LOG" || fail "no call matches: $1"
}

refute_call_matches() {
    ! grep -qE -- "$1" "$STUB_LOG" || fail "unexpected call matches: $1"
}

assert_output_matches() {
    grep -qE -- "$1" <<<"$OUTPUT" || fail "output does not match: $1"
}

assert_no_calls() {
    [[ ! -s $STUB_LOG ]] || fail "expected no stub calls"
}

run_test() {
    CURRENT="$1"
    setup
    link_runtime
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

CORE_APT="curl git unzip stow fzf bat lsd ripgrep fd-find git-delta fonts-firacode"

test_apt_core_installs_core_in_one_batch() {
    stub apt-get
    run_apps
    assert_status 0
    assert_call "apt-get update"
    assert_call "apt-get install -y --no-install-recommends $CORE_APT"
    refute_call_matches "apt-get install .*\bgh\b"
}

test_apps_does_not_try_to_install_stow_first() {
    stub apt-get
    run_apps
    assert_call_matches "^apt-get install -y --no-install-recommends curl "
    refute_call_matches "^apt-get install -y stow$"
}

test_apt_extra_adds_extras_and_uses_eget_for_nushell() {
    stub apt-get
    stub eget
    run_apps --extra
    assert_status 0
    assert_call_matches "^apt-get install .*\bfd-find\b.*\bfonts-firacode\b"
    assert_call_matches "^apt-get install .*\bgh\b"
    assert_call_matches "^apt-get install .*\bmiller\b"
    assert_call_matches "^apt-get install .*\bbtm\b"
    assert_call_matches "^apt-get install .*\bdu-dust\b"
    refute_call_matches "^apt-get install .*nushell"
    assert_call "eget nushell/nushell --file nu --asset musl --to $HOME/.local/bin"
}

test_apt_extra_skips_eget_when_binary_present() {
    stub apt-get
    stub eget
    stub nu
    run_apps --extra
    assert_status 0
    refute_call_matches "^eget "
}

test_pacman_uses_pacman_names() {
    stub pacman
    stub eget
    run_apps --extra
    assert_status 0
    assert_call_matches "^pacman -S --needed --noconfirm curl .*\bfd\b.*\bgit-delta\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bttf-fira-code\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bgithub-cli\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bbottom\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bnushell\b"
    refute_call_matches "^eget "
}

test_dnf_uses_dnf_names() {
    stub dnf
    run_apps
    assert_status 0
    assert_call "dnf install -y curl git unzip stow fzf bat lsd ripgrep fd-find git-delta fira-code-fonts"
}

test_brew_runs_without_sudo() {
    stub brew
    run_apps
    assert_status 0
    assert_call "brew install curl git unzip stow fzf bat lsd ripgrep fd git-delta font-fira-code"
    refute_call_matches "^sudo "
}

test_batch_failure_falls_back_to_one_by_one() {
    stub apt-get
    stub eget
    export STUB_FAIL_PKGS="tailspin"
    run_apps --extra
    assert_status 1
    assert_call "apt-get install -y --no-install-recommends gh"
    assert_call "apt-get install -y --no-install-recommends tailspin"
    assert_output_matches "[Ff]ailed.*tailspin"
}

test_failed_install_falls_back_to_eget() {
    stub pacman
    stub eget
    export STUB_FAIL_PKGS="nushell"
    run_apps --extra
    assert_status 0
    assert_call "eget nushell/nushell --file nu --asset musl --to $HOME/.local/bin"
}

test_container_ignores_extra() {
    stub apt-get
    export REMOTE_CONTAINERS=true
    run_apps --extra
    assert_status 0
    refute_call_matches "^apt-get install .*\bgh\b"
    assert_output_matches "container"
}

test_container_force_extra() {
    stub apt-get
    stub eget
    export CODESPACES=true APPS_FORCE_EXTRA=1
    run_apps --extra
    assert_status 0
    assert_call_matches "^apt-get install .*\bgh\b"
}

test_dry_run_prints_without_running() {
    stub apt-get
    export DRY_RUN=1
    run_apps
    assert_status 0
    assert_no_calls
    assert_output_matches "apt-get install -y --no-install-recommends $CORE_APT"
}

test_unknown_option_fails() {
    stub apt-get
    run_apps --bogus
    assert_status 2
    assert_no_calls
}

test_no_package_manager_fails() {
    run_apps
    assert_status 1
    assert_output_matches "[Nn]o supported package manager"
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
