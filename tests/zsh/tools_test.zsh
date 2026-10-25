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
  stub_init_cache zoxide atuin direnv
  source $CONF
  assert_eq "${(j:|:)CALLS}" "zoxide init zsh|atuin init zsh --disable-up-arrow|direnv hook zsh"
  assert_eq "$(zoxide_ok)$(atuin_ok)$(direnv_ok)" "okokok"
}

test_missing_tools_are_skipped() {
  stub_init_cache direnv
  source $CONF
  (( ! $+functions[zoxide_ok] && ! $+functions[atuin_ok] )) || fail "missing tool sourced"
  assert_eq "$(direnv_ok)" ok
  (( ! ${+REPLY} )) || fail "REPLY left set"
}

# Without the plugin (e.g. before chezmoi fetched it) there is nothing to call.
test_without_plugin_helper_nothing_happens() {
  unfunction _zc_init_cache 2>/dev/null
  source $CONF || fail "failed without the helper"
}

run_all
