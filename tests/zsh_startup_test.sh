#!/usr/bin/env bash
#
# Tests for zsh startup: ~/.zshenv, ~/.config/zsh/.zshrc and their .d dirs.
#
# ~/.zshenv belongs to the machine (installers append to it); chezmoi keeps one
# marked block at its top that sets ZDOTDIR and sources $ZDOTDIR/zshenv.d.
# .zshrc likewise keeps one block at its top that sources $ZDOTDIR/zshrc.d;
# the user's own lines stay below it. Machine-local
# snippets are unmanaged NN-name.zsh files in those dirs.
#
# Applies the real chezmoi source to a sandbox home with a throwaway config;
# nothing in ~ is touched.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
ZDOT=.config/zsh

setup() {
    SANDBOX="$(mktemp -d)"
    HOME_DIR="$SANDBOX/home"
    mkdir -p "$HOME_DIR/$ZDOT"
    OUTPUT=""
}

teardown() {
    rm -rf "$SANDBOX"
}

# cz ARGS...: chezmoi on the repo with a server machine config.
cz() {
    printf '[data]\n    machine = "server"\n    hasSecrets = false\n' >"$SANDBOX/chezmoi.toml"
    chezmoi --source="$REPO_DIR" --config="$SANDBOX/chezmoi.toml" \
        --persistent-state="$SANDBOX/chezmoi.db" --destination="$HOME_DIR" "$@" \
        2> >(grep -v 'config file template has changed' >&2)
}

# apply_zsh: apply the zsh startup files (and removals) only.
apply_zsh() {
    cz apply --force --exclude=scripts,externals "$HOME_DIR/.zshenv" "$HOME_DIR/$ZDOT"
}

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

