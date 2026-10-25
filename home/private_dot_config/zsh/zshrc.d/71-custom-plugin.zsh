# Personal plugin and theme. Cloned on first start (or over a copy without
# .git), fast-forwarded in the background on later starts, then sourced. Not
# bundled by antidote: it loads its conf.d/ itself, so updates need no
# rebundle. Set YUPPS_REPO or YUPPS_DIR earlier (e.g. zshrc.d/50-local.zsh)
# for a fork or an ssh URL.
: ${YUPPS_REPO:=https://github.com/JordanBradshaw/yupps-zsh.git}
: ${YUPPS_DIR:=$ZDOTDIR/plugins/yupps-zsh}

# Never under zssh: the bundle carries a copy and the host may be offline.
if [[ -z $ZSH_PORTABLE ]] && (( $+commands[git] )); then
  if [[ -d $YUPPS_DIR/.git ]]; then
    # In the background so startup never waits on the network; the next
    # shell gets the update. --ff-only never merges over local commits.
    command git -C $YUPPS_DIR pull --ff-only --quiet &>/dev/null &!
  else
    # Clone next to the target and rename, so a shell killed mid-clone
    # leaves no half checkout; a failed clone keeps any copy already there.
    () {
      local tmp=$YUPPS_DIR.clone.$$
      print -ru2 -- "🔧 Cloning $YUPPS_REPO..."
      if command git clone --quiet --depth 1 -- $YUPPS_REPO $tmp; then
        command rm -rf -- $YUPPS_DIR && command mv -- $tmp $YUPPS_DIR
      else
        command rm -rf -- $tmp
        print -ru2 -- "yupps-zsh: clone of $YUPPS_REPO failed"
      fi
    }
  fi
fi

# $ZSH_CUSTOM/themes -> the plugin's themes/, where use-omz looks for
# $ZSH_THEME. A real themes dir is left alone. use-omz (70-antidote) looked
# before this file ran, so when the link is new the theme loads here once.
() {
  local link=${ZSH_CUSTOM:-$ZDOTDIR}/themes target=$YUPPS_DIR/themes
  [[ -d $target ]] || return 0
  [[ $target == ${link:h}/* ]] && target=${target#${link:h}/}
  [[ -e $link && ! -L $link ]] && return 0
  [[ -L $link && $(command readlink -- $link) == $target ]] && return 0
  command ln -sfn -- $target $link || return 0
  if [[ -o interactive && -n $ZSH_THEME && -r $link/$ZSH_THEME.zsh-theme ]]; then
    source $link/$ZSH_THEME.zsh-theme
  fi
}

if [[ -r $YUPPS_DIR/yupps.plugin.zsh ]]; then
  source $YUPPS_DIR/yupps.plugin.zsh
fi
