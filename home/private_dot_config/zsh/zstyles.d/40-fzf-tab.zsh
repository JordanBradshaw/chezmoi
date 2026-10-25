# fzf-tab. Per-command previews are in 45-fzf-tab-previews.zsh.

zstyle ':fzf-tab:*' fzf-command fzf
zstyle ':fzf-tab:*' continuous-trigger '/'
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'

# Directory previews for cd, pushd and zoxide's z.
zstyle ':fzf-tab:complete:(cd|pushd|z):*' fzf-preview 'command eza -1 --color=always --icons=always -- $realpath 2>/dev/null || command lsd -1 --color=always -- $realpath 2>/dev/null || command ls -1 -- $realpath'

# fzf-tab does not follow FZF_DEFAULT_OPTS. Turning that on may break it
# (Aloxaf/fzf-tab#455):
#   zstyle ':fzf-tab:*' use-fzf-default-opts yes
# Catppuccin Mocha; bg:-1 keeps the terminal's own background.
zstyle ':fzf-tab:*' fzf-flags \
--color=fg:#cdd6f4,bg:-1,hl:#f38ba8 \
--color=fg+:#ffffff,bg+:#313244,hl+:#f38ba8 \
--color=info:#89dceb,prompt:#f9e2af,pointer:#f38ba8 \
--color=marker:#a6e3a1,spinner:#94e2d5,header:#b4befe \
--color=border:#585b70,label:#cba6f7 \
--pointer='▶' --marker='✓' \
--border=rounded --border-label=' complete ' \
--preview-window=right:55%:wrap:border-left \
--info=inline-right --layout=reverse-list --height=60%
