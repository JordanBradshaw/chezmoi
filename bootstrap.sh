#!/usr/bin/env bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Requirements
# ---------------------------------------------------------------------------
#if [[ $EUID -eq 0 ]]; then
#    SUDO=""
#elif command -v sudo >/dev/null 2>&1; then
#    SUDO="sudo"
#else
#    echo "Error: Root privileges are required, but sudo is not installed." >&2
#    exit 1
#fi

install_stow() {
    # Already installed.
    if command -v stow >/dev/null 2>&1; then
        return 0
    fi

    echo "GNU Stow is not installed."
    echo "Attempting to install it..."

    # Determine privilege escalation command.
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: Root privileges are required, but sudo is unavailable." >&2
        exit 1
    fi

    # Detect package manager.
    if command -v pacman >/dev/null 2>&1; then
        echo "Package manager: pacman"
        $SUDO pacman -S --needed --noconfirm stow

    elif command -v apt-get >/dev/null 2>&1; then
        echo "Package manager: apt"
        $SUDO apt-get update
        $SUDO apt-get install -y stow

    elif command -v dnf >/dev/null 2>&1; then
        echo "Package manager: dnf"
        $SUDO dnf install -y stow

    elif command -v zypper >/dev/null 2>&1; then
        echo "Package manager: zypper"
        $SUDO zypper --non-interactive install stow

    elif command -v apk >/dev/null 2>&1; then
        echo "Package manager: apk"
        $SUDO apk add stow

    elif command -v xbps-install >/dev/null 2>&1; then
        echo "Package manager: xbps"
        $SUDO xbps-install -Sy stow

    elif command -v emerge >/dev/null 2>&1; then
        echo "Package manager: emerge"
        $SUDO emerge app-admin/stow

    elif command -v brew >/dev/null 2>&1; then
        echo "Package manager: Homebrew"
        brew install stow

    else
        echo "Error: No supported package manager was found." >&2
        exit 1
    fi

    # Make absolutely sure installation worked.
    if ! command -v stow >/dev/null 2>&1; then
        echo "Error: GNU Stow installation failed." >&2
        exit 1
    fi

    echo "GNU Stow installed successfully."
}

install_stow
# if ! command -v stow >/dev/null 2>&1; then
#    echo "Error: GNU Stow is not installed." >&2
#    echo "Install it with: sudo pacman -S stow" >&2
#    exit 1
#fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Use $DOTFILES if it is set and points to a directory.
# Otherwise use the current working directory.
if [[ -n "${DOTFILES:-}" && -d "$DOTFILES" ]]; then
    DOTFILES_DIR="$DOTFILES"
else
    DOTFILES_DIR="$PWD"
fi

TARGET="$HOME"

echo "Dotfiles: $DOTFILES_DIR"
echo "Target:   $TARGET"

# ---------------------------------------------------------------------------
# Stow groups
# ---------------------------------------------------------------------------

case "${1:-}" in
    all)
        echo "Running command: stow -d "$DOTFILES_DIR" -t "$TARGET" -v atuin bat fd git htop lsd pip ripgrep tmux wizterm starship konsole yakuake"
	stow \
            -d "$DOTFILES_DIR" \
            -t "$TARGET" \
            -v atuin bat fd git htop lsd pip ripgrep tmux wizterm starship konsole yakuake
        ;;

    shell)
        stow \
            -d "$DOTFILES_DIR/shell" \
            -t "$TARGET" \
            zsh starship atuin
        ;;

    cli)
        stow \
            -d "$DOTFILES_DIR/cli" \
            -t "$TARGET" \
            bat btop lsd ripgrep micro
        ;;

    *)
        echo "Usage: $0 {terminal|shell|cli}" >&2
        exit 1
        ;;
esac
