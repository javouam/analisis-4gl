# PLAYBOOK 4GL — Réplica de la fábrica de análisis legacy sobre código 4GL

> Objetivo: producir para una aplicación **4GL** (ej. Informix 4GL `.4gl`/`.per`; Progress ABL `.p`/`.w`) el **mismo paquete de entregables** generado para AF-009 (Java EE), reutilizando la arquitectura facts→render de `toolbox/`.
> Etiquetas por paso: **[=]** idéntico al proceso Java · **[~]** adaptado · **[+]** nuevo/exclusivo 4GL.
>
> **Kit materializado y probado** (smoke-test end-to-end con fixture sintético): `tools/semgrep-4gl.yml` (8 reglas), `toolbox/extract/inventory_facts_4gl.py`, `toolbox/extract/callgraph_facts_4gl.py`, `toolbox/schemas/callgraph.schema.json`, `toolbox/templates/02-arquitectura/arquitectura.md.j2`, `toolbox/templates/05-modernizacion/modernizacion.md.j2`. Pipeline verificado: extractores → gate OK → render 9 docs byte-identical.

## Resultado esperado (espejo de AF-009)

```
docs/
├── 01-funcional/        casos de uso, reglas de negocio (BR-xxx con evidencia),
│                        catálogo de pantallas/forms, flujos de navegación,
│                        contratos de archivos batch, modelo de datos, mensajes
├── 02-arquitectura/     diagramas archify (HTML interactivo) + fuentes .puml/.mmd:
│                        componentes, flujo de negocio, data-flow seguridad, despliegue
├── 03-tecnica/          inventario (módulos/functions/reports/forms), stack runtime,
│                        métricas LOC/complejidad, navegación de código
├── 04-seguridad/        hallazgos por patrones priorizados, secrets (ofuscados)
├── 05-modernizacion/    README (brecha SDD + arquitectura objetivo) + specs/:
│                        casos-uso, reglas-negocio, modelo-datos, mensajes, layout-archivos
├── presentaciones/      analisis-<APP>.html (26 slides, ver Etapa 4)
│                        + catalogo-entregables-cliente.md
├── README.md            índice ejecutivo
└── preguntas-aclaraciones-<cliente>.md (+ xlsx de preguntas con el cliente)
```

`facts/synthesis.json` DEBE incluir `modernization_options` (alimenta 05) y `remediation` (alimenta 04 y la presentación).

---

## Etapa 0 — Bootstrap del repo

1. **[~]** Crear repo nuevo del cliente copiando del plantilla: `toolbox/`, `tools/` (scc, semgrep rules), `.agents/skills/legacy-*`, `AGENTS.md`. **NO copiar** `facts/`, `run-metadata.json`, `src/`, `input/`.
2. **[~]** Cargar el artefacto 4GL en `src/<APP>/` (SOLO LECTURA). Fuente `.4gl`/`.per` → copiar tal cual. Si llega compilado (`.4go`, r-code): documentar la limitación — no existe decompilador open source de bytecode 4GL (a diferencia de Vineflower/JVM).
3. **[~]** Crear `legacy-analysis.yaml` con **layout de 5 secciones**:
   ```yaml
   client: <cliente>
   language: es
   artifact: src/<APP>
   docs_layout: [01-funcional, 02-arquitectura, 03-tecnica, 04-seguridad, 05-modernizacion]
   presentations_dir: docs/presentaciones
   confidentiality: { secrets: obfuscate, distribution: private-repo-only }
   human_checkpoints: [critical-findings, parity-matrix, delivery]
   ```
4. **[+]** Sondeo preliminar → `AGENTS.md §2` (memoria de arranque de los agentes):
   ```bash
   find src -name '*.4gl' -o -name '*.per' | wc -l
   grep -rlE '^ *(MENU|MAIN|FUNCTION)' src | head    # entrypoints, menús, funciones
   grep -rE 'DATABASE|CONNECT TO' src | sort -u | head  # BDs que usa
   ```
5. **[=]** Commit inicial (árbol limpio).

## Etapa 1 — Fase A determinista (sin LLM) → `artifacts/` y facts semilla

6. **[=]** LOC/complejidad con `tools/scc` (Docker, salida JSON). Si el dialecto no se reconoce, conteo por extensión y anotarlo como limitación.
7. **[=]** Secrets con gitleaks (texto plano 4GL: credenciales en `CONNECT TO ... USER ... WITH PASSWORD`, rutas, URLs):
   ```bash
   docker run --rm -v "$PWD:/repo:ro" zricethezav/gitleaks:latest \
     detect --source /repo --no-git -r /repo/artifacts/gitleaks-$(date +%F).json
   ```
