# ssh logins land in tmux session $YUPPS_TMUX_SESSION (default main), the
# same one `t` (yupps-zsh plugin) attaches to at the desk. Detaching closes
# the connection; the session keeps running. Before the plugins load, so an
# attaching login doesn't pay for them.
#
# Skipped when: not an interactive ssh login, already inside tmux, a zssh
# bundle (ZSH_PORTABLE), VS Code remote (TERM_PROGRAM=vscode), or opted out
# with YUPPS_TMUX_AUTO=0 or LC_NO_TMUX=1 (`LC_NO_TMUX=1 ssh -o SendEnv=LC_NO_TMUX
# host`; sshd accepts LC_* by default). If tmux fails to start, the login
# falls through to a plain shell.
if [[ -o interactive && -n $SSH_TTY && -z $TMUX && -z $ZSH_PORTABLE ]] &&
   [[ ${YUPPS_TMUX_AUTO:-1} != 0 && -z $LC_NO_TMUX && $TERM_PROGRAM != vscode ]] &&
   (( ${+commands[tmux]} )); then
  command tmux new-session -A -s "${YUPPS_TMUX_SESSION:-main}" && exit
fi
