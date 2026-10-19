#!/usr/bin/env bash
#
# Set up this machine from the dotfiles repo: install chezmoi if needed, then
# apply. Codespaces runs this automatically for a dotfiles repo.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"

if ! command -v chezmoi >/dev/null 2>&1 && [[ ! -x $bin_dir/chezmoi ]]; then
    echo "Installing chezmoi to $bin_dir..."
    mkdir -p "$bin_dir"
    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"
    elif command -v wget >/dev/null 2>&1; then
        sh -c "$(wget -qO- get.chezmoi.io)" -- -b "$bin_dir"
    else
        echo "Error: curl or wget is required to install chezmoi." >&2
        exit 1
    fi
fi

chezmoi="$(command -v chezmoi || echo "$bin_dir/chezmoi")"
exec "$chezmoi" init --apply --source="$repo_dir" "$@"
