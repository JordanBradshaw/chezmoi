#!/usr/bin/env bash
#
# chezmoi pre-apply hook ([hooks.apply.pre] in .chezmoi.toml.tmpl): back up
# every existing file chezmoi apply is about to modify or remove, into
# ~/.local/state/chezmoi-backups/<time>/ (see scripts/lib/backup.sh).
#
# It asks chezmoi which targets differ (`chezmoi status`, files and symlinks
# only; externals and scripts are left out) using the same source,
# destination and config as the apply, and a copy of its persistent state so
# the apply's lock is never contended. A backup problem is a warning: the
# apply always goes ahead.

set -uo pipefail

[[ -n ${CHEZMOI:-} ]] || exit 0

# shellcheck source=lib/backup.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/backup.sh"

warn() { echo "backup: warning: $*" >&2; }

# state_file: the apply's --persistent-state, else the default next to the config.
state_file() {
    local -a args
    read -r -a args <<<"${CHEZMOI_ARGS:-}"
    local i
    for i in "${!args[@]}"; do
        case ${args[i]} in
            --persistent-state=*) echo "${args[i]#*=}"; return ;;
            --persistent-state) echo "${args[i + 1]:-}"; return ;;
        esac
    done
    echo "$(dirname "${CHEZMOI_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}")/chezmoistate.boltdb"
}

main() {
    local chezmoi=${CHEZMOI_EXECUTABLE:-chezmoi} dest=${CHEZMOI_DEST_DIR:-$HOME}
    local tmp state status line path count=0
    tmp="$(mktemp -d)" || { warn "no temp dir"; return 0; }
    trap 'rm -rf "$tmp"' RETURN
    state="$(state_file)"
    [[ -f $state ]] && cp "$state" "$tmp/state.db"

    local -a cmd=("$chezmoi" --destination "$dest" --persistent-state "$tmp/state.db")
    [[ -n ${CHEZMOI_SOURCE_DIR:-} ]] && cmd+=(--source "$CHEZMOI_SOURCE_DIR")
    [[ -n ${CHEZMOI_CONFIG_FILE:-} ]] && cmd+=(--config "$CHEZMOI_CONFIG_FILE")
    if ! status="$("${cmd[@]}" status --exclude=scripts,externals,dirs 2>"$tmp/err")"; then
        warn "chezmoi status failed, nothing backed up: $(grep -v 'config file template' "$tmp/err" | head -1)"
        return 0
    fi

    while IFS= read -r line; do
        # Second column: what apply will do to the target (M modify, D delete).
        [[ ${line:1:1} == [MD] ]] || continue
        path="$dest/${line:3}"
        [[ -f $path || -L $path ]] || continue
        if backup_path "$path"; then
            count=$((count + 1))
        else
            warn "could not back up ${line:3}"
        fi
    done <<<"$status"

    if ((count)); then
        echo "backup: $count file(s) backed up to $BACKUP_SET" >&2
        backup_prune || warn "could not prune old backups"
    fi
    return 0
}

main
exit 0
