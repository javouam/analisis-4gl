#!/usr/bin/env python3
"""Extractor A determinista (4GL): grafo de llamadas → facts/callgraph.json.

Nodos: archivos fuente (kind heredado del inventario si existe).
Aristas: archivo → archivo donde está DEFINIDA la función invocada
(resolución por nombre: en 4GL las funciones son globales por nombre).
Refs: evidence file:line de cada invocación (gate/schema exige ≥1).

Llamadas reconocidas:
- I4GL: CALL f( ... ) · START REPORT r · REPORT TO r (sintaxis clásica)
- ABL:  RUN p [(.p)] · p( ) invocación de FUNCTION

Las llamadas no resolubles (builtins del runtime: length, upshift, ...) se
descartan silenciosamente — el objetivo es el grafo ENTRE módulos propios.

Uso: callgraph_facts_4gl.py <repo-raíz> <facts-dir>
"""
import json
import os
import re
import sys

I4GL_EXT = (".4gl", ".per")
ABL_EXT = (".p", ".w", ".a", ".abl")

RE_DEF_I4GL = re.compile(r'^\s*(?:FUNCTION|REPORT)\s+(\w+)', re.I)
RE_DEF_ABL = re.compile(r'^\s*(?:PROCEDURE|FUNCTION)\s+(\w+)', re.I)
RE_CALL_I4GL = re.compile(r'^\s*CALL\s+(\w+)\s*\(', re.I)
RE_START_REPORT = re.compile(r'^\s*(?:START\s+REPORT|REPORT\s+TO)\s+(\w+)', re.I)
RE_RUN_ABL = re.compile(r'^\s*RUN\s+([\w.]+)', re.I)
RE_CALL_ABL_FUNC = re.compile(r'^\s*(\w+)\s*\(\s*[\w)]')  # invocación suelta
RE_MAIN = re.compile(r'^\s*MAIN\b', re.I)


def read_lines(path):
    try:
        with open(path, encoding="latin-1", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError as e:
        sys.exit(f"ERROR leyendo {path}: {e}")


def main():
    if len(sys.argv) != 3:
        sys.exit("Uso: callgraph_facts_4gl.py <repo-raíz> <facts-dir>")
    repo, facts_dir = sys.argv[1], sys.argv[2]
    src = os.path.join(repo, "src")
    if not os.path.isdir(src):
        sys.exit(f"ERROR: no existe {src}")
    os.makedirs(facts_dir, exist_ok=True)

    sources = []  # (relpath, ext, lines)
    for root, _dirs, files in os.walk(src):
        for name in sorted(files):
            ext = os.path.splitext(name)[1].lower()
            if ext in I4GL_EXT + ABL_EXT and ext != ".per":
                path = os.path.join(root, name)
                sources.append((os.path.relpath(path, repo), ext, read_lines(path)))
    if not sources:
        sys.exit("ERROR: sin archivos 4GL ejecutables bajo src/")

    # 1) mapa nombre-función → archivo que la define
    defined = {}
    for rel, _ext, lines in sources:
        for ln in lines:
            m = RE_DEF_I4GL.match(ln) or RE_DEF_ABL.match(ln)
            if m:
                defined.setdefault(m.group(1).lower(), rel)

    # 2) recolectar llamadas con evidence
    edge_refs = {}  # (from_rel, to_rel) -> {file:line,...}
    for rel, ext, lines in sources:
        for i, ln in enumerate(lines, 1):
            callees = []
            m = RE_CALL_I4GL.match(ln)
            if m:
                callees.append(m.group(1))
            m = RE_START_REPORT.match(ln)
            if m:
                callees.append(m.group(1))
            if ext in ABL_EXT:
                m = RE_RUN_ABL.match(ln)
                if m:
                    callees.append(m.group(1).rsplit(".", 1)[0])
            for callee in callees:
                target = defined.get(callee.lower())
                if target and target != rel:
                    edge_refs.setdefault((rel, target), []).append({"file": rel, "line": i})

    # 3) nodos (kind desde inventory.json si ya existe)
    kinds = {}
    inv_path = os.path.join(facts_dir, "inventory.json")
    if os.path.isfile(inv_path):
        try:
            with open(inv_path, encoding="utf-8") as fh:
                for mod in json.load(fh).get("app", {}).get("modules", []):
                    kinds[mod.get("name")] = mod.get("kind")
        except (OSError, ValueError):
            pass
    nodes = []
    for rel, _ext, lines in sources:
        nfun = sum(1 for ln in lines if (RE_DEF_I4GL.match(ln) or RE_DEF_ABL.match(ln)))
        node = {"name": rel, "functions": nfun}
        if rel in kinds:
            node["kind"] = kinds[rel]
        nodes.append(node)

    edges = [{"from": frm, "to": to, "refs": sorted(refs, key=lambda r: (r["file"], r.get("line", 0)))}
             for (frm, to), refs in sorted(edge_refs.items())]

    # 4) hubs: funciones más invocadas entre módulos
    callers_by_target = {}
    for e in edges:
        callers_by_target.setdefault(e["to"], set()).add(e["from"])
    most_called = [{"module": t, "callers": len(cs)} for t, cs in
                   sorted(callers_by_target.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:10]]

    facts = {
        "dialect": "informix-4gl/progress-abl",
        "nodes": nodes,
        "edges": edges,
        "stats": {
            "nodes": len(nodes),
            "edges": len(edges),
            "functions_defined": len(defined),
            "most_called": most_called,
        },
    }
    out = os.path.join(facts_dir, "callgraph.json")
    try:
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(facts, fh, indent=1, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
    except OSError as e:
        sys.exit(f"ERROR escribiendo {out}: {e}")
    print(f"facts/callgraph.json: {len(nodes)} nodos · {len(edges)} aristas "
          f"inter-módulo · {len(defined)} funciones definidas")


if __name__ == "__main__":
    main()
