#!/usr/bin/env bash
#
# Install the command-line tools this config relies on.
#
# Usage: install-apps.sh [--machine desktop|server|container] [--no-nala]
#                        [--build prebuilt|cargo]
#
#   Run by chezmoi (.chezmoiscripts/run_onchange_after_10-install-apps.sh.tmpl)
#   with the machine type and appsBuild from chezmoi data. Without --machine
#   the type is guessed: container markers, then plasmashell (desktop), else
#   server.
#
#   Tiers installed per machine type:
#     core     every machine
#     extra    server and desktop (APPS_FORCE_EXTRA=1 adds it in containers)
#     desktop  desktop only
#
#   On apt systems nala is installed first and used for the batch (parallel
#   downloads). --no-nala keeps apt-get; containers use apt-get unless
#   APPS_FORCE_NALA=1. A nala failure falls back to apt-get.
#
#   eget authenticates with EGET_GITHUB_TOKEN from the environment, then
#   ~/.config/secrets/env, then `gh auth token`.
#
#   --build (or APPS_BUILD) picks where the Rust tools come from:
#     prebuilt  packages, then eget releases (the default)
#     cargo     the same first, so every tool works even if a build fails;
#               then each Rust tool is rebuilt with `cargo install --locked`
#               for this CPU (target-cpu=native, fat LTO, one codegen unit)
#               into ~/.cargo/bin, which comes before the system dirs in PATH.
#               rustup is installed if needed (--no-modify-path: zshenv.d
#               adds ~/.cargo/bin). Copies in ~/.local/bin, which would shadow
#               the build, move to ~/.local/share/install-apps/replaced/;
#               package-manager copies stay. A failed build keeps the
#               prebuilt copy and is reported without failing the run.
#               Re-runs only rebuild crates with newer versions.
#
#   DRY_RUN=1 prints the commands instead of running them.

set -euo pipefail

# Columns: tier name apt pacman dnf brew eget cargo
#   "-"   not packaged for that manager.
#   eget  "owner/repo:binary[:asset[,asset...]]", used when the package is
#         unavailable or fails. Each asset filter narrows the release files;
#         a leading ^ excludes matches.
#   cargo "crate[:binary]" for --build cargo; the binary defaults to the
#         crate name.
APPS=(
    "core    curl     curl           curl          curl            curl           -                                              -"
    "core    git      git            git           git             git            -                                              -"
    "core    unzip    unzip          unzip         unzip           unzip          -                                              -"
    "core    fzf      fzf            fzf           fzf             fzf            -                                              -"
    "core    bat      bat            bat           bat             bat            -                                              bat"
    "core    eza      eza            eza           eza             eza            eza-community/eza:eza:gnu.tar.gz               eza"
    "core    lsd      lsd            lsd           lsd             lsd            -                                              lsd"
    "core    ripgrep  ripgrep        ripgrep       ripgrep         ripgrep        -                                              ripgrep:rg"
    "core    fd       fd-find        fd            fd-find         fd             -                                              fd-find:fd"
    "core    delta    git-delta      git-delta     git-delta       git-delta      -                                              git-delta:delta"
    "core    zoxide   zoxide         zoxide        zoxide          zoxide         ajeetdsouza/zoxide:zoxide:musl                 zoxide"
    "core    atuin    atuin          atuin         atuin           atuin          atuinsh/atuin:atuin:gnu.tar.gz,^server         atuin"
    "core    direnv   direnv         direnv        direnv          direnv         direnv/direnv:direnv                           -"
    "extra   miller   miller         miller        miller          miller         -                                              -"
    "extra   nushell  -              nushell       -               nushell        nushell/nushell:nu:musl                        nu"
    "extra   gh       gh             github-cli    gh              gh             -                                              -"
    "extra   tailspin tailspin       tailspin      tailspin        tailspin       -                                              tailspin:tspin"
    "extra   procs    procs          procs         procs           procs          dalance/procs:procs:x86_64-linux               procs"
    "extra   duf      duf            duf           duf             duf            -                                              -"
    "extra   dust     du-dust        dust          du-dust         dust           bootandy/dust:dust:musl                        du-dust:dust"
    "extra   btm      btm            bottom        bottom          bottom         -                                              bottom:btm"
    "extra   htop     htop           htop          htop            htop           -                                              -"
    "extra   tmux     tmux           tmux          tmux            tmux           -                                              -"
    "extra   starship starship       starship      starship        starship       starship/starship:starship:musl.tar.gz,^sha256 starship"
    "extra   micro    micro          micro         micro           micro          -                                              -"
    "extra   neovim   neovim         neovim        neovim          neovim         -                                              -"
    "extra   most     most           most          most            most           -                                              -"
    "extra   xfr      -              -             -               -              lance0/xfr:xfr:musl                            xfr"
    "extra   snitch   -              -             -               -              karol-broda/snitch:snitch:tar.gz               -"
    "extra   usbtree  -              -             -               -              gnomeria/usbtree:usbtree:tar.gz                usbtree"
    "extra   rustscan -              rustscan      -               rustscan       bee-san/RustScan:rustscan:x86-linux            rustscan"
    "desktop firacode fonts-firacode ttf-fira-code fira-code-fonts font-fira-code -                                              -"
#    "extra    -         -               -              -               -               sanford/lsnet"
)

