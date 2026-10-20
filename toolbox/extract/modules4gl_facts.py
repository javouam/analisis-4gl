#!/usr/bin/env python3
"""Extractor A determinista (4GL): módulos e includes → facts/modules4gl.json.

Análogo 4GL del extinto jars_facts.py: en lugar de jars internos con clases,
inventario de módulos (programas y forms) con sus funciones, líneas,
relaciones GLOBALS-include (quién incluye a quién) y llamadas externas
(shell RUN / stored procedures). Contrato: toolbox/schemas/modules4gl.schema.json.

Uso: modules4gl_facts.py <repo-raíz> <facts-dir>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse4gl import find_sources, parse_program  # noqa: E402


def main():
    if len(sys.argv) != 3:
        sys.exit("Uso: modules4gl_facts.py <repo-raíz> <facts-dir>")
    repo, facts_dir = sys.argv[1], sys.argv[2]
    os.makedirs(facts_dir, exist_ok=True)

    programs = []
    for rel, lines in find_sources(repo):
        if rel.lower().endswith(".4gl"):
            programs.append(parse_program(rel, lines))
    programs.sort(key=lambda x: x["file"])

    if not programs:
        sys.exit("ERROR: no se encontraron fuentes .4gl bajo src/")

    included_by = {}  # archivo incluido -> [archivos que lo incluyen]
    modules = []
    for p in programs:
        includes = []
        for inc, line in p["includes"]:
            # El include referencia al archivo por nombre base
            target = next((q["file"] for q in programs
                           if os.path.basename(q["file"]) == os.path.basename(inc)), inc)
            includes.append({"file": os.path.basename(inc), "resolves_to": target})
            included_by.setdefault(target, []).append({"file": p["file"], "line": line})
        shells = [{"command": c[:120], "line": line} for c, line in p["runs"]]
        sps = sorted({sp for sp, _line in p["procedures"]})
        modules.append({
            "name": os.path.basename(p["file"]),
            "kind": "program" if p["has_main"] else "library",
            "functions": [{"name": n, "line": line} for n, line in p["functions"]],
            "reports": [n for n, _line in p["reports"]],
            "loc": p["loc"],
            "ncloc": p["ncloc"],
            "includes": includes,
            "shell_commands": shells,
            "stored_procedures_called": sps,
            "evidence": ([{"file": p["file"], "line": p["functions"][0][1]}] if p["functions"]
                         else [{"file": p["file"], "line": 1}]),
        })
    for m in modules:
        target = next((q["file"] for q in programs
                       if os.path.basename(q["file"]) == m["name"]), m["name"])
        m["included_by"] = [dict(x) for x in included_by.get(target, [])]

    facts = {
        "modules": modules,
        "counts": {
            "modules": len(modules),
            "libraries": sum(1 for m in modules if m["kind"] == "library"),
            "includes": sum(len(m["includes"]) for m in modules),
            "stored_procedures": sorted({sp for m in modules
                                         for sp in m["stored_procedures_called"]}),
            "shell_commands": sum(len(m["shell_commands"]) for m in modules),
        },
    }
    # 'resolves_to' no está en el contrato (additionalProperties false) — aplanar
    for m in modules:
        for inc in m["includes"]:
            inc.pop("resolves_to", None)

    out = os.path.join(facts_dir, "modules4gl.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(facts, fh, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"modules4gl_facts: {len(modules)} módulos → {out}")


if __name__ == "__main__":
    main()
