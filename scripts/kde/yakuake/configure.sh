#!/usr/bin/env bash

set -euo pipefail

CONFIG="${HOME}/.config/yakuakerc"

# ─── Dependencies ────────────────────────────────────────────────────────────

if ! command -v kwriteconfig6 &>/dev/null; then
    echo "Error: kwriteconfig6 is not installed." >&2
    exit 1
fi

# ─── Configuration Helper ────────────────────────────────────────────────────

set_config() {
    local group="$1"
    local key="$2"
    local value="$3"
    local type="${4:-string}"

    kwriteconfig6 \
        --file "$CONFIG" \
        --group "$group" \
        --key "$key" \
        --type "$type" \
        "$value"

    printf '  %-20s %-40s %s\n' "$group" "$key" "$value"
}

# ─── Appearance ──────────────────────────────────────────────────────────────

echo
echo "Configuring Appearance..."

set_config Appearance BackgroundColorOpacity 15 int
set_config Appearance HideSkinBorders true bool
set_config Appearance Skin transparent-tabs
set_config Appearance SkinInstalledWithKns true bool
set_config Appearance TerminalHighlightOnManualActivation true bool
set_config Appearance Translucency true bool

# ─── Behavior ────────────────────────────────────────────────────────────────

echo
echo "Configuring Behavior..."

set_config Behavior FocusFollowsMouse true bool
set_config Behavior OpenAfterStart true bool
set_config Behavior RememberFullscreen true bool

# ─── Desktop Entry ───────────────────────────────────────────────────────────

echo
echo "Configuring Desktop Entry..."

set_config "Desktop Entry" DefaultProfile yupps.profile

# ─── Window ──────────────────────────────────────────────────────────────────

echo
echo "Configuring Window..."

set_config Window DynamicTabTitles true bool
set_config Window Height 100 int
set_config Window KeepOpenAfterLastSessionCloses true bool
set_config Window ToggleToFocus true bool

# ─── Shortcuts ───────────────────────────────────────────────────────────────

echo
echo "Configuring Shortcuts..."

set_config Shortcuts close-active-terminal 'Ctrl+Shift+R; Ctrl+Shift+Q'
set_config Shortcuts decrease-window-height 'Ctrl+Alt+Shift+Up'
set_config Shortcuts decrease-window-width 'Ctrl+Alt+Shift+Left'
set_config Shortcuts increase-window-height 'Ctrl+Alt+Shift+Down'
set_config Shortcuts increase-window-width 'Ctrl+Alt+Shift+Right'
set_config Shortcuts new-session 'Ctrl+Shift+T; Ctrl+Shift+N'
set_config Shortcuts next-session 'Shift+Right; Ctrl+Shift+Right'
set_config Shortcuts next-terminal 'Ctrl+Tab; Ctrl+Shift+Down'
set_config Shortcuts previous-session 'Shift+Left; Ctrl+Shift+Left'
set_config Shortcuts previous-terminal 'Ctrl+Shift+Tab; Ctrl+Shift+Up'
set_config Shortcuts split-left-right 'Ctrl++'
set_config Shortcuts split-top-bottom 'Ctrl+_'
set_config Shortcuts switch-to-session-1 'Alt+1; Ctrl+!'
set_config Shortcuts switch-to-session-2 'Alt+2; Ctrl+@'
set_config Shortcuts switch-to-session-3 'Alt+3; Ctrl+#'
set_config Shortcuts switch-to-session-4 'Alt+4; Ctrl+$'
set_config Shortcuts switch-to-session-5 'Alt+5; Ctrl+%'
set_config Shortcuts switch-to-session-6 'Alt+6; Ctrl+^'
set_config Shortcuts switch-to-session-7 'Alt+7; Ctrl+&'
set_config Shortcuts switch-to-session-8 'Alt+8; Ctrl+*'
set_config Shortcuts switch-to-session-9 'Alt+9; Ctrl+('
set_config Shortcuts switch-to-session-10 'Alt+0; Ctrl+)'

# ─── Complete ────────────────────────────────────────────────────────────────

echo
echo "Yakuake configuration updated successfully."
echo "Configuration: $CONFIG"
echo
echo "Restart Yakuake to apply all changes."