"""Bundles ModuleScripts into one chunk for the plain luau CLI (run_start.sh).

    python3 -S luau_bundle.py <repo src dir> <entry> [<entry> ...] > chunk.luau

Each entry is `shared/Name` or `server/Name`. Every module they require (script.Parent.X,
script.Parent.Parent.X or ReplicatedStorage.Shared.X), and every Config module they
read (Config.X), is wrapped as a local in dependency order, its requires turned into
those locals; `Config` is a table of the Config modules found, and `SERVICES` (what
cave_stub.luau's `game:GetService` answers) holds the shared ones, so
`game:GetService("ReplicatedStorage").Shared.X` resolves too. Modules added later
(a new server module Shelf.luau requires) come along by themselves. Put the stubs
(roblox_stub.luau, cave_stub.luau) before the chunk and the driver after it.
"""
import os
import re
import sys

SRC = os.path.abspath(sys.argv[1])
ENTRIES = sys.argv[2:]
REQUIRE = re.compile(r"require\((script\.Parent\.Parent|script\.Parent|ReplicatedStorage\.Shared)\.([A-Za-z]+)\)")
CONFIG_USE = re.compile(r"\bConfig\.([A-Z][A-Za-z]+)")

order = []  # (kind, name)
seen = set()
configs = []


def path_of(kind, name):
    if kind == "config":
        return os.path.join(SRC, "shared", "Config", name + ".luau")
    return os.path.join(SRC, kind, name + ".luau")


def text_of(kind, name):
    with open(path_of(kind, name)) as f:
        return f.read()


def need_config(name):
    if name in configs or not os.path.exists(path_of("config", name)):
        return
    configs.append(name)


def visit(kind, name):
    if (kind, name) in seen:
        return
    seen.add((kind, name))
    text = text_of(kind, name)
    for use in CONFIG_USE.findall(text):
        need_config(use)
    for prefix, dep in REQUIRE.findall(text):
        if dep == "Config":
            continue
        if prefix == "ReplicatedStorage.Shared":
            visit("shared", dep)
        elif prefix == "script.Parent":
            visit(kind, dep)
        else:  # script.Parent.Parent from a server Service: a server module
            visit("server", dep)
    order.append((kind, name))


for entry in ENTRIES:
    kind, name = entry.split("/")
    visit(kind, name)
# A config's own uses (Config.World inside Biomes, ...) and the ones the shared
# modules read through `local World = Config.World`
for name in list(configs):
    for use in CONFIG_USE.findall(text_of("config", name)):
        need_config(use)


def body(kind, name):
    text = text_of(kind, name)
    text = re.sub(r"^--!strict\s*\n", "", text)
    text = REQUIRE.sub(lambda m: "Config" if m.group(2) == "Config" else local_of(m.group(2)), text)
    return text


def local_of(name):
    return "M_" + name


out = []
for name in configs:
    out.append(f"local Config_{name} = (function()\n{body('config', name)}\nend)()")
out.append("local Config = {" + ", ".join(f"{n} = Config_{n}" for n in configs) + "}")
out.append("local Shared = { Config = Config }")
out.append("SERVICES = { ReplicatedStorage = { Shared = Shared } }")
for kind, name in order:
    if kind != "shared":
        continue
    out.append(f"local {local_of(name)} = (function()\n{body(kind, name)}\nend)()")
    out.append(f"Shared.{name} = {local_of(name)}")
for kind, name in order:
    if kind == "shared":
        continue
    out.append(f"local {local_of(name)} = (function()\n{body(kind, name)}\nend)()")
print("\n".join(out))
