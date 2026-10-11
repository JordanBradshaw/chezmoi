#!/usr/bin/env bash

set -euo pipefail
# ---------------------------------------------------------------------------
# Apps
# ---------------------------------------------------------------------------
# Usage: ./bootstrap.sh apps [--extra] [--no-nala]
#
#   core   Tools the shell config relies on. Always installed.
#   extra  Fonts, TUIs and heavier tools. Installed with --extra, but skipped
#          inside containers unless APPS_FORCE_EXTRA=1.
#
#   On apt systems nala is installed first and used for the batch (parallel
#   downloads; `nala fetch` picks fast mirrors once). --no-nala keeps apt-get;
#   containers use apt-get unless APPS_FORCE_NALA=1. A nala failure falls back
#   to apt-get.
#
#   DRY_RUN=1 prints the commands instead of running them.
#
# Columns: tier name apt pacman dnf brew eget
#   "-"   not packaged for that manager.
#   eget  "owner/repo:binary[:asset[,asset...]]", used when the package is
#         unavailable or fails. Each asset filter narrows the release files;
#         a leading ^ excludes matches.
APPS=(
    "core   curl      curl            curl           curl            curl            -"
    "core   git       git             git            git             git             -"
    "core   unzip     unzip           unzip          unzip           unzip           -"
    "core   stow      stow            stow           stow            stow            -"
    "core   fzf       fzf             fzf            fzf             fzf             -"
    "core   bat       bat             bat            bat             bat             -"
    "core   eza       eza             eza            eza             eza             eza-community/eza:eza:gnu.tar.gz"
    "core   lsd       lsd             lsd            lsd             lsd             -"
    "core   ripgrep   ripgrep         ripgrep        ripgrep         ripgrep         -"
    "core   fd        fd-find         fd             fd-find         fd              -"
    "core   delta     git-delta       git-delta      git-delta       git-delta       -"
    "core   zoxide    zoxide          zoxide         zoxide          zoxide          ajeetdsouza/zoxide:zoxide:musl"
    "core   atuin     atuin           atuin          atuin           atuin           atuinsh/atuin:atuin:gnu.tar.gz,^server"
    "core   direnv    direnv          direnv         direnv          direnv          direnv/direnv:direnv"
    "core  firacode  fonts-firacode  ttf-fira-code  fira-code-fonts font-fira-code  -"
    "extra  miller    miller          miller         miller          miller          -"
    "extra  nushell   -               nushell        -               nushell         nushell/nushell:nu:musl"
    "extra  gh        gh              github-cli     gh              gh              -"
    "extra  tailspin  tailspin        tailspin       tailspin        tailspin        -"
    "extra  procs     procs           procs          procs           procs           -"
    "extra  duf       duf             duf            duf             duf             -"
    "extra  dust      du-dust         dust           du-dust         dust            -"
    "extra  btm       btm             bottom         bottom          bottom          -"
    "extra  htop      htop            htop           htop            htop            -"
    "extra  tmux      tmux            tmux           tmux            tmux            -"
    "extra  starship  starship        starship       starship        starship        -"
    "extra  micro     micro           micro          micro           micro           -"
    "extra  neovim    neovim          neovim         neovim          neovim          -"
    "extra  most      most            most           most            most            -"
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

# install_eget "owner/repo:binary[:asset[,asset...]]"
install_eget() {
    local repo bin assets filter
    IFS=: read -r repo bin assets <<<"$1"

    if command -v "$bin" >/dev/null 2>&1; then
        echo "$bin is already installed, skipping eget."
        return 0
    fi
    if ! command -v eget >/dev/null 2>&1; then
        echo "Error: eget is required to install $repo." >&2
        return 1
    fi
    if [[ -z ${EGET_GITHUB_TOKEN:-} ]] && command -v gh >/dev/null 2>&1; then
        EGET_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
        export EGET_GITHUB_TOKEN
    fi

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

# setup_nala [SUDO...] - make sure nala is installed and has fast mirrors.
# Succeeds when nala can be used. Fetching mirrors is best effort.
setup_nala() {
    local sources=${APPS_NALA_SOURCES:-/etc/apt/sources.list.d/nala-sources.list}

    if ! command -v nala >/dev/null 2>&1; then
        echo "Installing nala for parallel downloads..."
        # A dry run never installs nala, so carry on as if it had.
        if ! run "$@" apt-get install -y --no-install-recommends nala \
            || { [[ -z ${DRY_RUN:-} ]] && ! command -v nala >/dev/null 2>&1; }; then
            echo "nala is unavailable, using apt-get." >&2
            return 1
        fi
    fi

    # `nala fetch --auto` still prompts when its mirror list exists, so only
    # run it once; stdin is closed so it can never wait for input.
    # if [[ ! -e $sources ]]; then
    #     echo "Picking the fastest mirrors with nala fetch..."
    #     if run "$@" nala fetch --auto </dev/null; then
    #         run "$@" nala update
    #     else
    #         echo "nala fetch failed, keeping the current mirrors." >&2
    #     fi
    # fi
}

install_apps() {
    local extra=1 nala=1 arg
    for arg in "$@"; do
        case "$arg" in
            --no-extra) extra=0 ;;
            --no-nala) nala=0 ;;
            *)
                echo "Usage: $0 apps [--no-extra] [--no-nala]" >&2
                return 2
                ;;
        esac
    done

    if (( extra )) && is_container && [[ -z ${APPS_FORCE_EXTRA:-} ]]; then
        echo "Running in a container: skipping extra apps (set APPS_FORCE_EXTRA=1 to install them)."
        extra=0
    fi

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
        sudo=(sudo)
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
    local -a fields pkgs=() egets=() failed=()
    local -A fallback=()
    for row in "${APPS[@]}"; do
        read -r -a fields <<<"$row"
        if [[ ${fields[0]} == extra ]] && (( ! extra )); then
            continue
        fi
        pkg="${fields[col]}"
        spec="${fields[6]}"
        if [[ $pkg != - ]]; then
            pkgs+=("$pkg")
            [[ $spec != - ]] && fallback[$pkg]="$spec"
        elif [[ $spec != - ]]; then
            egets+=("$spec")
        else
            failed+=("${fields[1]}")
        fi
    done

    if [[ $pm == apt ]]; then
        run "${sudo[@]}" apt-get update
        if (( nala )) && is_container && [[ -z ${APPS_FORCE_NALA:-} ]]; then
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

    if (( ${#failed[@]} )); then
        echo "Failed to install: ${failed[*]}" >&2
        return 1
    fi
    echo "Apps installed."
}

# ---------------------------------------------------------------------------
# Requirements
# ---------------------------------------------------------------------------
#if [[ $EUID -eq 0 ]]; then
#    SUDO=""
#elif command -v sudo >/dev/null 2>&1; then
#    SUDO="sudo"
#else
#    echo "Error: Root privileges are required, but sudo is not installed." >&2
#    exit 1
#fi

install_stow() {
    # Already installed.
    if command -v stow >/dev/null 2>&1; then
        return 0
    fi

    echo "GNU Stow is not installed."
    echo "Attempting to install it..."

    # Determine privilege escalation command.
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: Root privileges are required, but sudo is unavailable." >&2
        exit 1
    fi

    # Detect package manager.
    if command -v pacman >/dev/null 2>&1; then
        echo "Package manager: pacman"
        $SUDO pacman -S --needed --noconfirm stow

    elif command -v apt-get >/dev/null 2>&1; then
        echo "Package manager: apt"
        $SUDO apt-get update
        $SUDO apt-get install -y stow

    elif command -v dnf >/dev/null 2>&1; then
        echo "Package manager: dnf"
        $SUDO dnf install -y stow

    elif command -v zypper >/dev/null 2>&1; then
        echo "Package manager: zypper"
        $SUDO zypper --non-interactive install stow

    elif command -v apk >/dev/null 2>&1; then
        echo "Package manager: apk"
        $SUDO apk add stow

    elif command -v xbps-install >/dev/null 2>&1; then
        echo "Package manager: xbps"
        $SUDO xbps-install -Sy stow

    elif command -v emerge >/dev/null 2>&1; then
        echo "Package manager: emerge"
        $SUDO emerge app-admin/stow

    elif command -v brew >/dev/null 2>&1; then
        echo "Package manager: Homebrew"
        brew install stow

    else
        echo "Error: No supported package manager was found." >&2
        exit 1
    fi

    # Make absolutely sure installation worked.
    if ! command -v stow >/dev/null 2>&1; then
        echo "Error: GNU Stow installation failed." >&2
        exit 1
    fi

    echo "GNU Stow installed successfully."
}

if [[ ${1:-} == apps ]]; then
    shift
    install_apps "$@"
    exit
fi

install_stow
# if ! command -v stow >/dev/null 2>&1; then
#    echo "Error: GNU Stow is not installed." >&2
#    echo "Install it with: sudo pacman -S stow" >&2
#    exit 1
#fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Use $DOTFILES if it is set and points to a directory.
# Otherwise use the current working directory.
if [[ -n "${DOTFILES:-}" && -d "$DOTFILES" ]]; then
    DOTFILES_DIR="$DOTFILES"
else
    DOTFILES_DIR="$PWD"
fi

TARGET="$HOME"

echo "Dotfiles: $DOTFILES_DIR"
echo "Target:   $TARGET"

# ---------------------------------------------------------------------------
# Stow groups
# ---------------------------------------------------------------------------

case "${1:-}" in
    all)
        echo "Running command: stow -d "$DOTFILES_DIR" -t "$TARGET" -v atuin bat fd git htop lsd pip ripgrep tmux wizterm starship konsole yakuake"
	stow \
            -d "$DOTFILES_DIR" \
            -t "$TARGET" \
            -v atuin bat fd git htop lsd pip ripgrep tmux wizterm starship zsh eget
        ;;

    shell)
        stow \
            -d "$DOTFILES_DIR/shell" \
            -t "$TARGET" \
            zsh starship atuin
        ;;

    # cli)
    #     stow \
    #         -d "$DOTFILES_DIR/cli" \
    #         -t "$TARGET" \
    #         bat btop lsd ripgrep micro
        # ;;

    gui)
        stow \
            -d "$DOTFILES_DIR" \
            -t "$TARGET" \
            -v --adopt konsole yakuake
        ;;


    *)
        stow \
            -d "$DOTFILES_DIR" \
            -t "$TARGET" \
            -v $@
        ;;
esac
