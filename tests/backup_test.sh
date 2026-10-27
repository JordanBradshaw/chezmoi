#!/usr/bin/env bash
#
# Tests for scripts/lib/backup.sh and scripts/backup-before-apply.sh (the
# chezmoi pre-apply hook). The hook tests run real chezmoi applies against a
# sandbox source, home and config.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_DIR/scripts/lib/backup.sh"
HOOK="$REPO_DIR/scripts/backup-before-apply.sh"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    export HOME="$SANDBOX/home" CHEZMOI_BACKUP_DIR="$SANDBOX/backups"
    mkdir -p "$HOME" "$SANDBOX/src"
    OUTPUT=""
    STATUS=0
}

teardown() {
    rm -rf "$SANDBOX"
}

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_match() { [[ $1 =~ $2 ]] || fail "expected match '$2', got '$1'"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# lib CODE: run CODE in bash with scripts/lib/backup.sh sourced.
lib() {
    OUTPUT="$("$BASH_BIN" -c "set -u; source '$LIB'; $1" 2>&1)"
    STATUS=$?
}

# sets: the backup set directories, one per line.
sets() {
    find "$CHEZMOI_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

# cz ARGS...: chezmoi on the sandbox source with the backup hook configured.
cz() {
    printf '[hooks.apply.pre]\n    command = "%s"\n' "$HOOK" >"$SANDBOX/c.toml"
    chezmoi --source="$SANDBOX/src" --destination="$HOME" --config="$SANDBOX/c.toml" \
        --persistent-state="$SANDBOX/state.db" "$@"
}

# ---------------------------------------------------------------------------
# scripts/lib/backup.sh
# ---------------------------------------------------------------------------

test_backup_file_keeps_relative_path() {
    mkdir -p "$HOME/.config/x"
    echo mine >"$HOME/.config/x/conf"
    lib 'backup_path "$HOME/.config/x/conf"; echo "set=$BACKUP_SET"'
    assert_eq "$STATUS" 0
    local set
    set="$(sets)"
    assert_eq "$(cat "$set/.config/x/conf" 2>/dev/null)" mine
    assert_eq "$(cat "$HOME/.config/x/conf")" mine
}

test_backup_is_logged() {
    echo mine >"$HOME/.zshenv"
    lib 'backup_path "$HOME/.zshenv"'
    assert_match "$OUTPUT" "backed up .zshenv to $CHEZMOI_BACKUP_DIR/"
    assert_match "$(cat "$CHEZMOI_BACKUP_DIR/backup.log")" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} file .zshenv -> $CHEZMOI_BACKUP_DIR/[^ ]+$"
}

test_backup_folder_is_logged_as_folder() {
    mkdir -p "$HOME/.local/share/icons/candy-icons/apps"
    echo svg >"$HOME/.local/share/icons/candy-icons/apps/a.svg"
    lib 'backup_path "$HOME/.local/share/icons/candy-icons"'
    assert_eq "$(cat "$(sets)/.local/share/icons/candy-icons/apps/a.svg" 2>/dev/null)" svg
    assert_match "$(cat "$CHEZMOI_BACKUP_DIR/backup.log")" " folder .local/share/icons/candy-icons -> "
}

test_backup_move_removes_original() {
    mkdir -p "$HOME/dir"
    echo x >"$HOME/dir/f"
    lib 'backup_path --move "$HOME/dir"'
    [[ -e $HOME/dir ]] && fail "original still there"
    assert_eq "$(cat "$(sets)/dir/f" 2>/dev/null)" x
}

test_backup_keeps_symlink() {
    ln -s /nowhere "$HOME/.link"
    lib 'backup_path "$HOME/.link"'
    assert_eq "$(readlink "$(sets)/.link" 2>/dev/null)" /nowhere
}

test_one_set_per_run() {
    echo a >"$HOME/a"
    echo b >"$HOME/b"
    lib 'backup_path "$HOME/a"; backup_path "$HOME/b"'
    assert_eq "$(sets | wc -l)" 1
}

test_missing_path_is_not_an_error() {
    lib 'backup_path "$HOME/nope"; echo rc=$?'
    assert_eq "$OUTPUT" "rc=0"
    assert_eq "$(sets | wc -l)" 0
}

test_prune_keeps_ten_newest() {
    local i
    mkdir -p "$CHEZMOI_BACKUP_DIR"
    for i in $(seq -w 1 12); do mkdir "$CHEZMOI_BACKUP_DIR/2026-01-${i}T000000"; done
    lib 'backup_prune'
    assert_eq "$(sets | wc -l)" 10
    [[ -d $CHEZMOI_BACKUP_DIR/2026-01-01T000000 || -d $CHEZMOI_BACKUP_DIR/2026-01-02T000000 ]] &&
        fail "oldest sets kept"
    [[ -d $CHEZMOI_BACKUP_DIR/2026-01-12T000000 ]] || fail "newest set removed"
    return 0
}

test_paths_outside_home_are_refused() {
    echo x >"$SANDBOX/outside"
    lib 'backup_path "'"$SANDBOX"'/outside"; echo rc=$?'
    assert_match "$OUTPUT" "not under"
    assert_eq "$(sets | wc -l)" 0
}

# ---------------------------------------------------------------------------
# scripts/backup-before-apply.sh (chezmoi hooks.apply.pre)
# ---------------------------------------------------------------------------

test_apply_backs_up_changed_file() {
    echo new >"$SANDBOX/src/dot_a"
    echo old >"$HOME/.a"
    OUTPUT="$(cz apply --force 2>&1)"
    assert_eq "$(cat "$HOME/.a")" new
    assert_eq "$(cat "$(sets)/.a" 2>/dev/null)" old
    assert_match "$OUTPUT" "backed up .a"
}

test_apply_skips_unchanged_and_new_files() {
    echo same >"$SANDBOX/src/dot_same"
    echo same >"$HOME/.same"
    echo fresh >"$SANDBOX/src/dot_fresh"
    cz apply --force >/dev/null 2>&1
    assert_eq "$(sets | wc -l)" 0
    assert_eq "$(cat "$HOME/.fresh")" fresh
}

test_apply_backs_up_modify_script_target() {
    printf '#!/bin/sh\ncat\necho appended\n' >"$SANDBOX/src/modify_dot_rc"
    echo mine >"$HOME/.rc"
    cz apply --force >/dev/null 2>&1
    assert_eq "$(cat "$(sets)/.rc" 2>/dev/null)" mine
    assert_eq "$(tail -1 "$HOME/.rc")" appended
}

test_apply_backs_up_removed_file() {
    echo gone >"$SANDBOX/src/.chezmoiremove"
    echo bye >"$HOME/gone"
    cz apply --force >/dev/null 2>&1
    [[ -e $HOME/gone ]] && fail "not removed"
    assert_eq "$(cat "$(sets)/gone" 2>/dev/null)" bye
}

test_hook_failure_does_not_block_apply() {
    echo new >"$SANDBOX/src/dot_a"
    echo old >"$HOME/.a"
    # Backups can't be written: the backup dir is a file.
    : >"$CHEZMOI_BACKUP_DIR"
    OUTPUT="$(cz apply --force 2>&1)"
    STATUS=$?
    assert_eq "$STATUS" 0
    assert_eq "$(cat "$HOME/.a")" new
    assert_match "$OUTPUT" "warning"
}

test_hook_outside_chezmoi_does_nothing() {
    OUTPUT="$(env -u CHEZMOI bash "$HOOK" 2>&1)"
    STATUS=$?
    assert_eq "$STATUS" 0
    assert_eq "$(sets | wc -l)" 0
}

test_config_template_has_hook() {
    grep -qF '[hooks.apply.pre]' "$REPO_DIR/home/.chezmoi.toml.tmpl" || fail "no hooks.apply.pre"
    grep -qF 'scripts/backup-before-apply.sh' "$REPO_DIR/home/.chezmoi.toml.tmpl" || fail "hook not the backup script"
}

test_install_sh_applies_after_init() {
    # init --apply would apply before the generated config (with the hook)
    # exists, so a new machine's dotfiles wouldn't be backed up.
    grep -q 'init --apply' "$REPO_DIR/install.sh" && fail "install.sh still runs init --apply"
    grep -qE '"\$chezmoi" apply' "$REPO_DIR/install.sh" || fail "install.sh doesn't apply after init"
    return 0
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
