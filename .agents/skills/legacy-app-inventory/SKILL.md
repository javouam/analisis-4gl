---
name: "legacy-app-inventory"
description: "Inventario técnico determinista de aplicación legacy Java EE (EAR/WAR, Struts, WebSphere): descriptores application.xml/web.xml/struts-config, clasificación de librerías internas vs third-party desde SBOM, stack y conteos → facts/inventory.json. Usar cuando se pida inventariar un artefacto legacy, clasificar jars de WEB-INF/lib, o poblar facts/inventory.json."
version: 1
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar para poblar facts/inventory.json de un repo con manifiesto legacy-analysis.yaml: primera pasada sobre un artefacto nuevo, o refresco tras cambio de descriptores/librerías. Cargar legacy-analysis-common primero.

## Procedure
1. Correr primero el extractor determinista: docker run --rm -v "$PWD":/w -w /w python:3.12-slim python3 toolbox/extract/inventory_facts.py . facts — cubre descriptores + SBOM syft (busca trivy/osv y syft-sbom-*.json en artifacts/)
2. Si no existe SBOM: docker run --rm -v "$PWD/src:/src:ro" anchore/syft:latest dir:/src -o cyclonedx-json > artifacts/syft-sbom-$(date +%F).json y re-correr el extractor
3. Verificar descriptores manualmente: application.xml (display-name, módulos, context-root), web.xml (servlet-class → framework), struts-config.xml ACTIVO en WEB-INF/ (conteo de actions), META-INF/ibmconfig + ibm-web-bnd/ext.xml (servidor objetivo)
4. Completar stack.databases: el extractor no lo infiere — obtenerlo de datasources/DAOs JDBC leyendo el código (clases *DAO, cadenas jdbc:) con evidence file:line
5. Revisar counts contra libs[]: libs, libs_internal, libs_sin_version, actions_struts deben cuadrar exactamente con los arreglos
6. Todo campo dudoso → evidence al archivo descriptor correspondiente; nada de memoria ni suposiciones sin marca [inferencia]
7. Gate: docker run --rm -v "$PWD":/w -w /w python:3.12-slim bash -c "pip -q install jsonschema && python3 toolbox/gates/validate_facts.py facts"
8. Terminar con workflow_result {summary, facts_written:["facts/inventory.json"]}

## Pitfalls
- No confiar en WEB-INF/config/ para Struts: suele ser copia divergente; el descriptor activo es WEB-INF/struts-config.xml
- libs_sin_version y libs_internal solo coherentes si se derivan del MISMO conjunto libs[] (recontear tras editar)
- display-name puede faltar: derivar nombre del directorio raíz del EAR y marcar evidence al application.xml real
- Los conteos de acciones Struts son <action path=...> del config ACTIVO, no suma de configs alternos

## Verification
1. validate_facts.py exit=0
2. Re-correr inventory_facts.py no cambia el archivo (idempotente tras el ajuste manual — diff vacío)
3. counts.* == tamaño/filtro real de libs[] verificado con python (ej. len([l for l in libs if l.scope=='internal']))
4. Cada entrada de app.evidence apunta a un archivo existente del repo