ENV_BLOCK='# >>> zsh-config >>>
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export ZSH_CUSTOM="$ZDOTDIR"
for _zc_f in "$ZDOTDIR"/zshenv.d/*.zsh(N); do [[ ${_zc_f:t} == '"'~'"'* ]] || source "$_zc_f"; done
unset _zc_f
# <<< zsh-config <<<'

RC_BLOCK='# >>> zsh-config >>>
for _zc_f in "${ZDOTDIR:-$HOME}"/zshrc.d/*.zsh(N); do [[ ${_zc_f:t} == '"'~'"'* ]] || source "$_zc_f"; done
unset _zc_f
# <<< zsh-config <<<'

CARGO_LINE='. "$HOME/.cargo/env"'

PNPM_BLOCK='# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end'

zshenv() { cat "$HOME_DIR/.zshenv"; }
zshrc() { cat "$HOME_DIR/$ZDOT/.zshrc"; }

# run_zsh CODE: run CODE in zsh -f after sourcing the sandbox ~/.zshenv, with
# a clean environment pointing at the sandbox home.
run_zsh() {
    env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin TERM=dumb \
        zsh -fc "source \$HOME/.zshenv; $1"
}

# ---------------------------------------------------------------------------
# ~/.zshenv: one managed block at the top
# ---------------------------------------------------------------------------

test_missing_zshenv_gets_only_the_block() {
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK"
}

test_appended_zshenv_lines_stay_below_the_block() {
    printf '%s\n' "$CARGO_LINE" >"$HOME_DIR/.zshenv"
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
    printf 'export AFTER=1\n' >>"$HOME_DIR/.zshenv"
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE
export AFTER=1"
    assert_eq "$(cz diff --exclude=scripts,externals "$HOME_DIR/.zshenv")" ""
}

test_head_tail_blocks_are_replaced() {
    cat >"$HOME_DIR/.zshenv" <<EOF
# >>> zsh-config head >>>
[[ ! -r \$HOME/.config/zsh/.zshenv.head ]] || source \$HOME/.config/zsh/.zshenv.head
# <<< zsh-config head <<<

$CARGO_LINE

# >>> zsh-config tail >>>
[[ ! -r \$HOME/.config/zsh/.zshenv.tail ]] || source \$HOME/.config/zsh/.zshenv.tail
# <<< zsh-config tail <<<
EOF
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
}

test_older_hooks_are_replaced() {
    printf '# >>> zsh-config pre >>>\nold pre\n# <<< zsh-config pre <<<\n\n%s\n\n# >>> zsh-config post >>>\nold post\n# <<< zsh-config post <<<\n' \
        "$CARGO_LINE" >"$HOME_DIR/.zshenv"
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
    printf '[[ ! -f "$HOME/.config/zsh/.zshenv.init" ]] || source "$HOME/.config/zsh/.zshenv.init"\n%s\n' \
        "$CARGO_LINE" >"$HOME_DIR/.zshenv"
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
}

test_legacy_repo_zshenvs_are_replaced_keeping_appended_lines() {
    local rev
    for rev in b2f284e b0d2f72; do
        git -C "$REPO_DIR" show "$rev:home/dot_zshenv" >"$HOME_DIR/.zshenv" ||
            { fail "no legacy .zshenv $rev in git"; continue; }
        printf '%s\n' "$CARGO_LINE" >>"$HOME_DIR/.zshenv"
        apply_zsh
        assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
    done
}

test_zshenv_d_loads_in_order_then_machine_lines() {
    apply_zsh
    local d="$HOME_DIR/$ZDOT/zshenv.d"
    printf 'print -r 30\n' >"$d/30-a.zsh"
    printf 'print -r 60\n' >"$d/60-b.zsh"
    printf 'print -r skipped\n' >"$d/~40-off.zsh"
    printf 'print -r not-zsh\n' >"$d/50-notes.txt"
    printf 'print -r machine\n' >>"$HOME_DIR/.zshenv"
    OUTPUT="$(run_zsh '')"
    assert_eq "$(grep -vE '^$' <<<"$OUTPUT" | tr '\n' ' ')" "30 60 machine "
}

test_zshenv_d_base_sets_xdg_and_path() {
    apply_zsh
    OUTPUT="$(run_zsh 'print -r -- "$XDG_DATA_HOME|$XDG_STATE_HOME|$XDG_CACHE_HOME|$XDG_BIN_HOME|${path[1]}|$ZSH_CUSTOM|$HISTFILE|$EDITOR"')"
    local h=$HOME_DIR
    assert_eq "$OUTPUT" "$h/.local/share|$h/.local/state|$h/.cache|$h/.local/bin|$h/.local/bin|$h/$ZDOT|$h/.local/state/zsh/history|nano"
}

test_history_dir_is_created() {
    apply_zsh
    run_zsh 'true' >/dev/null
    [[ -d $HOME_DIR/.local/state/zsh ]] || fail "no history dir"
    return 0
}

# VS Code's shell integration sets HISTFILE=$ZDOTDIR/.zsh_history after
# .zshenv and before .zshrc; 00-early must put it back.
test_vscode_history_override_is_undone() {
    apply_zsh
    OUTPUT="$(run_zsh 'HISTFILE=$ZDOTDIR/.zsh_history; source $ZDOTDIR/zshrc.d/00-early.zsh; print -r -- $HISTFILE')"
    assert_eq "$OUTPUT" "$HOME_DIR/.local/state/zsh/history"
}

# zssh exports its bundle's HISTFILE; it must survive .zshenv and 00-early.
test_inherited_histfile_survives_rc() {
    apply_zsh
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin HISTFILE="$SANDBOX/bundle-hist" \
        zsh -fc 'source $HOME/.zshenv; source $ZDOTDIR/zshrc.d/00-early.zsh; print -r -- $HISTFILE')"
    assert_eq "$OUTPUT" "$SANDBOX/bundle-hist"
}

# use-omz names the dump after the host, so a hostname change left a new one.
test_compdump_has_fixed_name_in_cache_dir() {
    apply_zsh
    OUTPUT="$(run_zsh 'print -r -- "$ZSH_CACHE_DIR|$ZSH_COMPDUMP"')"
    assert_eq "$OUTPUT" "$HOME_DIR/.cache/zsh|$HOME_DIR/.cache/zsh/zcompdump-$(zsh -fc 'print $ZSH_VERSION')"
}

# Toolchain bin dirs go after ~/.local/bin and before the system dirs.
test_toolchain_bins_on_path_in_order() {
    apply_zsh
    local h=$HOME_DIR
    mkdir -p "$h/.local/share/pnpm/bin" "$h/.cargo/bin" "$h/go/bin"
    OUTPUT="$(run_zsh 'print -r -- "${(j.:.)path}|$PNPM_HOME"')"
    assert_eq "$OUTPUT" "$h/.local/bin:$h/.local/share/pnpm/bin:$h/.cargo/bin:$h/go/bin:/usr/bin:/bin|$h/.local/share/pnpm"
}

# Servers and containers without the toolchains keep a clean PATH.
test_missing_toolchain_dirs_are_skipped() {
    apply_zsh
    OUTPUT="$(run_zsh 'print -r -- "${(j.:.)path}|${+PNPM_HOME}"')"
    assert_eq "$OUTPUT" "$HOME_DIR/.local/bin:/usr/bin:/bin|0"
}

test_toolchain_home_overrides_are_used() {
    apply_zsh
    local s=$SANDBOX
    mkdir -p "$s/pnpm/bin" "$s/cargo/bin" "$s/gopath/bin" "$s/gobin" "$HOME_DIR/go/bin"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin PNPM_HOME="$s/pnpm" CARGO_HOME="$s/cargo" \
        GOPATH="$s/gopath:$s/other" zsh -fc 'source $HOME/.zshenv; print -r -- "${(j.:.)path}"')"
    assert_eq "$OUTPUT" "$HOME_DIR/.local/bin:$s/pnpm/bin:$s/cargo/bin:$s/gopath/bin:/usr/bin:/bin"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin GOBIN="$s/gobin" \
        zsh -fc 'source $HOME/.zshenv; print -r -- "${(j.:.)path}"')"
    assert_eq "$OUTPUT" "$HOME_DIR/.local/bin:$s/gobin:/usr/bin:/bin"
}

test_nested_shell_does_not_duplicate_toolchain_bins() {
    apply_zsh
    mkdir -p "$HOME_DIR/.cargo/bin" "$HOME_DIR/go/bin"
    OUTPUT="$(run_zsh 'zsh -fc "source \$HOME/.zshenv; print -r -- \${(j.:.)path}"')"
    assert_eq "$OUTPUT" "$HOME_DIR/.local/bin:$HOME_DIR/.cargo/bin:$HOME_DIR/go/bin:/usr/bin:/bin"
}

test_zshenv_keeps_inherited_dirs_as_zssh_sets_them() {
    apply_zsh
    # zssh exports these into its bundle; HOME stays the host's.
    local bundle="$SANDBOX/bundle"
    mkdir -p "$bundle/zsh"
    # A bundle carries the repo snippets, exported like the home's.
    cp -a "$HOME_DIR/$ZDOT/zshenv.d" "$bundle/zsh/"
    printf 'print -r bundle\n' >"$bundle/zsh/zshenv.d/10-x.zsh"
    printf 'print -r host\n' >"$HOME_DIR/$ZDOT/zshenv.d/10-x.zsh"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$bundle" \
        XDG_BIN_HOME="$bundle/bin" HISTFILE="$bundle/hist" \
        zsh -fc 'source $HOME/.zshenv; print -r -- "$ZDOTDIR|${path[1]}|$HISTFILE"')"
    assert_eq "$OUTPUT" "bundle
$bundle/zsh|$bundle/bin|$bundle/hist"
}

test_secrets_load_from_zshenv_d() {
    apply_zsh
    mkdir -p "$HOME_DIR/.config/secrets"
    printf 'MY_TOKEN=abc\n' >"$HOME_DIR/.config/secrets/env"
    OUTPUT="$(run_zsh 'print -r -- $MY_TOKEN; env | grep -c ^MY_TOKEN=')"
    assert_eq "$OUTPUT" "abc
1"
}

# ---------------------------------------------------------------------------
# .zshrc: belongs to the machine; chezmoi keeps one block at the top
# ---------------------------------------------------------------------------

test_missing_zshrc_gets_only_the_block() {
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK"
}

test_user_zshrc_lines_stay_below_the_block() {
    printf 'alias ll="ls -l"\n%s\n' "$PNPM_BLOCK" >"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

alias ll=\"ls -l\"
$PNPM_BLOCK"
    printf 'export AFTER=1\n' >>"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

alias ll=\"ls -l\"
$PNPM_BLOCK
export AFTER=1"
    assert_eq "$(cz diff --exclude=scripts,externals "$HOME_DIR/$ZDOT/.zshrc")" ""
}

test_old_zshrc_hooks_are_replaced() {
    cat >"$HOME_DIR/$ZDOT/.zshrc" <<EOF
# >>> zsh-config head >>>
[[ ! -r \${ZDOTDIR:-\$HOME}/.zshrc.head ]] || source \${ZDOTDIR:-\$HOME}/.zshrc.head
# <<< zsh-config head <<<

$PNPM_BLOCK

# >>> zsh-config tail >>>
[[ ! -r \${ZDOTDIR:-\$HOME}/.zshrc.tail ]] || source \${ZDOTDIR:-\$HOME}/.zshrc.tail
# <<< zsh-config tail <<<
EOF
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

$PNPM_BLOCK"
    printf '# >>> zsh-config pre >>>\nold\n# <<< zsh-config pre <<<\n%s\n# >>> zsh-config post >>>\nold\n# <<< zsh-config post <<<\n' \
        "$PNPM_BLOCK" >"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

$PNPM_BLOCK"
}

# Earlier versions of this repo wrote the whole .zshrc: the pre-split one
# (git 293e292) and the plain .zshrc.d loader. Both go; appended lines stay.
test_old_repo_zshrcs_are_replaced_keeping_appended_lines() {
    git -C "$REPO_DIR" show 293e292:home/private_dot_config/zsh/dot_zshrc >"$HOME_DIR/$ZDOT/.zshrc" ||
        { fail "no legacy .zshrc in git"; return; }
    printf '\n%s\n' "$PNPM_BLOCK" >>"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

$PNPM_BLOCK"
    cat >"$HOME_DIR/$ZDOT/.zshrc" <<'LOADER'
# zsh-config: everything lives in $ZDOTDIR/.zshrc.d/*.zsh, loaded in name
# order: repo snippets (00-early, 70-antidote, 80-zstyles.d, 90-host) and
# unmanaged local NN-name.zsh files between them. Files starting with ~ are
# skipped. chezmoi owns this file: put installer snippets (pnpm, nvm, ...) in
# .zshrc.d/50-name.zsh instead of appending here.
for _zc_f in "${ZDOTDIR:-$HOME}"/.zshrc.d/*.zsh(N); do
  [[ ${_zc_f:t} == '~'* ]] || source "$_zc_f"
done
unset _zc_f
LOADER
    printf '%s\n' "$CARGO_LINE" >>"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshrc)" "$RC_BLOCK

$CARGO_LINE"
}

test_zshrc_d_loads_in_order_then_user_lines() {
    apply_zsh
    local d="$HOME_DIR/$ZDOT/zshrc.d" f
    # Only the loader order: replace the repo files with markers.
    for f in "$d"/*.zsh; do printf 'print -r %s\n' "$(basename "$f" .zsh)" >"$f"; done
    printf 'print -r 50-local\n' >"$d/50-local.zsh"
    printf 'print -r skipped\n' >"$d/~60-off.zsh"
    printf 'print -r user\n' >>"$HOME_DIR/$ZDOT/.zshrc"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin ZDOTDIR="$HOME_DIR/$ZDOT" \
        zsh -fc 'source $ZDOTDIR/.zshrc')"
    assert_eq "$(tr '\n' ' ' <<<"$OUTPUT")" "00-early 50-local 70-antidote 71-custom-plugin 72-options 73-env 75-tools 76-keybindings 80-zstyles.d 90-host user "
}

test_apply_keeps_local_snippets() {
    apply_zsh
    printf 'export MINE=1\n' >"$HOME_DIR/$ZDOT/zshrc.d/50-local.zsh"
    printf 'export MINE=1\n' >"$HOME_DIR/$ZDOT/zshenv.d/50-local.zsh"
    apply_zsh
    [[ -f $HOME_DIR/$ZDOT/zshrc.d/50-local.zsh ]] || fail "local zshrc.d file removed"
    [[ -f $HOME_DIR/$ZDOT/zshenv.d/50-local.zsh ]] || fail "local zshenv.d file removed"
}

test_repo_zshrc_d_files_have_their_roles() {
    apply_zsh
    local d="$HOME_DIR/$ZDOT/zshrc.d" f
    grep -q 'zmodload zsh/zprof' "$d/00-early.zsh" || fail "00-early has no zprof"
    grep -q "zstyle ':antidote:bundle' use-friendly-names" "$d/00-early.zsh" || fail "antidote zstyles not early"
    # The theme loads through use-omz ($ZSH_CUSTOM/themes); DISABLE_LS_COLORS
    # stops its lib from aliasing ls to `ls --color=tty` over our ls function.
    grep -qx 'ZSH_THEME="yupps"' "$d/00-early.zsh" || fail "ZSH_THEME not set"
    grep -qx 'DISABLE_LS_COLORS=true' "$d/00-early.zsh" || fail "DISABLE_LS_COLORS not set"
    grep -q 'antidote bundle' "$d/70-antidote.zsh" || fail "70-antidote doesn't bundle"
    grep -q 'zsh_plugins}.zsh.\$\$' "$d/70-antidote.zsh" || fail "plugin file not written atomically"
    grep -q 'zstyles\.d/\*\.zsh' "$d/80-zstyles.d.zsh" || fail "80-zstyles.d doesn't source zstyles.d"
    # use-omz runs omz's update check on load; antidote owns that clone.
    grep -qx "zstyle ':omz:update' mode disabled" "$d/00-early.zsh" || fail "omz updater not disabled early"
    grep -q 'ZSH_PORTABLE.*\.aliases' "$d/90-host.zsh" || fail "90-host lacks the ~/.aliases guard"
    for f in "$d"/*.zsh "$HOME_DIR/$ZDOT/.zshrc" "$HOME_DIR/$ZDOT"/zshenv.d/*.zsh "$HOME_DIR/$ZDOT"/zstyles.d/*.zsh; do
        zsh -n "$f" || fail "syntax: ${f#$HOME_DIR/}"
    done
    return 0
}

# ---------------------------------------------------------------------------
# zstyles.d: completion and plugin zstyles, loaded by zshrc.d/80-zstyles.d.zsh
# ---------------------------------------------------------------------------

# zstyles CODE: source 80-zstyles.d.zsh in a clean zsh, then run CODE.
zstyles() {
    run_zsh "source \$ZDOTDIR/zshrc.d/80-zstyles.d.zsh; $1"
}

test_zstyles_d_loads_in_order_with_local_files() {
    apply_zsh
    local d="$HOME_DIR/$ZDOT/zstyles.d"
    [[ -d $d ]] || { fail "no zstyles.d"; return; }
    printf "zstyle ':completion:*' menu no\n" >"$d/99-local.zsh"
    printf "zstyle ':completion:*' menu skipped\n" >"$d/~99-off.zsh"
    assert_eq "$(zstyles "zstyle -s ':completion:*' menu v; print -r -- \$v")" "no"
    apply_zsh
    [[ -f $d/99-local.zsh ]] || fail "local zstyles.d file removed"
    [[ -e $HOME_DIR/$ZDOT/.zstyles ]] && fail ".zstyles still deployed"
    return 0
}

test_zstyles_values() {
    apply_zsh
    OUTPUT="$(zstyles '
        zstyle -L ":completion:\*" sort
        zstyle -L ":completion:\*:complete:" rehash
        zstyle -L ":completion:\*:kill:\*" command
        zstyle -L ":fzf-tab:complete:cd:\*"
        zstyle -s ":completion:*:*:*:*:processes" command v && print -r -- "processes=$v"
        zstyle -s ":completion:*:corrections" format v && print -r -- "corrections=$v"
        zstyle -t ":completion:*" keep-prefix && print keep-prefix
        zstyle -t ":completion:*" list-dirs-first && print list-dirs-first
        zstyle -t ":completion::complete:*" gain-privileges && print gain-privileges
        zstyle -t ":omz:plugins:ssh-agent" honor-existing && print ssh-honor-existing
        zstyle -t ":omz:plugins:ssh-agent" lazy && print ssh-lazy-needs-AddKeysToAgent
        zstyle -t ":omz:plugins:ssh-agent" quiet && print ssh-quiet
        zstyle -s ":fzf-tab:complete:z:x" fzf-preview v && print z-preview
        zstyle -s ":fzf-tab:complete:pushd:x" fzf-preview v && print pushd-preview
        zstyle -a ":completion:*" matcher-list v && print -r -- "matchers=$#v"
    ' 2>&1)"
    assert_eq "$OUTPUT" 'processes=ps -u $USER -o pid,%cpu,tty,cputime,cmd -w -w
corrections=[%d (errors: %e)]
keep-prefix
list-dirs-first
gain-privileges
ssh-honor-existing
ssh-quiet
z-preview
pushd-preview
matchers=4'
}

# Each context/style pair is set once: a second setting silently wins.
test_zstyles_set_each_key_once() {
    apply_zsh
    OUTPUT="$(cat "$HOME_DIR/$ZDOT"/zstyles.d/*.zsh |
        sed -nE "s/^[[:space:]]*zstyle[[:space:]]+('[^']*'|\"[^\"]*\")[[:space:]]+([a-z-]+).*/\1 \2/p" |
        sort | uniq -d)"
    assert_eq "$OUTPUT" ""
    # The plugin's 50-completion.zsh owns its keys; zstyles.d loads later and
    # would override them.
    local plugin="$HOME/.config/zsh/plugins/yupps-zsh/conf.d/50-completion.zsh"
    [[ -r $plugin ]] || return 0
    OUTPUT="$(cat "$plugin" "$HOME_DIR/$ZDOT"/zstyles.d/*.zsh |
        sed -nE "s/^[[:space:]]*zstyle[[:space:]]+(-e[[:space:]]+)?('[^']*'|\"[^\"]*\")[[:space:]]+([a-z-]+).*/\2 \3/p" |
        sort | uniq -d)"
    assert_eq "$OUTPUT" ""
}

