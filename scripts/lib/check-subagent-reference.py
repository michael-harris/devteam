#!/usr/bin/env python3
"""Check whether a literal `subagent_type: "<agent_id>"` (or `=`) reference to
agent_id exists in any *.md file under the given search directories, other
than exclude_file itself, with HTML comments stripped first so an
"anti-pattern, do NOT do this" example quoting the id isn't miscounted as a
live caller.

Used by scripts/validate-agent-wiring.sh -- kept as a standalone file rather
than an inline heredoc so the regex's mix of single/double quote characters
never has to survive nested bash quoting.

Usage: check-subagent-reference.py <agent_id> <exclude_file> <search_dir>...
Prints one matching file path per line (empty output = no match found).
"""
import sys
import re
import glob

agent_id = sys.argv[1]
exclude_file = sys.argv[2]
search_dirs = sys.argv[3:]

quote = "'" + '"'
pattern = re.compile(r"subagent_type[:=]\s*[" + quote + "]" + re.escape(agent_id) + r"[" + quote + "]")

found = []
for d in search_dirs:
    for path in glob.glob(d + "/**/*.md", recursive=True):
        if path == exclude_file:
            continue
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except OSError:
            continue
        stripped = re.sub(r"<!--.*?-->", "", content, flags=re.DOTALL)
        if pattern.search(stripped):
            found.append(path)

print("\n".join(found))
