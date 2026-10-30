"""Every request the server handles or a client sends is in Net.luau's REQUESTS.

Net.onRequest asserts on a name it doesn't know, and that assert stops the server's
service start where it happens (PC 2026-11-02: DenWing and four more were missing, so
DenService and everything after it never started). Run by tools/verify.sh.

    python3 tools/tests/check_requests.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
net = (ROOT / "src/server/Net.luau").read_text(encoding="utf-8")
block = re.search(r"local REQUESTS: \{ \[string\]: number \} = \{(.*?)\n\}", net, re.S)
if block is None:
    sys.exit("check_requests: no REQUESTS table in src/server/Net.luau")
known = set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", block.group(1), re.M))

used: dict[str, list[str]] = {}
patterns = [
    (ROOT / "src/server", re.compile(r'Net\.onRequest\(\s*"([A-Za-z0-9_]+)"')),
    (ROOT / "src/client", re.compile(r'ClientState\.request\(\s*"([A-Za-z0-9_]+)"')),
]
for folder, pattern in patterns:
    for path in folder.rglob("*.luau"):
        for name in pattern.findall(path.read_text(encoding="utf-8")):
            used.setdefault(name, []).append(str(path.relative_to(ROOT)))

missing = sorted(name for name in used if name not in known)
for name in missing:
    print(f"check_requests: {name} isn't in Net.luau's REQUESTS ({', '.join(sorted(set(used[name])))})")
if missing:
    sys.exit(1)
print(f"check_requests: OK ({len(used)} requests used, {len(known)} known)")
