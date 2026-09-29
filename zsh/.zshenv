export PROMPT_SYMBOL=""
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
# export ZSH="${XDG_CONFIG_HOME:-$HOME/.config}/.oh-my-zsh"

# Keep PATH unique so nested shells don't keep prepending.
typeset -gU path
path=("$HOME/.local/bin" $path)

[[ ! -f "$HOME/.zshenv.local" ]] || source "$HOME/.zshenv.local"