# Compilers and pkg-config for --build cargo, per package manager.
declare -A BUILD_DEPS=(
    [apt]="build-essential pkg-config"
    [pacman]="base-devel"
    [dnf]="gcc make pkgconf-pkg-config"
    [brew]=""
)

run() {
    if [[ -n ${DRY_RUN:-} ]]; then
        echo "+ $*"
    else
        "$@"
    fi
}

is_container() {
    [[ -f /.dockerenv || -f /run/.containerenv \
        || -n ${REMOTE_CONTAINERS:-} || -n ${CODESPACES:-} ]]
}

detect_machine() {
    if is_container; then
        echo container
    elif command -v plasmashell >/dev/null 2>&1; then
        echo desktop
    else
        echo server
    fi
}

detect_pkg_manager() {
    local pm
    for pm in pacman apt-get dnf brew; do
        if command -v "$pm" >/dev/null 2>&1; then
            echo "${pm%-get}"
            return 0
        fi
    done
    return 1
}

# load_github_token: set EGET_GITHUB_TOKEN from the secrets file or gh when it
# is not already in the environment. Missing tokens are fine; eget just gets
# lower GitHub rate limits.
load_github_token() {
    [[ -n ${EGET_GITHUB_TOKEN:-} ]] && return 0

    local secrets="${XDG_CONFIG_HOME:-$HOME/.config}/secrets/env" line
    if [[ -r $secrets ]]; then
        while IFS= read -r line; do
            if [[ $line == EGET_GITHUB_TOKEN=* ]]; then
                EGET_GITHUB_TOKEN="${line#EGET_GITHUB_TOKEN=}"
            fi
        done <"$secrets"
    fi

    if [[ -z ${EGET_GITHUB_TOKEN:-} ]] && command -v gh >/dev/null 2>&1; then
        EGET_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
    fi

    if [[ -n ${EGET_GITHUB_TOKEN:-} ]]; then
        export EGET_GITHUB_TOKEN
    fi
}

# ensure_eget: put eget on PATH, downloading it to ~/.local/bin when missing.
ensure_eget() {
    command -v eget >/dev/null 2>&1 && return 0
    if [[ -x $HOME/.local/bin/eget ]]; then
        PATH="$HOME/.local/bin:$PATH"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: eget is missing and curl is unavailable to fetch it." >&2
        return 1
    fi

    echo "Installing eget to $HOME/.local/bin..."
    [[ -n ${DRY_RUN:-} ]] && { echo "+ curl https://zyedidia.github.io/eget.sh | sh"; return 0; }
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL https://zyedidia.github.io/eget.sh -o "$tmp/eget.sh" \
        && (cd "$tmp" && bash eget.sh) && [[ -x $tmp/eget ]]; then
        mkdir -p "$HOME/.local/bin"
        mv "$tmp/eget" "$HOME/.local/bin/eget"
        rm -rf "$tmp"
        PATH="$HOME/.local/bin:$PATH"
        return 0
    fi
    rm -rf "$tmp"
    echo "Error: failed to install eget." >&2
    return 1
}

# install_eget "owner/repo:binary[:asset[,asset...]]"
install_eget() {
    local repo bin assets filter
    IFS=: read -r repo bin assets <<<"$1"

    if command -v "$bin" >/dev/null 2>&1; then
        echo "$bin is already installed, skipping eget."
        return 0
    fi
    ensure_eget || return 1
    load_github_token

    mkdir -p "$HOME/.local/bin"
    local -a asset_args=() filters=()
    if [[ -n $assets ]]; then
        IFS=, read -r -a filters <<<"$assets"
        for filter in "${filters[@]}"; do
            asset_args+=(--asset "$filter")
        done
    fi
    run eget "$repo" --file "$bin" "${asset_args[@]}" --to "$HOME/.local/bin"
}

