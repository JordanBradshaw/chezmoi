# Key bindings, for the plugins in .zsh_plugins.txt (zsh-vi-mode,
# history-substring-search, autosuggestions) and atuin.
#
# zsh-vi-mode rebuilds its keymaps on the first prompt, discarding bindings made
# earlier, so everything here is registered through zvm_after_init_commands.

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'

# Shift+Enter: add a line to the command without running it. In normal mode
# the cursor sits on a character, so the break goes after that character.
function _zc_insert_newline() {
  if [[ $KEYMAP == vicmd && -n $RBUFFER ]]; then
    LBUFFER+=${RBUFFER[1]}
    RBUFFER=${RBUFFER[2,-1]}
  fi
  LBUFFER+=$'\n'
}
zle -N _zc_insert_newline

function _zc_bind_keys() {
  [[ -v terminfo ]] || zmodload zsh/terminfo

  # zsh-history-substring-search: arrow keys (normal + application cursor mode)
  if (( ${+widgets[history-substring-search-up]} )); then
    local keymap
    for keymap in emacs viins; do
      bindkey -M $keymap '^[[A' history-substring-search-up
      bindkey -M $keymap '^[[B' history-substring-search-down
      [[ -n $terminfo[kcuu1] ]] && bindkey -M $keymap "$terminfo[kcuu1]" history-substring-search-up
      [[ -n $terminfo[kcud1] ]] && bindkey -M $keymap "$terminfo[kcud1]" history-substring-search-down
    done
    bindkey -M vicmd 'k' history-substring-search-up
    bindkey -M vicmd 'j' history-substring-search-down
    bindkey -M emacs '^P' history-substring-search-up
    bindkey -M emacs '^N' history-substring-search-down
  fi

  # zsh-autosuggestions: ^F accepts a word, ^E accepts the whole suggestion
  bindkey -M viins '^F' vi-forward-word
  bindkey -M viins '^E' vi-add-eol

  # Shift+Enter in Konsole and Yakuake sends ESC O M. Unbound, vi mode reads
  # it as ESC, O (open a line above) and a literal M.
  local km
  for km in emacs viins vicmd; do
    bindkey -M $km '^[OM' _zc_insert_newline
  done

  # atuin: Ctrl-R searches history; Up stays history-substring-search
  if (( ${+widgets[atuin-search]} )); then
    bindkey -M emacs '^R' atuin-search
    bindkey -M viins '^R' atuin-search-viins
    bindkey -M vicmd '^R' atuin-search-vicmd
  fi

  # yupps theme: toggle one/two line prompt
  if (( ${+widgets[toggle_oneline_prompt]} )); then
    bindkey -M emacs '^X^P' toggle_oneline_prompt
    bindkey -M viins '^X^P' toggle_oneline_prompt
  fi
}

if (( ${+functions[zvm_init]} )); then
  zvm_after_init_commands+=(_zc_bind_keys)
else
  # No zsh-vi-mode: bind once everything (theme, plugins) has loaded.
  autoload -Uz add-zsh-hook
  function _zc_bind_keys_once() {
    _zc_bind_keys
    add-zsh-hook -d precmd _zc_bind_keys_once
    unfunction _zc_bind_keys_once
  }
  add-zsh-hook precmd _zc_bind_keys_once
fi
