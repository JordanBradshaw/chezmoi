#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

CONFIG = Path.home() / ".config/plasma-org.kde.plasma.desktop-appletsrc"

SECTION = re.compile(r"^\[([^\]]+(?:\]\[[^\]]+)*)\]\s*$")
CONTAINMENT = re.compile(r"^\[Containments\]\[(\d+)\]")
APPLET = re.compile(r"\[Applets\]\[(\d+)\]")
ID_FIELDS = re.compile(r"^(\s*(?:appletOrder|AppletOrder)\s*=\s*)(.*)$")


def sections(text):
    result = []
    current = None

    for line in text.splitlines(keepends=True):
        match = SECTION.match(line.strip())

        if match:
            current = match.group(1)

        result.append((current, line))

    return result


def all_ids(text):
    ids = set()

    for match in re.finditer(
        r"\[(?:Containments|Applets)\]\[(\d+)\]",
        text,
    ):
        ids.add(int(match.group(1)))

    return ids


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("panel_file", type=Path)
    args = parser.parse_args()

    source = args.panel_file.read_text()
    destination = CONFIG.read_text()

    panel_ids = {
        int(m.group(1))
        for m in CONTAINMENT.finditer(source)
    }

    if len(panel_ids) != 1:
        sys.exit("Expected exactly one panel containment.")

    old_panel = next(iter(panel_ids))

    if not re.search(
        rf"(?m)^plugin=org\.kde\.panel\s*$",
        source,
    ):
        sys.exit("Export does not appear to contain a Plasma panel.")

    used = all_ids(destination) | all_ids(source)
    next_id = max(used, default=0) + 1

    def allocate():
        nonlocal next_id
        value = next_id
        next_id += 1
        return value

    new_panel = allocate()

    applet_ids = {
        int(m.group(1))
        for m in APPLET.finditer(source)
    }

    applet_map = {
        old: allocate()
        for old in sorted(applet_ids)
    }

    output = []

    for section, line in sections(source):
        if line.startswith("[Containments]["):
            line = re.sub(
                rf"^\[Containments\]\[{old_panel}\]",
                f"[Containments][{new_panel}]",
                line,
            )

            for old, new in applet_map.items():
                line = line.replace(
                    f"[Applets][{old}]",
                    f"[Applets][{new}]",
                )

        match = ID_FIELDS.match(line)

        if match:
            prefix, value = match.groups()

            value = re.sub(
                r"\b\d+\b",
                lambda m: str(
                    applet_map.get(int(m.group()), int(m.group()))
                ),
                value,
            )

            line = prefix + value + "\n"

        output.append(line)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = CONFIG.with_name(CONFIG.name + f".backup-{timestamp}")

    shutil.copy2(CONFIG, backup)

    merged = destination.rstrip("\n") + "\n\n" + "".join(output)

    temp = CONFIG.with_name(CONFIG.name + ".tmp")
    temp.write_text(merged)
    os.chmod(temp, CONFIG.stat().st_mode & 0o777)
    os.replace(temp, CONFIG)

    print(f"Imported panel: {old_panel} -> {new_panel}")
    print(f"Remapped {len(applet_map)} applets")
    print(f"Backup: {backup}")
    print("Restart Plasma to load the imported configuration.")


if __name__ == "__main__":
    main()