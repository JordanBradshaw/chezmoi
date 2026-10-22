#!/bin/sh
#
# Usage: load-plugins.sh NAME...
#
# Run each plugin's *.tmux from ./plugins, in the order given. Plugins come
# from chezmoi externals (and the zssh bundle) instead of TPM. A plugin that
# is missing (externals not fetched yet) is skipped.

dir=$(cd "$(dirname "$0")" && pwd)/plugins
for name in "$@"; do
    for entry in "$dir/$name"/*.tmux; do
        [ -x "$entry" ] && "$entry"
    done
done
exit 0
