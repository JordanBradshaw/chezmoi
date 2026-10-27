#!/usr/bin/env bash
#
# Tests for scripts/install-icons.sh (candy-icons and Sweet folders on
# desktops) and its chezmoi run_onchange script. git, curl and kbuildsycoca6
# are stubs that log their arguments; the Sweet archive is a local fixture.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS="$REPO_DIR/scripts/install-icons.sh"
CANDY_URL=https://github.com/EliverLara/candy-icons.git
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    STUBS="$SANDBOX/stubs"
    export HOME="$SANDBOX/home" STUB_LOG="$SANDBOX/calls.log"
    export CHEZMOI_BACKUP_DIR="$SANDBOX/backups" SWEET_FIXTURE="$SANDBOX/sweet.tar.gz"
    unset STUB_GIT_FAIL STUB_CURL_FAIL XDG_STATE_HOME
    ICONS_DIR="$HOME/.local/share/icons"
    mkdir -p "$STUBS" "$HOME"
    : >"$STUB_LOG"
    make_stubs
    make_sweet_fixture v1
    OUTPUT=""
    STATUS=0
}

teardown() {
    rm -rf "$SANDBOX"
}

# make_stubs: git (clone makes DIR/.git with the origin URL), curl (copies
# the Sweet fixture to -o), kbuildsycoca6. STUB_GIT_FAIL=clone|pull and
# STUB_CURL_FAIL=1 make them fail.
make_stubs() {
    cat >"$STUBS/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB_LOG"
dir=.
if [[ $1 == -C ]]; then dir=$2; shift 2; fi
case $1 in
    clone)
        [[ ${STUB_GIT_FAIL:-} == clone ]] && exit 128
        url=${@: -2:1} dest=${@: -1}
        mkdir -p "$dest/.git" && echo "$url" >"$dest/.git/origin" && echo cloned >"$dest/index.theme"
        ;;
    config) [[ -f $dir/.git/origin ]] && cat "$dir/.git/origin" || exit 1 ;;
    pull) [[ ${STUB_GIT_FAIL:-} == pull ]] && exit 1; echo pulled >"$dir/pulled" ;;
esac
EOF
    cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$STUB_LOG"
