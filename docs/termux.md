# Termux

A phone running Termux gets the full setup natively: zsh with the theme,
tmux, every tool Termux packages, and zssh to reach servers.

## Bootstrap

In Termux:

```sh
pkg upgrade -y
pkg install -y git
git clone https://github.com/JordanBradshaw/chezmoi.git ~/repos/chezmoi
~/repos/chezmoi/install.sh
```

`install.sh` installs chezmoi with `pkg`. Init detects Termux (Termux's
chezmoi reports `os = "android"`; `TERMUX_VERSION` is set in every Termux
session), so it asks no machine-type or KDE question: Termux is a desktop
without KDE. Answer **no** to building the Rust tools with cargo unless you
want them compiled on the phone (slow; see below).

The apply then:

- installs the tools from the manifest's `termux` column with `pkg`
  (no sudo), after `root-repo`, `openssh`, `python` and `golang`;
- skips tools without a Termux package: release binaries need glibc, or a
  `/etc/resolv.conf` Android lacks, so they can't run or can't resolve DNS;
- builds `eget` with `go install` into `~/.local/bin`, for zssh;
- sets zsh as the Termux shell with Termux's `chsh -s zsh`;
- puts FiraCode Nerd Font in `~/.termux/font.ttf` and runs
  `termux-reload-settings`.

Restart Termux to get zsh.

## zssh

zssh runs from Termux as on a desktop: `zssh user@server`. It builds the
bundle for the server's CPU with `~/.local/share/chezmoi-deploy`, so the
bundle's binaries never run on the phone. The ssh control socket lives in
`$TMPDIR` (Termux has no `/tmp` or `XDG_RUNTIME_DIR`).

Log in to GitHub once (`gh auth login`) so eget downloads during bundle
builds carry a token and avoid GitHub's rate limit.

## Rust tools without a Termux package

`appsBuild = "cargo"` in `~/.config/chezmoi/chezmoi.toml` (or answering yes
at init) installs Termux's `rust` package and builds every `crate:` row
natively, including ones Termux doesn't package (tailspin, bottom, ...).

## Root tools

`tcpdump` and `ethtool` come from Termux's root-repo and need root to be
useful; run them with `tsu` or `sudo` on a rooted phone.

## proot Debian instead

If you want the full Debian tool set (every release download), run
`install.sh` inside `proot-distro login debian` instead, choose machine type
`desktop` and answer no to KDE. It is slower, and the font still goes in
Termux's `~/.termux/font.ttf`.
