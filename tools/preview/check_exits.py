"""Checks that the hub's ways out are open in the Terrain fill ops: the four tunnels
from the cavern out onto the sand, the twelve den doorways into the cavern, and the
oculus (owner, 2026-10-11: "ensure all exits from the den are clear and open"; the
tunnels had stopped inside the seamount's foot after it was widened for the dens).

    DUMP_ONLY=1 LUAU=<luau> bash tools/preview/run_world.sh <dir>
    python3 tools/preview/check_exits.py <dir>/world_ops.jsonl

Fills every op in order over sample points (the same rules Terrain:Fill* follow:
later ops overwrite earlier ones) and reports any rock left in a way out. Exit code 1
when one is blocked. The previews' Random isn't Roblox's, so jitter differs from the
game; the structure (radii, heights, which ops cut where) is the game's.
"""

import json
import math
import pathlib
import re
import sys

import numpy as np

HUB_RADIUS = 95
DEN_DEPTH = 34
DEN_FLOOR = 4
SEGMENTS = 24
TUNNEL_HEIGHT = 36
TUNNEL_RADIUS = TUNNEL_HEIGHT / 2 - 2
HEIGHT = 110
# The tube's reach, as Cave.luau carves it (World.hub.tunnelLength read from the config)
_world = (pathlib.Path(__file__).resolve().parents[2] / "src/shared/Config/World.luau").read_text()
TUNNEL_LENGTH = float(re.search(r"tunnelLength = (\d+)", _world).group(1))
WALL = float(re.search(r"wallThickness = (\d+)", _world).group(1))
REACH = HUB_RADIUS + WALL + TUNNEL_LENGTH + 10


def load(path):
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def fill(ops, pts):
    solid = np.zeros(len(pts), bool)
    for op in ops:
        c = np.array(op["center"])
        d = pts - c
        kind = op["kind"]
        if kind == "ball":
            inside = np.einsum("ij,ij->i", d, d) <= op["radius"] ** 2
        else:
            axes = op["axes"]
            right = np.array(axes[0]) if axes[0] else np.array([1.0, 0, 0])
            up = np.array(axes[1]) if axes[1] else np.array([0, 1.0, 0])
            look = np.array(axes[2]) if axes[2] else np.array([0, 0, -1.0])
            x, y, z = d @ right, d @ up, d @ look
            if kind == "block":
                s = op["size"]
                inside = (np.abs(x) <= s[0] / 2) & (np.abs(y) <= s[1] / 2) & (np.abs(z) <= s[2] / 2)
            else:  # cylinder: its axis is the frame's Y
                inside = (np.abs(y) <= op["height"] / 2) & (x * x + z * z <= op["radius"] ** 2)
        if not inside.any():
            continue
        solid[inside] = op["material"] != "Air"
    return solid


def radial(angle, r, y, side):
    out = np.array([math.cos(angle), 0, math.sin(angle)])
    right = np.cross(out, [0, 1, 0])
    return out * r + np.array([0, y, 0]) + right * side


def main():
    ops = load(sys.argv[1])
    blocked = []
    # Tunnels: segments 1, 7, 13, 19, from inside the wall to well out on the sand
    for segment in range(1, SEGMENTS + 1, 6):
        angle = (segment - 1) * 2 * math.pi / SEGMENTS
        pts, where = [], []
        # The whole tube, then 30 studs on past its mouth above the sand's dunes
        for r in np.arange(HUB_RADIUS - 6, REACH + 30, 2):
            for y in (5, 12, TUNNEL_RADIUS + 1, 24, 29) if r <= REACH else (14, TUNNEL_RADIUS + 1, 24, 29):
                for side in (-9, 0, 9):
                    pts.append(radial(angle, r, y, side))
                    where.append((r, y, side))
        solid = fill(ops, np.array(pts))
        hits = [where[i] for i in np.flatnonzero(solid)]
        name = f"tunnel {math.degrees(angle):.0f}°"
        if hits:
            rs = sorted({h[0] for h in hits})
            blocked.append(f"{name}: rock at r {rs[0]:.0f}..{rs[-1]:.0f} ({len(hits)} of {len(pts)} samples)")
        else:
            print(f"[exits] {name}: open from the cavern to its mouth at r {REACH:.0f} and on out")
    # Den doorways: from the room's middle out through the door into the cavern
    dens = [s for s in range(1, SEGMENTS + 1) if (s - 1) % 6 % 2 == 1]
    for n, segment in enumerate(dens, 1):
        angle = (segment - 1) * 2 * math.pi / SEGMENTS
        pts, where = [], []
        # (since 2026-10-16 a doorway is a shallow alcove to its den's portal, 9 studs
        # into the wall: Layout.doorFrame; the den itself is elsewhere)
        for r in np.arange(HUB_RADIUS - 8, HUB_RADIUS + 8, 1.5):
            for y in (DEN_FLOOR + 5, DEN_FLOOR + 11, DEN_FLOOR + 17):
                for side in (-5, 0, 5):
                    pts.append(radial(angle, r, y, side))
                    where.append((r, y, side))
        solid = fill(ops, np.array(pts))
        hits = [where[i] for i in np.flatnonzero(solid)]
        if hits:
            blocked.append(f"den {n} doorway: rock at {sorted(set(hits))[:4]}")
    if not any(b.startswith("den") for b in blocked):
        print(f"[exits] all {len(dens)} den doorways open")
    # The oculus, straight up through the roof
    pts = np.array([[0, y, 0] for y in np.arange(60, HEIGHT + 60, 2)] + [[10, y, 0] for y in np.arange(60, HEIGHT + 60, 2)])
    if fill(ops, pts).any():
        blocked.append("oculus: rock in the shaft")
    else:
        print("[exits] oculus open")
    for line in blocked:
        print(f"[exits] BLOCKED {line}")
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
