#!/usr/bin/env python3
"""Assert v1Migrate helm render: separate mark Job + parseable answers.toml."""
from pathlib import Path
import sys
import tomllib

text = Path(sys.argv[1]).read_text()
for doc in text.split("---"):
    if "kind: Job" in doc and "component: v1-migrate" in doc:
        if "name: migrate" not in doc:
            raise SystemExit("v1-migrate Job missing migrate container")
        if "name: mark" in doc:
            raise SystemExit("v1-migrate Job must not embed mark")
        break
else:
    raise SystemExit("v1-migrate Job missing")

answers: list[str] = []
grab = False
for line in text.splitlines():
    if line.startswith("  answers.toml:"):
        grab = True
        continue
    if grab:
        if line and not line.startswith(" "):
            break
        answers.append(line[4:] if line.startswith("    ") else line)
tomllib.loads("\n".join(answers))
print("v1 migrate render ok")