# The first .d layout used hidden dirs; their loader blocks are rewritten.
test_hidden_d_dir_blocks_are_rewritten() {
    printf '# >>> zsh-config >>>\nfor _zc_f in "$ZDOTDIR"/.zshenv.d/*.zsh(N); do source "$_zc_f"; done\n# <<< zsh-config <<<\n\n%s\n' \
        "$CARGO_LINE" >"$HOME_DIR/.zshenv"
    printf '# >>> zsh-config >>>\nfor _zc_f in "${ZDOTDIR:-$HOME}"/.zshrc.d/*.zsh(N); do source "$_zc_f"; done\n# <<< zsh-config <<<\n\n%s\n' \
        "$CARGO_LINE" >"$HOME_DIR/$ZDOT/.zshrc"
    apply_zsh
    assert_eq "$(zshenv)" "$ENV_BLOCK

$CARGO_LINE"
    assert_eq "$(zshrc)" "$RC_BLOCK

$CARGO_LINE"
}

test_local_files_are_not_sourced() {
    apply_zsh
    grep -rqE '\.zshrc\.local|\.zshenv\.local|\.zstyles\.local' "$HOME_DIR/$ZDOT/.zshrc" \
        "$HOME_DIR/$ZDOT/zshrc.d" "$HOME_DIR/$ZDOT/zshenv.d" "$HOME_DIR/.zshenv" &&
        fail "a .local file is still sourced"
    return 0
}

