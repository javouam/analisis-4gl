#!/usr/bin/env python3
"""Renderer determinista del toolbox de análisis legacy.

facts/*.json + templates/*.j2 → documentos (md/html). Garantías:
- Sin fechas ni aleatoriedad: el contexto inyecta SOLO campos estables
  de run-metadata.json (templates_version, artifact_hash, client,
  language). La fecha de corrida NO existe aquí.
- Orden estable: los hechos llegan ordenados por los extractores;
  las plantillas no reordenan.
- --check: re-renderiza y compara byte a byte contra el output;
  exit 1 si difiere (gate de CI / determinismo).

Ejecución (contenedor, sin instalar nada en el host):
  docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
    bash -c "pip -q install jinja2 && python3 toolbox/render.py \
             --facts facts --templates toolbox/templates --out docs-generated"

Uso: render.py --facts FACTS --templates TPL --out OUT [--check] [--meta run-metadata.json]
"""
import argparse
import json
import os
import shutil
import sys
import tempfile

try:
    from jinja2 import Environment, FileSystemLoader, select_autoescape
except ImportError:
    sys.exit("ERROR: falta jinja2 (usar contenedor python:3.12-slim con pip install jinja2)")

STABLE_META = ("templates_version", "artifact_hash", "client", "language")
MISSING = "N/D"


def load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        raise SystemExit(f"ERROR leyendo {path}: {e}")


def load_facts(facts_dir):
    if not os.path.isdir(facts_dir):
        raise SystemExit(f"ERROR: no existe el directorio de facts {facts_dir}")
    try:
        names = sorted(os.listdir(facts_dir))
    except OSError as e:
        raise SystemExit(f"ERROR listando {facts_dir}: {e}")
    facts = {}
    for name in names:
        if name.endswith(".json"):
            facts[name[:-5]] = load_json(os.path.join(facts_dir, name))
    return facts


def load_meta(meta_path):
    if not meta_path or not os.path.exists(meta_path):
        return {}
    meta = load_json(meta_path)
    return {k: meta[k] for k in STABLE_META if k in meta}


def render_tree(facts, meta, templates_dir, out_dir):
    env = Environment(
        loader=FileSystemLoader(templates_dir),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
        autoescape=select_autoescape(enabled_extensions=("html", "htm", "xml"),
                                     default_for_string=False, default=False),
    )
    ctx = {"f": facts, "meta": meta, "nd": MISSING}
    written = []
    for root, _dirs, files in os.walk(templates_dir):
        for name in sorted(files):
            if not name.endswith(".j2"):
                continue
            rel = os.path.relpath(os.path.join(root, name), templates_dir)
            target_rel = rel[:-3]
            tpl = env.get_template(rel.replace(os.sep, "/"))
            out_path = os.path.join(out_dir, target_rel)
            try:
                os.makedirs(os.path.dirname(out_path) or out_dir, exist_ok=True)
                with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(tpl.render(**ctx))
            except OSError as e:
                raise SystemExit(f"ERROR escribiendo {out_path}: {e}")
            written.append(target_rel)
    return sorted(written)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--facts", required=True)
    ap.add_argument("--templates", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--meta", default="run-metadata.json")
    ap.add_argument("--check", action="store_true",
                    help="tras renderizar, re-renderiza y verifica byte-identical")
    args = ap.parse_args()

    facts = load_facts(args.facts)
    meta = load_meta(args.meta)
    written = render_tree(facts, meta, args.templates, args.out)
    print(f"render: {len(written)} documentos → {args.out}")

    if args.check:
        tmp = tempfile.mkdtemp(prefix="render-check-")
        try:
            render_tree(facts, meta, args.templates, tmp)
            bad = []
            for rel in written:
                try:
                    with open(os.path.join(args.out, rel), "rb") as a, \
                         open(os.path.join(tmp, rel), "rb") as b:
                        if a.read() != b.read():
                            bad.append(rel)
                except OSError as e:
                    bad.append(f"{rel} ({e})")
            if bad:
                print("DETERMINISMO ROTO en:", ", ".join(bad))
                sys.exit(1)
            print(f"determinismo OK: re-render byte-identical ({len(written)} documentos)")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
