# Machine-local zstyles from zstyles.d/*.zsh, in name order, after plugins so
# oh-my-zsh's lib/completion.zsh and the yupps-zsh plugin's zstyles.d (the
# repo's completion and plugin zstyles) don't overwrite them. The files are
# unmanaged NN-name.zsh; names starting with ~ are skipped.
for _zc_f in "${ZDOTDIR:-$HOME}"/zstyles.d/*.zsh(N); do [[ ${_zc_f:t} == '~'* ]] || source "$_zc_f"; done
unset _zc_f
