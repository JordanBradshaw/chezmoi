#!/usr/bin/env bash
#
# Tests for apps/apps.tsv and apps/lib.sh. Every test sources the libs in a subshell.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_LIB="$REPO_DIR/apps/lib.sh"
APPS_TSV="$REPO_DIR/apps/apps.tsv"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

setup() {
    SANDBOX="$(mktemp -d)"
    export SANDBOX
    unset CHEZMOI_SRC APPS_FILE
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

# al CODE: run CODE in a bash with apps/lib.sh sourced under set -u.
al() {
    OUTPUT="$("$BASH_BIN" -c "set -u; source '$APPS_LIB'; $1" 2>&1)"
    STATUS=$?
}

# real CODE: like al, with the real manifest loaded.
real() { al "apps_load '$APPS_TSV' || exit 9; $1"; }

HEADER='# name tier portable apt pacman dnf brew release file assets build'
RG_ROW='rg core zssh,dev ripgrep ripgrep ripgrep ripgrep BurntSushi/ripgrep rg musl|gnu crate:ripgrep:rg'

test_real_manifest_loads() {
    al "apps_load '$APPS_TSV'"
    assert_eq "$STATUS" 0
}

test_header_must_name_every_column() {
    printf '%s\n' '# name tier portable apt pacman dnf brew release file assets' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" 'header'
}

test_short_row_names_line() {
    printf '%s\n\n%s\n' "$HEADER" 'rg core zssh a b c d e f g' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" "a.tsv:3: 10 fields, expected 11"
}

test_duplicate_name_fails() {
    printf '%s\n%s\n%s\n' "$HEADER" "$RG_ROW" "$RG_ROW" >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'"
    assert_eq "$STATUS" 1
    assert_match "$OUTPUT" 'duplicate rg'
}

test_columns_read_by_name() {
    printf '%s\n%s\n' '# build tier portable apt pacman dnf brew release file assets name' \
        'crate:ripgrep:rg core zssh a b c d e f g rg' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv' && app rg build"
    assert_eq "$OUTPUT" "crate:ripgrep:rg"
}

test_known_tiers() {
    real 'for n in "${APPS_NAMES[@]}"; do
        case $(app "$n" tier) in core|extra|desktop|-) ;; *) echo "$n: bad tier $(app "$n" tier)" ;; esac
    done'
    assert_eq "$OUTPUT" ""
}

test_portable_rows_have_a_source() {
    real 'for n in $(apps_names --portable zssh; apps_names --portable dev); do
        [[ $(app "$n" release) != - || $(app "$n" build) != - ]] || echo "$n: no release and no build"
    done'
    assert_eq "$OUTPUT" ""
}

test_known_portable_values() {
    real 'for n in "${APPS_NAMES[@]}"; do
        case $(app "$n" portable) in zssh|dev|zssh,dev|-) ;; *) echo "$n: bad portable $(app "$n" portable)" ;; esac
    done'
    assert_eq "$OUTPUT" ""
}

# The dev bundle is built on x86 from releases and static: builds, so a dev
# row needs one of them.
test_dev_rows_have_source() {
    local check='for n in $(apps_names --portable dev); do
        [[ $(app "$n" release) != - || $(app "$n" build) == static:* ]] || echo "$n: dev row has no release or static build"
    done'
    real "$check"
    assert_eq "$OUTPUT" ""
    printf '%s\n%s\n%s\n' "$HEADER" 'nor core dev a b c d - f g crate:nor' \
        'sta core dev a b c d - f g static:sta' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'; $check"
    assert_eq "$OUTPUT" "nor: dev row has no release or static build"
}

test_known_build_sources() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" build) =~ ^(crate:[a-z0-9_-]+(:[A-Za-z0-9_-]+)?(:.*)?|go:[^[:space:]]+|cross:[a-z0-9-]+|static:[a-z0-9-]+|pipx:[^[:space:]]+|-)$ ]] ||
            echo "$n: bad build $(app "$n" build)"
    done'
    assert_eq "$OUTPUT" ""
}

test_cross_rows_have_no_release() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" build) == cross:* && $(app "$n" release) != - ]] && echo "$n: cross row has release"
    done
    app tmux build'
    assert_eq "$OUTPUT" "cross:tmux"
}

# static:NAME rows are built from source by the portable build; a release
# would never be used.
test_static_rows_have_no_release() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" build) == static:* && $(app "$n" release) != - ]] && echo "$n: static row has release"
    done
    printf "%s|" "$(app ss build)" "$(app ss portable)" "$(app ss apt)" "$(app lsof build)" "$(app lsof portable)" "$(app lsof tier)"'
    assert_eq "$OUTPUT" "static:ss|zssh,dev|iproute2|static:lsof|zssh,dev|extra|"
}

