#!/usr/bin/env bash

set -euo pipefail

CONFIG="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [PANEL_ID] [OUTPUT_FILE]

Export a specific KDE Plasma panel and its widgets.

Options:
    -l, --list       List available panels
    -h, --help       Show this help

Arguments:
    PANEL_ID         Containment ID of the panel to export
    OUTPUT_FILE      Optional output filename
                     Default: panel-<PANEL_ID>.conf

Examples:
    $(basename "$0") --list
    $(basename "$0") 7
    $(basename "$0") 7 ~/dotfiles/kde/panel.conf
EOF
}

list_panels() {
    echo "Available KDE Plasma panels:"
    echo

    awk '
        /^\[Containments\]\[[0-9]+\]$/ {
            id = $0
            gsub(/[^0-9]/, "", id)
            location = "unknown"
            is_panel = 0
            next
        }

        /^\[/ {
            if (is_panel)
                printf "Panel ID: %-5s Location: %s\n", id, location

            is_panel = 0
            next
        }

        /^location=/ {
            location = $0
            sub(/^location=/, "", location)
        }

        /^plugin=org\.kde\.panel$/ {
            is_panel = 1
        }

        END {
            if (is_panel)
                printf "Panel ID: %-5s Location: %s\n", id, location
        }
    ' "$CONFIG"
}

export_panel() {
    local panel_id="$1"
    local output="${2:-panel-${panel_id}.conf}"

    if [[ ! "$panel_id" =~ ^[0-9]+$ ]]; then
        echo "Error: PANEL_ID must be numeric." >&2
        exit 1
    fi

    # Verify the containment exists and is a panel.
    if ! awk -v id="$panel_id" '
        $0 == "[Containments][" id "]" {
            found = 1
            next
        }

        /^\[/ {
            found = 0
        }

        found && /^plugin=org\.kde\.panel$/ {
            valid = 1
        }

        END {
            exit !valid
        }
    ' "$CONFIG"; then
        echo "Error: Panel $panel_id not found." >&2
        exit 1
    fi

    # Extract the panel and all its nested applet sections.
    awk -v id="$panel_id" '
        /^\[Containments\]\[/ {
            keep = (
                index($0, "[Containments][" id "]") == 1 &&
                (
                    $0 == "[Containments][" id "]" ||
                    index($0, "[Containments][" id "][") == 1
                )
            )
        }

        keep {
            print
        }
    ' "$CONFIG" > "$output"

    echo "Successfully exported panel $panel_id"
    echo "Output: $output"
}

main() {
    if [[ ! -f "$CONFIG" ]]; then
        echo "Error: KDE Plasma configuration not found: $CONFIG" >&2
        exit 1
    fi

    case "${1:-}" in
        -l|--list)
            list_panels
            ;;
        -h|--help)
            usage
            ;;
        "")
            list_panels
            echo
            usage
            ;;
        *)
            export_panel "$@"
            ;;
    esac
}

main "$@"