test_personal_plugin_is_not_an_antidote_bundle() {
    apply_zsh
    local z="$HOME_DIR/$ZDOT"
    grep -q 'yupps' <(grep -v '^\s*#' "$z/.zsh_plugins.txt") && fail "yupps-zsh still bundled by antidote"
    grep -qE '^JordanBradshaw/zsh-config|plugins/jordanbradshaw' "$z/.zsh_plugins.txt" && fail "old plugin still active"
    grep -qF 'YUPPS_REPO:=https://github.com/JordanBradshaw/yupps-zsh.git' "$z/zshrc.d/71-custom-plugin.zsh" ||
        fail "71-custom-plugin.zsh doesn't default to the GitHub repo"
    return 0
}

# 71-custom-plugin.zsh owns plugins/yupps-zsh: an exact chezmoi external there would
# wipe the clone's .git on every refresh.
test_yupps_has_no_chezmoi_external_or_pin() {
    printf '[data]\n    machine = "server"\n    hasSecrets = false\n' >"$SANDBOX/chezmoi.toml"
    OUTPUT="$(chezmoi --source="$REPO_DIR" --config="$SANDBOX/chezmoi.toml" \
        --persistent-state="$SANDBOX/p.db" --destination="$HOME_DIR" execute-template \
        <"$REPO_DIR/home/.chezmoiexternal.toml.tmpl" 2>/dev/null)"
    grep -q '^\[".config/zsh/plugins/yupps' <<<"$OUTPUT" && fail "yupps-zsh still a chezmoi external"
    local f
    for f in home/.chezmoidata.toml scripts/bump-yupps.sh tests/yupps_pin_test.sh; do
        [[ -e $REPO_DIR/$f ]] && fail "$f still exists"
    done
    grep -q 'pluginDev' "$REPO_DIR/home/.chezmoi.toml.tmpl" "$REPO_DIR/home/.chezmoiexternal.toml.tmpl" &&
        fail "pluginDev still in the templates"
    [[ -e $REPO_DIR/home/private_dot_config/zsh/symlink_themes ]] && fail "chezmoi still owns the themes link"
    grep -qsx '.config/zsh/plugins/yupps-zsh' "$REPO_DIR/home/.chezmoiremove" && fail "clone would be removed"
    return 0
}

