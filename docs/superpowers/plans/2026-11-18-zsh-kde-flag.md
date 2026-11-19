# zsh package + KDE flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install zsh from the package manager everywhere, and gate the KDE UI pieces on a new `kde` data flag so a non-KDE desktop (the phone in proot Debian) gets every app and zssh.

**Architecture:** A `zsh` core row in the app manifest; a tty-only chezmoi script for `chsh`; a `kde` key computed in `.chezmoi.toml.tmpl` and read through one shared template that falls back to `machine == "desktop"`; the chezmoi-deploy external opened to servers.

**Tech Stack:** chezmoi templates, bash, the repo's bash test harnesses.

**Spec:** `docs/superpowers/specs/2026-11-18-zsh-kde-flag-design.md`

## Global Constraints

- A config saved before `kde` existed must still render: a missing key falls back to `eq .machine "desktop"`.
- App tiers do not change; `server` stays lean.
- `chsh` never fails `chezmoi apply`.
- New test files join the `.github/workflows/tests.yml` matrix.

## Review Focus

1. Existing desktop config without `kde` keeps Konsole, icons and fonts (Task 3 fallback test, Task 4 existing tests).
2. Desktop with `kde=false` gets desktop-tier apps but no KDE files or fonts (Task 4).
3. Non-interactive apply (CI, scripts) renders the login-shell script empty: no `chsh` (Task 2).
4. zsh missing from `/etc/shells`: warn, no `chsh`, exit 0 (Task 2).
5. Container: no chezmoi-deploy external, no `chsh` (Tasks 2, 5).

---

### Task 1: zsh in the core tier

**Files:** Modify `apps/apps.tsv`, `tests/install_apps_test.sh`, `tests/apps_test.sh`

- [ ] **Step 1:** In `install_apps_test.sh` set `CORE_APT="curl git unzip zsh fzf bat eza lsd ripgrep fd-find git-delta zoxide atuin direnv"`; in `apps_test.sh` assert the core list contains ` zsh `.
- [ ] **Step 2:** Run `bash tests/install_apps_test.sh`. Expected: `test_container_installs_core_only` FAILS.
- [ ] **Step 3:** Add row after `unzip`: `zsh core - zsh zsh zsh zsh - - - -`.
- [ ] **Step 4:** Run `bash tests/install_apps_test.sh && bash tests/apps_test.sh`. Expected: PASS.
- [ ] **Step 5:** Commit `apps: install zsh from the package manager`.

### Task 2: Login shell

**Files:** Create `scripts/set-login-shell.sh`, `home/.chezmoiscripts/run_onchange_after_15-login-shell.sh.tmpl`, `tests/login_shell_test.sh`; modify `.github/workflows/tests.yml`

**Interfaces:** `set-login-shell.sh` takes no arguments, always exits 0, reads `SHELLS_FILE` (default `/etc/shells`); current login shell from `getent passwd "$(id -un)" | cut -d: -f7`, else `$SHELL`.

- [ ] **Step 1:** Tests (stubs for `zsh`, `getent`, `chsh` on PATH): `test_already_zsh_no_chsh`, `test_bash_runs_chsh` (log has `chsh -s $STUBS/zsh`), `test_zsh_not_in_shells_warns_no_chsh`, `test_chsh_failure_exits_0`, `test_no_zsh_warns_exits_0`, `test_template_empty_for_container`, `test_template_empty_without_tty`.
- [ ] **Step 2:** Run `bash tests/login_shell_test.sh`. Expected: FAIL (script missing).
- [ ] **Step 3:** Implement the script; template wrapped in `{{ if and (ne .machine "container") stdinIsATTY }}`, carries a hash comment of the script, `exec`s it.
- [ ] **Step 4:** Run. Expected: PASS. Add to CI matrix.
- [ ] **Step 5:** Commit `zsh: make zsh the login shell on interactive applies`.

### Task 3: `kde` data and helper

