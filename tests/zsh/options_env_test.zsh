#!/usr/bin/env -S zsh -f
#
# Tests for zshrc.d/72-options.zsh and 73-env.zsh (moved from the yupps-zsh
# plugin). Run: zsh -f tests/zsh/options_env_test.zsh

typeset -g ZDOT=${0:A:h:h:h}/home/private_dot_config/zsh
source ${0:A:h}/lib.zsh

test_options() {
  source $ZDOT/zshrc.d/72-options.zsh
  local o
  for o in extended_glob share_history hist_ignore_all_dups auto_cd \
    interactive_comments prompt_subst rm_star_wait; do
    [[ -o $o ]] || fail "$o not set"
  done
  # zstyles.d relies on this: an unquoted # there would be a glob otherwise.
  [[ ! -o nomatch ]] || fail "nomatch still on"
  [[ ! -o flow_control && ! -o beep ]] || fail "flow_control/beep still on"
}

test_env_with_bat_and_fd() {
  stub_echo bat fd fzf less
  path=($STUB_BIN)
  rehash
  unset FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS MANPAGER LESSHISTFILE
  source $ZDOT/zshrc.d/73-env.zsh
  assert_eq "$MANPAGER" "sh -c 'col -bx | bat --language=man --style=plain'" MANPAGER
  assert_eq "$FZF_DEFAULT_COMMAND" "fd --type f" FZF_DEFAULT_COMMAND
  [[ $FZF_DEFAULT_OPTS == *"--preview 'bat "* ]] || fail "no bat preview: $FZF_DEFAULT_OPTS"
  assert_eq "$LESSHISTFILE" "-" LESSHISTFILE
  (( ! ${+_zc_bat} )) || fail "_zc_bat left set"
}

test_env_falls_back_without_tools() {
  path=($STUB_BIN)
  rehash
  unset FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS MANPAGER
  source $ZDOT/zshrc.d/73-env.zsh
  assert_eq "$MANPAGER" "less -R" MANPAGER
  (( ! ${+FZF_DEFAULT_COMMAND} )) || fail "FZF_DEFAULT_COMMAND without fd"
}

test_env_does_not_repeat_base_vars() {
  ! grep -q SSH_ASKPASS_REQUIRE $ZDOT/zshrc.d/73-env.zsh || fail "SSH_ASKPASS_REQUIRE duplicated"
}

test_paths_unique() {
  source $ZDOT/zshenv.d/00-base.zsh
  local p
  for p in path cdpath fpath manpath; do
    [[ ${(t)${(P)p}} == *unique* ]] || fail "$p not unique: ${(t)${(P)p}}"
  done
}

# Containers (proot-distro, docker) often start with no locale, which leaves
# zsh counting bytes instead of characters in the prompt.
test_locale_defaults_to_c_utf8() {
  unset LANG LC_ALL LC_CTYPE
  source $ZDOT/zshenv.d/00-base.zsh
  assert_eq "$LANG" "C.UTF-8" LANG
  [[ ${(t)LANG} == *export* ]] || fail "LANG not exported: ${(t)LANG}"
  local t="╔═🪐"
  assert_eq "${(m)#t}" "4" "prompt width"
}

test_locale_keeps_existing_settings() {
  local v
  for v in LANG LC_ALL LC_CTYPE; do
    (
      unset LANG LC_ALL LC_CTYPE
      export $v=en_US.UTF-8
      source $ZDOT/zshenv.d/00-base.zsh
      if [[ $v == LANG ]]; then
        assert_eq "$LANG" "en_US.UTF-8" "LANG with $v set"
      else
        assert_eq "${LANG-unset}" "unset" "LANG with $v set"
      fi
    ) || fail "with $v set"
  done
}

run_all
