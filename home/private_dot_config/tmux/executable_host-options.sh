#!/bin/sh
#
# Usage: host-options.sh
#
# Options that depend on the host, which tmux.conf can't express: paths under
# the XDG state dir (zssh points it into ~/.zsh-portable, so nothing lands in
# someone else's home) and the clipboard command for tmux-yank.

state=${XDG_STATE_HOME:-$HOME/.local/state}/tmux
mkdir -p "$state/resurrect" "$state/logs"

tmux set -g history-file "$state/history" \; \
    set -g @resurrect-dir "$state/resurrect" \; \
    set -g @logging-path "$state/logs" \; \
    set -g @screen-capture-path "$state/logs" \; \
    set -g @save-complete-history-path "$state/logs"

# tmux-yank knows pbcopy, xclip and xsel but not wl-copy. With none of them
# (ssh hosts), copies still reach the local clipboard through OSC 52
# (set-clipboard on), so give yank a sink instead of its error message.
have() { command -v "$1" >/dev/null 2>&1; }
if [ -n "${WAYLAND_DISPLAY:-}" ] && have wl-copy; then
    tmux set -g @override_copy_command "wl-copy"
elif ! have pbcopy && ! have xclip && ! have xsel && ! have clip.exe; then
    tmux set -g @override_copy_command "cat >/dev/null"
fi
