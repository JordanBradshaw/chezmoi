#!/usr/bin/env bash
#
# Make zsh the login shell. Run by chezmoi on interactive applies
# (run_onchange_after_15-login-shell.sh.tmpl), after install-apps.sh has
# installed zsh. Never fails the apply: every problem is a warning.
#
#   SHELLS_FILE  the list chsh accepts (default /etc/shells)

shells_file=${SHELLS_FILE:-/etc/shells}

warn() { echo "set-login-shell: warning: $*" >&2; }

if ! zsh_path=$(command -v zsh); then
    warn "zsh not found, login shell unchanged"
    exit 0
fi

# Termux: its own chsh takes a shell name and links ~/.termux/shell (bash
# when missing); there is no /etc/shells, passwd entry or sudo to use.
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/* ]]; then
    current=$(readlink "$HOME/.termux/shell" 2>/dev/null)
    [[ ${current##*/} == zsh ]] && exit 0
    echo "Changing the Termux shell to zsh"
    chsh -s zsh || warn "chsh failed; run it yourself: chsh -s zsh"
    exit 0
fi

current=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
current=${current:-${SHELL:-}}
[[ ${current##*/} == zsh ]] && exit 0

if ! grep -qxF "$zsh_path" "$shells_file" 2>/dev/null; then
    warn "$zsh_path is not in $shells_file; add it as root, then run: chsh -s $zsh_path"
    exit 0
fi

echo "Changing the login shell to $zsh_path"
# Passwordless sudo first: cloud VM users often have no password for chsh.
if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1 &&
    sudo -n chsh -s "$zsh_path" "$(id -un)" 2>/dev/null; then
    exit 0
fi
chsh -s "$zsh_path" || warn "chsh failed; run it yourself: chsh -s $zsh_path"
exit 0
