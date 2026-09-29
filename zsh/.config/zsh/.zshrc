#!/bin/zsh
color_prompt=yes

# Antidote settings must be in place before `antidote load`.
zstyle ':antidote:bundle' use-friendly-names 'yes'

[[ -d ${ZDOTDIR:-$HOME}/.antidote ]] || {
  echo "🔧 Installing Antidote..."
  git clone --depth=1 https://github.com/mattmc3/antidote "${ZDOTDIR:-$HOME}/.antidote"
}
if [[ -f "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh"
  # Regenerate the static plugin file only when the plugin list changes;
  # `antidote load` does this check the slow way on every startup.
  zsh_plugins=${ZDOTDIR:-$HOME}/.zsh_plugins
  if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
    antidote bundle <${zsh_plugins}.txt >|${zsh_plugins}.zsh
  fi
  source ${zsh_plugins}.zsh
  unset zsh_plugins
fi

# Completion zstyles are applied after plugins so oh-my-zsh's lib/completion.zsh
# doesn't overwrite them.
[[ ! -f ${ZDOTDIR:-$HOME}/.zstyles ]] || source ${ZDOTDIR:-$HOME}/.zstyles
[[ ! -f ${ZDOTDIR:-$HOME}/.zstyles.local ]] || source ${ZDOTDIR:-$HOME}/.zstyles.local

if [ -f ~/.aliases ]; then
    . ~/.aliases
fi
