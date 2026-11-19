# zshrinkwrap: keep the split prompt off until its resize timer is fixed.
#
# On a resize it collapses the input line to `%` and restores it from a 0.2s
# `zle -F` timer that TRAPWINCH registers. zsh 5.9's raw_getbyte only builds
# its poll list when it starts waiting for a key, or after a watched fd fires,
# so a timer added by a second resize at the same prompt is never polled: the
# prompt stays `%` until a key is pressed. tmux with two clients of different
# sizes resizes the pane each time the active client changes, and hits this
# every time. `none` leaves the whole prompt to zle, which can leave stale
# prompt lines behind after a terminal reflows them.
zstyle ':zshrinkwrap:resize:*' strategy none
