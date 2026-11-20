# Shell hooks: zoxide (z, zi), atuin (Ctrl-R history search) and direnv.
#
# _zc_init_cache (yupps-zsh plugin) caches each tool's init script, so startup
# doesn't run two extra processes; it fails when the tool isn't installed.
# atuin's Ctrl-R binding is (re)applied in 76-keybindings.zsh, because
# zsh-vi-mode resets key bindings on the first prompt.
#
# direnv's hook is written here rather than taken from `direnv hook zsh`: that
# embeds direnv's path from /proc/self/exe, which on Termux is
# /system/bin/linker64, so every prompt failed with 'expected absolute path:
# "export"'. Calling direnv by name works everywhere.

if (( ${+functions[_zc_init_cache]} )); then
  # Sourced at top level: these scripts set global variables.
  _zc_init_cache zoxide init zsh && source $REPLY
  _zc_init_cache atuin init zsh --disable-up-arrow && source $REPLY
  unset REPLY
fi

if (( ${+commands[direnv]} )); then
  function _direnv_hook() {
    trap -- '' SIGINT
    eval "$(command direnv export zsh)"
    trap - SIGINT
  }
  typeset -ag precmd_functions chpwd_functions
  (( ${precmd_functions[(Ie)_direnv_hook]} )) || precmd_functions=(_direnv_hook $precmd_functions)
  (( ${chpwd_functions[(Ie)_direnv_hook]} )) || chpwd_functions=(_direnv_hook $chpwd_functions)
fi
