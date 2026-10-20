# Toolbox de análisis legacy — determinista por construcción

> Capa portable del método: **facts(JSON) + Jinja2 = documentos idénticos siempre**. Las skills `legacy-*` aportan el procedimiento: 5 de dominio versionadas en `.agents/skills/` del repo (viajan con el git); `legacy-analysis-bootstrap` es global en pi (arranca repos de clientes nuevos). Este toolbox aporta los contratos (schemas), la plantilla única (templates versionados), los extractores deterministas, los gates y el workflow de orquestación. Lo específico del cliente vive en `legacy-analysis.yaml` del repo.

## Capas y determinismo

| Capa | Responsable | Determinismo |
|---|---|---|
| A. Tooling/extractores | `extract/*.py` + docker (syft/trivy/vineflower/…) | Byte-idéntico por construcción (orden estable, sin fechas) |
| B. Hechos de análisis | agentes con skills `legacy-*` | Acotado: schema + evidencia + verificación adversarial; cache first-run-wins (no se re-ejecuta sin cambio de input) |
| C. Render | `render.py` + `templates/` | Byte-idéntico: re-render == commit (verificable con `--check`) |
| Metadatos | `run-metadata.json` (repo raíz) | Único lugar con fechas/hash de corrida — jamás dentro de facts |

## Uso

```bash
# 1) Extraer facts deterministas (fase A) — ejemplo CVEs
docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
  python3 toolbox/extract/vulns_to_facts.py artifacts facts

# 2) Gate: schemas + densidad de evidencia
docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
  bash -c "pip -q install jsonschema && python3 toolbox/gates/validate_facts.py facts"

# 3) Render determinista + verificación (salida a docs-generated/, gitignored)
docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
  bash -c "pip -q install jinja2 && python3 toolbox/render.py \
           --facts facts --templates toolbox/templates --out docs-generated --check"

# 4) Fábrica completa (workflow; árbol limpio):
workflow --scriptPath toolbox/workflows/legacy-analysis-factory.wf.js \
         --name fabrica-legacy --args '{"apps":["AF-009"]}'   # force:true re-analiza todo
```

El workflow procesa las apps secuencialmente (un checkpoint CRITICAL a la vez;
paralelismo interno en fase B) y pausa ante hallazgos CRITICAL confirmados
(`workflow_respond` para aprobar/rechazar). Extractores A cableados: vulns,
inventario, jars, calidad, arquitectura — los que fallen por insumos faltantes
quedan warn-only y fase B los cubre con skills.

## Estructura

```
toolbox/
├── schemas/      10 JSON Schemas — contrato de facts por dominio
├── templates/    plantilla ÚNICA versionada (v1): md + índice html
├── extract/      extractores deterministas fase A (trivy/osv→facts…)
├── gates/        validate_facts.py (schema + evidencia) — exit≠0 rompe el workflow
├── workflows/    legacy-analysis-factory.wf.js (orquestador pi-extensible-workflows)
└── facts/        seed local (los facts reales viven en <repo>/facts/)
```

## Reglas inviolables

1. **Los agentes nunca escriben documentos** — solo `facts/*.json` validables; el render es el único escritor de docs.
2. **Sin fechas ni ids aleatorios en facts** — la corrida se registra en `run-metadata.json` (raíz del repo).
3. **Toda afirmación lleva evidence `file:line`** — el gate la exige (sast/br/vulnerabilities).
4. **Contenedores `:ro`** para el repo; outputs root-owned → `docker run --rm -v "$PWD":/w busybox chown -R $(id -u):$(id -g) /w/<salida>`.
5. **Calibración**: `render(facts)` debe reproducir `golden_docs` (AF-009 = oracle inicial de la fábrica).

## Pendiente de materializar (roadmap)

- Extractores A restantes: inventory (descriptores+SBOM), jars (vineflower+conteos), quality (SonarQube API), architecture (deps/UML) — hoy cubiertos por skills en fase B.
- Templates v2: contratos layout/datos/mensajes (ya especados en SURA como markdown golden; derivar .j2).
- Checkpoint humano en workflow para hallazgos CRITICAL confirmados (gate + pausa).
