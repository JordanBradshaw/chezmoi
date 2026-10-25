# How completion lists look: groups, headers and colours.
#
# fzf-tab shows group headers but ignores escape sequences in them, so the
# headers it shows (descriptions, corrections) use plain brackets.

zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'
# Typo-corrected matches from _approximate.
zstyle ':completion:*:corrections' format '[%d (errors: %e)]'
zstyle ':completion:*:messages' format '%F{blue}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'
zstyle ':completion:*' auto-description 'specify: %d'

zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Prompt when list is too long
zstyle ':completion:*' list-prompt '%SAt %p: hit TAB for more, or the character to insert%s'
zstyle ':completion:*' select-prompt '%SScrolling list: current selection at %p%s'
