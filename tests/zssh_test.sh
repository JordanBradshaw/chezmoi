#!/usr/bin/env bash
#
# Tests for zssh.
#
# zssh runs against a stub ssh that executes remote commands locally with HOME
# pointing into a sandbox, and a stub builder that produces a tiny fake
# bundle, so nothing touches the network or a real host.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZSSH="$REPO_DIR/home/dot_local/bin/executable_zssh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Sandbox helpers
# ---------------------------------------------------------------------------

setup() {
    SANDBOX="$(mktemp -d)"
    STUBS="$SANDBOX/stubs"
    export REMOTE_HOME="$SANDBOX/remote-home"
    export STUB_LOG="$SANDBOX/calls.log"
    export DIST="$SANDBOX/dist"
    export REMOTE_ARCH=aarch64
    export FAKE_VERSION=v1
    unset REMOTE_PATH_ONLY
    mkdir -p "$STUBS" "$REMOTE_HOME" "$DIST"
    : >"$STUB_LOG"
    OUTPUT=""
    STATUS=0
}

teardown() {
    rm -rf "$SANDBOX"
}

# stub_remote: fake ssh and builder for zssh.
stub_remote() {
    # Remote commands see this uname.
    mkdir -p "$SANDBOX/remote-bin"
    cat >"$SANDBOX/remote-bin/uname" <<'EOF'
#!/bin/sh
echo "$REMOTE_ARCH"
EOF
    chmod +x "$SANDBOX/remote-bin/uname"

    cat >"$STUBS/ssh" <<'EOF'
#!/usr/bin/env bash
echo "ssh $*" >>"$STUB_LOG"
args=("$@")
i=0
while (( i < ${#args[@]} )); do
    case ${args[i]} in
        -[oipJlFSEcmbLRDWO]) i=$((i + 2)) ;;
        -*) i=$((i + 1)) ;;
        *) break ;;
    esac
done
host=${args[i]}
cmd="${args[*]:i+1}"
echo "host $host" >>"$STUB_LOG"
[[ -n $cmd ]] || { echo "stub ssh: no command" >&2; exit 255; }
if [[ -n ${REMOTE_PATH_ONLY:-} ]]; then
    remote_path="$SANDBOX_REMOTE_BIN"
else
    remote_path="$SANDBOX_REMOTE_BIN:$PATH"
fi
HOME="$REMOTE_HOME" PATH="$remote_path" exec sh -c "$cmd"
EOF
    chmod +x "$STUBS/ssh"
    export SANDBOX_REMOTE_BIN="$SANDBOX/remote-bin"

    cat >"$STUBS/build.sh" <<'EOF'
#!/usr/bin/env bash
echo "build $*" >>"$STUB_LOG"
[[ $1 == --arch ]] || exit 2
case $2 in aarch64|armv7l|x86_64) ;; *) echo "unsupported arch: $2" >&2; exit 1 ;; esac
app="$(mktemp -d)"
printf '%s\n' "$FAKE_VERSION" >"$app/VERSION"
cat >"$app/setup.sh" <<'SETUP'
#!/bin/sh
echo "setup $1" >>"$HOME/remote.log"
SETUP
cat >"$app/enter" <<'ENTER'
#!/bin/sh
echo "enter $(cat "$(dirname "$0")/VERSION")" >>"$HOME/remote.log"
ENTER
chmod +x "$app/setup.sh" "$app/enter"
out="$DIST/zsh-portable-$2.tar.gz"
tar -czf "$out" -C "$app" .
printf '%s\n' "$FAKE_VERSION" >"$DIST/zsh-portable-$2.version"
rm -rf "$app"
echo "$out"
EOF
    chmod +x "$STUBS/build.sh"

    # Local fonts, as fc-list : family prints them.
    export FAKE_FONTS="FiraCode Nerd Font"
    cat >"$STUBS/fc-list" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_FONTS"
EOF
    chmod +x "$STUBS/fc-list"
}

run_zssh() {
    OUTPUT="$(PATH="$STUBS:$PATH" ZSSH_BUILDER="$STUBS/build.sh" \
        XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" "$@" 2>&1)"
    STATUS=$?
}

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

