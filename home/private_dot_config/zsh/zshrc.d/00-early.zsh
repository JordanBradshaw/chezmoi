# Loaded first from zshrc.d: what must be in place before anything else.

# `zsh-prof` sets ZSH_PROF to profile startup; this must stay first.
[[ -n $ZSH_PROF ]] && zmodload zsh/zprof
color_prompt=yes

# VS Code's shell integration sets HISTFILE=$ZDOTDIR/.zsh_history between
# .zshenv and .zshrc; use the file zshenv.d/00-base.zsh picked.
[[ -n $ZC_HISTFILE ]] && HISTFILE=$ZC_HISTFILE

# use-omz loads the theme from $ZSH_CUSTOM/themes (the zsh-themes external)
# at the first prompt. Its lib then aliases ls to `ls --color=tty`, which
# would shadow our ls function; DISABLE_LS_COLORS stops that.
ZSH_THEME="yupps"
DISABLE_LS_COLORS=true

# Antidote settings must be in place before `antidote load`.
zstyle ':antidote:bundle' use-friendly-names 'yes'
# Don't let zsh-defer re-run precmd hooks after each deferred plugin. zshrinkwrap
# prints the top prompt line from precmd, and zsh-defer sends that output to
# /dev/null, which wiped the first line of the first prompt.
zstyle ':antidote:bundle:*' defer-options '-m'

# use-omz runs oh-my-zsh's update check when it loads. antidote owns that clone
# (`antidote update`), so omz must not offer to update it.
zstyle ':omz:update' mode disabled