8. **[+]** Semgrep modo `generic` con reglas 4GL — **ya incluidas en `tools/semgrep-4gl.yml`** (8 reglas: credenciales en CONNECT/LET, SQL dinámico por concatenación con rastreo LET→PREPARE, RUN/OS-COMMAND con concatenación, DISPLAY de variables sensibles, pistas en comentarios; severidades [inferencia] a calibrar contra el código real). Correr → `artifacts/semgrep-4gl-$(date +%F).json`.
9. **[~]** SBOM/vulns: syft SOLO si el artefacto trae acompañantes (jars, scripts, binarios nativos). Documentar explícitamente: **el eje CVE-por-dependencia es N/A para el core 4GL** — la seguridad se sostiene en 7+8. No correr trivy/osv sobre lo propio.
10. **[+]** Extractores `toolbox/extract/` — **incluidos y probados**:
    - `inventory_facts_4gl.py`: parsea `FUNCTION`/`REPORT`/`MAIN`, forms `.per` (`SCREEN RECORD`), `MENU`→`COMMAND`, `DATABASE`/`CONNECT TO` → `facts/inventory.json` (packaging "4gl", dialecto detectado, evidence file:line; conserva enriquecimiento fase B en re-corridas)
    - `callgraph_facts_4gl.py`: aristas inter-módulo con refs `file:line` (`CALL`, `START REPORT`, `RUN` ABL) → `facts/callgraph.json` (valida contra `toolbox/schemas/callgraph.schema.json`; alimenta 02-arquitectura y la matriz de dependencias)
11. **[=]** Gate: `python3 toolbox/gates/validate_facts.py facts` → exit 0.

## Etapa 2 — Adaptar contrato (skills, schemas, templates)

12. **[~]** Schemas: `inventory.schema.json` con `packaging: "4gl"` y módulos `kind: function|report|form|menu`; sustituir `jars.schema.json` por schema de módulos/includes 4GL. Los demás (functional, br, usecases, sast, synthesis) se mantienen.
13. **[~]** Skills de dominio variantes `legacy-4gl-*`: inventory (sin descriptores EE), sast (pattern-based, sin decompilación), functional (flujos desde menús→programas→forms en vez de struts-config), synthesis y common casi intactas.
14. **[+]** Templates v2 del renderer para cubrir las 5 secciones (la v1 solo renderiza 01/03/04): `02-arquitectura/arquitectura.md.j2` y `05-modernizacion/modernizacion.md.j2` **ya incluidos y probados** (defensivos ante facts ausentes); derivar los restantes de los golden docs de AF-009.
15. **[=]** Prueba de humo: `render.py --facts facts --templates toolbox/templates --out docs-generated --check` → exit 0.

## Etapa 3 — Lanzar la fábrica (fases B/C/D)

16. **[~]** Commit y lanzar:
    ```bash
    workflow --scriptPath toolbox/workflows/legacy-analysis-factory.wf.js \
             --name fabrica-legacy --args '{"apps":["<APP-ID>"]}'
    ```
    Fase B: agentes 4GL en paralelo (solo emiten facts; el render es el único escritor de docs). Fase C: síntesis con `modernization_options` + `remediation`. Fase D: render + `--check`.
17. **[=]** Atender checkpoint `critical-findings` (p.ej. credenciales BD en claro): revisar con el cliente, responder `workflow_respond`.
18. **[=]** Cierre de corrida: `chown -R $(id -u):$(id -g)` de outputs root-owned; regenerar `run-metadata.json` (hash del artefacto).

## Etapa 4 — Productos visuales y modernización (post-facts, con skills)

> Igual que en AF-009: estos productos se generan SOBRE los facts consolidados, nunca a mano desde cero.

19. **[~]** Diagramas de `02-arquitectura/` con la skill **archify** (quality profile `showcase`, guardar JSON junto al HTML) + fuente textual `.puml`/`.mmd` versionable. Mapa mínimo 4GL:
    1. Componentes: terminal/cliente de caracteres → runtime 4GL (fglrun/prowin) → Informix/BD, integraciones (archivos batch, correo, impresión)
    2. Flujo de negocio principal (del facts functional/usecases)
    3. Data-flow de seguridad (input usuario → validación → SQL → BD/archivos)
    4. Despliegue del runtime (hosts, variables de entorno, versiones)
