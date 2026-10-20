---
name: "legacy-analysis-bootstrap"
description: "Bootstrap de la fábrica de análisis legacy para un cliente/aplicación NUEVA: copiar toolbox+tools del repo plantilla, explotar el artefacto EAR/WAR en src/, crear legacy-analysis.yaml, correr scanners base y lanzar el workflow de la fábrica. Usar al iniciar el análisis documental de otra aplicación legacy Java EE."
version: 3
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar cuando llega una aplicación legacy Java EE nueva de cualquier cliente (EAR/WAR sin documentación confiable) y se quiere montar la fábrica facts→render: setup de repo, manifiesto, scanners base y primer lanzamiento del workflow. Cargar legacy-analysis-common para conocer el contrato de facts.

## Procedure
1. Crear repo nuevo para el cliente y copiar del repo plantilla (ej. sura-poc-doc): toolbox/ completo, tools/ (vineflower.jar, spotbugs/, findsecbugs-plugin.jar, ck.jar, scc/, jqassistant-*), .agents/skills/ (las 5 skills de dominio legacy-* — así la fábrica del repo nuevo resuelve sus agentes sin depender de skills globales) y AGENTS.md como punto de partida (adaptar §2 al nuevo artefacto)
2. Explotar el artefacto: si llega .ear/.war binario → mkdir -p src && unzip input/<artefacto> -d src/<APP>EAR/ (y desanidar .war → WebContent/WEB-INF); si llega workspace Eclipse/RAD explotado → copiarlo tal cual a src/
3. Crear legacy-analysis.yaml en la raíz: client, language (es para clientes MX/LATAM), artifact: src/<APP>EAR, toolbox_path, facts_dir, golden_docs, deliverable_template (si hay xlsx de preguntas), confidentiality {secrets: obfuscate}, docs_layout, human_checkpoints [critical-findings, parity-matrix, delivery]
4. Actualizar AGENTS.md §2 con los hallazgos preliminares del NUEVO artefacto (application.xml: ¿1 war o varios? ¿EJBs? ¿framework web? ¿drivers?) — es la memoria de arranque de los agentes
5. Scanners base a artifacts/: docker run --rm -v "$PWD/src:/src:ro" anchore/syft:latest dir:/src -o cyclonedx-json > artifacts/syft-sbom-$(date +%F).json y luego trivy sbom + osv-scanner sobre ese SBOM (copiar a .cdx.json; exit=1 = halló vulns, normal)
6. Commit inicial (árbol limpio) y lanzar la fábrica: workflow --scriptPath toolbox/workflows/legacy-analysis-factory.wf.js --name fabrica-legacy --args '{"apps":["<APP-ID>"]}' — añade force:true para re-analizar dominios ya cacheados
7. Monitorear: el workflow pausa en checkpoint critical-findings si sast.json tiene CRITICAL confirmados — responder con workflow_respond tras revisar con el cliente
8. Al terminar: revisar docs-generated/ vs golden_docs (calibración), regenerar run-metadata.json (hash del artefacto) y abrir el xlsx de preguntas con el cliente
## Pitfalls
- NUNCA editar src/ ni input/ — son evidencia del cliente; los binarios de decompilador viven en tools/ del propio repo
- Un .ear/.war binario NO va directo a trivy: explotar primero y generar SBOM con syft (jars 2009-era sin pom.properties son invisibles a trivy fs)
- El manifiesto es por cliente: si el repo plantilla tiene facts/run-metadata del cliente anterior, NO copiarlos — facts/ arranca limpio
- workflow legacy-analysis-factory requiere árbol limpio (withWorktree): commit previo obligatorio
- Outputs de contenedores root-owned: chown -R $(id -u):$(id -g) tras cada corrida que escriba en el repo

## Verification
1. toolbox/gates/validate_facts.py facts exit=0 desde el arranque (facts seed válidos aunque mínimos)
2. render determinista: toolbox/render.py --check exit=0 con el layout del manifiesto
3. El workflow corre al menos hasta fase A sin error de estructura (fase B con agentes = validación end-to-end)
4. AGENTS.md §2 refleja el artefacto real (nombres de módulos/wars verificados contra application.xml)