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
# Yakuake shortcuts without the prefix
# ---------------------------------------------------------------------------

# send_raw BYTES...: attach a client in a pty and type each argument (Python
# escapes, e.g. '\x1f'), pausing so tmux handles them one at a time.
send_raw() {
    python3 - "$@" <<'EOF'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("tmux", ["tmux", "-L", "test", "attach", "-t", "t"])
def drain(seconds):
    end = time.time() + seconds
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                os.read(fd, 65536)
            except OSError:
                return
drain(1.0)
for arg in sys.argv[1:]:
    os.write(fd, arg.encode().decode("unicode_escape").encode("latin-1"))
    drain(0.5)
os.kill(pid, 9)
EOF
}

# Each Yakuake key arrives under different names depending on the terminal's
# encoding (classic, xterm modifyOtherKeys, CSI u), so all are bound.
test_yakuake_keys_bound_without_prefix() {
    start_tmux
    local k
    for k in C-_ C-S--; do assert_match "$(key root $k)" '^split-window -v -c'; done
    for k in C-S-= C-+ C-S-+; do assert_match "$(key root $k)" '^split-window -h -c'; done
    for k in C-S-Up C-BTab C-S-Tab; do assert_eq "$(key root $k)" "select-pane -t :.-"; done
    for k in C-S-Down C-Tab; do assert_eq "$(key root $k)" "select-pane -t :.+"; done
    for k in S-Left C-S-Left; do assert_eq "$(key root $k)" "previous-window"; done
    for k in S-Right C-S-Right; do assert_eq "$(key root $k)" "next-window"; done
    for k in C-S-t C-S-T C-S-n C-S-N; do assert_match "$(key root $k)" '^new-window -c'; done
    for k in C-S-r C-S-R C-S-q C-S-Q; do assert_eq "$(key root $k)" "kill-pane"; done
    assert_eq "$(key root M-1)" "select-window -t :=1"
    assert_eq "$(key root M-0)" "select-window -t :=10"
    assert_eq "$(t show -sv extended-keys)" "on"
}

# The bytes real terminals send for these keys reach the bindings.
test_yakuake_keys_from_raw_terminal_input() {
    start_tmux
    # Ctrl+Shift+- classic (0x1f), Ctrl+Shift+= as modifyOtherKeys.
    send_raw '\x1f' '\x1b[27;6;61~'
    assert_eq "$(t list-panes -t t | wc -l)" 3
    # Ctrl+Tab as CSI u: next pane wraps from the last split to the first.
    local before after
    before="$(t display -p -t t '#{pane_index}')"
    send_raw '\x1b[9;5u'
    after="$(t display -p -t t '#{pane_index}')"
    [[ $before != "$after" ]] || fail "Ctrl+Tab did not change pane"
    # Ctrl+Shift+T as CSI u opens a window; Alt+1 goes back to window 1.
    send_raw '\x1b[116;6u'
    assert_eq "$(t list-windows -t t | wc -l)" 2
    send_raw '\x1b1'
    assert_eq "$(t display -p -t t '#{window_index}')" 1
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
    assert_eq "$(t show -gv @continuum-restore)" "on"
    # continuum only autosaves when it is the only tmux server, so environments
    # don't overwrite each other's saves; with yours running, it holds back.
    local ours others
    ours="$(t display -p '#{pid}')"
    # Counted like continuum does (ps command line; pgrep misses the server).
    others="$(ps -Ao 'command pid' | grep -E '^tmux' | grep -vE " $ours\$" | grep -vc 'tmux -L test')"
    if (( others > 0 )); then
        echo "  note [$CURRENT]: $others other tmux server(s) running, autosave hook not checked"
        return 0
    fi
    assert_match "$(t show -gv status-right)" 'continuum_save\.sh'
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
