# zsh from the package manager, and a KDE flag

## Why

Every bootstrap should install zsh from the distro's package manager. A
full non-KDE setup is needed for a phone (Termux with proot Debian) that
runs tmux with the full theme and uses zssh to reach servers.

## Goals

- zsh is installed from the package manager on every machine.
- A desktop without KDE gets all apps and zssh, without Konsole, Yakuake,
  icons, latte, libinput-gestures or fonts.
- zssh works from desktop and server machines (the chezmoi-deploy external
  is fetched on both).

## Non-goals

- A zsh newer than the distro's.
- Native Termux support (pkg backend, `$PREFIX/tmp`).
- Changing the app tiers: `server` stays lean.
- Prebuilt zssh bundles.

## Approaches

1. **Proot Debian with a `kde` flag (chosen).** The phone runs the normal
   Debian bootstrap inside proot; a `kde` flag separate from the machine
   type gates the UI pieces. Almost no phone-specific code.
2. **Native Termux.** Needs a `pkg` backend, `/tmp` rewrites and DNS
   workarounds for static binaries, for one device.
3. **Thin client.** The phone only ssh-es to a host that runs zssh; no
   local theme, so it misses the goal.

## Design

1. **zsh package.** A `zsh` row in the `core` tier of `apps/apps.tsv`
   (apt, pacman, dnf and brew package `zsh`).
2. **Login shell.** A chezmoi script makes zsh the login shell with
   `chsh`, only when stdin is a terminal, the machine is not a container
   and the login shell is not already zsh. It warns and never fails the
   apply.
3. **`kde` data** in `home/.chezmoi.toml.tmpl`:
   - a value saved by an earlier init wins;
   - else, on a `desktop` machine: `true` when `plasmashell` is on PATH,
     otherwise asked once (`promptBoolOnce`) on interactive inits;
   - else `false`.
   A config saved before `kde` existed renders as before: a missing key
   falls back to `machine == "desktop"`.
4. **Gates.** The KDE files in `.chezmoiignore` (konsole, yakuake, icons,
   libinput-gestures, latte), the `20-kde-*` and `30-kde-icons` scripts,
   `30-fonts` and the FiraCode external move from `machine == "desktop"`
   to `kde`.
5. **chezmoi-deploy external** for every machine except containers.
6. **Phone notes** (`docs/termux-proot.md`): run `install.sh` inside proot
   Debian, choose machine `desktop` and no KDE, start tmux in proot, and
   put the Nerd Font in `~/.termux/font.ttf`.

## Left to the builder

Where the `chsh` step lives, and the test layout.
