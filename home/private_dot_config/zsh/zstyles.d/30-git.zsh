# git completion. Previews for git commands are in 45-fzf-tab-previews.zsh.

zstyle ':completion:*:*:git:*' tag-order 'common-commands' 'main'
# Keep git's own order (most recent first) for checkout and branches.
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:*:git:*:branches' sort false
zstyle ':completion:*:*:git:*:branches' ignored-patterns 'HEAD'
