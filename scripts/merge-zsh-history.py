#!/usr/bin/env python3
"""Merge zsh history files into one, ordered by timestamp.

Usage: merge-zsh-history.py OUT IN...

Entries are extended-history records (": <start>:<elapsed>;<command>"),
including commands continued over several lines with a trailing backslash.
Lines from before EXTENDED_HISTORY have no timestamp and keep their place
after the entry before them. Exact duplicates are dropped. Bytes are kept as
they are (zsh's metafied encoding included). OUT may be one of the inputs;
missing inputs are skipped. OUT is written atomically with mode 600.
"""

import os
import re
import sys
import tempfile

HEADER = re.compile(rb"^: (\d+):\d+;")


def entries(path):
    """Yield (timestamp, entry bytes) for each history entry in path."""
    with open(path, "rb") as f:
        lines = f.read().split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    ts = 0
    current = []
    for line in lines:
        if current and current[-1].endswith(b"\\"):
            current.append(line)
            continue
        if current:
            yield ts, b"\n".join(current)
        m = HEADER.match(line)
        if m:
            ts = int(m.group(1))
        current = [line]
    if current:
        yield ts, b"\n".join(current)


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    out, inputs = argv[1], argv[2:]

    merged = []
    for path in inputs:
        if os.path.exists(path):
            merged.extend(entries(path))
    # Stable: equal timestamps keep their input order.
    merged.sort(key=lambda e: e[0])

    seen = set()
    data = []
    for _, entry in merged:
        if entry not in seen:
            seen.add(entry)
            data.append(entry)

    directory = os.path.dirname(os.path.abspath(out))
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".history.")
    with os.fdopen(fd, "wb") as f:
        f.write(b"\n".join(data) + (b"\n" if data else b""))
    os.chmod(tmp, 0o600)
    os.replace(tmp, out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
