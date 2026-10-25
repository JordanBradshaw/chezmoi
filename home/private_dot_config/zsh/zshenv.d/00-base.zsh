# Base environment for every zsh, loaded first from zshenv.d by ~/.zshenv.
# Values already set win, so zssh can point the XDG dirs into its bundle.

export PROMPT_SYMBOL=""

# XDG Base Directory spec: fill in defaults only when unset or empty.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
# Not in the spec, but ~/.local/bin is; XDG_BIN_HOME is the de facto name
# (uv, others). XDG_BIN_DIR mirrors it for tools that use that spelling.
export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
export XDG_BIN_DIR="${XDG_BIN_DIR:-$XDG_BIN_HOME}"
# The spec gives no default; only point at the logind dir when it exists and is ours.
if [[ -z $XDG_RUNTIME_DIR && -d /run/user/$UID && -O /run/user/$UID ]]; then
  export XDG_RUNTIME_DIR=/run/user/$UID
fi

# xdg-user-dirs (XDG_DOWNLOAD_DIR, XDG_DOCUMENTS_DIR, ...) from user-dirs.dirs.
() {
  local file=$XDG_CONFIG_HOME/user-dirs.dirs line name value
  [[ -r $file ]] || return 0
  for line in "${(@f)$(<$file)}"; do
    [[ $line =~ '^(XDG_[A-Z]+_DIR)=(.*)$' ]] || continue
    name=$match[1]
    [[ -z ${(P)name} ]] || continue
    value=${(Q)match[2]}
    export $name="${value/#\$HOME/$HOME}"
  done
}

export EDITOR=nano
export SSH_ASKPASS_REQUIRE=never

# One history file for every terminal, in the XDG state dir. An inherited
# HISTFILE wins (zssh exports its bundle's). ZC_HISTFILE remembers the choice:
# VS Code's shell integration overwrites HISTFILE before .zshrc, and
# zshrc.d/00-early.zsh restores it.
typeset -g ZC_HISTFILE="${HISTFILE:-$XDG_STATE_HOME/zsh/history}"
HISTFILE=$ZC_HISTFILE
[[ -d ${HISTFILE:h} ]] || mkdir -p -- "${HISTFILE:h}"

# Completion dump: a fixed name, so use-omz and ez-compinit agree and a
# hostname change doesn't leave a new dump behind.
ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-$XDG_CACHE_HOME/zsh}"
ZSH_COMPDUMP="${ZSH_COMPDUMP:-$ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION}"

# Keep the search paths unique so nested shells don't keep prepending.
typeset -gU path cdpath fpath manpath
path=("$XDG_BIN_HOME" $path)
