#!/usr/bin/env python3
"""Extractor A determinista (4GL): fuentes .4gl/.per → facts/inventory.json.

Reemplaza a inventory_facts.py (Java EE) para stack 4GL: en lugar de
descriptores EAR/WAR/SBOM, parsea DATABASE/MAIN/FUNCTION/REPORT/MENU/
COMMAND/GLOBALS de las fuentes. Evidencia file:line por hecho.

Uso: inventory_facts_4gl.py <repo-raíz> <facts-dir>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse4gl import RE_MAIN, find_sources, parse_program, read_source  # noqa: E402


def main():
    if len(sys.argv) != 3:
        sys.exit("Uso: inventory_facts_4gl.py <repo-raíz> <facts-dir>")
    repo, facts_dir = sys.argv[1], sys.argv[2]
    os.makedirs(facts_dir, exist_ok=True)

    programs, forms = [], []
    for rel, lines in find_sources(repo):
        parsed = parse_program(rel, lines)
        (programs if rel.lower().endswith(".4gl") else forms).append(parsed)

    if not programs and not forms:
        sys.exit("ERROR: no se encontraron fuentes .4gl/.per bajo src/")

    databases = {}
    evidence = []
    modules = []
    counts = {
        "programs": len(programs),
        "forms": len(forms),
        "functions": 0,
        "reports": 0,
        "menus": 0,
        "menu_commands": 0,
        "lines_total": 0,
    }

    def first_lineMatching(p, regex):
        for i, ln in enumerate(read_source(os.path.join(repo, p["file"])), 1):
            if regex.search(ln):
                return i
        return 1

    for p in sorted(programs, key=lambda x: x["file"]):
        kind = "program" if p["has_main"] or p["functions"] else "shared-module"
        modules.append({
            "name": os.path.basename(p["file"]),
            "kind": kind,
            "entry": p["has_main"],
            "functions": len(p["functions"]),
        })
        counts["functions"] += len(p["functions"])
        counts["reports"] += len(p["reports"])
        counts["menus"] += len(p["menus"])
        counts["menu_commands"] += len(p["commands"])
        counts["lines_total"] += p["loc"]
        for db, line in p["databases"]:
            databases.setdefault(db, (p["file"], line))

    for p in sorted(forms, key=lambda x: x["file"]):
        modules.append({"name": os.path.basename(p["file"]), "kind": "form", "entry": False,
                        "functions": 0})
        counts["lines_total"] += p["loc"]

    # Evidencia: primer MAIN, cada DATABASE distinto, cada MENU, cada form
    for p in sorted(programs, key=lambda x: x["file"]):
        if p["has_main"]:
            evidence.append({"file": p["file"], "line": first_lineMatching(p, RE_MAIN)})
            break
    for db, (f, line) in sorted(databases.items()):
        evidence.append({"file": f, "line": line})
    for p in sorted(programs, key=lambda x: x["file"]):
        for _title, line in p["menus"]:
            evidence.append({"file": p["file"], "line": line})
    for p in sorted(forms, key=lambda x: x["file"]):
        evidence.append({"file": p["file"], "line": 1})

    facts = {
        "app": {
            "name": "AF009 — fuentes 4GL proyecto safre_af [inferencia: cabeceras]",
            "packaging": "4gl",
            "modules": modules,
            "evidence": evidence,
        },
        "stack": {
            "languages": ["informix-4gl"],
            "framework": "Informix 4GL (.4gl + forms .per)",
            "databases": sorted(databases.keys()),
        },
        "libs": [],
        "counts": counts,
    }

    out = os.path.join(facts_dir, "inventory.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(facts, fh, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"inventory_facts_4gl: {counts['programs']} programas, {counts['forms']} forms, "
          f"{counts['functions']} funciones → {out}")


if __name__ == "__main__":
    main()