# make_yupps_repo: a local git repo standing in for GitHub, with a theme that
# says when it loads; sets YUPPS_URL.
make_yupps_repo() {
    local r="$SANDBOX/yupps-repo"
    mkdir -p "$r/conf.d" "$r/themes"
    printf 'print -r loaded:${0:A:h:t}\n' >"$r/yupps.plugin.zsh"
    printf 'print -r theme-loaded\n' >"$r/themes/yupps.zsh-theme"
    git -C "$r" init -q && git -C "$r" add -A &&
        git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
    YUPPS_URL="file://$r"
}

# yupps_commit FILE: add FILE to the stand-in repo and commit it.
yupps_commit() {
    local r="$SANDBOX/yupps-repo"
    printf 'x\n' >"$r/$1"
    git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t commit -qm "$1"
}

# wait_for PATH: up to 5s for PATH to appear (background pulls).
wait_for() {
    local i
    for i in {1..50}; do [[ -e $1 ]] && return 0; sleep 0.1; done
    return 1
}

# yupps_rc [CODE]: source 71-custom-plugin.zsh with YUPPS_REPO=$YUPPS_URL, then CODE.
yupps_rc() {
    run_zsh "YUPPS_REPO='$YUPPS_URL'; source \$ZDOTDIR/zshrc.d/71-custom-plugin.zsh; ${1:-}" 2>&1
}

