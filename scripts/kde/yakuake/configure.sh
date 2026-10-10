#!/usr/bin/env bash

set -euo pipefail

CONFIG="${HOME}/.config/yakuakerc"

# ─── Dependencies ────────────────────────────────────────────────────────────

if ! command -v kwriteconfig6 &>/dev/null; then
    echo "Error: kwriteconfig6 is not installed." >&2
    exit 1
fi

# ─── Backup ──────────────────────────────────────────────────────────────────

if [[ -f "$CONFIG" ]]; then
    BACKUP="${CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG" "$BACKUP"
    echo "Backup created: $BACKUP"
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
set_config Window KeepOpenAfterLastSessionCloses true bool
set_config Window ToggleToFocus true bool

# ─── Complete ────────────────────────────────────────────────────────────────

echo
echo "Yakuake configuration updated successfully."
echo "Configuration: $CONFIG"
echo
echo "Restart Yakuake to apply all changes."