assert_eq() {
    [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"
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

assert_file_contains() {
    grep -qE -- "$2" "$1" 2>/dev/null || fail "$1 does not match: $2"
}

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# ---------------------------------------------------------------------------
# zssh
# ---------------------------------------------------------------------------

test_zssh_installs_bundle_and_enters() {
    stub_remote
    run_zssh jetson
    assert_status 0
    assert_call_matches "^build --arch aarch64$"
    assert_eq "$(cat "$REMOTE_HOME/.zsh-portable/app/VERSION" 2>/dev/null)" v1
    assert_file_contains "$REMOTE_HOME/remote.log" "^setup $REMOTE_HOME/.zsh-portable/app$"
    assert_file_contains "$REMOTE_HOME/remote.log" "^enter v1$"
    assert_call_matches "^ssh .*-t.* jetson "
}

test_zssh_skips_upload_when_version_matches() {
    stub_remote
    run_zssh jetson
    : >"$REMOTE_HOME/remote.log"
    run_zssh jetson
    assert_status 0
    grep -q '^setup' "$REMOTE_HOME/remote.log" && fail "bundle uploaded again"
    assert_file_contains "$REMOTE_HOME/remote.log" "^enter v1$"
}

test_zssh_replaces_app_and_keeps_state() {
    stub_remote
    run_zssh jetson
    echo "history" >"$REMOTE_HOME/.zsh-portable/state/keep"
    FAKE_VERSION=v2 run_zssh jetson
    assert_status 0
    assert_eq "$(cat "$REMOTE_HOME/.zsh-portable/app/VERSION")" v2
    assert_eq "$(cat "$REMOTE_HOME/.zsh-portable/state/keep")" history
    [[ -e $REMOTE_HOME/.zsh-portable/app.new || -e $REMOTE_HOME/.zsh-portable/app.old ]] \
        && fail "leftover app.new/app.old"
    return 0
}

test_zssh_probe_does_not_read_stdin() {
    stub_remote
    run_zssh jetson
    assert_call_matches "^ssh -n .* jetson uname -m"
}

test_zssh_sends_plain_tar_without_remote_gzip() {
    stub_remote
    # Remote PATH without gzip: tar can't decompress there.
    local t
    for t in sh tar mkdir rm mv cat dirname; do
        ln -s "$(command -v "$t")" "$SANDBOX/remote-bin/$t"
    done
    export REMOTE_PATH_ONLY=1
    run_zssh jetson
    assert_status 0
    assert_eq "$(cat "$REMOTE_HOME/.zsh-portable/app/VERSION" 2>/dev/null)" v1
    assert_output_matches "no gzip"
}

test_zssh_fails_clearly_without_remote_tar() {
    stub_remote
    local t
    for t in sh mkdir rm mv cat dirname; do
        ln -s "$(command -v "$t")" "$SANDBOX/remote-bin/$t"
    done
    export REMOTE_PATH_ONLY=1
    run_zssh jetson
    [[ $STATUS -ne 0 ]] || fail "expected failure"
    assert_output_matches "needs tar"
    refute_call_matches "^ssh .* -t "
}

test_zssh_passes_ssh_options() {
    stub_remote
    run_zssh -p 2222 -J bastion jetson
    assert_status 0
    assert_call_matches "^ssh .*-p 2222 -J bastion jetson"
    assert_call_matches "^host jetson$"
}

test_zssh_maps_remote_arch() {
    stub_remote
    REMOTE_ARCH=armv7l run_zssh pi
    assert_status 0
    assert_call_matches "^build --arch armv7l$"
}

test_zssh_rebuild_flag_forces_build() {
    stub_remote
    run_zssh --rebuild jetson
    assert_status 0
    assert_call_matches "^build --arch aarch64 --force$"
}

test_zssh_unsupported_arch_fails_without_session() {
    stub_remote
    REMOTE_ARCH=mips run_zssh router
    [[ $STATUS -ne 0 ]] || fail "expected failure"
    refute_call_matches "^ssh .* -t "
}

test_zssh_requires_host() {
    stub_remote
    run_zssh
    assert_status 2
    assert_output_matches "[Uu]sage"
}

test_zssh_custom_remote_dir() {
    stub_remote
    ZSSH_REMOTE_DIR="$SANDBOX/elsewhere" run_zssh jetson
    assert_status 0
    assert_eq "$(cat "$SANDBOX/elsewhere/app/VERSION" 2>/dev/null)" v1
}

# The local terminal draws the icons; the remote side can't supply a font.
test_zssh_warns_without_local_nerd_font() {
    stub_remote
    FAKE_FONTS=$'Fira Code\nDejaVu Sans Mono' run_zssh jetson
    assert_status 0
    assert_output_matches "no Nerd Font"
    assert_file_contains "$REMOTE_HOME/remote.log" "^enter v1$"
}

test_zssh_quiet_with_local_nerd_font() {
    stub_remote
    FAKE_FONTS=$'Fira Code\nFiraCode Nerd Font Mono' run_zssh jetson
    assert_status 0
    grep -q "Nerd Font" <<<"$OUTPUT" && fail "warned despite a Nerd Font"
    return 0
}

test_zssh_uses_zssh_deploy() {
    stub_remote
    mkdir -p "$SANDBOX/deploy/portable"
    cp "$STUBS/build.sh" "$SANDBOX/deploy/portable/build.sh"
    OUTPUT="$(env -u ZSSH_BUILDER PATH="$STUBS:$PATH" ZSSH_DEPLOY="$SANDBOX/deploy" \
        CHEZMOI_SRC="$SANDBOX" XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 0
    assert_call_matches "^build --arch aarch64$"
}

test_zssh_falls_back_to_chezmoi_external() {
    stub_remote
    mkdir -p "$SANDBOX/xdg/chezmoi-deploy/portable"
    cp "$STUBS/build.sh" "$SANDBOX/xdg/chezmoi-deploy/portable/build.sh"
    OUTPUT="$(env -u ZSSH_BUILDER -u ZSSH_DEPLOY PATH="$STUBS:$PATH" XDG_DATA_HOME="$SANDBOX/xdg" \
        CHEZMOI_SRC="$SANDBOX" XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 0
    assert_call_matches "^build --arch aarch64$"
}

test_zssh_without_wrapper_fails_clearly() {
    stub_remote
    OUTPUT="$(env -u ZSSH_BUILDER -u ZSSH_DEPLOY PATH="$STUBS:$PATH" XDG_DATA_HOME="$SANDBOX/none" \
        CHEZMOI_SRC="$SANDBOX" XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 1
    assert_output_matches "zssh: no chezmoi-deploy checkout; set ZSSH_DEPLOY or run chezmoi apply on a desktop"
    refute_call_matches "^ssh "
}

test_zssh_exports_chezmoi_src() {
    stub_remote
    sed -i '2a echo "CHEZMOI_SRC=$CHEZMOI_SRC" >>"$STUB_LOG"' "$STUBS/build.sh"
    mkdir -p "$SANDBOX/cz/home"
    git init -q "$SANDBOX/cz"
    printf '#!/bin/sh\necho "%s"\n' "$SANDBOX/cz/home" >"$STUBS/chezmoi"
    chmod +x "$STUBS/chezmoi"
    OUTPUT="$(env -u CHEZMOI_SRC PATH="$STUBS:$PATH" ZSSH_BUILDER="$STUBS/build.sh" \
        XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 0
    assert_call_matches "^CHEZMOI_SRC=$SANDBOX/cz$"
}

test_zssh_unset_chezmoi_src_without_chezmoi_fails() {
    stub_remote
    mkdir -p "$SANDBOX/deploy/portable"
    cp "$STUBS/build.sh" "$SANDBOX/deploy/portable/build.sh"
    OUTPUT="$(env -u ZSSH_BUILDER -u CHEZMOI_SRC PATH="$STUBS:/usr/bin:/bin" ZSSH_DEPLOY="$SANDBOX/deploy" \
        XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 1
    assert_eq "$OUTPUT" "zssh: set CHEZMOI_SRC to your chezmoi checkout"
    refute_call_matches "^ssh "
}

test_zssh_failing_chezmoi_ignores_cwd_repo() {
    stub_remote
    mkdir -p "$SANDBOX/deploy/portable" "$SANDBOX/other"
    cp "$STUBS/build.sh" "$SANDBOX/deploy/portable/build.sh"
    git init -q "$SANDBOX/other"
    printf '#!/bin/sh\necho boom >&2\nexit 1\n' >"$STUBS/chezmoi"
    chmod +x "$STUBS/chezmoi"
    OUTPUT="$(cd "$SANDBOX/other" && env -u ZSSH_BUILDER -u CHEZMOI_SRC PATH="$STUBS:/usr/bin:/bin" \
        ZSSH_DEPLOY="$SANDBOX/deploy" XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 1
    assert_eq "$OUTPUT" "zssh: set CHEZMOI_SRC to your chezmoi checkout"
    refute_call_matches "^ssh "
}

test_zssh_builder_override_tolerates_failing_chezmoi() {
    stub_remote
    printf '#!/bin/sh\necho boom >&2\nexit 1\n' >"$STUBS/chezmoi"
    chmod +x "$STUBS/chezmoi"
    OUTPUT="$(env -u CHEZMOI_SRC PATH="$STUBS:$PATH" ZSSH_BUILDER="$STUBS/build.sh" \
        XDG_RUNTIME_DIR="$SANDBOX" bash "$ZSSH" jetson 2>&1)"
    STATUS=$?
    assert_status 0
    ! grep -q boom <<<"$OUTPUT" || fail "chezmoi stderr leaked"
}

test_deploy_external_desktop_only() {
    local m
    for m in desktop server; do
        printf '[data]\n    machine = "%s"\n    hasSecrets = false\n' "$m" >"$SANDBOX/chezmoi.toml"
        OUTPUT="$(chezmoi --source="$REPO_DIR" --config="$SANDBOX/chezmoi.toml" \
            --persistent-state="$SANDBOX/p.db" --destination="$SANDBOX/dest" execute-template \
            <"$REPO_DIR/home/.chezmoiexternal.toml.tmpl" 2>/dev/null)"
        if [[ $m == desktop ]]; then
            grep -qF '[".local/share/chezmoi-deploy"]' <<<"$OUTPUT" || fail "desktop lacks chezmoi-deploy external"
        else
            ! grep -qF '[".local/share/chezmoi-deploy"]' <<<"$OUTPUT" || fail "server has chezmoi-deploy external"
        fi
    done
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