test_lock_names_in_manifest() {
    local n=0
    for lock in "$REPO_DIR"/apps/locks/*.lock; do
        n=$((n + 1))
        real "while IFS=\$'\\t' read -r name src ver; do
            [[ \$name == '#'* || -z \$name ]] && continue
            [[ \$(app \"\$name\" portable) == *zssh* ]] || { echo \"\$name: not a zssh row\"; continue; }
            want=\$(app \"\$name\" build); [[ \$want == - ]] && want=release
            [[ \$src == \"\$want\" ]] || echo \"\$name: lock source \$src, manifest \$want\"
        done <'$lock'"
        [[ -z $OUTPUT ]] || fail "$(basename "$lock"): $OUTPUT"
    done
    ((n >= 1)) || fail "expected locks in apps/locks"
}

test_merged_rows() {
    real 'printf "%s|" "$(app rg apt)" "$(app tspin tier)" "$(app nu release)" "$(app atuin build)" "$(app lazydocker tier)" "$(app firacode portable)"'
    assert_eq "$OUTPUT" "ripgrep|extra|nushell/nushell|-|desktop|-|"
}

# eBPF tools for zssh hosts only; bpftrace's raw release assets name only
# the CPU, so each alternative picks one.
test_zssh_bpf_tools() {
    real 'for n in pwru bpftrace; do printf "%s|" "$(app $n tier)" "$(app $n portable)" "$(app $n release)" "$(app $n assets)"; done'
    assert_eq "$OUTPUT" "-|zssh|cilium/pwru|tar.gz|-|zssh|bpftrace/bpftrace|x86_64,^bundle|aarch64,^bundle|"
}

# Monitoring tools for zssh hosts only: btop and sysdig from releases,
# nethogs, iftop and below built static.
test_zssh_monitoring_tools() {
    real 'for n in btop sysdig csysdig nethogs iftop below; do printf "%s|" "$(app $n tier)$(app $n portable)" "$(app $n release)" "$(app $n build)"; done'
    assert_eq "$OUTPUT" "-zssh|aristocratos/btop|-|-zssh|draios/sysdig|-|-zssh|draios/sysdig|-|-zssh|-|static:nethogs|-zssh|-|static:iftop|-zssh|-|static:below|"
}

# pipx installs on hosts only; build-tools.sh has no pipx recipe.
test_pipx_rows_not_portable() {
    real 'for n in $(apps_names --portable zssh; apps_names --portable dev); do
        [[ $(app "$n" build) == pipx:* ]] && echo "$n: portable pipx row"
    done'
    assert_eq "$OUTPUT" ""
}

# install-apps can install every row it selects: a package for some manager,
# a release, a crate (--build cargo) or a pipx spec.
test_tiered_rows_installable() {
    real 'for n in "${APPS_NAMES[@]}"; do
        [[ $(app "$n" tier) == - ]] && continue
        [[ $(app "$n" apt)$(app "$n" pacman)$(app "$n" dnf)$(app "$n" brew) != ---- ]] && continue
        [[ $(app "$n" release) != - || $(app "$n" build) == crate:* || $(app "$n" build) == pipx:* ]] ||
            echo "$n: nothing installs it"
    done'
    assert_eq "$OUTPUT" ""
}

# pipx itself is a row, installed by the package batch before the pipx rows.
test_pipx_rows_share_pipx_tier() {
    real 'printf "pipx=%s %s\n" "$(app pipx tier)" "$(app pipx apt)"
        for n in "${APPS_NAMES[@]}"; do
            [[ $(app "$n" build) == pipx:* && $(app "$n" tier) != "$(app pipx tier)" ]] && echo "$n: tier differs from pipx"
        done'
    assert_eq "$OUTPUT" "pipx=desktop pipx"
}

# Former ~/.eget.toml entries and floating tools, now desktop rows.
test_desktop_rows() {
    real 'for n in lsoff bandwhich lazydocker lnav systemd-manager-tui tori lazygit lazyrsync nerdlog depot \
            envx sake prettyping oryx act gitleaks cloudflared lsnet tldr xxh jtui tuistore; do
            [[ $(app "$n" tier) == desktop ]] || echo "$n: tier $(app "$n" tier)"
        done
        printf "%s|" "$(app lazygit release)" "$(app tori file)" "$(app cloudflared assets)" \
            "$(app lsnet build)" "$(app xxh build)" "$(app jtui build)" "$(app prettyping apt)" "$(app lsoff portable)"'
    assert_eq "$OUTPUT" "jesseduffield/lazygit|tori*|^fips|crate:lsnet|pipx:xxh-xxh|pipx:git+https://github.com/runpantheon/ltui#subdirectory=jtui|prettyping|zssh,dev|"
}

test_desktop_rows_not_on_servers() {
    real 'apps_names --tier extra | tr "\n" " "'
    [[ " $OUTPUT " != *" lazygit "* && " $OUTPUT " != *" lsoff "* ]] || fail "desktop tools in extra: $OUTPUT"
}

test_apps_names_filters() {
    real 'apps_names --tier core | tr "\n" " "; echo; apps_names --portable dev | tr "\n" " "; echo; apps_names --portable zssh | tr "\n" " "'
    local core=" ${OUTPUT%%$'\n'*}" rest=${OUTPUT#*$'\n'}
    local dev=" ${rest%%$'\n'*}" zssh=" ${rest#*$'\n'}"
    assert_match "$core" ' curl '
    [[ $core != *lazydocker* ]] || fail "core has lazydocker"
    assert_match "$dev" 'lazydocker'
    [[ $dev != *' tmux '* ]] || fail "dev has tmux"
    [[ $dev != *' curl '* ]] || fail "dev has curl"
    assert_match "$zssh" ' tmux '
}

test_portable_filter_matches_list_members() {
    printf '%s\n%s\n%s\n%s\n' "$HEADER" \
        'both core zssh,dev a b c d r f g -' 'devonly core dev a b c d r f g -' 'none core - a b c d r f g -' >"$SANDBOX/a.tsv"
    al "apps_load '$SANDBOX/a.tsv'; apps_names --portable zssh | tr '\n' ' '; echo; apps_names --portable dev | tr '\n' ' '"
    assert_eq "$OUTPUT" "both 
both devonly "
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
