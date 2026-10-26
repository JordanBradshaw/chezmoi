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
#   The tools come from apps/apps.tsv, the app manifest shared with the portable
#   build (apps/lib.sh reads it; the file documents the columns). Each row in a
#   selected tier is installed from its package-manager package; a tool with no
#   package, or whose package fails, is downloaded from its GitHub release with
#   eget (release, file and assets columns; Linux only).
#
#   eget authenticates with EGET_GITHUB_TOKEN from the environment, then
#   ~/.config/secrets/env, then `gh auth token`.
#
#   --build (or APPS_BUILD) picks where the Rust tools come from:
#     prebuilt  packages, then eget releases (the default)
#     cargo     the same first, so every tool works even if a build fails;
#               then each `crate:` build in the manifest is rebuilt with
#               `cargo install --locked` for this CPU (target-cpu=native, fat LTO, one codegen unit)
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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../apps/lib.sh"
apps_load || exit 1

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

# install_release NAME: download NAME's release binary to ~/.local/bin, from
# the manifest's release, file and assets columns.
install_release() {
    local name=$1 arch
    if command -v "$name" >/dev/null 2>&1; then
        echo "$name is already installed, skipping eget."
        return 0
    fi
    if [[ $(uname -s) != Linux ]]; then
        echo "Error: $name needs a release download, which works on Linux only." >&2
        return 1
    fi
    ensure_eget || return 1
    arch="$(normalize_arch "$(uname -m)")" || return 1

    run mkdir -p "$HOME/.local/bin"
    if ! run fetch_release "$name" "$(app "$name" release)" "$(app "$name" file)" \
        "$(app "$name" assets)" "$arch" "$HOME/.local/bin/$name"; then
        echo "Error: no usable $arch release asset for $name." >&2
        return 1
    fi
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

# install_cargo "CRATE[:BIN[:ARGS]]": build the crate for this CPU into
# ~/.cargo/bin. A shared target dir keeps dependencies between crates and
# runs. Any RUSTFLAGS already set are kept.
#
# cargo skips a crate already at the latest version whatever the flags, so
# BUILT_RECORD lists the crates built with exactly these settings; anything
# else (a plain `cargo install`, other RUSTFLAGS) is rebuilt once with --force.
BUILT_RECORD="$HOME/.local/share/install-apps/cargo-built"
install_cargo() {
    local crate bin cargs rustflags settings line force=--force
    local -a args=()
    IFS=: read -r crate bin cargs <<<"$1"
    bin=${bin:-$crate}
    [[ -n $cargs ]] && IFS=, read -r -a args <<<"$cargs"
    rustflags="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu=native"
    settings="$crate RUSTFLAGS=$rustflags LTO=fat CGU=1"
    [[ -n $cargs ]] && settings+=" ARGS=$cargs"
    if [[ -r $BUILT_RECORD ]]; then
        while IFS= read -r line; do
            [[ $line == "$settings" ]] && force="" && break
        done <"$BUILT_RECORD"
    fi

    echo "Building $crate for this CPU..."
    run env RUSTFLAGS="$rustflags" \
        CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
        CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/install-apps/cargo-target" \
        cargo install --locked $force "${args[@]}" "$crate" || return 1
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

    local -a install
    case "$pm" in
        apt)
                        install=(apt-get install -y --no-install-recommends)
            export DEBIAN_FRONTEND=noninteractive
            ;;
        pacman) install=(pacman -S --needed --noconfirm) ;;
        dnf)    install=(dnf install -y) ;;
        brew)   install=(brew install) ;;
    esac
    echo "Package manager: $pm"

    local name pkg release spec
    local -a fields pkgs=() releases=() failed=() crates=() cargo_failed=()
    local -A fallback=()
    for name in "${APPS_NAMES[@]}"; do
        [[ -n ${tiers[$(app "$name" tier)]:-} ]] || continue
        pkg="$(app "$name" "$pm")"
        release="$(app "$name" release)"
        spec="$(app "$name" build)"
        [[ $spec == crate:* ]] && crates+=("${spec#crate:}")
        if [[ $pkg != - ]]; then
            pkgs+=("$pkg")
            [[ $release != - ]] && fallback[$pkg]="$name"
        elif [[ $release != - ]]; then
            releases+=("$name")
        else
            failed+=("$name")
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
                releases+=("${fallback[$pkg]}")
            else
                failed+=("$pkg")
            fi
        done
    fi

    for name in "${releases[@]}"; do
        install_release "$name" || failed+=("$name")
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
