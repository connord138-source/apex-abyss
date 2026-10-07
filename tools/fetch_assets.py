"""
Download every 3D model listed in tools/assets_manifest.json into assets/.

    python tools/fetch_assets.py            # downloads what's new or whose link changed
    python tools/fetch_assets.py --force    # re-download everything

Each file's link is remembered in assets/.sources.json, so a model that was replaced
in the manifest (a new link) is downloaded again.

Layout it creates (all gitignored):
    assets/glb/species/<SpeciesId>.glb   -> rig with tools/blender/rig_fish.py, then import
    assets/glb/prey/<PreyId>.glb         -> rig with tools/blender/rig_fish.py, then import
    assets/glb/props/<Name>.glb          -> ReplicatedStorage.WorldProps (no rig)
    assets/glb/food/<Name>.glb           -> ReplicatedStorage.WorldProps (no rig)
    assets/glb/vendors/<Name>.glb        -> ReplicatedStorage.WorldProps (no rig)
"""

import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
GROUPS = ("species", "prey", "props", "food", "vendors")

manifest = json.loads((ROOT / "tools/assets_manifest.json").read_text())
force = "--force" in sys.argv
SOURCES = ROOT / "assets" / ".sources.json"
sources = json.loads(SOURCES.read_text()) if SOURCES.exists() else {}
failed = []
count = 0
for group in GROUPS:
    out_dir = ROOT / "assets" / "glb" / group
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, url in manifest.get(group, {}).items():
        out = out_dir / f"{name}.glb"
        key = f"{group}/{name}.glb"
        if out.exists() and not force and sources.get(key) == url:
            continue
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "apex-abyss-assets"})
            with urllib.request.urlopen(request, timeout=120) as response:
                out.write_bytes(response.read())
            sources[key] = url
            count += 1
            print(f"fetched {key}")
        except Exception as error:  # noqa: BLE001
            failed.append((key, str(error)))
SOURCES.write_text(json.dumps(sources, indent=1, sort_keys=True) + "\n")
print(f"{count} file(s) downloaded")
for key, error in failed:
    print(f"FAILED {key}: {error}")
if failed:
    sys.exit(1)
