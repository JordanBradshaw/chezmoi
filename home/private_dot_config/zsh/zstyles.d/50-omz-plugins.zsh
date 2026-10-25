# oh-my-zsh plugin settings. The plugins are deferred, so these are in place
# before they load.

# ssh-agent: reuse a running agent and start quietly. Not `lazy`: without
# AddKeysToAgent in ~/.ssh/config (not managed here) keys would never reach the
# agent, and every ssh would ask for the passphrase.
zstyle ':omz:plugins:ssh-agent' honor-existing yes
zstyle ':omz:plugins:ssh-agent' quiet yes