**Files:** Modify `home/.chezmoi.toml.tmpl`; create `home/.chezmoitemplates/kde`, `tests/kde_test.sh`; modify `.github/workflows/tests.yml`

**Interfaces:** Produces `includeTemplate "kde" .` → exactly `true` or `false` (`.kde` if the key exists, else `eq .machine "desktop"`); `[data] kde = <bool>`.

Logic: saved `kde` wins; else if `$machine` is `desktop`: `lookPath "plasmashell"` → `true`, else on a tty `promptBoolOnce . "kde" "Is this machine using KDE" false`, else `false`; other machines `false`.

- [ ] **Step 1:** Tests (`execute-template --init`, stub `plasmashell` on a controlled PATH): `test_plasmashell_sets_kde`, `test_desktop_without_plasmashell_non_tty_is_false`, `test_server_is_false_even_with_plasmashell`, `test_saved_kde_false_wins_over_plasmashell`, `test_helper_falls_back_to_machine_without_key` (desktop→true, server→false), `test_helper_uses_kde_key` (desktop + kde=false → false).
- [ ] **Step 2:** Run `bash tests/kde_test.sh`. Expected: FAIL.
- [ ] **Step 3:** Implement both files.
- [ ] **Step 4:** Run. Expected: PASS. Add to CI.
- [ ] **Step 5:** Commit `chezmoi: add kde flag, detected or asked once`.

### Task 4: Gate the UI pieces on `kde`

**Files:** Modify `home/.chezmoiignore`, `home/.chezmoiscripts/run_onchange_after_20-kde-konsole.sh.tmpl`, `run_onchange_after_20-kde-yakuake.sh.tmpl`, `run_onchange_after_30-kde-icons.sh.tmpl`, `run_onchange_after_30-fonts.sh.tmpl`, font block of `home/.chezmoiexternal.toml.tmpl`; tests `tests/fonts_test.sh`, `tests/icons_test.sh`

**Consumes:** Task 3 helper; gate `{{ if eq (includeTemplate "kde" .) "true" }}` (negated in `.chezmoiignore`).

- [ ] **Step 1:** Let test config helpers take an optional `kde` value; add `test_desktop_without_kde_gets_no_fonts`, `test_desktop_without_kde_font_script_empty`, `test_desktop_without_kde_icon_script_empty`, `test_desktop_without_kde_ignores_konsole_yakuake` (`chezmoi managed`). Existing desktop tests (no key) cover the fallback.
- [ ] **Step 2:** Run. Expected: new tests FAIL.
- [ ] **Step 3:** Swap the gates.
- [ ] **Step 4:** Run `bash tests/fonts_test.sh && bash tests/icons_test.sh && bash tests/zsh_startup_test.sh`. Expected: PASS.
- [ ] **Step 5:** Commit `chezmoi: gate KDE files, icons and fonts on kde`.

### Task 5: chezmoi-deploy external on servers

**Files:** Modify `home/.chezmoiexternal.toml.tmpl` (split deploy out of the font block), `tests/zssh_test.sh`

- [ ] **Step 1:** Rename `test_deploy_external_desktop_only` → `test_deploy_external_not_in_containers`: present for desktop and server, absent for container.
- [ ] **Step 2:** Run `bash tests/zssh_test.sh`. Expected: FAIL on server.
- [ ] **Step 3:** Gate the block on `{{ if ne .machine "container" }}`.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `zssh: fetch chezmoi-deploy on servers too`.

### Task 6: Phone notes

**Files:** Create `docs/termux-proot.md`

- [ ] **Step 1:** Write: run `install.sh` inside proot Debian; pick machine `desktop`, answer no to KDE; start tmux inside proot; copy `FiraCodeNerdFont-Regular.ttf` to `~/.termux/font.ttf` and run `termux-reload-settings`; `gh auth login` in proot for the eget token.
- [ ] **Step 2:** Commit `docs: Termux proot setup`.
