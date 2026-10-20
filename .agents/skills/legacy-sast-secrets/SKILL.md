---
name: "legacy-sast-secrets"
description: "SAST y secrets de aplicación legacy Java: decompilar jars cerrados con Vineflower, correr semgrep/gitleaks/findsecbugs/trivy, deduplicar hallazgos con severity/status/evidence → facts/sast.json. Usar al analizar vulnerabilidades de código propio, secrets hardcodeados en jars sin fuente, o poblar facts/sast.json."
version: 1
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar para poblar facts/sast.json en un repo con manifiesto legacy-analysis.yaml: análisis de vulnerabilidades estáticas, caza de secrets en fuente y bytecode, preparación del checkpoint de hallazgos CRITICAL. Cargar legacy-analysis-common primero.

## Procedure
1. Decompilar TODO jar propietario sin fuente ANTES de escanear: mkdir -p artifacts/decompiled && docker run --rm -v "$PWD":/w -w /w eclipse-temurin:21-jre java -jar tools/vineflower.jar src/.../WEB-INF/lib/<jar> artifacts/decompiled/<nombre>/ — FindSecBugs es lo ÚNICO que ve secrets en constantes de bytecode (caso real: credenciales BD en EnvioCorreos.jar)
2. Semgrep sobre fuente propia y decompilada: docker run --rm -v "$PWD":/src:ro returntocorp/semgrep semgrep scan --config auto --json --output /src/artifacts/semgrep-<fecha>.json /src/src — configs p/owasp-top-ten, p/java, p/secrets
3. Gitleaks sin git: docker run --rm -v "$PWD":/repo:ro zricethezav/gitleaks:latest detect --source /repo --no-git -r /repo/artifacts/gitleaks-<fecha>.json
4. FindSecBugs sobre bytecode: docker run --rm -v "$PWD":/w -w /w eclipse-temurin:21-jre java -jar tools/spotbugs/lib/spotbugs.jar -textui -xml:withMessages -output artifacts/findsecbugs-<target>-<fecha>.xml -pluginList tools/findsecbugs-plugin.jar [-auxclasspath <libs>] <targets .class|jars>
5. Secreto en modo fs como triangulación: docker run --rm -v "$PWD":/repo:ro aquasec/trivy:latest fs --scanners secret /repo (opcional)
6. Consolidar a facts/sast.json (schema sast): findings[{rule,severity,status,target,tool,evidence}] deduplicados por (rule,target) conservando la tool más específica; scans[{tool,report,scope}] registra cada reporte crudo en artifacts/
7. Severity conservadora (máximo entre herramientas); status: confirmed | needs_validation | false_positive (false_positive solo con justificación en evidence)
8. Secrets OBFUSCADOS: ubicación + tipo (password BD, api key...), NUNCA el valor — regla de confidencialidad del manifiesto
9. Si aparece CRITICAL confirmed: reportar al humano primero (checkpoint critical-findings del workflow) y pausar antes de continuar
10. Gate + workflow_result {summary, facts_written:["facts/sast.json"]}

## Pitfalls
- NO escanear solo el fuente: los jars cerrados esconden credenciales en constantes de bytecode que semgrep/gitleaks jamás verán — decompilar primero, FindSecBugs después
- SpotBugs flag válido es -xml:withMessages (NO -xml:xmlWithMessages)
- FindSecBugs necesita -auxclasspath con los jars dependientes o dará falsos heuristic-only
- Never parsear el reporte XML con grep — usar python3 xml.etree; BugInstance/BugPattern artefactos de namespaces
- Secrets ofuscados SIEMPRE: docs/facts jamás contienen el valor; solo ubicación + tipo + evidence
- status=confirmed solo con certeza (código alcanzable, valor real); needs_validation es el default honesto para hallazgos de taint/flujo

## Verification
1. validate_facts.py exit=0 y NINGÚN findings[*].evidence vacío (el gate lo exige)
2. scans[] lista todos los reportes crudos realmente existentes en artifacts/ (ls artifacts/ | grep -E 'semgrep|gitleaks|findsecbugs')
3. Búsqueda inversa: ningún valor de secret aparece en claro en facts/ ni docs/ (grep de fragmentos conocidos)
4. Deduplicación verificada: no hay dos findings con mismo (rule,target)