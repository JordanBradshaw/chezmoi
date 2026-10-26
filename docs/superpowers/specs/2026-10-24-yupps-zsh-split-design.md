# yupps-zsh split design

> **Update 2026-10-25:** the release pin, dev mode and the chezmoi external
> were dropped. `zshrc.d/71-custom-plugin.zsh` clones `$YUPPS_REPO` (default
> `https://github.com/JordanBradshaw/yupps-zsh.git`) to `plugins/yupps-zsh`
> on first start, replacing any copy without `.git`, fast-forwards it in the
> background on later starts, links `$ZDOTDIR/themes` to its `themes/`, then
> sources it; antidote no longer bundles it. Update with `git -C $YUPPS_DIR pull`. zssh bundles
> this machine's checkout minus `.git` (or `$ZSSH_YUPPS_DIR`) and never
> clones. Tests are in `tests/zsh_startup_test.sh`.

## Goal

Move the personal zsh plugin and the yupps theme out of orphan branches of
`jordanbradshaw/zsh-config` into their own repo, `jordanbradshaw/yupps-zsh`,
with tagged releases. This dotfiles repo pins one release. Personal
preferences that ended up in the plugin (options, environment, tool init, key
bindings, zstyles) move into this repo, next to the plugin list they depend
on.

Rule for the split: the plugin is behaviour that works on any machine and
degrades gracefully when a tool is missing. This repo holds preferences and
anything tied to its plugin list (`.zsh_plugins.txt`).

## yupps-zsh repo

```
yupps-zsh/
├── yupps.plugin.zsh        conf.d loader (was zsh-config.plugin.zsh)
├── conf.d/                 25-*, 26-*, 27-* functions; 30-aliases (wrappers);
│                           45-init-cache (_zc_init_cache helper only);
│                           50-completion (completion for its own functions)
├── bin/zc-apt
├── themes/                 yupps.zsh-theme, yupps-classic.zsh-theme
├── tests/                  zsh tests for the above
├── README.md, CHANGELOG.md
└── .github/workflows/test.yml
```

- History comes from the `zsh-plugin` branch (including uncommitted work in
  the live clone). `zsh-themes` is merged in under `themes/` with history.
- Internal `_zc_` names stay. `_zc_init_cache` is the helper this repo calls.
- First release: `v1.0.0`. The old branches stay frozen until every machine
  uses the pin, then they are deleted.

## This repo

- `.chezmoiexternal.toml.tmpl`: an `archive` external
  `.config/zsh/plugins/yupps-zsh` pinned to the tag tarball, with the version
  set in one place. It replaces the `plugins/jordanbradshaw` and `themes`
  git-repo externals.
- Dev mode: with `pluginDev = true` (and optional `pluginDevPath`, default
  `~/repos/yupps-zsh`) under `[data]` in the local chezmoi config, chezmoi
  skips the external and makes `plugins/yupps-zsh` a symlink to the working
  clone.
- `$ZDOTDIR/themes` is a chezmoi symlink to `plugins/yupps-zsh/themes`, so
  `ZSH_CUSTOM="$ZDOTDIR"` and `ZSH_THEME="yupps"` keep loading the theme
  through use-omz.
- `.zsh_plugins.txt` loads `$ZDOTDIR/plugins/yupps-zsh/yupps.plugin.zsh`.
- Moved here from the plugin:
  - `zshrc.d/10-options.zsh` (setopt list)
  - `zshrc.d/30-env.zsh` (MANPAGER, LESS, FZF_DEFAULT_*)
  - `zshrc.d/75-tools.zsh` (zoxide, atuin, direnv through `_zc_init_cache`;
    runs after 70-plugins)
  - `zshrc.d/76-keybindings.zsh` (history-substring-search, atuin Ctrl-R,
    vi-mode keys)
  - `zstyles.d/15-ssh.zsh`, `zstyles.d/45-fzf-tab-previews.zsh` and the other
    completion zstyles
  - `typeset -gU cdpath fpath manpath` in `zshenv.d/00-base.zsh`
- Dropped: `00-tmux.zsh` (all commented out), the duplicate
  `SSH_ASKPASS_REQUIRE`, the `.opencode` folders inside the plugin.
- `.chezmoiremove` removes the old `plugins/jordanbradshaw` and `themes`
  checkouts.
- `scripts/bump-yupps.sh vX.Y.Z`: changes the pin and runs the tests.
- zssh bundles include the archive external and the `themes` symlink.

## As built (differences from the plan above)

- chezmoi can't have an external and a symlink at the same path, so the
  release unpacks to `plugins/yupps-zsh-release` and `plugins/yupps-zsh` is a
  chezmoi symlink to it (or to the working clone in dev mode). The version
  lives in `home/.chezmoidata.toml`; `yupps.url` overrides the download URL.
- The moved files keep their old position in the startup order, after
  plugins: `72-options`, `73-env`, `75-tools`, `76-keybindings`. Inside the
  plugin they also ran after oh-my-zsh's libs and zsh-utils, so they win over
  those.
- `_zc_ssh_hosts` stays in the plugin: its lazyjournal helper uses it.
  `zstyles.d/15-ssh.zsh` only sets the zstyles, calling it when present.
- Dev mode also covers zssh: `build.sh` bundles the working clone (from
  `pluginDev`/`pluginDevPath`, or `ZSSH_YUPPS_DIR`) as a `file://` tarball,
  and the clone's content is part of the rebuild stamp.
  `.chezmoi.toml.tmpl` keeps `pluginDev`/`pluginDevPath` across re-inits.
- The moved tests live in `tests/zsh/` (run with `bash tests/zsh/run.sh`);
  the pin, dev mode and bump script are tested in `tests/yupps_pin_test.sh`
  against a localhost copy of the release tarball.
- The GitHub repo didn't exist yet when this was built, so this laptop runs in
  dev mode. Publishing: create `JordanBradshaw/yupps-zsh`, push `main` and
  `v1.0.0`, then remove `pluginDev` from the local chezmoi config.

## Testing

- yupps-zsh: its own tests, run by CI.
- This repo: tests for the moved files (options, env, tools, keybindings,
  zstyles), the pin, dev-mode symlink and bump script; the existing startup,
  portable and end-to-end tests, where the e2e test checks the theme, aliases
  and that `ls` has no alias from the pinned release.

## Rollout

1. Build yupps-zsh locally, move files out, run its tests, tag `v1.0.0`.
   The GitHub repo must be created by the user (`gh` isn't logged in); then
   push.
2. Switch this repo to the pin, add the moved files, run everything, apply
   locally and verify an interactive shell, refresh the Jetson bundle.
3. Freeze the old branches; delete them later.
