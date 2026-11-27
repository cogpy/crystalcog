#!/usr/bin/env python3
"""Fail if any workflow installs a Crystal older than the supported floor.

src/cogserver/cogserver.cr reopens HTTP::WebSocket and calls private stdlib
methods (do_ping) that exist in Crystal 1.20 but not in 1.12-1.14. The scheduled
workflows that still pinned 1.12-1.14 failed to compile it on 2026-11-27.
"""
import pathlib
import re
import sys

FLOOR = (1, 20, 1)
ROOT = pathlib.Path(__file__).resolve().parents[2] / ".github" / "workflows"
# Version literals that follow a crystal key, image tag or CRYSTAL_VERSION.
PATTERNS = [
    re.compile(r"""crystal(?:_version|-version)?\s*:\s*\[?([^\n#]*)""", re.I),
    re.compile(r"CRYSTAL_VERSION\s*:\s*([^\n#]*)"),
    re.compile(r"default:\s*'(\d+\.\d+\.\d+)'"),
    re.compile(r"crystallang/crystal:(\d+\.\d+(?:\.\d+)?)"),
    re.compile(r"\|\|\s*'(\d+\.\d+\.\d+)'"),
]
VERSION = re.compile(r"\b1\.(\d+)(?:\.(\d+))?\b")


def versions(line):
    found = {}
    for pattern in PATTERNS:
        match = pattern.search(line)
        if match:
            for v in VERSION.finditer(match.group(1)):
                # A bare "1.20" floats to the latest 1.20.x, so it meets the floor.
                patch = int(v.group(2)) if v.group(2) else 999
                found[v.group(0)] = (1, int(v.group(1)), patch)
    for text, parsed in found.items():
        yield parsed, text


def main():
    bad = []
    for path in sorted(ROOT.glob("*.yml")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for parsed, text in versions(line):
                if parsed < FLOOR:
                    bad.append(f"{path.name}:{number}: Crystal {text} is below 1.20.1")
    if bad:
        print("\n".join(bad))
        return 1
    print("all workflow Crystal pins are >= 1.20.1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
