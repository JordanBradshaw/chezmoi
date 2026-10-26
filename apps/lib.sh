# Shared by the dotfiles' install-apps.sh and the portable build: the app
# manifest (apps.tsv) reader, architectures, eget asset selection, ELF checks
# and the GitHub token. Bash and coreutils only; sets no shell options.

APPS_COLUMNS=(name tier bundle apt pacman dnf brew release file assets build)
APPS_FILE="${APPS_FILE:-$(dirname "${BASH_SOURCE[0]}")/apps.tsv}"
declare -ga APPS_NAMES=()
declare -gA APP=()

# apps_load [FILE]: read the manifest into APPS_NAMES (file order) and APP
# (key "NAME,COLUMN"). Columns are located by the header line: a "# " comment
# naming at least name and tier (the column documentation uses wider indents).
# Returns 1 with "FILE:LINE: message" on stderr when the file is malformed.
apps_load() {
    local file=${1:-$APPS_FILE} line n=0 hdr=0 f i c
    local -a cols=() fields=()
    local -A idx=()
    APPS_NAMES=()
    APP=()
    if [[ ! -r $file ]]; then
        echo "$file: cannot read" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        if [[ $line =~ ^\#\ [a-z] && $line =~ [[:space:]]name([[:space:]]|$) && $line =~ [[:space:]]tier([[:space:]]|$) ]]; then
            read -ra cols <<<"${line#\#}"
            hdr=1
            idx=()
            for i in "${!cols[@]}"; do idx[${cols[$i]}]=$i; done
            for c in "${APPS_COLUMNS[@]}"; do
                if [[ ! -v idx[$c] ]]; then
                    echo "$file:$n: header lacks column $c" >&2
                    return 1
                fi
            done
            continue
        fi
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        if ((!hdr)); then
            echo "$file:$n: row before header" >&2
            return 1
        fi
        read -ra fields <<<"$line"
        if ((${#fields[@]} != ${#cols[@]})); then
            echo "$file:$n: ${#fields[@]} fields, expected ${#cols[@]}" >&2
            return 1
        fi
        f=${fields[${idx[name]}]}
        if [[ -n ${APP[$f,name]+x} ]]; then
            echo "$file:$n: duplicate $f" >&2
            return 1
        fi
        APPS_NAMES+=("$f")
        for c in "${APPS_COLUMNS[@]}"; do
            APP[$f,$c]=${fields[${idx[$c]}]}
        done
    done <"$file"
    if ((!hdr)); then
        echo "$file: no header line (# name tier ...)" >&2
        return 1
    fi
}

# apps_names [--tier T | --bundle]: print app names in file order.
apps_names() {
    local n
    for n in "${APPS_NAMES[@]}"; do
        case ${1:-} in
            --tier) [[ ${APP[$n,tier]} == "${2:-}" ]] || continue ;;
            --bundle) [[ ${APP[$n,bundle]} == y ]] || continue ;;
        esac
        echo "$n"
    done
}

# app NAME COLUMN: print the value.
app() { echo "${APP[$1,$2]-}"; }

# Release files that are never the binary we want.
ASSET_EXCLUDES=(^.deb ^.rpm ^.apk ^.msi ^.sha ^.sig ^.asc ^.sbom ^.pem)

# normalize_arch UNAME_M: print the bundle arch name, or fail if unsupported.
normalize_arch() {
    case $1 in
        aarch64 | arm64) echo aarch64 ;;
        armv7l | armv7 | armhf | armv8l) echo armv7l ;;
        x86_64 | amd64) echo x86_64 ;;
        *)
            echo "unsupported arch: $1 (supported: aarch64, armv7l, x86_64)" >&2
            return 1
            ;;
    esac
}

# eget_system ARCH: eget --system value for a normalized arch.
eget_system() {
    case $1 in
        aarch64) echo linux/arm64 ;;
        armv7l) echo linux/arm ;;
        x86_64) echo linux/amd64 ;;
    esac
}

# asset_candidates ARCH SPEC: print one comma-separated filter list per line,
# in the order to try. An empty line means "no filters".
asset_candidates() {
    local arch=$1 spec=$2 alt
    if [[ $spec == - ]]; then
        echo
        return
    fi
    local IFS='|'
    for alt in $spec; do
        [[ $arch == armv7l ]] && echo "armv7,$alt"
        echo "$alt"
    done
}

# asset_args FILTERS: eget --asset arguments, one per line, for a
# comma-separated filter list plus excludes for packages and checksums.
asset_args() {
    local f fl=()
    IFS=, read -ra fl <<<"$1"
    for f in "${fl[@]}" "${ASSET_EXCLUDES[@]}"; do
        echo "--asset=$f"
    done
}

# elf_arch FILE: print the bundle arch an ELF binary was built for.
elf_arch() {
    local magic class machine
    magic="$(head -c4 "$1" 2>/dev/null | od -An -c | tr -d ' ')"
    [[ $magic == '177ELF' ]] || return 1
    class="$(od -An -tu1 -j4 -N1 "$1" | tr -d ' ')"
    machine="$(od -An -tu2 -j18 -N2 --endian=little "$1" | tr -d ' ')"
    case $class:$machine in
        2:62) echo x86_64 ;;
        2:183) echo aarch64 ;;
        1:40) echo armv7l ;;
        *) return 1 ;;
    esac
}

# load_github_token: export EGET_GITHUB_TOKEN from the environment, the
# secrets file or `gh auth token`, when there is one (higher API limits).
load_github_token() {
    [[ -n ${EGET_GITHUB_TOKEN:-} ]] && return 0
    local secrets="${XDG_CONFIG_HOME:-$HOME/.config}/secrets/env" line
    if [[ -r $secrets ]]; then
        while IFS= read -r line; do
            [[ $line == EGET_GITHUB_TOKEN=* ]] && EGET_GITHUB_TOKEN="${line#EGET_GITHUB_TOKEN=}"
        done <"$secrets"
    fi
    if [[ -z ${EGET_GITHUB_TOKEN:-} ]] && command -v gh >/dev/null 2>&1; then
        EGET_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
    fi
    [[ -n ${EGET_GITHUB_TOKEN:-} ]] && export EGET_GITHUB_TOKEN
    return 0
}

# fetch_release NAME REPO FILE SPEC ARCH OUT [TAG]: download NAME's release
# binary for ARCH to OUT with eget, trying each asset alternative of SPEC (see
# tools.tsv) until one is an ELF binary for ARCH. TAG pins the release.
# Fails, leaving nothing at OUT, when no alternative fits.
fetch_release() {
    local name=$1 repo=$2 file=$3 spec=$4 arch=$5 out=$6 tag=${7:-} filters cfg
    local system
    system="$(eget_system "$arch")"
    # An empty config keeps ~/.eget.toml (target dir, upgrade_only) out of it.
    cfg="$(mktemp)"
    load_github_token
    rm -f "$out"
    while IFS= read -r filters; do
        local args=(--system "$system" --file "$file" --to "$out" --quiet)
        [[ -n $tag ]] && args+=(--tag "$tag")
        mapfile -t -O "${#args[@]}" args < <(asset_args "$filters")
        if EGET_CONFIG="$cfg" eget "${args[@]}" "$repo" </dev/null >/dev/null 2>&1; then
            # Asset filters can leave a single asset for the wrong CPU, which
            # eget takes without checking --system.
            if [[ $(elf_arch "$out") == "$arch" ]]; then
                rm -f "$cfg"
                return 0
            fi
            rm -f "$out"
        fi
    done < <(asset_candidates "$arch" "$spec")
    rm -f "$cfg"
    return 1
}