YUPPS_DIR_REL=$ZDOT/plugins/yupps-zsh

test_yupps_is_cloned_then_loaded() {
    apply_zsh
    make_yupps_repo
    OUTPUT="$(yupps_rc 'print -r -- dir=$YUPPS_DIR')"
    grep -qx 'loaded:yupps-zsh' <<<"$OUTPUT" || fail "not loaded: $OUTPUT"
    grep -qx "dir=$HOME_DIR/$YUPPS_DIR_REL" <<<"$OUTPUT" || fail "wrong YUPPS_DIR: $OUTPUT"
    [[ -d $HOME_DIR/$YUPPS_DIR_REL/.git ]] || fail "not a git checkout"
    return 0
}

test_existing_checkout_is_kept() {
    apply_zsh
    make_yupps_repo
    yupps_rc >/dev/null
    printf 'mine\n' >"$HOME_DIR/$YUPPS_DIR_REL/local-edit"
    OUTPUT="$(yupps_rc)"
    assert_eq "$OUTPUT" "loaded:yupps-zsh"
    [[ -f $HOME_DIR/$YUPPS_DIR_REL/local-edit ]] || fail "checkout was re-cloned"
    return 0
}

# The chezmoi external left a copy without .git; it becomes a checkout.
test_archive_copy_is_replaced_by_a_clone() {
    apply_zsh
    make_yupps_repo
    mkdir -p "$HOME_DIR/$YUPPS_DIR_REL"
    printf 'print -r archive-copy\n' >"$HOME_DIR/$YUPPS_DIR_REL/yupps.plugin.zsh"
    OUTPUT="$(yupps_rc)"
    grep -qx 'loaded:yupps-zsh' <<<"$OUTPUT" || fail "clone not loaded: $OUTPUT"
    [[ -d $HOME_DIR/$YUPPS_DIR_REL/.git ]] || fail "not a git checkout"
    return 0
}