[[ -n ${STUB_CURL_FAIL:-} ]] && exit 22
out=""
while (( $# )); do [[ $1 == -o ]] && out=$2; shift; done
cp "$SWEET_FIXTURE" "$out"
EOF
    printf '#!/usr/bin/env bash\necho "kbuildsycoca6 $*" >>"$STUB_LOG"\n' >"$STUBS/kbuildsycoca6"
    chmod +x "$STUBS"/*
}

# make_sweet_fixture CONTENT: the Sweet-folders archive layout (one top dir,
# Sweet-* themes inside, plus files the install must ignore).
make_sweet_fixture() {
    local src="$SANDBOX/fixture/Sweet-folders-master"
    rm -rf "$SANDBOX/fixture"
    mkdir -p "$src/Sweet-Mars/places" "$src/Sweet-Rainbow" "$src/screenshots"
    echo "$1" >"$src/Sweet-Mars/places/folder.svg"
    echo rainbow >"$src/Sweet-Rainbow/index.theme"
    echo readme >"$src/README.md"
    tar -czf "$SWEET_FIXTURE" -C "$SANDBOX/fixture" Sweet-folders-master
}

run_icons() {
    OUTPUT="$(PATH="$STUBS:$PATH" bash "$ICONS" 2>&1)"
    STATUS=$?
}

sets() {
    find "$CHEZMOI_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_match() { [[ $1 =~ $2 ]] || fail "expected match '$2', got '$1'"; }
assert_call_matches() { grep -qE -- "$1" "$STUB_LOG" || fail "no call matches: $1"; }
refute_call_matches() { ! grep -qE -- "$1" "$STUB_LOG" || fail "unexpected call: $(grep -E -- "$1" "$STUB_LOG" | head -1)"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# ---------------------------------------------------------------------------

test_fresh_install_clones_and_extracts() {
    run_icons
    assert_eq "$STATUS" 0
    assert_call_matches "^git clone --depth 1 $CANDY_URL $ICONS_DIR/candy-icons$"
    assert_eq "$(cat "$ICONS_DIR/Sweet-Mars/places/folder.svg" 2>/dev/null)" v1
    [[ -e $ICONS_DIR/Sweet-Rainbow/index.theme ]] || fail "Sweet-Rainbow missing"
    [[ -e $ICONS_DIR/screenshots || -e $ICONS_DIR/README.md ]] && fail "non-theme files extracted"
    assert_call_matches "^kbuildsycoca6 --noincremental$"
    assert_eq "$(sets | wc -l)" 0
}

test_existing_clone_is_pulled() {
    mkdir -p "$ICONS_DIR/candy-icons/.git"
    echo "$CANDY_URL" >"$ICONS_DIR/candy-icons/.git/origin"
    run_icons
    assert_eq "$STATUS" 0
    assert_call_matches "^git -C $ICONS_DIR/candy-icons pull --ff-only$"
    refute_call_matches "^git clone"
    assert_eq "$(sets | wc -l)" 0
}

test_failed_pull_warns() {
    mkdir -p "$ICONS_DIR/candy-icons/.git"
    echo "$CANDY_URL" >"$ICONS_DIR/candy-icons/.git/origin"
    export STUB_GIT_FAIL=pull
    run_icons
    assert_eq "$STATUS" 0
    assert_match "$OUTPUT" "warning: .*candy-icons"
}

# The failure that started this: candy-icons installed another way.
test_existing_folder_is_backed_up_and_replaced() {
    mkdir -p "$ICONS_DIR/candy-icons/apps"
    echo mine >"$ICONS_DIR/candy-icons/apps/a.svg"
    run_icons
    assert_eq "$STATUS" 0
    assert_eq "$(cat "$ICONS_DIR/candy-icons/index.theme" 2>/dev/null)" cloned
    assert_eq "$(cat "$(sets)/.local/share/icons/candy-icons/apps/a.svg" 2>/dev/null)" mine
    assert_match "$(cat "$CHEZMOI_BACKUP_DIR/backup.log")" " folder .local/share/icons/candy-icons -> "
    assert_match "$OUTPUT" "backed up .local/share/icons/candy-icons"
}

test_clone_of_another_repo_is_backed_up() {
    mkdir -p "$ICONS_DIR/candy-icons/.git"
    echo https://example.com/fork.git >"$ICONS_DIR/candy-icons/.git/origin"
    run_icons
    assert_call_matches "^git clone --depth 1 $CANDY_URL "
    assert_eq "$(cat "$(sets)/.local/share/icons/candy-icons/.git/origin" 2>/dev/null)" https://example.com/fork.git
}

test_failed_clone_restores_existing_folder() {
    mkdir -p "$ICONS_DIR/candy-icons"
    echo mine >"$ICONS_DIR/candy-icons/keep"
    export STUB_GIT_FAIL=clone
    run_icons
    assert_eq "$STATUS" 0
    assert_eq "$(cat "$ICONS_DIR/candy-icons/keep" 2>/dev/null)" mine
    assert_match "$OUTPUT" "warning: .*candy-icons"
}

test_changed_sweet_folder_is_backed_up() {
    mkdir -p "$ICONS_DIR/Sweet-Mars/places"
    echo old >"$ICONS_DIR/Sweet-Mars/places/folder.svg"
    echo extra >"$ICONS_DIR/Sweet-Mars/mine.svg"
    run_icons
    assert_eq "$STATUS" 0
    assert_eq "$(cat "$ICONS_DIR/Sweet-Mars/places/folder.svg")" v1
    assert_eq "$(cat "$(sets)/.local/share/icons/Sweet-Mars/places/folder.svg" 2>/dev/null)" old
    assert_match "$(cat "$CHEZMOI_BACKUP_DIR/backup.log")" " folder .local/share/icons/Sweet-Mars -> "
}

test_identical_sweet_folder_not_backed_up() {
    run_icons
    run_icons
    assert_eq "$STATUS" 0
    assert_eq "$(sets | wc -l)" 0
}

test_download_failure_keeps_existing_and_warns() {
    mkdir -p "$ICONS_DIR/Sweet-Mars"
    echo old >"$ICONS_DIR/Sweet-Mars/keep"
    export STUB_CURL_FAIL=1
    run_icons
    assert_eq "$STATUS" 0
    assert_eq "$(cat "$ICONS_DIR/Sweet-Mars/keep")" old
    assert_match "$OUTPUT" "warning: .*Sweet"
}

test_other_icon_themes_untouched() {
    mkdir -p "$ICONS_DIR/Papirus"
    echo p >"$ICONS_DIR/Papirus/index.theme"
    run_icons
    assert_eq "$(cat "$ICONS_DIR/Papirus/index.theme")" p
}

# ---------------------------------------------------------------------------
# chezmoi wiring
# ---------------------------------------------------------------------------

render() {
    printf '[data]\n    machine = "%s"\n    hasSecrets = false\n' "$1" >"$SANDBOX/c.toml"
    chezmoi --source="$REPO_DIR" --config="$SANDBOX/c.toml" --persistent-state="$SANDBOX/s.db" \
        --destination="$HOME" execute-template <"$REPO_DIR/home/$2" 2>/dev/null
}

test_externals_no_longer_install_icons() {
    local out
    out="$(render desktop .chezmoiexternal.toml.tmpl)"
    [[ $out == *candy-icons* || $out == *Sweet-folders* || $out == *'".local/share/icons"'* ]] &&
        fail "icons still chezmoi externals"
    return 0
}

test_desktop_script_runs_install_icons() {
    local out
    out="$(render desktop .chezmoiscripts/run_onchange_after_30-kde-icons.sh.tmpl)"
    assert_match "$out" "scripts/install-icons.sh"
    assert_match "$out" "install-icons.sh hash: [0-9a-f]{64}"
    assert_match "$out" "week: [0-9]+"
}

test_server_script_is_empty() {
    local out
    out="$(render server .chezmoiscripts/run_onchange_after_30-kde-icons.sh.tmpl)"
    assert_eq "${out//[[:space:]]/}" ""
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
