#!/usr/bin/env bash
#
# Tests for the FiraCode Nerd Font setup: the chezmoi external, the font cache
# script and the Konsole/Yakuake profile.
#
# Renders the real chezmoi source for a desktop and a server machine with
# throwaway configs; nothing in ~ is touched. The font archive download is
# cached by chezmoi.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FONT_DIR=.local/share/fonts/FiraCodeNerdFont

setup() {
    SANDBOX="$(mktemp -d)"
    OUTPUT=""
}

teardown() {
    rm -rf "$SANDBOX"
}

# cz MACHINE ARGS...: chezmoi on the repo with machine type MACHINE.
cz() {
    local machine=$1
    shift
    printf '[data]\n    machine = "%s"\n    hasSecrets = false\n' "$machine" >"$SANDBOX/$machine.toml"
    chezmoi --source="$REPO_DIR" --config="$SANDBOX/$machine.toml" \
        --persistent-state="$SANDBOX/$machine.db" --destination="$SANDBOX/home" "$@" \
        2> >(grep -v 'config file template has changed' >&2)
}

CURRENT=""

fail() {
    echo "  FAIL [$CURRENT]: $*"
    FAIL=$((FAIL + 1))
    return 1
}

assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'"; }

run_test() {
    CURRENT="$1"
    setup
    local before=$FAIL
    "$1"
    [[ $FAIL -eq $before ]] && PASS=$((PASS + 1)) && echo "  ok   $1"
    teardown
}

# ---------------------------------------------------------------------------

test_desktop_gets_firacode_nerd_font() {
    cz desktop archive --format=tar --output="$SANDBOX/fonts.tar" "$SANDBOX/home/$FONT_DIR"
    OUTPUT="$(tar -tf "$SANDBOX/fonts.tar" 2>/dev/null)"
    grep -qx "$FONT_DIR/FiraCodeNerdFont-Regular.ttf" <<<"$OUTPUT" || fail "Regular.ttf missing"
    grep -qx "$FONT_DIR/FiraCodeNerdFontMono-Regular.ttf" <<<"$OUTPUT" || fail "Mono Regular.ttf missing"
    grep -vE '/$|\.ttf$' <<<"$OUTPUT" | grep -q . && fail "non-font files: $(grep -vE '/$|\.ttf$' <<<"$OUTPUT" | head -3)"
    return 0
}

test_server_gets_no_fonts() {
    OUTPUT="$(cz server managed --include=externals 2>/dev/null)"
    grep -q 'fonts' <<<"$OUTPUT" && fail "server manages fonts: $OUTPUT"
    return 0
}

test_font_cache_refreshed_on_desktop_only() {
    local script="$REPO_DIR/home/.chezmoiscripts/run_onchange_after_30-fonts.sh.tmpl"
    [[ -f $script ]] || { fail "no font cache script"; return; }
    OUTPUT="$(cz desktop execute-template <"$script")"
    grep -q "fc-cache .*$FONT_DIR" <<<"$OUTPUT" || fail "desktop script runs no fc-cache: $OUTPUT"
    # Re-runs when the font external changes.
    grep -q 'chezmoiexternal.toml.tmpl hash: [0-9a-f]\{64\}' <<<"$OUTPUT" || fail "not keyed on externals"
    assert_eq "$(cz server execute-template <"$script" | tr -d '[:space:]')" ""
}

test_yupps_profile_uses_firacode_nerd_font() {
    local font
    font="$(sed -n 's/^Font=//p' "$REPO_DIR/home/dot_local/share/konsole/yupps.profile")"
    assert_eq "${font%%,*}" "FiraCode Nerd Font"
    # Same size as before.
    assert_eq "$(cut -d, -f2 <<<"$font")" 10
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
