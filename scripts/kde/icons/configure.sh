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

find ~/.local/share/icons/Sweet-folders \
    -mindepth 2 -maxdepth 2 \
    -name index.theme -printf '%h\n' |
while IFS= read -r dir; do
    dest="$HOME/.local/share/icons/$(basename "$dir")"

    if [[ ! -e "$dest" ]]; then
        cp -a -- "$dir" "$dest"
        echo "Installed $(basename "$dir")"
    else
        echo "Skipping existing $(basename "$dir")"
    fi
done

echo
echo "Installation complete."
echo "Icon directory: $ICON_DIR"

kbuildsycoca6 --noincremental

kwriteconfig6 --file "kdeglobals --group Icons --key Theme candy-icons