---
name: "legacy-analysis-common"
description: "Contrato compartido de la fábrica de análisis legacy (Java EE EAR/WAR sin documentación): leer legacy-analysis.yaml, emitir SOLO facts/*.json validables contra toolbox/schemas con evidence file:line, sin fechas, secrets ofuscados, scanners en contenedor read-only. Cargar SIEMPRE junto a cualquier skill legacy-* de dominio (inventory, sast, functional, synthesis) y antes de producir cualquier fact."
version: 1
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar en toda tarea de análisis legacy que alimente la fábrica facts→render: cualquier agente que vaya a producir o modificar facts/*.json de un repo con legacy-analysis.yaml. Es prerrequisito de legacy-app-inventory, legacy-sast-secrets, legacy-functional-recovery y legacy-docs-synthesis. No aplica para análisis ad-hoc fuera de la fábrica.

## Procedure
1. Leer legacy-analysis.yaml en la raíz del repo del cliente: client, language, artifact (ruta del artefacto explotado), toolbox_path, facts_dir, golden_docs, confidentiality, human_checkpoints
2. Localizar el toolbox (por defecto toolbox/): schemas/*.schema.json son el contrato EXACTO de cada fact; gates/validate_facts.py es el validador; extract/*.py son extractores deterministas fase A
3. Cache first-run-wins: si el facts/<dominio>.json objetivo ya existe y pasa el gate, NO regenerarlo — solo refrescar si el input cambió o se pide force
4. Producir únicamente facts/<dominio>.json: JSON válido contra su schema, sin fechas ni ids aleatorios ni timestamps (la corrida se registra en run-metadata.json de la raíz, jamás dentro de facts)
5. Toda afirmación lleva evidence file:line apuntando a archivo del repo o reporte en artifacts/; si es inferencia, marcarla como [inferencia] en el texto del hecho
6. Ejecutar el gate antes de terminar: docker run --rm -v "$PWD":/w -w /w python:3.12-slim bash -c "pip -q install jsonschema && python3 toolbox/gates/validate_facts.py facts" — exit≠0 significa contrato roto
7. Scanners SIEMPRE en contenedor con montaje read-only (:ro) del repo; si un output quedó root-owned: docker run --rm -v "$PWD":/w busybox chown -R $(id -u):$(id -g) /w/<salida>
8. Secretos y credenciales: reportar ofuscados (ubicación + tipo, NUNCA el valor en claro); hallazgos CRITICAL confirmados se reportan al humano primero (checkpoint human_checkpoints: critical-findings) antes de continuar
9. Jamás modificar src/ ni input/ (evidencia del cliente, solo lectura); toda escritura va en facts/, artifacts/ o docs/
10. Terminar con workflow_result {summary, facts_written[]} — el render determinista (toolbox/render.py + templates) es el ÚNICO escritor de documentos; los agentes nunca escriben docs/

## Pitfalls
- additionalProperties: false en TODOS los schemas — un campo inventado rompe el gate; no agregar claves fuera de contrato
- osv-scanner termina exit=1 cuando HALLA vulnerabilidades (normal, no error); zap-baseline exit=1 con WARNs también es normal
- Los contenedores escriben outputs como root: montar :ro el repo y hacer chown de salidas o escribir solo en artifacts/
- WEB-INF/config/ suele contener copias DIVERGENTES de struts-config — usar solo el descriptor activo en WEB-INF/
- No re-ejecutar análisis LLM si el fact ya existe y valida (cache first-run-wins): borrar el archivo o pasar force para refrescar
- Los jars de 2009-era no traen pom.properties: trivy en modo fs NO los ve — el flujo válido es syft SBOM → trivy sbom

## Verification
1. toolbox/gates/validate_facts.py facts termina exit=0 incluyendo el/los facts producidos
2. El JSON no contiene claves fuera del schema (additionalProperties false) ni fechas/timestamps
3. Cada hallazgo/assert tiene evidence file:line no vacía o provenance a otro fact
4. git status confirma que src/ e input/ quedaron intactos