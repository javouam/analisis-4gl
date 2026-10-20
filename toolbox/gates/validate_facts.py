#!/usr/bin/env python3
"""Gate de facts: valida facts/*.json contra toolbox/schemas/*.schema.json
y aplica reglas de densidad de evidencia.

Reglas de evidencia (deterministas):
- sast.findings[*].evidence  → no vacío
- br.rules[*].evidence       → no vacío
- vulnerabilities.items[*]   → al menos 1 source o evidence

Exit codes: 0 = OK, 1 = violación, 2 = error de entorno.

Uso (contenedor):
  docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
    bash -c "pip -q install jsonschema && python3 toolbox/gates/validate_facts.py facts"
"""
import json
import os
import sys

try:
    from jsonschema import Draft7Validator
except ImportError:
    sys.exit("ERROR: falta jsonschema (contenedor python:3.12-slim + pip install jsonschema)")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCHEMAS = os.path.join(REPO, "toolbox", "schemas")


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        print(f"ERROR leyendo {path}: {e}")
        sys.exit(2)


def main():
    facts_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "facts")
    if not os.path.isdir(facts_dir):
        print(f"ERROR: no existe {facts_dir}")
        sys.exit(2)

    violaciones = []
    hechos = 0
    try:
        nombres = sorted(os.listdir(facts_dir))
    except OSError as e:
        print(f"ERROR listando {facts_dir}: {e}")
        sys.exit(2)
    for name in nombres:
        if not name.endswith(".json"):
            continue
        key = name[:-5]
        facts = load(os.path.join(facts_dir, name))
        hechos += 1
        schema_path = os.path.join(SCHEMAS, key + ".schema.json")
        if os.path.exists(schema_path):
            schema = load(schema_path)
            errs = sorted(Draft7Validator(schema).iter_errors(facts), key=lambda e: e.path)
            for e in errs:
                violaciones.append(f"[schema] {name}: {'/'.join(map(str, e.path)) or '(raíz)'} — {e.message}")

    # Densidad de evidencia (por tipo)
    def check_evidence(fname, items, label):
        if not items:
            return
        for i, it in enumerate(items):
            ev = it.get("evidence") or []
            if not ev:
                violaciones.append(f"[evidencia] {fname}[{i}] ({label}): sin evidence file:line")

    sast = load(os.path.join(facts_dir, "sast.json")) if os.path.exists(os.path.join(facts_dir, "sast.json")) else {}
    check_evidence("sast.json", sast.get("findings"), "finding")
    br = load(os.path.join(facts_dir, "br.json")) if os.path.exists(os.path.join(facts_dir, "br.json")) else {}
    check_evidence("br.json", br.get("rules"), "regla")

    vul = load(os.path.join(facts_dir, "vulnerabilities.json")) if os.path.exists(os.path.join(facts_dir, "vulnerabilities.json")) else {}
    for i, it in enumerate(vul.get("items", [])):
        if not it.get("sources") and not it.get("evidence"):
            violaciones.append(f"[evidencia] vulnerabilities.json[{i}]: sin fuente ni evidence")

    if violaciones:
        print(f"GATE FALLA — {len(violaciones)} violación(es):")
        for v in violaciones:
            print("  " + v)
        sys.exit(1)
    print(f"GATE OK — {hechos} archivo(s) de facts validados, evidencia completa")


if __name__ == "__main__":
    main()
