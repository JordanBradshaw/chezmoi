#!/usr/bin/env bash
set -euo pipefail

ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"

mkdir -p "$ICON_DIR"

install_or_update() {
    local repo="$1"
    local name="$2"
    local dest="$ICON_DIR/$name"

    if [[ -d "$dest/.git" ]]; then
        echo "Updating $name..."

        # Don't overwrite local modifications
        if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then
            echo "WARNING: $name has local changes. Skipping update."
            return 0
        fi

        git -C "$dest" pull --ff-only

    elif [[ -e "$dest" ]]; then
        echo "WARNING: $dest already exists and is not a Git repository."
        echo "Skipping to avoid overwriting files."

    else
        echo "Installing $name..."

        # Clone into a temporary directory first
        local tmp
        tmp=$(mktemp -d "$ICON_DIR/.${name}.XXXXXX")

        if git clone --depth=1 "$repo" "$tmp/repo"; then
            mv "$tmp/repo" "$dest"
            rmdir "$tmp"
            echo "Installed $name successfully."
        else
            rm -rf -- "$tmp"
            echo "ERROR: Failed to install $name." >&2
            return 1
        fi
    fi
}

install_or_update \
    "https://github.com/EliverLara/candy-icons.git" \
    "candy-icons"

install_or_update \
    "https://github.com/EliverLara/Sweet-folders.git" \
    "Sweet-folders"

echo
echo "Installation complete."
echo "Icon directory: $ICON_DIR"