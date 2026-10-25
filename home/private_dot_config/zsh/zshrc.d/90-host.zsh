# The machine's own ~/.aliases, if any. Not in zssh bundles: there it belongs
# to whoever owns the host (on the Jetsons it runs camera commands).
if [[ -z $ZSH_PORTABLE && -f ~/.aliases ]]; then
  . ~/.aliases
fi
