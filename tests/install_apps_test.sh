#!/usr/bin/env bash
#
# Tests for scripts/install-apps.sh.
#
# Package managers, sudo and eget are replaced by stubs on a sandboxed PATH
# that only log their arguments, so nothing is really installed.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_APPS="$REPO_DIR/scripts/install-apps.sh"
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

    unset REMOTE_CONTAINERS CODESPACES APPS_FORCE_EXTRA APPS_FORCE_NALA DRY_RUN \
        STUB_FAIL_PKGS STUB_FAIL_CRATES APPS_BUILD RUSTFLAGS EGET_GITHUB_TOKEN XDG_CONFIG_HOME
    stub sudo
}

teardown() {
    rm -rf "$SANDBOX"
}

# stub NAME: create a fake command that logs "NAME args..." and fails if any
# argument appears in $STUB_FAIL_PKGS. `sudo` logs and runs its arguments,
# skipping its own -n flag.
stub() {
    local name="$1"
    if [[ $name == sudo ]]; then
        cat >"$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -n ]] && shift
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

# stub_apt_get_with_nala: apt-get stub that also "installs" a nala stub when
# asked for the nala package.
stub_apt_get_with_nala() {
    stub nala
    mv "$STUBS/nala" "$STUBS/.nala"
    cat >"$STUBS/apt-get" <<EOF
#!/usr/bin/env bash
echo "apt-get \$*" >>"\$STUB_LOG"
if [[ \$1 == install && " \$* " == *" nala "* ]]; then
    cp "$STUBS/.nala" "$STUBS/nala"
fi
exit 0
EOF
    sed -i "s|^    cp |    $(command -v cp) -p |" "$STUBS/apt-get"
    chmod +x "$STUBS/apt-get"
}

# stub_nala_failing SUBCOMMAND: nala stub that fails for SUBCOMMAND.
stub_nala_failing() {
    stub nala
    sed -i "2a [[ \$1 == $1 ]] \&\& exit 1" "$STUBS/nala"
}

# stub_eget_logging: eget stub that only logs, including the token it sees.
# It is called with `--file NAME`, so it must not honour STUB_FAIL_PKGS.
stub_eget_logging() {
    cat >"$STUBS/eget" <<'EOF'
#!/usr/bin/env bash
echo "eget $*" >>"$STUB_LOG"
echo "token=${EGET_GITHUB_TOKEN:-}" >>"$STUB_LOG"
EOF
    chmod +x "$STUBS/eget"
}

# Shebangs use /usr/bin/env, so stubs need env and bash on PATH as well.
link_runtime() {
    ln -s "$(command -v env)" "$STUBS/env"
    ln -s "$BASH_BIN" "$STUBS/bash"
}

run_apps() {
    OUTPUT="$(PATH="$STUBS" "$BASH_BIN" "$INSTALL_APPS" "$@" 2>&1 </dev/null)"
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
# Tiers by machine type
# ---------------------------------------------------------------------------

CORE_APT="curl git unzip fzf bat eza lsd ripgrep fd-find git-delta zoxide atuin direnv"

test_container_installs_core_only() {
    stub apt-get
    run_apps --machine container
    assert_status 0
    assert_call "apt-get update"
    assert_call "apt-get install -y --no-install-recommends $CORE_APT"
    refute_call_matches "^apt-get install .*\bgh\b"
    refute_call_matches "fonts-firacode"
}

test_server_installs_core_and_extra_without_fonts() {
    stub apt-get
    stub eget
    run_apps --machine server --no-nala
    assert_status 0
    assert_call_matches "^apt-get install .*\bdirenv\b.*\bmiller\b"
    assert_call_matches "^apt-get install .*\bgh\b"
    assert_call_matches "^apt-get install .*\bbtm\b"
    assert_call_matches "^apt-get install .*\bdu-dust\b"
    refute_call_matches "fonts-firacode"
}

test_desktop_installs_all_tiers() {
    stub apt-get
    stub eget
    run_apps --machine desktop --no-nala
    assert_status 0
    assert_call_matches "^apt-get install .*\bgh\b"
    assert_call_matches "^apt-get install .*\bfonts-firacode\b"
}

test_stow_is_not_installed() {
    stub apt-get
    run_apps --machine desktop --no-nala
    refute_call_matches "\bstow\b"
}

test_container_force_extra() {
    stub apt-get
    stub eget
    export APPS_FORCE_EXTRA=1
    run_apps --machine container
    assert_status 0
    assert_call_matches "^apt-get install .*\bgh\b"
    refute_call_matches "fonts-firacode"
}

test_machine_defaults_to_container_when_detected() {
    stub apt-get
    export REMOTE_CONTAINERS=true
    run_apps
    assert_status 0
    refute_call_matches "^apt-get install .*\bgh\b"
    assert_output_matches "container"
}

test_invalid_machine_fails() {
    stub apt-get
    run_apps --machine laptop
    assert_status 2
    assert_no_calls
}

test_atuin_is_core_not_extra() {
    stub apt-get
    stub eget
    run_apps --machine desktop --no-nala
    assert_status 0
    [[ $(grep -c '^apt-get install .*\batuin\b' "$STUB_LOG") -eq 1 ]] \
        || fail "atuin should appear in exactly one install batch"
}

# ---------------------------------------------------------------------------
# Package manager names
# ---------------------------------------------------------------------------

test_apt_extra_uses_eget_for_nushell() {
    stub apt-get
    stub_eget_logging
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^apt-get install .*nushell"
    assert_call "eget nushell/nushell --file nu --asset musl --to $HOME/.local/bin"
}

# Not packaged anywhere: always installed from GitHub releases.
assert_network_tools_from_eget() {
    local pm=$1
    stub "$pm"
    stub_eget_logging
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^($pm|nala) .*\b(xfr|snitch|usbtree)\b"
    assert_call "eget lance0/xfr --file xfr --asset musl --to $HOME/.local/bin"
    assert_call "eget karol-broda/snitch --file snitch --asset tar.gz --to $HOME/.local/bin"
    assert_call "eget gnomeria/usbtree --file usbtree --asset tar.gz --to $HOME/.local/bin"
}

test_apt_network_tools_come_from_eget() {
    assert_network_tools_from_eget apt-get
}

test_apt_installs_rustscan_from_eget() {
    stub apt-get
    stub_eget_logging
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^apt-get install .*\brustscan\b"
    assert_call "eget bee-san/RustScan --file rustscan --asset x86-linux --to $HOME/.local/bin"
}

test_pacman_installs_rustscan_package() {
    stub pacman
    stub_eget_logging
    run_apps --machine server
    assert_status 0
    assert_call_matches "^pacman -S --needed --noconfirm .*\brustscan\b"
    refute_call_matches "^eget bee-san/RustScan"
}

test_pacman_network_tools_come_from_eget() {
    assert_network_tools_from_eget pacman
}

test_eget_skipped_when_binary_present() {
    stub apt-get
    stub eget
    stub nu
    stub xfr
    stub snitch
    stub usbtree
    stub rustscan
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^eget "
}

test_pacman_uses_pacman_names() {
    stub pacman
    stub eget
    run_apps --machine desktop
    assert_status 0
    assert_call_matches "^pacman -S --needed --noconfirm curl .*\bfd\b.*\bgit-delta\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bttf-fira-code\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bgithub-cli\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bbottom\b"
    assert_call_matches "^pacman -S --needed --noconfirm .*\bnushell\b"
    # Only tools with no pacman package (xfr, snitch) come from eget.
    refute_call_matches "^eget (nushell|bootandy|ajeetdsouza|atuinsh|direnv|eza-community|starship|dalance)/"
}

test_dnf_uses_dnf_names() {
    stub dnf
    run_apps --machine container
    assert_status 0
    assert_call "dnf install -y curl git unzip fzf bat eza lsd ripgrep fd-find git-delta zoxide atuin direnv"
}

test_brew_runs_without_sudo() {
    stub brew
    run_apps --machine container
    assert_status 0
    assert_call "brew install curl git unzip fzf bat eza lsd ripgrep fd git-delta zoxide atuin direnv"
    refute_call_matches "^sudo "
}

# ---------------------------------------------------------------------------
# Fallbacks
# ---------------------------------------------------------------------------

test_batch_failure_falls_back_to_one_by_one() {
    stub apt-get
    stub eget
    export STUB_FAIL_PKGS="tailspin"
    run_apps --machine server --no-nala
    assert_status 1
    assert_call "apt-get install -y --no-install-recommends gh"
    assert_call "apt-get install -y --no-install-recommends tailspin"
    assert_output_matches "[Ff]ailed.*tailspin"
}

test_failed_install_falls_back_to_eget() {
    stub pacman
    stub_eget_logging
    export STUB_FAIL_PKGS="nushell"
    run_apps --machine server
    assert_status 0
    assert_call "eget nushell/nushell --file nu --asset musl --to $HOME/.local/bin"
}

test_shell_tools_fall_back_to_eget_releases() {
    stub apt-get
    stub_eget_logging
    export STUB_FAIL_PKGS="zoxide atuin direnv"
    run_apps --machine container
    assert_status 0
    assert_call "eget ajeetdsouza/zoxide --file zoxide --asset musl --to $HOME/.local/bin"
    assert_call "eget atuinsh/atuin --file atuin --asset gnu.tar.gz --asset ^server --to $HOME/.local/bin"
    assert_call "eget direnv/direnv --file direnv --to $HOME/.local/bin"
}

test_eza_falls_back_to_eget_release() {
    stub apt-get
    stub_eget_logging
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_status 0
    assert_call "apt-get install -y --no-install-recommends eza"
    assert_call "eget eza-community/eza --file eza --asset gnu.tar.gz --to $HOME/.local/bin"
}

# stub_curl_eget_installer: curl stub that serves an eget.sh installer which
# drops a logging eget stub into the current directory.
stub_curl_eget_installer() {
    cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$STUB_LOG"
out=""
while (( $# )); do [[ $1 == -o ]] && out=$2; shift; done
cat >"$out" <<'INSTALLER'
printf '#!/usr/bin/env bash\necho "eget $*" >>"$STUB_LOG"\n' >eget
chmod +x eget
INSTALLER
EOF
    chmod +x "$STUBS/curl"
    local tool
    for tool in mktemp chmod mv rm cat; do
        ln -s "$(command -v "$tool")" "$STUBS/$tool"
    done
}

test_missing_eget_is_installed_on_demand() {
    stub apt-get
    stub_curl_eget_installer
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_status 0
    assert_call_matches "^curl .*zyedidia.github.io/eget.sh"
    assert_call "eget eza-community/eza --file eza --asset gnu.tar.gz --to $HOME/.local/bin"
    [[ -x $HOME/.local/bin/eget ]] || fail "eget not installed to ~/.local/bin"
}

test_missing_eget_without_curl_fails() {
    stub apt-get
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_status 1
    assert_output_matches "[Ff]ailed.*eza"
}

# ---------------------------------------------------------------------------
# GitHub token for eget
# ---------------------------------------------------------------------------

test_token_from_environment_wins() {
    stub apt-get
    stub_eget_logging
    mkdir -p "$HOME/.config/secrets"
    echo "EGET_GITHUB_TOKEN=from-file" >"$HOME/.config/secrets/env"
    export EGET_GITHUB_TOKEN=from-env STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_call "token=from-env"
}

test_token_from_secrets_file() {
    stub apt-get
    stub_eget_logging
    stub gh
    mkdir -p "$HOME/.config/secrets"
    echo "EGET_GITHUB_TOKEN=from-file" >"$HOME/.config/secrets/env"
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_call "token=from-file"
    refute_call_matches "^gh auth"
}

test_token_from_gh_when_no_file() {
    stub apt-get
    stub_eget_logging
    printf '#!/usr/bin/env bash\necho "gh $*" >>"$STUB_LOG"\necho from-gh\n' >"$STUBS/gh"
    chmod +x "$STUBS/gh"
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_call "gh auth token"
    assert_call "token=from-gh"
}

test_no_token_still_runs_eget() {
    stub apt-get
    stub_eget_logging
    export STUB_FAIL_PKGS="eza"
    run_apps --machine container
    assert_status 0
    assert_call "token="
}

# ---------------------------------------------------------------------------
# sudo
# ---------------------------------------------------------------------------

test_non_interactive_sudo_uses_n_flag() {
    stub apt-get
    cat >"$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"$STUB_LOG"
[[ $1 == -n ]] && shift
exec "$@"
EOF
    chmod +x "$STUBS/sudo"
    run_apps --machine container
    assert_status 0
    assert_call_matches "^sudo -n apt-get update"
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------

test_dry_run_prints_without_running() {
    stub apt-get
    stub eget
    export DRY_RUN=1
    run_apps --machine desktop
    assert_status 0
    assert_no_calls
    assert_output_matches "apt-get install -y --no-install-recommends nala$"
    assert_output_matches "nala install -y --no-install-recommends $CORE_APT"
}

test_dry_run_no_nala_prints_apt_get() {
    stub apt-get
    export DRY_RUN=1
    run_apps --machine container --no-nala
    assert_status 0
    assert_no_calls
    assert_output_matches "apt-get install -y --no-install-recommends $CORE_APT$"
}

# ---------------------------------------------------------------------------
# nala (apt only): installed first by default, then used for the batch
# ---------------------------------------------------------------------------

test_apt_installs_nala_first_and_uses_it() {
    stub_apt_get_with_nala
    stub eget
    run_apps --machine server
    assert_status 0
    assert_call "apt-get update"
    assert_call "apt-get install -y --no-install-recommends nala"
    assert_call_matches "^nala install -y --no-install-recommends $CORE_APT "
    refute_call_matches "^apt-get install .*\bcurl\b"
}

test_apt_uses_existing_nala() {
    stub apt-get
    stub nala
    stub eget
    run_apps --machine server
    assert_status 0
    refute_call_matches "^apt-get install .*\bnala\b"
    assert_call_matches "^nala install -y --no-install-recommends $CORE_APT "
}

test_nala_batch_failure_falls_back_to_apt_get() {
    stub apt-get
    stub_nala_failing install
    stub eget
    run_apps --machine desktop
    assert_status 0
    assert_call "apt-get install -y --no-install-recommends curl"
    assert_call "apt-get install -y --no-install-recommends fonts-firacode"
}

test_nala_unavailable_uses_apt_get() {
    stub apt-get
    stub eget
    export STUB_FAIL_PKGS="nala"
    run_apps --machine server
    assert_status 0
    refute_call_matches "^nala "
    assert_call_matches "^apt-get install -y --no-install-recommends $CORE_APT "
    assert_output_matches "nala"
}

test_no_nala_flag_skips_nala() {
    stub apt-get
    stub nala
    stub eget
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^nala "
    refute_call_matches "^apt-get install .*\bnala\b"
    assert_call_matches "^apt-get install -y --no-install-recommends $CORE_APT "
}

test_container_skips_nala() {
    stub apt-get
    stub nala
    run_apps --machine container
    assert_status 0
    refute_call_matches "^nala "
    assert_call "apt-get install -y --no-install-recommends $CORE_APT"
}

test_container_force_nala() {
    stub apt-get
    stub nala
    export APPS_FORCE_NALA=1
    run_apps --machine container
    assert_status 0
    assert_call "nala install -y --no-install-recommends $CORE_APT"
}

test_nala_not_used_for_other_managers() {
    stub dnf
    stub nala
    run_apps --machine container
    assert_status 0
    refute_call_matches "^nala "
}

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

test_unknown_option_fails() {
    stub apt-get
    run_apps --bogus
    assert_status 2
    assert_no_calls
}

test_no_package_manager_fails() {
    run_apps --machine container
    assert_status 1
    assert_output_matches "[Nn]o supported package manager"
}

# ---------------------------------------------------------------------------
# --build cargo: Rust tools rebuilt for this CPU
# ---------------------------------------------------------------------------

CORE_CRATES="bat eza lsd ripgrep fd-find git-delta zoxide atuin"
EXTRA_CRATES="nu tailspin procs du-dust bottom starship xfr rustscan usbtree"

# stub_cargo: cargo stub that logs each install with the build settings it
# sees, and fails for crates in $STUB_FAIL_CRATES.
stub_cargo() {
    cat >"$STUBS/cargo" <<'EOF'
#!/usr/bin/env bash
echo "cargo $*" >>"$STUB_LOG"
echo "cargo-env RUSTFLAGS=${RUSTFLAGS:-} LTO=${CARGO_PROFILE_RELEASE_LTO:-} CGU=${CARGO_PROFILE_RELEASE_CODEGEN_UNITS:-}" >>"$STUB_LOG"
for bad in ${STUB_FAIL_CRATES:-}; do
    [[ " $* " == *" $bad "* ]] && exit 1
done
exit 0
EOF
    chmod +x "$STUBS/cargo"
}

# first_line PATTERN: line number of the first logged call matching PATTERN.
first_line() {
    grep -nE -- "$1" "$STUB_LOG" | head -1 | cut -d: -f1
}

test_default_build_never_calls_cargo() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine server --no-nala
    assert_status 0
    refute_call_matches "^cargo "
    refute_call_matches "build-essential"
}

test_bad_build_value_fails() {
    run_apps --machine server --build fast
    assert_status 2
    assert_no_calls
}

test_cargo_build_installs_prebuilt_first_then_crates() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine server --no-nala --build cargo
    assert_status 0
    assert_call_matches "^apt-get install -y --no-install-recommends .*\bripgrep\b"
    local pkg_line cargo_line
    pkg_line="$(first_line '^apt-get install')"
    cargo_line="$(first_line '^cargo install')"
    [[ -n $cargo_line && $pkg_line -lt $cargo_line ]] || fail "cargo ran before the packages"
    local crate
    for crate in $CORE_CRATES $EXTRA_CRATES; do
        assert_call_matches "^cargo install --locked (--force )?$crate$"
    done
}

test_cargo_build_uses_native_lto_flags() {
    stub apt-get
    stub eget
    stub_cargo
    RUSTFLAGS="-C debuginfo=0" run_apps --machine container --build cargo
    assert_status 0
    assert_call "cargo-env RUSTFLAGS=-C debuginfo=0 -C target-cpu=native LTO=fat CGU=1"
}

test_cargo_build_only_rust_tools() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine server --no-nala --build cargo
    local tool
    for tool in curl git fzf direnv gh duf htop tmux micro miller snitch; do
        refute_call_matches "^cargo install --locked (--force )?$tool$"
    done
}

test_cargo_build_respects_tiers() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine container --build cargo
    assert_status 0
    assert_call_matches "^cargo install --locked (--force )?ripgrep$"
    refute_call_matches "^cargo install --locked (--force )?(nu|starship|rustscan)$"
}

test_cargo_build_deps_per_manager() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine container --build cargo
    assert_call_matches "^apt-get install -y --no-install-recommends .*\bbuild-essential pkg-config\b"
    : >"$STUB_LOG"
    rm "$STUBS/apt-get"
    stub pacman
    run_apps --machine container --build cargo
    assert_call_matches "^pacman -S --needed --noconfirm .*\bbase-devel\b"
    : >"$STUB_LOG"
    rm "$STUBS/pacman"
    stub dnf
    run_apps --machine container --build cargo
    assert_call_matches "^dnf install -y .*\bgcc make pkgconf-pkg-config\b"
}

