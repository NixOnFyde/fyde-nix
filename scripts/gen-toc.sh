#!/usr/bin/env bash
set -euo pipefail

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

TOC_MARKER_START = "<!-- toc -->"
TOC_MARKER_END = "<!-- /toc -->"

CODE_BLOCK_PATTERN = re.compile(r"^\s*(```|~~~)")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")

def generate_slug(heading_title, seen_slugs):
    slug = heading_title.strip().lower().replace("`", "")
    slug = re.sub(r"[^\w\- ]", "", slug)
    slug = slug.replace(" ", "-")

    occurrences = seen_slugs.get(slug, 0)
    seen_slugs[slug] = occurrences + 1

    return slug if occurrences == 0 else f"{slug}-{occurrences}"

for file_path_arg in sys.argv[1:]:
    target_path = Path(file_path_arg)
    file_lines = target_path.read_text(encoding="utf-8").splitlines()

    try:
        toc_start_index = file_lines.index(TOC_MARKER_START)
        toc_end_index = file_lines.index(TOC_MARKER_END, toc_start_index)
    except ValueError:
        sys.exit(f"{target_path}: missing {TOC_MARKER_START} / {TOC_MARKER_END} block")

    inside_code_block = False
    seen_slugs = {}
    collected_headings = []

    # Extract markdown headings outside of fenced code blocks
    for line in file_lines:
        if CODE_BLOCK_PATTERN.match(line):
            inside_code_block = not inside_code_block
            continue

        if inside_code_block:
            continue

        heading_match = HEADING_PATTERN.match(line)
        if heading_match:
            heading_level = len(heading_match.group(1))
            heading_title = heading_match.group(2)
            collected_headings.append(
                (heading_level, heading_title, generate_slug(heading_title, seen_slugs))
            )

    if not collected_headings:
        toc_lines = []
    else:
        min_heading_level = min(level for level, _, _ in collected_headings)
        toc_lines = [
            f"{'  ' * (level - min_heading_level)}- [{title}](#{slug})"
            for level, title, slug in collected_headings
        ]

    # Splice generated TOC between markers
    updated_file_lines = (
        file_lines[: toc_start_index + 1]
        + toc_lines
        + file_lines[toc_end_index:]
    )

    target_path.write_text("\n".join(updated_file_lines) + "\n", encoding="utf-8")

    print(f"{target_path}: {len(collected_headings)} headings")
PY
