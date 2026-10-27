# Backups of files and folders that chezmoi (or a chezmoi script) is about to
# overwrite. Sourced by scripts/backup-before-apply.sh and
# scripts/install-icons.sh.
#
# Each run gets one set, $CHEZMOI_BACKUP_DIR/<YYYY-MM-DDTHHMMSS>/, holding the
# backed-up paths relative to $HOME. Every backup is printed and appended to
# $CHEZMOI_BACKUP_DIR/backup.log as "<time> file|folder <path> -> <set>".
# The newest $CHEZMOI_BACKUP_KEEP sets (10) are kept.

CHEZMOI_BACKUP_DIR=${CHEZMOI_BACKUP_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/chezmoi-backups}
CHEZMOI_BACKUP_KEEP=${CHEZMOI_BACKUP_KEEP:-10}
BACKUP_SET=""

# backup_set: create this run's set directory once and set BACKUP_SET.
backup_set() {
    [[ -n $BACKUP_SET ]] && return 0
    local stamp set n=1
    stamp="$(date +%Y-%m-%dT%H%M%S)"
    set="$CHEZMOI_BACKUP_DIR/$stamp"
    while [[ -e $set ]]; do
        n=$((n + 1))
        set="$CHEZMOI_BACKUP_DIR/$stamp-$n"
    done
    mkdir -p "$set" || return 1
    BACKUP_SET=$set
}

# backup_path [--move] PATH: copy (or move) PATH, a file, symlink or folder
# under $HOME, into this run's set and log it. A missing PATH is not an error.
backup_path() {
    local move=""
    [[ ${1:-} == --move ]] && move=1 && shift
    local path=$1 rel kind
    [[ -e $path || -L $path ]] || return 0
    case $path in
        "$HOME"/*) rel=${path#"$HOME"/} ;;
        *)
            echo "backup: $path is not under $HOME, not backed up" >&2
            return 1
            ;;
    esac
    backup_set || { echo "backup: warning: cannot create a backup set in $CHEZMOI_BACKUP_DIR" >&2; return 1; }
    kind=file
    [[ -d $path && ! -L $path ]] && kind=folder
    mkdir -p "$BACKUP_SET/$(dirname "$rel")" || return 1
    if [[ -n $move ]]; then
        mv "$path" "$BACKUP_SET/$rel" || return 1
    else
        cp -a "$path" "$BACKUP_SET/$rel" || return 1
    fi
    printf '%s %s %s -> %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$kind" "$rel" "$BACKUP_SET" \
        >>"$CHEZMOI_BACKUP_DIR/backup.log"
    echo "backup: backed up $rel to $BACKUP_SET" >&2
}

# backup_prune: delete all but the newest $CHEZMOI_BACKUP_KEEP sets.
backup_prune() {
    local -a all=()
    local d
    [[ -d $CHEZMOI_BACKUP_DIR ]] || return 0
    for d in "$CHEZMOI_BACKUP_DIR"/[0-9][0-9][0-9][0-9]-*; do
        [[ -d $d ]] && all+=("$d")
    done
    local excess=$((${#all[@]} - CHEZMOI_BACKUP_KEEP))
    ((excess > 0)) || return 0
    # Set names sort by time; the glob already sorts them oldest first.
    rm -rf -- "${all[@]:0:excess}"
}