test_apps_build_env_selects_cargo() {
    stub apt-get
    stub eget
    stub_cargo
    APPS_BUILD=cargo run_apps --machine container
    assert_status 0
    assert_call_matches "^cargo install --locked (--force )?ripgrep$"
}

test_failed_crate_keeps_prebuilt_and_succeeds() {
    stub apt-get
    stub eget
    stub_cargo
    ln -s "$(command -v mv)" "$STUBS/mv"
    mkdir -p "$HOME/.local/bin"
    printf 'prebuilt\n' >"$HOME/.local/bin/atuin"
    export STUB_FAIL_CRATES="atuin"
    run_apps --machine container --build cargo
    assert_status 0
    assert_output_matches "cargo build failed.*atuin"
    [[ -f $HOME/.local/bin/atuin ]] || fail "prebuilt atuin moved after a failed build"
    assert_call_matches "^cargo install --locked (--force )?zoxide$"
}

test_eget_copy_moved_aside_after_build() {
    stub apt-get
    stub eget
    stub_cargo
    ln -s "$(command -v mv)" "$STUBS/mv"
    mkdir -p "$HOME/.local/bin"
    printf 'eget copy\n' >"$HOME/.local/bin/rustscan"
    printf 'eget copy\n' >"$HOME/.local/bin/dust"
    run_apps --machine server --no-nala --build cargo
    assert_status 0
    [[ -e $HOME/.local/bin/rustscan ]] && fail "eget rustscan still shadows the cargo build"
    [[ -f $HOME/.local/share/install-apps/replaced/rustscan ]] || fail "rustscan not kept aside"
    # Crate and binary names differ: du-dust installs dust.
    [[ -f $HOME/.local/share/install-apps/replaced/dust ]] || fail "dust not kept aside"
    return 0
}

