# Completion behaviour: completers, matching, caching, menu and paths.

# Pick up new executables without `rehash`.
zstyle ':completion:*' rehash true

# Cache for slow completions (apt, dpkg, ...).
mkdir -p -- "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# Completion strategies: *.ext<TAB> extensions, normal, glob match, typo
# correction (max-errors below)
zstyle ':completion:*' completer _extensions _complete _match _approximate

# Matching: exact case first, then ignore case, then partial words around
# . _ -, then substring
zstyle ':completion:*' matcher-list \
  '' \
  'm:{a-zA-Z}={A-Za-z}' \
  'r:|[._-]=* r:|=*' \
  'l:|=*'

# `menu yes` makes zsh report a menu insert, so fzf-tab opens on the first Tab
# instead of inserting the common prefix (e.g. tem -> temp) and waiting for a
# second Tab. Use `menu no` to get the prefix-first behaviour back.
zstyle ':completion:*' menu yes
# oh-my-zsh lib/completion.zsh sets `menu select` on a more specific pattern, which would win
zstyle -d ':completion:*:*:*:*:*' menu

# accept-exact: `yes` takes an exact name match (temp<Tab> -> temp) instead of
# opening the menu with temp, temp2, ... Off by default. To try it:
#   ZSH_ACCEPT_EXACT=yes zsh                         # new shell
#   zstyle ':completion:*' accept-exact yes          # current shell
zstyle ':completion:*' accept-exact ${ZSH_ACCEPT_EXACT:-no}

zstyle ':completion:*' beep no

# Paths
zstyle ':completion:*' ignore-parents parent pwd
zstyle ':completion:*' list-dirs-first true
# Keep ~/ and $VAR/ as typed instead of expanding them.
zstyle ':completion:*' keep-prefix true
zstyle ':completion:*:cd:*' tag-order local-directories directory-stack path-directories

# With sudo in front, complete paths only root can read. Uses `sudo -n`, so it
# never asks for a password.
zstyle ':completion::complete:*' gain-privileges 1

# Process list for kill and friends. oh-my-zsh sets this on the same pattern;
# a less specific pattern would lose to it.
zstyle ':completion:*:*:*:*:processes' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd -w -w'

# Typo tolerance: one error per three typed characters, at most seven.
zstyle -e ':completion:*:approximate:*' max-errors \
  'reply=($(( ($#PREFIX + $#SUFFIX) / 3 > 7 ? 7 : ($#PREFIX + $#SUFFIX) / 3 )) numeric)'

# Hide completion internals and hook functions when completing commands
zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec)|prompt_*)'

# a//b -> a/b instead of a/*/b
zstyle ':completion:*' squeeze-slashes true

# Don't offer arguments already on the command line
zstyle ':completion:*:(rm|kill|diff|cp|mv):*' ignore-line other

# Editors skip build artifacts
zstyle ':completion:*:*:(nvim|vim|micro|code):*:*files' ignored-patterns \
  '*.(o|pyc|zwc|class|swp)' '*~'

# sudo completes commands from root's PATH
zstyle ':completion:*:sudo:*' command-path \
  /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

# man: group pages by section
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.*' insert-sections true

# docker: complete after stacked short options, e.g. `docker run -it<TAB>`
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# make: list targets by running make
zstyle ':completion:*:make:*:targets' call-command true
