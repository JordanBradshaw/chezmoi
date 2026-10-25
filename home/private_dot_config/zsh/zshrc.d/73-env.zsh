# Interactive environment: pager, less and fzf defaults, depending on which
# tools are installed.

# bat is installed as `batcat` on Debian/Ubuntu.
if (( ${+commands[batcat]} )); then
    _zc_bat=batcat
elif (( ${+commands[bat]} )); then
    _zc_bat=bat
else
    _zc_bat=
fi

#
# Pager (bat-based man pager)
#
# MANROFFOPT=-c makes groff emit overstrike formatting, which `col -bx`
# strips before bat re-highlights it.
#
if [[ -n $_zc_bat ]]; then
    export MANPAGER="sh -c 'col -bx | $_zc_bat --language=man --style=plain'"
    export MANROFFOPT="-c"
elif (( ${+commands[most]} )); then
    export MANPAGER="most -s"
else
    export MANPAGER="less -R"
fi

#
# less defaults
#
if (( ${+commands[less]} )); then
    export LESS="-R"
    export LESSHISTFILE="-"
fi

#
# fd-find + fzf integration
#
if (( ${+commands[fd]} )); then
    export FZF_DEFAULT_COMMAND="fd --type f"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
elif (( ${+commands[fdfind]} )); then
    export FZF_DEFAULT_COMMAND="fdfind --type f"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

if (( ${+commands[fzf]} )); then
    export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border"

    # fzf preview using bat
    if [[ -n $_zc_bat ]]; then
        export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
--preview '$_zc_bat --style=numbers --color=always {} | head -200'"
    fi
fi

unset _zc_bat