test_system_packages_are_not_removed() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine server --no-nala --build cargo
    refute_call_matches "^apt-get (remove|purge|autoremove)"
}

# cargo skips a crate already at the latest version whatever RUSTFLAGS say,
# so one built some other way (plain `cargo install`) is forced once.
test_unrecorded_crates_are_rebuilt_once() {
    stub apt-get
    stub eget
    stub_cargo
    run_apps --machine container --build cargo
    assert_call "cargo install --locked --force ripgrep"
    : >"$STUB_LOG"
    run_apps --machine container --build cargo
    assert_call "cargo install --locked ripgrep"
    refute_call_matches "^cargo install .*--force"
    # Other settings (here extra RUSTFLAGS) count as a different build.
    : >"$STUB_LOG"
    RUSTFLAGS="-C debuginfo=0" run_apps --machine container --build cargo
    assert_call "cargo install --locked --force ripgrep"
}

test_failed_crate_is_not_recorded() {
    stub apt-get
    stub eget
    stub_cargo
    STUB_FAIL_CRATES="atuin" run_apps --machine container --build cargo
    : >"$STUB_LOG"
    run_apps --machine container --build cargo
    assert_call "cargo install --locked --force atuin"
    assert_call "cargo install --locked zoxide"
}

# stub_curl_rustup_installer: curl stub serving a rustup-init that logs its
# arguments and drops a cargo stub into ~/.cargo/bin.
stub_curl_rustup_installer() {
    cat >"$STUBS/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >>"\$STUB_LOG"
out=""
while (( \$# )); do [[ \$1 == -o ]] && out=\$2; shift; done
cat >"\$out" <<'INSTALLER'
echo "rustup-init \$*" >>"\$STUB_LOG"
mkdir -p "\$HOME/.cargo/bin"
cp "$STUBS/.cargo" "\$HOME/.cargo/bin/cargo"
INSTALLER
EOF
    chmod +x "$STUBS/curl"
    stub_cargo
    mv "$STUBS/cargo" "$STUBS/.cargo"
    local tool
    for tool in mktemp rm cat sh cp; do
        ln -s "$(command -v "$tool")" "$STUBS/$tool"
    done
}

test_rustup_installed_when_cargo_missing() {
    stub apt-get
    stub eget
    stub_curl_rustup_installer
    run_apps --machine container --build cargo
    assert_status 0
    assert_call_matches "^curl .*https://sh\.rustup\.rs"
    assert_call "rustup-init -y --no-modify-path --profile minimal"
    assert_call_matches "^cargo install --locked (--force )?ripgrep$"
}

test_rustup_without_toolchain_gets_stable() {
    stub apt-get
    stub eget
    stub_curl_rustup_installer
    cat >"$STUBS/rustup" <<'EOF'
#!/usr/bin/env bash
echo "rustup $*" >>"$STUB_LOG"
EOF
    chmod +x "$STUBS/rustup"
    run_apps --machine container --build cargo
    assert_call "rustup default stable"
    refute_call_matches "^rustup-init"
}

test_existing_cargo_home_is_used() {
    stub apt-get
    stub eget
    stub_cargo
    mkdir -p "$HOME/.cargo/bin"
    mv "$STUBS/cargo" "$HOME/.cargo/bin/cargo"
    run_apps --machine container --build cargo
    assert_status 0
    assert_call_matches "^cargo install --locked (--force )?ripgrep$"
}

# ---------------------------------------------------------------------------
# chezmoi: appsBuild picks the build
# ---------------------------------------------------------------------------

# render FILE [DATA_LINES]: FILE from home/ rendered with a sandbox config.
render() {
    printf '[data]\n    machine = "server"\n    hasSecrets = false\n%s\n' "${2:-}" >"$SANDBOX/chezmoi.toml"
    PATH="$REAL_PATH" chezmoi --source="$REPO_DIR" --config="$SANDBOX/chezmoi.toml" \
        --persistent-state="$SANDBOX/state.db" --destination="$HOME" \
        execute-template ${3:-} <"$REPO_DIR/home/$1" 2>/dev/null
}

REAL_PATH=$PATH
RUN_ONCHANGE=.chezmoiscripts/run_onchange_after_10-install-apps.sh.tmpl

test_run_onchange_passes_build() {
    command -v chezmoi >/dev/null || return 0
    OUTPUT="$(render $RUN_ONCHANGE)"
    assert_output_matches "--machine server --build prebuilt\$"
    OUTPUT="$(render $RUN_ONCHANGE '    appsBuild = "cargo"')"
    assert_output_matches "--machine server --build cargo\$"
    # The setting is in the rendered text, so changing it re-runs the script.
    assert_output_matches "^# appsBuild: cargo\$"
}

test_init_keeps_and_defaults_apps_build() {
    command -v chezmoi >/dev/null || return 0
    OUTPUT="$(render .chezmoi.toml.tmpl '    appsBuild = "cargo"' --init)"
    assert_output_matches '^    appsBuild = "cargo"$'
    OUTPUT="$(render .chezmoi.toml.tmpl '' --init)"
    assert_output_matches '^    appsBuild = "prebuilt"$'
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
