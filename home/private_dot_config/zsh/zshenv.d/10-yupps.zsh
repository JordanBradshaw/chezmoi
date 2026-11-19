# The yupps-zsh plugin's zshenv.d (toolchain PATH, ...), after 00-base so the
# XDG dirs are set and before local snippets. A missing checkout, or one from
# before the plugin had zshenv.d, loads nothing.
for _zc_yf in "$YUPPS_DIR"/zshenv.d/*.zsh(N); do
  [[ ${_zc_yf:t} == '~'* ]] || source "$_zc_yf"
done
unset _zc_yf