20. **[~]** `05-modernizacion/`: README de brecha SDD + `specs/` (casos-uso, reglas-negocio, modelo-datos, mensajes, layout-archivos si hay batch) derivados de facts; 3-5 opciones de modernización con riesgo/esfuerzo desde `synthesis.modernization_options` (p.ej. refront character-to-web manteniendo lógica, extracción de reglas a servicio, re-escritura dirigida por specs, encapsular con API).
21. **[~]** Presentación `docs/presentaciones/analisis-<APP>.html` con la skill **html-presentation**, **contenido espejo de las 26 slides de AF-009** (mapeo Java→4GL abajo): scroll-snap a pantalla completa, tema oscuro slate + acento ámbar, Mermaid para diagramas, badges de severidad, tarjetas de métricas, nav lateral, pie `.src` con evidencia por slide.
22. **[=]** `catalogo-entregables-cliente.md`: copiar del plantilla y ajustar la fila "binarios cerrados" (en 4GL no hay decompilación) y "grafo de conocimiento".

### Mapeo de slides de la presentación (Java → 4GL)

| # | Slide AF-009 | Equivalente 4GL |
|---|---|---|
| 1 | Portada + agenda | [=] portada con nombre/versión del sistema |
| 2 | ¿Qué es un CVE? (educativa) | [~] ¿Qué es un hallazgo de seguridad? (sin ecosistema CVE: patrones + CIS) |
| 3 | Estado en números | [=] métricas: módulos, functions, forms, LOC, menús |
| 4 | Monolito Struts + dependencias | [~] Monolito 4GL: programs → BD, sin capas |
| 5 | Topología WebSphere | [~] Topología runtime 4GL (del diagrama 4 de archify) |
| 6 | Qué depende de qué (imports) | [~] Call-graph real entre módulos (extractor paso 10) |
| 7 | Flujo "carga de archivo" | [~] Flujo del proceso principal (facts usecases) |
| 8-9 | 23 CVEs resumen + detalle | [~] Hallazgos confirmados por patrones (tabla con severidad y evidencia) |
| 10 | Credenciales BD en claro | [=] (gitleaks paso 7 — típico en 4GL) |
| 11 | Cripto débil + SQLi descartada | [=] patrones cripto/SQL del paso 8 |
| 12 | Deuda técnica (h) | [~] estimada desde LOC/complejidad scc, marcada **[inferencia]** |
| 13 | 7 opciones de menú | [=] menús `MENU/COMMAND` (ABL: frames) con privilegios |
| 14 | 10 pantallas | [~] catálogo de forms `.per` con campos y validaciones |
| 15 | Diagrama maestro SSO→diálogo | [~] diagrama maestro terminal→BD |
| 16 | Ciclo de vida del lote | [=] ciclo del proceso batch (si existe) |
| 17 | Librerías internas decompiladas | [~] módulos internos + includes con conteos |
| 18 | Qué hacer primero (15 CVEs bajo esfuerzo) | [~] remediación priorizada (synthesis.remediation) |
| 19 | Cuatro rutas + recomendación | [=] synthesis.modernization_options |
| 20 | 34 reglas con evidencia | [=] facts br.json |
| 21 | 8 casos de uso | [=] facts usecases.json |
| 22 | Layout posicional 600 chars | [~] contratos de archivos batch (si aplica) |
| 23 | 2 BDs + ER lógico | [=] modelo de datos (tablas/SPs reales) |
| 24 | Catálogo de lo producido | [=] listado de entregables |

## Etapa 5 — Cierre y verificación

23. **[=]** Calibración: `render(facts)` reproduce `golden_docs`; revisar `docs-generated/` vs `docs/`.
24. **[=]** Verificación final (todas deben pasar):
    - `validate_facts.py facts` exit 0; `render.py --check` exit 0
    - `docs/` contiene las **5 secciones + presentaciones** con al menos 1 doc por sección, con fecha/autor/referencias a evidencia
    - La presentación abre standalone (`file://` sin red salvo CDN de Mermaid) y cada slide con cifras lleva pie `.src` apuntando a fact/archivo
    - Secrets del 4GL en `docs/` ofuscados (ubicación+tipo, nunca el valor)
    - `05-modernizacion/specs/` completo y trazable a facts
25. **[=]** Abrir el xlsx de preguntas/aclaraciones con el cliente (glosario de negocio 4GL incluido).

## Reglas inviolables (heredadas de la fábrica)

1. `src/` e `input/` jamás se editan.
2. Los agentes solo escriben facts; el render es el único escritor de docs.
3. Toda afirmación lleva evidence `file:line`; lo inferido se marca **[inferencia]**.
4. Sin fechas/ids aleatorios en facts (viven en `run-metadata.json`).
5. Contenedores `:ro`; chown tras cada corrida que escriba en el repo.
