# Termux with proot Debian

A phone running Termux gets the full setup (theme, tmux, every app and
zssh) by bootstrapping inside proot Debian. Termux itself only draws the
terminal.

## Bootstrap

In Termux:

```sh
pkg install proot-distro
proot-distro install debian
proot-distro login debian
```

Inside proot Debian (you are root, so nothing asks for sudo):

```sh
apt-get update && apt-get install -y git curl
git clone https://github.com/JordanBradshaw/chezmoi.git ~/repos/chezmoi
~/repos/chezmoi/install.sh
```

Answer the init questions:

- **Machine type:** `desktop`, so it gets every app tier.
- **Is this machine using KDE:** no. Konsole, Yakuake, icons, latte,
  gestures and the font download are skipped.

The bootstrap installs zsh with apt and makes it root's login shell in
proot. It also fetches `~/.local/share/chezmoi-deploy`, which zssh uses to
build bundles.

## Daily use

Start tmux inside proot, not in Termux:

```sh
proot-distro login debian -- tmux new -A -s main
```

zssh runs from there: `zssh user@server`.

Log in to GitHub once (`gh auth login`) so eget downloads during installs
and zssh builds carry a token and avoid GitHub's rate limit.

## Font

Termux draws the glyphs, so it needs a Nerd Font. In Termux (outside
proot), download FiraCode Nerd Font, copy one `.ttf` to `~/.termux/font.ttf`
and reload:

```sh
curl -fLo "$TMPDIR/FiraCode.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/FiraCode.tar.xz
mkdir -p "$TMPDIR/fira" && tar -xJf "$TMPDIR/FiraCode.tar.xz" -C "$TMPDIR/fira"
mkdir -p ~/.termux && cp "$TMPDIR/fira"/FiraCodeNerdFont-Regular.ttf ~/.termux/font.ttf
termux-reload-settings
```