# ensure_rustup: put cargo on PATH, from ~/.cargo/bin, a rustup without a
# default toolchain, or a fresh rustup install (minimal profile). PATH and
# the shell config are left alone: zshenv.d/10-toolchains.zsh adds
# ~/.cargo/bin.
ensure_rustup() {
    local cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"
    PATH="$cargo_bin:$PATH"
    command -v cargo >/dev/null 2>&1 && return 0
    if command -v rustup >/dev/null 2>&1; then
        run rustup default stable
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: cargo is missing and curl is unavailable to fetch rustup." >&2
        return 1
    fi

    echo "Installing rustup (stable, minimal profile)..."
    [[ -n ${DRY_RUN:-} ]] && {
        echo "+ curl https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal"
        return 0
    }
    local tmp
    tmp="$(mktemp)"
    if curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o "$tmp" \
        && sh "$tmp" -y --no-modify-path --profile minimal \
        && command -v cargo >/dev/null 2>&1; then
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    echo "Error: failed to install rustup." >&2
    return 1
}

# retire_local_copy BINARY: move ~/.local/bin/BINARY (an eget download that
# comes first in PATH) out of the way of the cargo build, keeping it.
retire_local_copy() {
    local copy="$HOME/.local/bin/$1" keep="$HOME/.local/share/install-apps/replaced"
    [[ -e $copy || -L $copy ]] || return 0
    [[ $copy -ef ${CARGO_HOME:-$HOME/.cargo}/bin/$1 ]] && return 0
    echo "Moving $copy to $keep/ (the cargo build replaces it)."
    run mkdir -p "$keep"
    run mv -f "$copy" "$keep/$1"
}

# install_cargo "crate[:binary]": build the crate for this CPU into
# ~/.cargo/bin. A shared target dir keeps dependencies between crates and
# runs. Any RUSTFLAGS already set are kept.
#
# cargo skips a crate already at the latest version whatever the flags, so
# BUILT_RECORD lists the crates built with exactly these settings; anything
# else (a plain `cargo install`, other RUSTFLAGS) is rebuilt once with --force.
BUILT_RECORD="$HOME/.local/share/install-apps/cargo-built"
install_cargo() {
    local crate bin rustflags settings line force=--force
    IFS=: read -r crate bin <<<"$1"
    bin=${bin:-$crate}
    rustflags="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu=native"
    settings="$crate RUSTFLAGS=$rustflags LTO=fat CGU=1"
    if [[ -r $BUILT_RECORD ]]; then
        while IFS= read -r line; do
            [[ $line == "$settings" ]] && force="" && break
        done <"$BUILT_RECORD"
    fi

    echo "Building $crate for this CPU..."
    run env RUSTFLAGS="$rustflags" \
        CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
        CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/install-apps/cargo-target" \
        cargo install --locked $force "$crate" || return 1
    if [[ -n $force && -z ${DRY_RUN:-} ]]; then
        mkdir -p "${BUILT_RECORD%/*}"
        echo "$settings" >>"$BUILT_RECORD"
    fi
    retire_local_copy "$bin"
}

# setup_nala [SUDO...] - make sure nala is installed.
# Succeeds when nala can be used.
setup_nala() {
    if ! command -v nala >/dev/null 2>&1; then
        echo "Installing nala for parallel downloads..."
        # A dry run never installs nala, so carry on as if it had.
        if ! run "$@" apt-get install -y --no-install-recommends nala \
            || { [[ -z ${DRY_RUN:-} ]] && ! command -v nala >/dev/null 2>&1; }; then
            echo "nala is unavailable, using apt-get." >&2
            return 1
        fi
    fi
}

