"""Validate the kernel patch set in pkgs/linux-fydetab.

Checked for each patch file:
  * hunk headers agree with their bodies (and bodies contain no blank lines,
    which `patch` rejects),
  * the diffstat numbers match the diff itself,
  * every patch is referenced by package.nix, and every patch
    package.nix references exists.

Usage: check-kernel-patches.py [patch-directory]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
FILE_HEADER = re.compile(r"^(?:\+\+\+|---) ")
INSERTIONS = re.compile(r"(\d+) insertions?\(\+\)")
DELETIONS = re.compile(r"(\d+) deletions?\(-\)")
DIFFSTAT = re.compile(
    r"^\s*(?P<path>\S.*?)\s*\|\s*(?P<total>\d+)\s*(?P<bar>[+\-]*)\s*$"
)


def check_diff(path: Path, text: str) -> list[str]:
    """Check one patch file; returns a list of human readable problems."""
    problems: list[str] = []

    if not text.endswith("\n"):
        problems.append("file does not end with a newline (patch needs one)")

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    inserts = sum(
        1 for line in lines if line.startswith("+") and not line.startswith("+++")
    )
    deletes = sum(
        1 for line in lines if line.startswith("-") and not line.startswith("---")
    )

    i, hunks = 0, 0
    while i < len(lines):
        match = HUNK.match(lines[i])
        if not match:
            i += 1
            continue

        hunks += 1
        at = i + 1
        want_old, want_new = int(match.group(2) or 1), int(match.group(4) or 1)
        i += 1
        seen_old = seen_new = 0

        while (seen_old < want_old or seen_new < want_new) and i < len(lines):
            line = lines[i]
            if line.startswith("@@ "):  # counts were wrong; next hunk already
                break
            if line.startswith("\\"):  # "\ No newline at end of file"
                i += 1
                continue
            if line.startswith("+"):
                seen_new += 1
            elif line.startswith("-"):
                seen_old += 1
            elif line.startswith(" "):
                seen_old += 1
                seen_new += 1
            else:
                problems.append(
                    "line %d: line starts with neither ' ', '+' nor '-' "
                    "(a blank line inside a hunk is not valid)" % (i + 1)
                )
                break
            i += 1

        if (seen_old, seen_new) != (want_old, want_new):
            problems.append(
                "line %d: hunk header is -%d +%d but the body holds -%d +%d lines"
                % (at, want_old, want_new, seen_old, seen_new)
            )
        elif i < len(lines):
            nxt = lines[i]
            if nxt[:1] in "+- " and not FILE_HEADER.match(nxt):
                problems.append(
                    "line %d: %r is left over after the hunk, so the header count "
                    "is too small" % (i + 1, nxt)
                )

    if hunks == 0:
        problems.append("no unified diff hunks found")

    claimed_ins = INSERTIONS.search(text)
    claimed_del = DELETIONS.search(text)
    if claimed_ins or claimed_del:
        want = (
            int(claimed_ins.group(1)) if claimed_ins else 0,
            int(claimed_del.group(1)) if claimed_del else 0,
        )
        if want != (inserts, deletes):
            problems.append(
                "diffstat claims %d insertions(+), %d deletions(-) but the diff has %d/%d"
                % (want[0], want[1], inserts, deletes)
            )

    for line in lines:
        entry = DIFFSTAT.match(line)
        if not entry:
            continue
        if int(entry.group("total")) != inserts + deletes:
            problems.append(
                "diffstat entry claims %s changed lines, the diff has %d"
                % (entry.group("total"), inserts + deletes)
            )
        bar = entry.group("bar")
        if len(bar) == inserts + deletes:  # otherwise git scaled the bar
            if (bar.count("+"), bar.count("-")) != (inserts, deletes):
                problems.append(
                    "diffstat bar shows %d insertions / %d deletions, the diff has %d/%d"
                    % (bar.count("+"), bar.count("-"), inserts, deletes)
                )

    return problems


def check_manifest(patch_dir: Path) -> list[str]:
    """Check that package.nix and the patch directory concur on what exists."""
    problems: list[str] = []
    package_nix = patch_dir / "package.nix"
    if not package_nix.is_file():
        return ["%s is missing, cannot check the patch list" % package_nix.name]

    referenced = {
        name
        for name in re.findall(r"\./([0-9A-Za-z._-]+\.patch)", package_nix.read_text())
    }
    on_disk = {entry.name for entry in patch_dir.glob("*.patch")}

    for name in sorted(on_disk - referenced):
        problems.append(
            "%s: not referenced by package.nix, so it is never applied" % name
        )
    for name in sorted(referenced - on_disk):
        problems.append("%s: referenced by package.nix but missing from repo" % name)

    return problems


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        patch_dir = Path(argv[1])
    else:
        patch_dir = Path(__file__).resolve().parent.parent / "pkgs" / "linux-fydetab"

    if not patch_dir.is_dir():
        print("error: %s is not a directory" % patch_dir, file=sys.stderr)
        return 2

    patches = sorted(patch_dir.glob("*.patch"))
    if not patches:
        print("error: no *.patch files in %s" % patch_dir, file=sys.stderr)
        return 2

    problems = []
    for patch in patches:
        for problem in check_diff(patch, patch.read_text(errors="surrogateescape")):
            problems.append("%s: %s" % (patch.name, problem))
    problems.extend(check_manifest(patch_dir))

    for problem in problems:
        print("ERROR: %s" % problem)
    if problems:
        print("\n%d problem(s) in %s" % (len(problems), patch_dir))
        return 1

    print(
        "kernel patch check: %d patches in %s are consistent "
        "(hunks, diffstat, package.nix)" % (len(patches), patch_dir)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
