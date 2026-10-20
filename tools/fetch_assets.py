"""
Download the game's 3D model bundles (tools/assets_manifest.json) into assets/.

    python tools/fetch_assets.py            # downloads bundles that are new or whose link changed
    python tools/fetch_assets.py --force    # re-download everything

Each bundle is a zip hosted on a durable link; it's unzipped into the folder the
manifest names. Links are remembered in assets/.sources.json, so a bundle that was
replaced in the manifest (a new link) is downloaded again.

What lands where (all gitignored):
    assets/fbx/species/<SpeciesId>.fbx   rigged fish  -> Studio: File > Import 3D -> ReplicatedStorage.FishModels
    assets/glb/prey/<PreyId>.glb         static prey  -> ReplicatedStorage.PreyModels
    assets/glb/props/<Name>.glb          props, food  -> ReplicatedStorage.WorldProps
tools/studio/organize_imports.luau files the imports after Studio brings them in.
"""

import hashlib
import io
import json
import pathlib
import sys
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

manifest = json.loads((ROOT / "tools/assets_manifest.json").read_text())
force = "--force" in sys.argv
SOURCES = ROOT / "assets" / ".sources.json"
SOURCES.parent.mkdir(parents=True, exist_ok=True)
sources = json.loads(SOURCES.read_text()) if SOURCES.exists() else {}
failed = []
count = 0
for name, bundle in manifest.get("bundles", {}).items():
    url = bundle["url"]
    into = ROOT / bundle["into"]
    if not force and sources.get(name) == url and into.exists():
        continue
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "apex-tide-assets"})
        with urllib.request.urlopen(request, timeout=600) as response:
            data = response.read()
        # A bundle that isn't the one screened is never unpacked (it could be an
        # older one with normal maps, or a skin that failed the screen)
        want = bundle.get("sha256")
        got = hashlib.sha256(data).hexdigest()
        if want and got != want:
            raise ValueError(f"sha256 {got[:8]} is not the manifest's {want[:8]}")
        into.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            archive.extractall(into)
            files = [n for n in archive.namelist() if not n.endswith("/")]
        sources[name] = url
        count += 1
        print(f"fetched {name}: {len(files)} file(s) -> {bundle['into']} (sha256 {got[:8]})")
    except Exception as error:  # noqa: BLE001
        failed.append((name, str(error)))
SOURCES.write_text(json.dumps(sources, indent=1, sort_keys=True) + "\n")
print(f"{count} bundle(s) downloaded")
for name, error in failed:
    print(f"FAILED {name}: {error}")
if failed:
    sys.exit(1)
