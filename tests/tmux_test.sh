#!/usr/bin/env bash
#
# Tests for the tmux config (home/private_dot_config/tmux) and its plugins.
#
# The config and the plugin externals are exported with `chezmoi archive`
# (as zssh's build.sh does) into a sandbox HOME, then a real tmux server is
# started there on its own socket. Needs tmux and chezmoi; plugin downloads
# are cached by chezmoi.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

# export_config DIR: write the tmux config and plugins as chezmoi would.
export_config() {
    local dest=$1 tmp
    tmp="$(mktemp -d)"
    printf '[data]\n    machine = "container"\n    hasSecrets = false\n' >"$tmp/c.toml"
    chezmoi --source="$REPO_DIR" --config="$tmp/c.toml" --persistent-state="$tmp/s.db" \
        --destination="$tmp/home" archive --format=tar --exclude=encrypted,scripts \
        --output="$tmp/tmux.tar" "$tmp/home/.config/tmux" 2>/dev/null
    mkdir -p "$dest"
    tar -xmf "$tmp/tmux.tar" -C "$dest"
    rm -rf "$tmp"
}

CONFIG_CACHE="$(mktemp -d)"
trap 'rm -rf "$CONFIG_CACHE"' EXIT
export_config "$CONFIG_CACHE"

setup() {
    SANDBOX="$(mktemp -d)"
    export HOME="$SANDBOX/home"
    # Outside HOME, as under zssh, so a hard-coded ~/.local path shows up.
    export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$SANDBOX/xdg/state"
    export XDG_DATA_HOME="$SANDBOX/xdg/data" XDG_CACHE_HOME="$SANDBOX/xdg/cache"
    export TMUX_TMPDIR="$SANDBOX/run"
    unset TMUX
    mkdir -p "$HOME" "$TMUX_TMPDIR"
    cp -a "$CONFIG_CACHE/." "$HOME/"
    OUTPUT=""
}

teardown() {
    tmux -L test kill-server 2>/dev/null
    rm -rf "$SANDBOX"
}

# start_tmux: start a detached server with the config; $OUTPUT gets errors
# from sourcing it again in the running server.
start_tmux() {
    tmux -L test -f "$XDG_CONFIG_HOME/tmux/tmux.conf" new-session -d -s t -x 200 -y 50
    OUTPUT="$(tmux -L test source-file "$XDG_CONFIG_HOME/tmux/tmux.conf" 2>&1)"
}

t() { tmux -L test "$@"; }

# key TABLE KEY: the command bound to KEY.
key() { t list-keys -T "$1" "$2" 2>/dev/null | sed -E 's/^bind-key +(-r +)?-T +[^ ]+ +[^ ]+ +//'; }

# ---------------------------------------------------------------------------

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    [[ -n $OUTPUT ]] && sed 's/^/    /' <<<"$OUTPUT"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_match() { [[ $1 =~ $2 ]] || fail "'$1' does not match /$2/"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# ---------------------------------------------------------------------------
# Config loads
# ---------------------------------------------------------------------------

test_config_sources_without_errors() {
    start_tmux
    assert_eq "$OUTPUT" ""
}

# ---------------------------------------------------------------------------
# Yakuake shortcuts behind the prefix
# ---------------------------------------------------------------------------

test_new_window_like_yakuake_new_session() {
    start_tmux
    assert_match "$(key prefix T)" '^new-window -c "#\{pane_current_path\}"$'
    assert_match "$(key prefix N)" '^new-window -c "#\{pane_current_path\}"$'
}

test_close_pane_like_yakuake_close_terminal() {
    start_tmux
    assert_eq "$(key prefix R)" "kill-pane"
    assert_eq "$(key prefix Q)" "kill-pane"
    assert_match "$(key prefix r)" 'source-file'
}

test_arrows_switch_windows_like_yakuake_sessions() {
    start_tmux
    local k
    for k in Left S-Left C-S-Left; do assert_eq "$(key prefix $k)" "previous-window"; done
    for k in Right S-Right C-S-Right; do assert_eq "$(key prefix $k)" "next-window"; done
}

test_up_down_tab_switch_panes_like_yakuake_terminals() {
    start_tmux
    local k
    for k in Up C-S-Up BTab; do assert_eq "$(key prefix $k)" "select-pane -t :.-"; done
    for k in Down C-S-Down Tab; do assert_eq "$(key prefix $k)" "select-pane -t :.+"; done
}

test_splits_like_yakuake() {
    start_tmux
    assert_match "$(key prefix +)" '^split-window -h -c "#\{pane_current_path\}"$'
    assert_match "$(key prefix _)" '^split-window -v -c "#\{pane_current_path\}"$'
}

test_number_keys_pick_windows_1_to_10() {
    start_tmux
    assert_eq "$(key prefix 1)" "select-window -t :=1"
    assert_eq "$(key prefix 0)" "select-window -t :=10"
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------

test_catppuccin_mocha_status() {
    start_tmux
    assert_eq "$(t show -gv @catppuccin_flavor)" "mocha"
    # Defined by the plugin itself, unlike the flavor set in tmux.conf.
    [[ -n $(t show -gv @catppuccin_status_session) ]] || fail "catppuccin not loaded"
}

test_prefix_highlight_in_status() {
    start_tmux
    local right
    right="$(t show -gv status-right)"
    [[ $right != *'#{prefix_highlight}'* ]] || fail "placeholder not replaced"
    assert_match "$right" 'client_prefix'
}

test_continuum_saves_automatically() {
    start_tmux
    assert_match "$(t show -gv status-right)" 'continuum_save\.sh'
    assert_eq "$(t show -gv @continuum-restore)" "on"
}

test_resurrect_bindings() {
    start_tmux
    assert_match "$(key prefix C-s)" 'resurrect.*save'
    assert_match "$(key prefix C-r)" 'resurrect.*restore'
}

test_yank_and_osc52_clipboard() {
    start_tmux
    assert_match "$(key copy-mode-vi y)" 'copy-pipe'
    assert_eq "$(t show -sv set-clipboard)" "on"
}

test_logging_bindings() {
    start_tmux
    assert_match "$(key prefix P)" 'logging'
    assert_match "$(key prefix M-P)" 'screen_capture|save_complete_history|logging'
}

# extrakto's default key (Tab) is taken by the Yakuake pane mapping.
test_extrakto_on_e() {
    start_tmux
    assert_match "$(key prefix e)" 'extrakto'
}

# ---------------------------------------------------------------------------
# Files stay in XDG dirs (zssh points them into ~/.zsh-portable)
# ---------------------------------------------------------------------------

test_state_goes_to_xdg_dirs() {
    start_tmux
    assert_eq "$(t show -gv history-file)" "$XDG_STATE_HOME/tmux/history"
    assert_eq "$(t show -gv @resurrect-dir)" "$XDG_STATE_HOME/tmux/resurrect"
    assert_eq "$(t show -gv @logging-path)" "$XDG_STATE_HOME/tmux/logs"
    t run-shell "$XDG_CONFIG_HOME/tmux/plugins/tmux-resurrect/scripts/save.sh quiet"
    [[ -n $(ls "$XDG_STATE_HOME/tmux/resurrect" 2>/dev/null) ]] || fail "resurrect saved nothing"
    local extra
    extra="$(cd "$HOME" && ls -A | grep -vxE '\.config')"
    assert_eq "$extra" ""
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
