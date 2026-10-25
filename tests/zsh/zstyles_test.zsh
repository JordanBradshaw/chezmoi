#!/usr/bin/env -S zsh -f
#
# Tests for zstyles.d/*.zsh: ssh hosts, general completion styles and the
# fzf-tab previews (moved from the yupps-zsh plugin's 50-completion.zsh).
# Run: zsh -f tests/zsh/zstyles_test.zsh
#
# Each test runs in a subshell with a temporary HOME, cache dir, PATH stubs and
# fpath stubs, against a real compinit.

typeset -g ZDOT=${0:A:h:h:h}/home/private_dot_config/zsh
source ${0:A:h}/lib.zsh

# load_conf: compinit, then every zstyles.d file in order, as 80-zstyles.d does.
load_conf() {
  rehash
  autoload -Uz compinit
  compinit -D -i
  local f
  for f in $ZDOT/zstyles.d/*.zsh(N); do source $f; done
}

# ---------------------------------------------------------------------------
# SSH (15-ssh.zsh)
# ---------------------------------------------------------------------------

# Parsing ssh configs is the yupps-zsh plugin's _zc_ssh_hosts (tested there).
test_ssh_zstyles_cover_ssh_family() {
  function _zc_ssh_hosts() { reply=(zbox) }
  load_conf
  local cmd
  local -a hosts users
  for cmd in ssh scp sftp rsync ssh-copy-id mosh sshfs; do
    zstyle -a ":completion::complete:${cmd}:argument-1:hosts" hosts hosts
    assert_eq "$hosts" "zbox" "hosts for $cmd"
    zstyle -a ":completion::complete:${cmd}:argument-1:users" users users
    assert_eq "$users" "root $USER" "users for $cmd"
  done
}

test_ssh_without_plugin_sets_users_only() {
  unfunction _zc_ssh_hosts 2>/dev/null
  load_conf
  local -a hosts users
  zstyle -a ':completion::complete:ssh:argument-1:hosts' hosts hosts
  assert_eq "${#hosts}" 0 hosts
  zstyle -a ':completion::complete:ssh:argument-1:users' users users
  assert_eq "$users" "root $USER" users
}

# ---------------------------------------------------------------------------
# General completion styles (10-completion.zsh)
# ---------------------------------------------------------------------------

test_approximate_scales_with_length() {
  load_conf
  local v PREFIX=abcdefghi SUFFIX=
  zstyle -s ':completion::approximate:::' max-errors v
  assert_eq "$v" "3 numeric"
}

test_topic_zstyles() {
  load_conf
  zstyle -t ':completion::complete:docker:argument-1:' option-stacking || fail docker
  zstyle -t ':completion::complete:man:argument-1:manuals' separate-sections || fail man
  zstyle -t ':completion::complete:make:argument-1:targets' call-command || fail make
  zstyle -t ':completion::complete:cd:argument-1:' squeeze-slashes || fail squeeze
  local v
  zstyle -s ':completion::complete:rm:argument-rest:' ignore-line v
  assert_eq "$v" "other" ignore-line
  zstyle -s ':completion::complete:-command-::functions' ignored-patterns v
  [[ _foo == ${~v} ]] || fail "functions ignore _*"
}

# ---------------------------------------------------------------------------
# fzf-tab previews (45-fzf-tab-previews.zsh)
# ---------------------------------------------------------------------------

test_fzf_tab_previews_defined() {
  load_conf
  local ctx v
  for ctx in \
    ':fzf-tab:complete:kill:argument-rest' \
    ':fzf-tab:complete:systemctl-status:argument-1' \
    ':fzf-tab:complete:git-log:argument-1' \
    ':fzf-tab:complete:git-diff:argument-rest' \
    ':fzf-tab:complete:git-checkout:argument-rest' \
    ':fzf-tab:complete:man:argument-1' \
    ':fzf-tab:complete:-command-:' \
    ':fzf-tab:complete:-parameter-:' \
    ':fzf-tab:complete:nvim:argument-rest' \
    ':fzf-tab:complete:cd:argument-1'; do
    zstyle -s $ctx fzf-preview v || fail "no preview for $ctx"
  done
}

# A per-context fzf-flags would replace the global colors from 40-fzf-tab.
test_fzf_flags_only_global() {
  stub_echo fzf
  load_conf
  local line
  for line in "${(@f)$(zstyle -L 'fzf-tab*' fzf-flags)}"; do
    [[ -z $line || $line == "zstyle ':fzf-tab:*' fzf-flags "* ]] || fail "per-context fzf-flags: $line"
  done
}

test_git_diff_preview_without_preview_columns() {
  (( $+commands[git] )) || return 0
  load_conf
  cd $SANDBOX
  git init -q repo && cd repo
  print one >| f && git add f && git -c user.name=t -c user.email=t@t commit -qm init
  print two >| f
  unset FZF_PREVIEW_COLUMNS
  local v out word=f group='[modified file]'
  zstyle -s ':fzf-tab:complete:git-diff:argument-rest' fzf-preview v
  out=$(eval $v 2>&1) || fail "preview failed: $out"
  # delta colours words separately; compare the plain text.
  out=${out//$'\e'\[[0-9;]#m/}
  [[ $out == *two* ]] || fail "diff missing: $out"
}

dir_preview() {
  local v realpath=$SANDBOX
  zstyle -s ':fzf-tab:complete:cat:argument-rest' fzf-preview v
  eval $v
}

test_dir_preview_prefers_eza() {
  stub_echo eza lsd
  load_conf
  local out=$(dir_preview)
  [[ $out == eza\ * ]] || fail "expected eza, got: $out"
}

test_dir_preview_falls_back_to_lsd() {
  stub_echo lsd
  load_conf
  path=($STUB_BIN)
  local out=$(dir_preview)
  [[ $out == lsd\ * ]] || fail "expected lsd, got: $out"
}

command_preview() {
  local v word=$1
  zstyle -s ':fzf-tab:complete:-command-:' fzf-preview v
  eval $v
}

test_command_preview_uses_offline_tldr_first() {
  stub_cmd tldr 'echo "TLDR src=$TLDR_PAGES_SOURCE_LOCATION args=$*"'
  load_conf
  local out=$(command_preview foo)
  assert_eq "$out" "TLDR src=file:///nonexistent args=--color foo"
}

test_command_preview_falls_back_without_tldr_page() {
  stub_cmd tldr 'exit 1'
  stub_cmd zzfoo
  load_conf
  rehash
  local out=$(command_preview zzfoo)
  [[ $out == "zzfoo is $STUB_BIN/zzfoo" ]] || fail "expected whence output, got: $out"
}

# ---------------------------------------------------------------------------

run_all
