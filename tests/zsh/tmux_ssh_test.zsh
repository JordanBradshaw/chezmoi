#!/usr/bin/env -S zsh -f
#
# Tests for zshrc.d/01-tmux-ssh.zsh: ssh logins attach to tmux.
# Run: zsh -f tests/zsh/tmux_ssh_test.zsh
#
# login ENV...: an interactive zsh with ENV that sources the file, then
# prints "shell" (only reached when it didn't attach and exit). tmux is a
# stub logging its arguments; it fails when $SANDBOX/tmux-fails exists.

typeset -g ZDOT=${0:A:h:h:h}/home/private_dot_config/zsh
typeset -g CONF=$ZDOT/zshrc.d/01-tmux-ssh.zsh
source ${0:A:h}/lib.zsh

stub_tmux() {
  stub_cmd tmux 'echo "$*" >> '$SANDBOX'/tmux.log; [ ! -e '$SANDBOX'/tmux-fails ]'
}

login() {
  env -i HOME=$HOME PATH=$STUB_BIN:/usr/bin:/bin TERM=dumb "$@" \
    zsh -fic "source $CONF; print shell" </dev/null 2>/dev/null
}

tmux_log() { [[ -r $SANDBOX/tmux.log ]] && print -r -- "$(<$SANDBOX/tmux.log)" }

test_ssh_login_attaches_main_and_exits() {
  stub_tmux
  assert_eq "$(login SSH_TTY=/dev/pts/9)" "" output
  assert_eq "$(tmux_log)" "new-session -A -s main"
}

test_session_name_from_env() {
  stub_tmux
  login SSH_TTY=/dev/pts/9 YUPPS_TMUX_SESSION=dev >/dev/null
  assert_eq "$(tmux_log)" "new-session -A -s dev"
}

# A tmux that can't start (bad config) must not lock the login out.
test_tmux_failure_leaves_a_shell() {
  stub_tmux
  touch $SANDBOX/tmux-fails
  assert_eq "$(login SSH_TTY=/dev/pts/9)" "shell"
}

test_local_terminal_not_attached() {
  stub_tmux
  assert_eq "$(login)" "shell"
  assert_eq "$(tmux_log)" "" tmux
}

test_already_in_tmux() {
  stub_tmux
  assert_eq "$(login SSH_TTY=/dev/pts/9 TMUX=/tmp/tmux-1000/default,1,0)" "shell"
}

test_opt_outs() {
  stub_tmux
  assert_eq "$(login SSH_TTY=/dev/pts/9 YUPPS_TMUX_AUTO=0)" "shell" YUPPS_TMUX_AUTO
  assert_eq "$(login SSH_TTY=/dev/pts/9 LC_NO_TMUX=1)" "shell" LC_NO_TMUX
  assert_eq "$(login SSH_TTY=/dev/pts/9 ZSH_PORTABLE=/b)" "shell" zssh
  assert_eq "$(login SSH_TTY=/dev/pts/9 TERM_PROGRAM=vscode)" "shell" vscode
  assert_eq "$(tmux_log)" "" tmux
}

test_without_tmux() {
  assert_eq "$(login SSH_TTY=/dev/pts/9)" "shell"
}

test_non_interactive_not_attached() {
  stub_tmux
  assert_eq "$(env -i HOME=$HOME PATH=$STUB_BIN:/usr/bin:/bin SSH_TTY=/dev/pts/9 zsh -fc "source $CONF; print shell")" "shell"
}

run_all