# zssh bundles carry a copy without .git, and the host may be offline.
test_no_clone_under_zssh() {
    apply_zsh
    make_yupps_repo
    local rc="ZSH_PORTABLE=/b YUPPS_REPO='$YUPPS_URL'; source \$ZDOTDIR/zshrc.d/71-custom-plugin.zsh"
    OUTPUT="$(run_zsh "$rc; print -r rc=\$?" 2>&1)"
    assert_eq "$OUTPUT" "rc=0"
    [[ -e $HOME_DIR/$YUPPS_DIR_REL ]] && fail "cloned under zssh"
    mkdir -p "$HOME_DIR/$YUPPS_DIR_REL"
    printf 'print -r bundle-copy\n' >"$HOME_DIR/$YUPPS_DIR_REL/yupps.plugin.zsh"
    OUTPUT="$(run_zsh "$rc" 2>&1)"
    assert_eq "$OUTPUT" "bundle-copy"
    [[ -e $HOME_DIR/$YUPPS_DIR_REL/.git ]] && fail "cloned under zssh"
    return 0
}

test_failed_clone_warns_and_keeps_going() {
    apply_zsh
    YUPPS_URL="file://$SANDBOX/missing-repo"
    OUTPUT="$(yupps_rc 'print -r rc=$?')"
    grep -q 'yupps-zsh: clone of .* failed' <<<"$OUTPUT" || fail "no warning: $OUTPUT"
    grep -qx 'rc=0' <<<"$OUTPUT" || fail "nonzero status: $OUTPUT"
    [[ -z $(ls -A "$HOME_DIR/$ZDOT/plugins" 2>/dev/null) ]] || fail "left files: $(ls -A "$HOME_DIR/$ZDOT/plugins")"
    # An existing copy survives a failed re-clone.
    mkdir -p "$HOME_DIR/$YUPPS_DIR_REL"
    printf 'print -r old-copy\n' >"$HOME_DIR/$YUPPS_DIR_REL/yupps.plugin.zsh"
    OUTPUT="$(yupps_rc)"
    grep -qx 'old-copy' <<<"$OUTPUT" || fail "old copy not loaded: $OUTPUT"
    return 0
}

test_existing_checkout_is_fast_forwarded_in_background() {
    apply_zsh
    make_yupps_repo
    yupps_rc >/dev/null
    yupps_commit conf.d/new.zsh
    OUTPUT="$(yupps_rc)"
    assert_eq "$OUTPUT" "loaded:yupps-zsh"
    wait_for "$HOME_DIR/$YUPPS_DIR_REL/conf.d/new.zsh" || fail "not pulled"
    return 0
}

# --ff-only: local commits are never merged over.
test_diverged_checkout_is_left_alone() {
    apply_zsh
    make_yupps_repo
    yupps_rc >/dev/null
    local c="$HOME_DIR/$YUPPS_DIR_REL"
    printf 'mine\n' >"$c/mine" && git -C "$c" add mine &&
        git -C "$c" -c user.name=t -c user.email=t@t commit -qm mine
    local before && before="$(git -C "$c" rev-parse HEAD)"
    yupps_commit theirs
    yupps_rc >/dev/null
    sleep 1
    assert_eq "$(git -C "$c" rev-parse HEAD)" "$before"
    [[ -e $c/theirs ]] && fail "merged over a local commit"
    return 0
}

