#!/usr/bin/env python3
"""Print `<name>\t<tools>` for one agent markdown file's YAML frontmatter.

Both fields come from the frontmatter block between the two `---` lines,
never the filename -- name and tools can be empty strings if the field is
missing, which the caller (scripts/validate-agent-wiring.sh) treats as a
real defect rather than silently falling back to a filename-derived guess.

Usage: read-agent-frontmatter.py <file>
"""
import sys

path = sys.argv[1]
with open(path, encoding="utf-8", errors="ignore") as f:
    lines = f.read().splitlines()

name = ""
tools = ""
dash_count = 0
for line in lines:
    stripped = line.rstrip("\r")
    if stripped.strip() == "---":
        dash_count += 1
        if dash_count >= 2:
            break
        continue
    if dash_count != 1:
        continue
    if stripped.startswith("name:"):
        name = stripped[len("name:"):].strip().strip("'\"")
    elif stripped.startswith("tools:"):
        tools = stripped[len("tools:"):].strip()

print(f"{name}\t{tools}")
