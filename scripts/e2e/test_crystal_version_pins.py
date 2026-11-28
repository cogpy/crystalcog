#!/usr/bin/env python3
"""Fail if any workflow installs a Crystal older than the supported floor.

src/cogserver/cogserver.cr reopens HTTP::WebSocket and calls private stdlib
methods (do_ping) that exist in Crystal 1.20 but not in 1.12-1.14. The scheduled
workflows that still pinned 1.12-1.14 failed to compile it on 2026-11-27.

Only Crystal pins are checked, so unrelated version literals are ignored:
  * any YAML key whose name contains "crystal" (crystal:, crystal-version:,
    CRYSTAL_VERSION:, CRYSTAL_ARM64_VERSION:, ...), including "|| 'x'" fallbacks
    and matrix lists in its value;
  * "default:" directly under an input whose name contains "crystal";
  * crystallang/crystal:<tag> container images anywhere.

Run with --self-test to check the matcher against known good and bad lines.
"""
import pathlib
import re
import sys

FLOOR = (1, 20, 1)
ROOT = pathlib.Path(__file__).resolve().parents[2] / ".github" / "workflows"

KEY = re.compile(r"^(\s*)(?:-\s+)?([\w.-]+)\s*:(?:\s+(.*))?$")
IMAGE = re.compile(r"crystallang/crystal:(\d+\.\d+(?:\.\d+)?)")
VERSION = re.compile(r"(?<![\w.])1\.(\d+)(?:\.(\d+))?(?![\w.])")


def strip_comment(text):
    return re.split(r"(?:^|\s)#", text, maxsplit=1)[0]


def parse(text):
    # A bare "1.20" floats to the latest 1.20.x, so it meets the floor.
    for v in VERSION.finditer(text):
        patch = int(v.group(2)) if v.group(2) else 999
        yield (1, int(v.group(1)), patch), v.group(0)


def scan(lines):
    """Yield (line number, parsed version, text) for every Crystal pin."""
    parents = []  # (indent, key) for keys whose value is a nested block
    for number, raw in enumerate(lines, 1):
        line = strip_comment(raw)
        if not line.strip():
            continue
        for v in IMAGE.finditer(line):
            for parsed, text in parse(v.group(1)):
                yield number, parsed, text
        match = KEY.match(line)
        if not match:
            continue
        indent, key, value = len(match.group(1)), match.group(2), match.group(3) or ""
        while parents and parents[-1][0] >= indent:
            parents.pop()
        parent = parents[-1][1] if parents else ""
        if "crystal" in key.lower() or (key == "default" and "crystal" in parent.lower()):
            if "crystallang/crystal:" not in value:
                for parsed, text in parse(value):
                    yield number, parsed, text
        if not value.strip():
            parents.append((indent, key))


def check(path):
    bad = []
    for number, parsed, text in scan(path.read_text().splitlines()):
        if parsed < FLOOR:
            bad.append(f"{path.name}:{number}: Crystal {text} is below 1.20.1")
    return bad


SELF_TEST = [
    # (snippet, expected number of findings below the floor)
    ("env:\n  CRYSTAL_VERSION: '1.20.1'\n", 0),
    ("env:\n  CRYSTAL_VERSION: '1.14.0'\n", 1),
    ("env:\n  CRYSTAL_ARM64_VERSION: '1.19.0'\n", 1),
    ("env:\n  CRYSTAL_ARM64_VERSION: '1.22.0'\n", 0),
    ("    with:\n      crystal: 1.12.1\n", 1),
    ("    with:\n      crystal: ${{ env.CRYSTAL_ARM64_VERSION }}\n", 0),
    ("      matrix:\n        crystal: [1.20.1, 1.13.0, latest]\n", 1),
    ("      matrix:\n        crystal: [1.20, latest]\n", 0),
    ("env:\n  CRYSTAL_VERSION: ${{ inputs.crystal_version || '1.14.0' }}\n", 1),
    ("inputs:\n  crystal_version:\n    description: x\n    default: '1.14.0'\n", 1),
    ("inputs:\n  crystal_version:\n    default: '1.20.1'\n", 0),
    ("inputs:\n  node_version:\n    default: '1.5.0'\n", 0),
    ("inputs:\n  crystal_version:\n    default: '1.20.1'\n  tool_version:\n    default: '1.2.0'\n", 0),
    ("env:\n  TOOL: ${{ inputs.tool || '1.2.0' }}\n", 0),
    ("    container: crystallang/crystal:1.14.0\n", 1),
    ("    container:\n      image: crystallang/crystal:1.13\n", 1),
    ("    run: docker run crystallang/crystal:1.20.1 crystal spec\n", 0),
    ("env:\n  # CRYSTAL_VERSION: '1.12.0'\n  CRYSTAL_VERSION: '1.20.1' # was 1.14.0\n", 0),
]


def self_test():
    failures = 0
    for snippet, expected in SELF_TEST:
        found = [p for _, p, _ in scan(snippet.splitlines()) if p < FLOOR]
        if len(found) != expected:
            failures += 1
            print(f"self-test FAIL: expected {expected}, got {len(found)}: {snippet!r}")
    print(f"self-test: {len(SELF_TEST) - failures}/{len(SELF_TEST)} cases passed")
    return 1 if failures else 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    root = pathlib.Path(argv[1]) if len(argv) > 1 else ROOT
    bad = []
    for path in sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml")):
        bad.extend(check(path))
    if bad:
        print("\n".join(bad))
        return 1
    print("all workflow Crystal pins are >= 1.20.1")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
