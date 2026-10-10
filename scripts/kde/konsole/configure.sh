#!/usr/bin/env bash

set -euo pipefail

CONFIG="${HOME}/.config/konsolerc"

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

    local args=(
        --file "$CONFIG"
    )

    # Empty group means root-level configuration
    if [[ -n "$group" ]]; then
        args+=(--group "$group")
    fi

    args+=(
        --key "$key"
        --type "$type"
        "$value"
    )

    kwriteconfig6 "${args[@]}"

    printf '  %-20s %-35s %s\n' \
        "${group:-ROOT}" "$key" "$value"
}

# ─── Root Configuration ──────────────────────────────────────────────────────

echo
echo "Configuring root settings..."

set_config "" MenuBar Disabled

# ─── Desktop Entry ───────────────────────────────────────────────────────────

echo
echo "Configuring Desktop Entry..."

set_config "Desktop Entry" DefaultProfile yupps.profile

# ─── General ─────────────────────────────────────────────────────────────────

echo
echo "Configuring General..."

set_config General ConfigVersion 1 int

# ─── KonsoleWindow ───────────────────────────────────────────────────────────

echo
echo "Configuring KonsoleWindow..."

set_config KonsoleWindow AllowMenuAccelerators true bool
set_config KonsoleWindow ForceNewTabs true bool

# ─── UiSettings ──────────────────────────────────────────────────────────────

echo
echo "Configuring UiSettings..."

set_config UiSettings ColorScheme ""

# ─── Complete ────────────────────────────────────────────────────────────────

echo
echo "Konsole configuration updated successfully."
echo "Configuration: $CONFIG"
echo
echo "Restart Konsole to apply all changes."