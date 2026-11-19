# Language toolchains' bin dirs, after ~/.local/bin and before the system dirs.
# Homes already set win; dirs that don't exist are skipped, so servers and
# containers keep a clean PATH. This replaces the installers' snippets
# (~/.cargo/env, pnpm's PATH block). GOPATH is read directly: running
# `go env GOPATH` on every shell is slow. ~/.local/tuned/bin (CPU-tuned
# builds from chezmoi-deploy's builder.sh, copied in by hand on Termux)
# comes first of all.
() {
  local pnpm=${PNPM_HOME:-$XDG_DATA_HOME/pnpm} gopath=${GOPATH:-$HOME/go}
  [[ -d $pnpm ]] && export PNPM_HOME=$pnpm
  path=(
    $HOME/.local/tuned/bin(N-/)
    $XDG_BIN_HOME
    $pnpm/bin(N-/)
    ${CARGO_HOME:-$HOME/.cargo}/bin(N-/)
    ${GOBIN:-${gopath%%:*}/bin}(N-/)
    $path
  )
}
