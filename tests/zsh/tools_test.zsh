#!/usr/bin/env -S zsh -f
#
# Tests for zshrc.d/75-tools.zsh: which tools are initialized, with which
# arguments. The caching itself is the yupps-zsh plugin's _zc_init_cache,
# tested there; here it is a stub that records calls.
# Run: zsh -f tests/zsh/tools_test.zsh

typeset -g ZDOT=${0:A:h:h:h}/home/private_dot_config/zsh
typeset -g CONF=$ZDOT/zshrc.d/75-tools.zsh
source ${0:A:h}/lib.zsh

# Stub: record the call; succeed with an init script defining <tool>_ok when
# the tool is "installed" (listed in $INSTALLED).
stub_init_cache() {
  typeset -ga CALLS=() INSTALLED=("$@")
  function _zc_init_cache() {
    CALLS+=("$*")
    (( ${INSTALLED[(Ie)$1]} )) || return 1
    print -r -- "function ${1}_ok() { print ok }" >| $SANDBOX/$1.zsh
    REPLY=$SANDBOX/$1.zsh
  }
}

test_tools_initialized_with_their_arguments() {
  stub_init_cache zoxide atuin
  source $CONF
  assert_eq "${(j:|:)CALLS}" "zoxide init zsh|atuin init zsh --disable-up-arrow"
  assert_eq "$(zoxide_ok)$(atuin_ok)" "okok"
}

test_missing_tools_are_skipped() {
  stub_init_cache atuin
  source $CONF
  (( ! $+functions[zoxide_ok] )) || fail "missing tool sourced"
  assert_eq "$(atuin_ok)" ok
  (( ! ${+REPLY} )) || fail "REPLY left set"
}

# direnv's own hook embeds its path from /proc/self/exe. On Termux that is
# /system/bin/linker64, which then fails with 'expected absolute path:
# "export"' at every prompt. The repo's hook calls direnv by name.
test_direnv_hook_calls_direnv_by_name() {
  path=($STUB_BIN)
  stub_cmd direnv 'echo "print -r -- direnv:$*"'
  rehash
  source $CONF
  (( ${precmd_functions[(Ie)_direnv_hook]} )) || fail "no precmd hook"
  (( ${chpwd_functions[(Ie)_direnv_hook]} )) || fail "no chpwd hook"
  assert_eq "$(_direnv_hook)" "direnv:export zsh"
  [[ $functions[_direnv_hook] != */* ]] || fail "hook has a path: $functions[_direnv_hook]"
}

test_direnv_hook_registered_once() {
  path=($STUB_BIN)
  stub_cmd direnv
  rehash
  source $CONF
  source $CONF
  local -a pre=(${(M)precmd_functions:#_direnv_hook}) chp=(${(M)chpwd_functions:#_direnv_hook})
  assert_eq $#pre 1 precmd
  assert_eq $#chp 1 chpwd
}

test_no_direnv_no_hook() {
  path=($STUB_BIN)
  rehash
  source $CONF
  (( ! ${+functions[_direnv_hook]} )) || fail "hook without direnv"
  (( ! ${precmd_functions[(Ie)_direnv_hook]:-0} )) || fail "precmd hook without direnv"
}

# Without the plugin (e.g. before chezmoi fetched it) there is nothing to call.
test_without_plugin_helper_nothing_happens() {
  unfunction _zc_init_cache 2>/dev/null
  source $CONF || fail "failed without the helper"
}

run_all
