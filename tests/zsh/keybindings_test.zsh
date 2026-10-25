#!/usr/bin/env -S zsh -f
#
# Tests for zshrc.d/76-keybindings.zsh (moved from the yupps-zsh plugin).
# Run: zsh -f tests/zsh/keybindings_test.zsh

typeset -g ZDOT=${0:A:h:h:h}/home/private_dot_config/zsh
typeset -g CONF=$ZDOT/zshrc.d/76-keybindings.zsh
source ${0:A:h}/lib.zsh

load_conf() {
  zmodload zsh/zle
  source $CONF
  _zc_bind_keys
}

# Konsole and Yakuake send ESC O M for Shift+Enter. Unbound, zsh-vi-mode reads
# it as ESC (normal mode), O (open a line above) and a literal M.
test_shift_enter_bound_in_insert_mode() {
  load_conf
  assert_eq "$(bindkey -M viins '^[OM')" '"^[OM" _zc_insert_newline'
}

test_shift_enter_bound_in_normal_mode() {
  load_conf
  assert_eq "$(bindkey -M vicmd '^[OM')" '"^[OM" _zc_insert_newline'
}

test_shift_enter_bound_in_emacs_mode() {
  load_conf
  assert_eq "$(bindkey -M emacs '^[OM')" '"^[OM" _zc_insert_newline'
}

test_insert_newline_splits_at_cursor() {
  load_conf
  LBUFFER='echo' RBUFFER=' hi'
  _zc_insert_newline
  assert_eq "$LBUFFER" $'echo\n' left
  assert_eq "$RBUFFER" ' hi' right
}

test_insert_newline_at_end() {
  load_conf
  LBUFFER='echo hi' RBUFFER=
  _zc_insert_newline
  assert_eq "$LBUFFER$RBUFFER" $'echo hi\n'
}

# In normal mode the cursor sits on a character, so the break goes after it.
test_insert_newline_normal_mode_breaks_after_cursor_char() {
  load_conf
  KEYMAP=vicmd LBUFFER='echo hi' RBUFFER='!'
  _zc_insert_newline
  assert_eq "$LBUFFER$RBUFFER" $'echo hi!\n'
}

test_ctrl_r_bound_to_atuin_up_untouched() {
  zmodload zsh/zle
  function _w() { : }
  zle -N atuin-search _w
  zle -N atuin-search-viins _w
  zle -N atuin-search-vicmd _w
  zle -N history-substring-search-up _w
  zle -N history-substring-search-down _w
  load_conf
  assert_eq "$(bindkey -M emacs '^R')" '"^R" atuin-search' emacs
  assert_eq "$(bindkey -M viins '^R')" '"^R" atuin-search-viins' viins
  assert_eq "$(bindkey -M vicmd '^R')" '"^R" atuin-search-vicmd' vicmd
  assert_eq "$(bindkey -M viins '^[[A')" '"^[[A" history-substring-search-up' up
}

test_ctrl_r_untouched_without_atuin() {
  zmodload zsh/zle
  local before=$(bindkey -M emacs '^R')
  load_conf
  assert_eq "$(bindkey -M emacs '^R')" "$before"
}

run_all
