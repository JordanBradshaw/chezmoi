# Completion and plugin zstyles from zstyles.d/*.zsh, in name order, after
# plugins so oh-my-zsh's lib/completion.zsh doesn't overwrite them. Local
# overrides: unmanaged zstyles.d/NN-name.zsh files; names starting with ~ are
# skipped.
for _zc_f in "${ZDOTDIR:-$HOME}"/zstyles.d/*.zsh(N); do [[ ${_zc_f:t} == '~'* ]] || source "$_zc_f"; done
unset _zc_f
