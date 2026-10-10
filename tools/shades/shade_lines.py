"""The skin lines (lines.json): which shades each fish gets, in what order, and each
one's tier. make_shades.py, render_shades.py, contact_sheet.py and pack_shades.py all
read the per-fish lists from here, so a fish only ever gets its own line plus the
universal skins (catch track, weekly, trophies and treasure).

    import shade_lines
    shade_lines.shades("Nibbler")   # ["NibPercula", ..., "Prismatic", "CatchGolden", ...]
"""

from __future__ import annotations

import json
import pathlib

HERE = pathlib.Path(__file__).parent
LINES = json.loads((HERE / "lines.json").read_text())


def fishes() -> list[str]:
    """The fish with a line, in lines.json order."""
    return list(LINES["fish"])


def entries(fish: str) -> list[dict]:
    """Every shade a fish gets, in order: its own line, then every universal skin."""
    return list(LINES["fish"].get(fish, {}).get("line", [])) + list(LINES["universal"])


def shades(fish: str) -> list[str]:
    return [e["id"] for e in entries(fish)]


def tier(fish: str, shade: str) -> str:
    for e in entries(fish):
        if e["id"] == shade:
            return e.get("tier", "")
    return ""


def universal(shade: str) -> bool:
    return any(e["id"] == shade for e in LINES["universal"])
