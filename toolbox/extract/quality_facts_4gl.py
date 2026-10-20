#!/usr/bin/env python3
"""Extractor A determinista (4GL): métricas → facts/quality.json.

ncloc por conteo directo (scc NO reconoce .4gl/.per — ver artifacts/scc-*.json
y AGENTS.md §2/§4.1) y complejidad como proxy cyclomatic (puntos de decisión
IF/CASE/WHEN/FOR/WHILE/INPUT/CONSTRUCT). Sin SonarQube: bugs/smells N/A.

Uso: quality_facts_4gl.py <repo-raíz> <facts-dir>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse4gl import find_sources, parse_program  # noqa: E402


def main():
    if len(sys.argv) != 3:
        sys.exit("Uso: quality_facts_4gl.py <repo-raíz> <facts-dir>")
    repo, facts_dir = sys.argv[1], sys.argv[2]
    os.makedirs(facts_dir, exist_ok=True)

    parsed = [parse_program(rel, lines) for rel, lines in find_sources(repo)]
    if not parsed:
        sys.exit("ERROR: no se encontraron fuentes .4gl/.per bajo src/")

    ncloc = sum(p["ncloc"] for p in parsed)
    complexity = sum(p["decision_count"] for p in parsed)
    biggest = sorted(parsed, key=lambda p: (-p["ncloc"], p["file"]))[:5]
    god_classes = [
        {"class": p["file"], "loc": p["ncloc"], "wmc": p["decision_count"]}
        for p in biggest
    ]
    evidence = [{"file": p["file"]} for p in sorted(parsed, key=lambda x: x["file"])[:3]]

    facts = {
        "measures": {"ncloc": ncloc, "complexity": complexity},
        "god_classes": god_classes,
        "tools": [{
            "name": "loc-by-extension (fallback scc)",
            "version": "scc no reconoce dialecto 4GL — conteo directo",
        }],
        "evidence": evidence,
    }
    out = os.path.join(facts_dir, "quality.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(facts, fh, ensure_ascii=False, indent=1, sort_keys=True)
    print(f"quality_facts_4gl: ncloc={ncloc}, complejidad={complexity} → {out}")


if __name__ == "__main__":
    main()
