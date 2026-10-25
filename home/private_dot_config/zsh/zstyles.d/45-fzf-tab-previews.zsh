# -------------------------------------------------------------------
# fzf-tab previews
#
# Only fzf-preview is set per context: a per-context fzf-flags would
# replace the global colors in 40-fzf-tab.zsh.
# -------------------------------------------------------------------
if (( ${+commands[batcat]} )); then
  _zc_bat=batcat
elif (( ${+commands[bat]} )); then
  _zc_bat=bat
else
  _zc_bat=
fi

if (( ${+commands[delta]} )); then
  _zc_gdiff='git diff $word | delta --width=${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}'
  _zc_gshow='git show $word | delta --width=${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}'
else
  _zc_gdiff='git diff --color=always $word'
  _zc_gshow='git show --color=always $word'
fi

# Files and directories
zstyle ':fzf-tab:complete:(cat|bat|batcat|less|more|head|tail|nvim|vim|micro|code):*' fzf-preview \
  "if [[ -d \$realpath ]]; then
     command eza -1 --color=always --icons=always -- \$realpath 2>/dev/null ||
       command lsd -1 --color=always -- \$realpath 2>/dev/null ||
       command ls -1 --color=always -- \$realpath
   else
     ${_zc_bat:+command $_zc_bat --color=always --style=numbers --line-range=:200 -- \$realpath 2>/dev/null ||} command head -n 200 -- \$realpath
   fi"

# Processes: full command line
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
  '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'

# systemd units
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview \
  'SYSTEMD_COLORS=1 systemctl status -- $word'

# git
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview "$_zc_gdiff"
zstyle ':fzf-tab:complete:git-log:*' fzf-preview 'git log --color=always $word'
zstyle ':fzf-tab:complete:git-show:*' fzf-preview \
  "case \$group in
     '[commit tag]') git show --color=always \$word ;;
     *) $_zc_gshow ;;
   esac"
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview \
  "case \$group in
     '[modified file]') $_zc_gdiff ;;
     '[recent commit object name]') $_zc_gshow ;;
     *) git log --color=always \$word ;;
   esac"

# man pages
zstyle ':fzf-tab:complete:(\\|*/|)man:*' fzf-preview \
  'MANWIDTH=$FZF_PREVIEW_COLUMNS man -- $word 2>/dev/null'

# Commands: tldr page, man page, or what the name resolves to.
# The python tldr client downloads on a cache miss (~2s, and it ignores
# TLDR_NETWORK_ENABLED); a file:// source makes misses fail fast while cached
# pages, even stale ones, still render.
zstyle ':fzf-tab:complete:-command-:*' fzf-preview \
  '{ TLDR_PAGES_SOURCE_LOCATION=file:///nonexistent tldr --color $word ||
     MANWIDTH=$FZF_PREVIEW_COLUMNS man -- $word ||
     whence -v -- $word ||
     print -r -- ${(P)word} } 2>/dev/null'

# Variables: current value
zstyle ':fzf-tab:complete:(-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview \
  'print -r -- ${(P)word}'

unset _zc_bat _zc_gdiff _zc_gshow