test_no_pull_under_zssh() {
    apply_zsh
    make_yupps_repo
    yupps_rc >/dev/null
    yupps_commit conf.d/new.zsh
    run_zsh "ZSH_PORTABLE=/b; source \$ZDOTDIR/zshrc.d/71-custom-plugin.zsh" >/dev/null 2>&1
    sleep 1
    [[ -e $HOME_DIR/$YUPPS_DIR_REL/conf.d/new.zsh ]] && fail "pulled under zssh"
    return 0
}

# $ZSH_CUSTOM/themes points into the plugin, relative, for use-omz.
test_themes_dir_is_linked() {
    apply_zsh
    make_yupps_repo
    yupps_rc >/dev/null
    assert_eq "$(readlink "$HOME_DIR/$ZDOT/themes")" "plugins/yupps-zsh/themes"
    [[ -f $HOME_DIR/$ZDOT/themes/yupps.zsh-theme ]] || fail "theme not reachable"
    return 0
}

test_wrong_themes_link_is_fixed_but_real_dir_kept() {
    apply_zsh
    make_yupps_repo
    ln -s /nowhere "$HOME_DIR/$ZDOT/themes"
    yupps_rc >/dev/null
    assert_eq "$(readlink "$HOME_DIR/$ZDOT/themes")" "plugins/yupps-zsh/themes"
    rm "$HOME_DIR/$ZDOT/themes"
    mkdir -p "$HOME_DIR/$ZDOT/themes"
    printf 'mine\n' >"$HOME_DIR/$ZDOT/themes/mine.zsh-theme"
    yupps_rc >/dev/null
    [[ -L $HOME_DIR/$ZDOT/themes ]] && fail "replaced a real themes dir"
    [[ -f $HOME_DIR/$ZDOT/themes/mine.zsh-theme ]] || fail "real themes dir changed"
    return 0
}

# use-omz (70-antidote) looks for the theme before this file runs: when the
# link is new, the theme loads here once; after that use-omz finds it.
test_new_themes_link_loads_theme_once_in_interactive_shells() {
    apply_zsh
    make_yupps_repo
    local rc="ZSH_THEME=yupps YUPPS_REPO='$YUPPS_URL'; source \$ZDOTDIR/zshrc.d/71-custom-plugin.zsh"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin TERM=dumb zsh -fic "source \$HOME/.zshenv; $rc" 2>&1)"
    grep -qx 'theme-loaded' <<<"$OUTPUT" || fail "theme not loaded on first start: $OUTPUT"
    OUTPUT="$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin TERM=dumb zsh -fic "source \$HOME/.zshenv; $rc" 2>&1)"
    grep -qx 'theme-loaded' <<<"$OUTPUT" && fail "theme loaded again (use-omz's job): $OUTPUT"
    rm "$HOME_DIR/$ZDOT/themes"
    OUTPUT="$(run_zsh "$rc" 2>&1)"
    grep -qx 'theme-loaded' <<<"$OUTPUT" && fail "theme loaded in a non-interactive shell"
    return 0
}

# zssh: no clone or pull, but the link is still made in the bundle.
test_themes_linked_under_zssh() {
    apply_zsh
    mkdir -p "$HOME_DIR/$YUPPS_DIR_REL/themes"
    printf 'print -r bundle-copy\n' >"$HOME_DIR/$YUPPS_DIR_REL/yupps.plugin.zsh"
    OUTPUT="$(run_zsh "ZSH_PORTABLE=/b; source \$ZDOTDIR/zshrc.d/71-custom-plugin.zsh" 2>&1)"
    assert_eq "$OUTPUT" "bundle-copy"
    assert_eq "$(readlink "$HOME_DIR/$ZDOT/themes")" "plugins/yupps-zsh/themes"
}

# ---------------------------------------------------------------------------
# Portable bundle: chezmoi archive renders against an empty home.
# ---------------------------------------------------------------------------

test_archive_has_block_loader_and_repo_snippets_only() {
    apply_zsh
    printf 'export MINE=1\n' >"$HOME_DIR/$ZDOT/zshrc.d/50-local.zsh"
    cz archive --format=tar --output="$SANDBOX/a.tar" --exclude=scripts,externals \
        "$HOME_DIR/.zshenv" "$HOME_DIR/$ZDOT" || { fail "archive failed"; return; }
    mkdir "$SANDBOX/x"
    tar -xf "$SANDBOX/a.tar" -C "$SANDBOX/x"
    assert_eq "$(cat "$SANDBOX/x/.zshenv")" "$ENV_BLOCK"
    assert_eq "$(cat "$SANDBOX/x/$ZDOT/.zshrc")" "$RC_BLOCK"
    [[ -f $SANDBOX/x/$ZDOT/zshenv.d/00-base.zsh ]] || fail "00-base.zsh not archived"
    [[ -e $SANDBOX/x/$ZDOT/zshrc.d/50-local.zsh ]] && fail "local snippet archived"
    return 0
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
