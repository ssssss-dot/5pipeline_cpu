"""Check the local RTL file list and named module connections."""

from pathlib import Path
import re
import sys


root = Path(__file__).resolve().parent
files = [root / name.strip() for name in (root / "rtl.f").read_text().splitlines() if name.strip()]
errors = []
sources = {}

for path in files:
    if not path.is_file():
        errors.append(f"missing file: {path}")
        continue
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    sources[path] = text

modules = {}
for path, text in sources.items():
    for match in re.finditer(r"\bmodule\s+(\w+)\s*(?:#\s*\([^;]*?\)\s*)?\((.*?)\)\s*;", text, flags=re.S):
        name, header = match.groups()
        if name in modules:
            errors.append(f"duplicate module: {name}")
        ports = set()
        for part in header.split(","):
            end = re.search(r"([A-Za-z_]\w*)\s*$", part)
            if end:
                ports.add(end.group(1))
        modules[name] = (path, ports)

for name, (path, ports) in modules.items():
    if not ports:
        errors.append(f"no ports parsed: {name} ({path})")

for path, text in sources.items():
    for instance_match in re.finditer(r"\b([A-Za-z_]\w*)(?:\s*#\s*\([^;]*?\)\s*|\s+)((?:u_|inst_)\w+)\s*\(", text, flags=re.S):
        module, instance = instance_match.groups()
        if module != "module" and module not in modules:
            errors.append(f"{path.name}: {instance} uses unavailable module {module}")
    for module, (_, ports) in modules.items():
        pattern = rf"\b{re.escape(module)}(?:\s*#\s*\([^;]*?\)\s*|\s+)((?:u_|inst_)\w+)\s*\((.*?)\)\s*;"
        for match in re.finditer(pattern, text, flags=re.S):
            instance, body = match.groups()
            connected = re.findall(r"\.([A-Za-z_]\w*)\s*\(", body)
            unknown = set(connected) - ports
            missing = ports - set(connected)
            duplicates = {port for port in connected if connected.count(port) > 1}
            for kind, names in (("unknown", unknown), ("missing", missing), ("duplicate", duplicates)):
                if names:
                    errors.append(f"{path.name}: {instance} ({module}) {kind} ports: {', '.join(sorted(names))}")

for top in ("cpu_top", "cpu_loader_top"):
    if top not in modules:
        errors.append(f"{top} module not found")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(files)} source files, {len(modules)} modules, named ports connected")