main() {
    local machine="" nala=1 build=${APPS_BUILD:-prebuilt}
    local usage="Usage: $0 [--machine desktop|server|container] [--no-nala] [--build prebuilt|cargo]"
    while (( $# )); do
        case "$1" in
            --machine)
                machine="${2:-}"
                shift
                ;;
            --machine=*) machine="${1#--machine=}" ;;
            --no-nala) nala=0 ;;
            --build)
                build="${2:-}"
                shift
                ;;
            --build=*) build="${1#--build=}" ;;
            *)
                echo "$usage" >&2
                return 2
                ;;
        esac
        shift
    done
    if [[ $build != prebuilt && $build != cargo ]]; then
        echo "Error: unknown build '$build' (expected prebuilt or cargo)." >&2
        return 2
    fi

    [[ -n $machine ]] || machine="$(detect_machine)"
    local -A tiers=([core]=1)
    case "$machine" in
        desktop)   tiers[extra]=1; tiers[desktop]=1 ;;
        server)    tiers[extra]=1 ;;
        container) [[ -n ${APPS_FORCE_EXTRA:-} ]] && tiers[extra]=1 ;;
        *)
            echo "Error: unknown machine type '$machine' (expected desktop, server or container)." >&2
            return 2
            ;;
    esac
    echo "Machine: $machine (tiers: ${!tiers[*]})"
    [[ $build == cargo ]] && echo "Build: cargo (Rust tools rebuilt for this CPU after the prebuilt install)"

    local pm
    if ! pm="$(detect_pkg_manager)"; then
        echo "Error: No supported package manager was found." >&2
        return 1
    fi

    local -a sudo=()
    if [[ $pm != brew && $EUID -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "Error: Root privileges are required, but sudo is unavailable." >&2
            return 1
        fi
        # Without a terminal a password prompt would hang; fail fast instead.
        if [[ -t 0 ]]; then
            sudo=(sudo)
        else
            sudo=(sudo -n)
        fi
    fi

    local col
    local -a install
    case "$pm" in
        apt)
            col=2
            install=(apt-get install -y --no-install-recommends)
            export DEBIAN_FRONTEND=noninteractive
            ;;
        pacman) col=3; install=(pacman -S --needed --noconfirm) ;;
        dnf)    col=4; install=(dnf install -y) ;;
        brew)   col=5; install=(brew install) ;;
    esac
    echo "Package manager: $pm"

    local row pkg spec
    local -a fields pkgs=() egets=() failed=() crates=() cargo_failed=()
    local -A fallback=()
    for row in "${APPS[@]}"; do
        read -r -a fields <<<"$row"
        [[ -n ${tiers[${fields[0]}]:-} ]] || continue
        pkg="${fields[col]}"
        spec="${fields[6]}"
        [[ ${fields[7]} != - ]] && crates+=("${fields[7]}")
        if [[ $pkg != - ]]; then
            pkgs+=("$pkg")
            [[ $spec != - ]] && fallback[$pkg]="$spec"
        elif [[ $spec != - ]]; then
            egets+=("$spec")
        else
            failed+=("${fields[1]}")
        fi
    done
    if [[ $build == cargo && -n ${BUILD_DEPS[$pm]} ]]; then
        read -r -a fields <<<"${BUILD_DEPS[$pm]}"
        pkgs+=("${fields[@]}")
    fi

    if [[ $pm == apt ]]; then
        run "${sudo[@]}" apt-get update
        if (( nala )) && [[ $machine == container ]] && [[ -z ${APPS_FORCE_NALA:-} ]]; then
            echo "Running in a container: using apt-get (set APPS_FORCE_NALA=1 to use nala)."
        elif (( nala )) && setup_nala "${sudo[@]}"; then
            install=(nala install -y --no-install-recommends)
        fi
    fi

    if ! run "${sudo[@]}" "${install[@]}" "${pkgs[@]}"; then
        # Retry with apt-get: its exit codes are reliable per package.
        if [[ ${install[0]} == nala ]]; then
            echo "nala failed, retrying with apt-get..."
            install=(apt-get install -y --no-install-recommends)
        fi
        echo "Batch install failed, retrying one package at a time..."
        for pkg in "${pkgs[@]}"; do
            if run "${sudo[@]}" "${install[@]}" "$pkg"; then
                continue
            elif [[ -n ${fallback[$pkg]:-} ]]; then
                egets+=("${fallback[$pkg]}")
            else
                failed+=("$pkg")
            fi
        done
    fi

    for spec in "${egets[@]}"; do
        install_eget "$spec" || failed+=("${spec%%:*}")
    done

    if [[ $build == cargo ]] && (( ${#crates[@]} )); then
        if ensure_rustup; then
            for spec in "${crates[@]}"; do
                install_cargo "$spec" || cargo_failed+=("${spec%%:*}")
            done
        else
            cargo_failed=("${crates[@]%%:*}")
        fi
        if (( ${#cargo_failed[@]} )); then
            echo "Warning: cargo build failed, keeping the prebuilt copy: ${cargo_failed[*]}" >&2
        fi
    fi

    if (( ${#failed[@]} )); then
        echo "Failed to install: ${failed[*]}" >&2
        return 1
    fi
    echo "Apps installed."
}

main "$@"
