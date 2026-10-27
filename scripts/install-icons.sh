#!/usr/bin/env bash
#
# Install the desktop icon themes into ~/.local/share/icons: candy-icons (a
# git clone, updated with --ff-only) and the Sweet-* folder themes (from the
# Sweet-folders archive). Run by chezmoi
# (.chezmoiscripts/run_onchange_after_30-kde-icons.sh.tmpl) on desktops.
#
# Something already in the way never fails the run:
#   - a candy-icons that isn't a clone of the upstream repo (installed by
#     hand or through KDE's "Get New Icons") is moved into the backup set and
#     replaced; if the clone then fails it is moved back;
#   - a Sweet-* folder that differs from the archive is backed up, then
#     replaced; identical ones are left alone.
# Backups and the backup log are described in scripts/lib/backup.sh. Network
# failures are warnings. The script always exits 0.

set -uo pipefail

CANDY_URL=https://github.com/EliverLara/candy-icons.git
SWEET_URL=https://github.com/EliverLara/Sweet-folders/archive/refs/heads/master.tar.gz
ICONS_DIR=${ICONS_DIR:-$HOME/.local/share/icons}

# shellcheck source=lib/backup.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/backup.sh"

warn() { echo "icons: warning: $*" >&2; }

install_candy() {
    local dir="$ICONS_DIR/candy-icons" origin
    if [[ -d $dir/.git ]]; then
        origin="$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)"
        if [[ $origin == "$CANDY_URL" ]]; then
            git -C "$dir" pull --ff-only >/dev/null 2>&1 || warn "could not update candy-icons (git pull failed)"
            return 0
        fi
    fi
    local moved=""
    if [[ -e $dir || -L $dir ]]; then
        if ! backup_path --move "$dir"; then
            warn "candy-icons exists and could not be backed up; leaving it"
            return 0
        fi
        moved="$BACKUP_SET/${dir#"$HOME"/}"
    fi
    mkdir -p "$ICONS_DIR"
    if ! git clone --depth 1 "$CANDY_URL" "$dir" >/dev/null 2>&1; then
        warn "could not clone candy-icons"
        rm -rf "$dir"
        if [[ -n $moved ]]; then
            mv "$moved" "$dir" && echo "icons: restored the previous candy-icons" >&2
        fi
    fi
}

install_sweet() {
    local tmp theme name dest
    tmp="$(mktemp -d)" || { warn "no temp dir for Sweet folders"; return 0; }
    if ! curl -fsSL -o "$tmp/sweet.tar.gz" "$SWEET_URL" || ! tar -xzf "$tmp/sweet.tar.gz" -C "$tmp"; then
        warn "could not download the Sweet folders; keeping what is installed"
        rm -rf "$tmp"
        return 0
    fi
    mkdir -p "$ICONS_DIR"
    for theme in "$tmp"/*/Sweet-*; do
        [[ -d $theme ]] || continue
        name=${theme##*/}
        dest="$ICONS_DIR/$name"
        if [[ -e $dest || -L $dest ]]; then
            diff -rq "$theme" "$dest" >/dev/null 2>&1 && continue
            if ! backup_path "$dest"; then
                warn "$name differs and could not be backed up; leaving it"
                continue
            fi
            rm -rf "$dest"
        fi
        cp -a "$theme" "$dest" || warn "could not install $name"
    done
    rm -rf "$tmp"
}

install_candy
install_sweet
[[ -n $BACKUP_SET ]] && { backup_prune || warn "could not prune old backups"; }
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi
exit 0
