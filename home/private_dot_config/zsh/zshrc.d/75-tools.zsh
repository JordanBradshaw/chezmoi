# Shell hooks: zoxide (z, zi), atuin (Ctrl-R history search) and direnv.
#
# _zc_init_cache (yupps-zsh plugin) caches each tool's init script, so startup
# doesn't run three extra processes; it fails when the tool isn't installed.
# atuin's Ctrl-R binding is (re)applied in 76-keybindings.zsh, because
# zsh-vi-mode resets key bindings on the first prompt.

if (( ${+functions[_zc_init_cache]} )); then
  # Sourced at top level: these scripts set global variables.
  _zc_init_cache zoxide init zsh && source $REPLY
  _zc_init_cache atuin init zsh --disable-up-arrow && source $REPLY
  _zc_init_cache direnv hook zsh && source $REPLY
  unset REPLY
fi
