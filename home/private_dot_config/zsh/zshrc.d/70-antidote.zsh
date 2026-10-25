# Plugins, after local snippets numbered below 70 so PATH entries they add
# (pnpm, nvm, ...) are in place when plugins check which commands exist.

[[ -d ${ZDOTDIR:-$HOME}/.antidote ]] || {
  echo "🔧 Installing Antidote..."
  git clone --depth=1 https://github.com/mattmc3/antidote "${ZDOTDIR:-$HOME}/.antidote"
}
if [[ -f "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh"
  # Regenerate the static plugin file only when the plugin list changes;
  # `antidote load` does this check the slow way on every startup. Write to a
  # temp file and rename: a shell killed mid-bundle (e.g. tmux kill-server)
  # must not leave an empty file newer than the list, which would never be
  # regenerated. An empty file counts as stale for the same reason.
  zsh_plugins=${ZDOTDIR:-$HOME}/.zsh_plugins
  if [[ ! -s ${zsh_plugins}.zsh || ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
    if antidote bundle <${zsh_plugins}.txt >|${zsh_plugins}.zsh.$$; then
      command mv -f ${zsh_plugins}.zsh.$$ ${zsh_plugins}.zsh
    else
      command rm -f ${zsh_plugins}.zsh.$$
    fi
  fi
  source ${zsh_plugins}.zsh
  unset zsh_plugins
fi
