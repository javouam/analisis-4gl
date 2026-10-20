---
name: "legacy-4gl-inventory"
description: "Inventario técnico determinista de aplicación legacy Informix 4GL (fuentes .4gl/.per): MAIN/FUNCTION/REPORT/MENU/COMMAND/GLOBALS, BDs por DATABASE, módulos e includes, forms → facts/inventory.json + facts/modules4gl.json. Usar cuando se pida inventariar fuentes 4GL, mapear módulos compartidos o poblar inventory/modules4gl en un repo con manifiesto stack: 4gl."
version: 1
created: "2026-10-19"
updated: "2026-10-19"
---
## When to Use
Usar para poblar/refinar facts/inventory.json y facts/modules4gl.json de un repo con manifiesto legacy-analysis.yaml (stack: 4gl): primera pasada sobre fuentes .4gl/.per nuevas, o refresco tras cambio de fuentes. Cargar legacy-analysis-common primero.

## Procedure
1. Correr primero los extractores deterministas (host sin docker — python3 directo): `python3 toolbox/extract/inventory_facts_4gl.py . facts` y `python3 toolbox/extract/modules4gl_facts.py . facts` — cubren MAIN/FUNCTION/REPORT/MENU/COMMAND/PROMPT/GLOBALS/DATABASE/RUN/EXECUTE PROCEDURE con evidence file:line
2. Verificar el sondeo contra las fuentes: cabeceras #Proyecto/#Programa/#Descripcion de cada .4gl (nombres funcionales reales), encoding latin-1
3. Refinar app.name con el nombre funcional de las cabeceras (no dejar el placeholder del extractor si hay mejor evidencia)
4. modules4gl: validar que las librerías compartidas (sin MAIN, incluidas vía GLOBALS) tengan kind=library e included_by correcto; cruce EXCB102/103→EXCB136 estilo
5. Completar lo que el extractor no infiere: versión/dialecto 4GL (si hay Makefile/.4gl con marcas), runtime objetivo (p.ej. Informix 4GL/I4GL c4gl), evidencia de compilación — siempre con evidence file:line o marca [inferencia]
6. Revisar counts contra modules[]: programs, forms, functions, lines_total deben cuadrar exactamente
7. Gate: `python3 toolbox/gates/validate_facts.py facts` (exit 0)
8. Terminar con workflow_result {summary, facts_written:[...]}

## Pitfalls
- Encoding: SIEMPRE latin-1/errors=replace — leer como UTF-8 corrompe acentos y rompe regex (ver AGENTS.md §2)
- Un .4gl sin MAIN pero con funciones puede ser librería O programa llamado desde shell: verificar GLOBALS-includes y referencias cruzadas antes de fijar kind
- DATABASE <nombre> conmuta la BD activa EN EJECUCIÓN: una función puede escribir en safre_seg y volver a safre_af — las BDs son un conjunto por programa, no una por archivo
- No inventar stack.server/framework: en 4GL no hay contenedor web; framework = "Informix 4GL (.4gl + forms .per)" salvo evidencia de runtime distinto
- scc NO reconoce .4gl/.per: no citar scc como fuente de LOC, usar el conteo del extractor (fallback documentado)

## Verification
1. validate_facts.py exit=0
2. Re-correr los extractores no cambia los archivos (idempotentes tras ajuste manual — diff vacío)
3. counts.* == conteos reales de modules[] (python: len/sum filters)
4. Cada entrada de app.evidence apunta a archivo+línea existente bajo src/
