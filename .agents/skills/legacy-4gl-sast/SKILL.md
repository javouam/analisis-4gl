---
name: "legacy-4gl-sast"
description: "SAST/secrets de aplicación legacy Informix 4GL por patrones (sin decompilación, sin CVE-por-dependencia): triaje de hallazgos semgrep-4gl + gitleaks locales, SQL por concatenación en PREPARE, RUN de shell, credenciales en CONNECT/CHANGE PASSWORD → facts/sast.json. Usar al analizar vulnerabilidades de fuentes .4gl/.per o poblar facts/sast.json en un repo con manifiesto stack: 4gl."
version: 1
created: "2026-10-19"
updated: "2026-10-19"
---
## When to Use
Usar para poblar facts/sast.json de un repo con manifiesto legacy-analysis.yaml (stack: 4gl): triaje de hallazgos de reglas custom sobre .4gl/.per, verificación de flujo PROMPT→concatenación→PREPARE, y reporte de secrets ofuscados. Cargar legacy-analysis-common primero.

## Procedure
1. Scanners (host sin docker — motor local equivalente, AGENTS.md §4.2): `python3 tools/pattern_scan.py semgrep --rules tools/semgrep-4gl.yml --src src --out artifacts/semgrep-$(date +%F).json` y `python3 tools/pattern_scan.py gitleaks --src src --out artifacts/gitleaks-$(date +%F).json` (idempotentes: ya corridos en fase A si existen, verificar fecha)
2. Triagear CADA resultado con lectura del código: status confirmed (patrón real y alcanzable), refuted (falso positivo — justificar), needs_validation (depende de datos/runtime), latent (real pero no explotable en flujo actual)
3. 4gl-sql-string-concat (HIGH): confirmar SOLO si la variable concatenada fluye a PREPARE <var> FROM — si el SQL usa placeholders ? y las variables entran por EXECUTE ... USING, es parametrizado → refuted con justificación; el riesgo es la concatenación, no el PREPARE
4. 4gl-run-shell-with-input (HIGH): confirmar SOLO si el argumento del RUN proviene de PROMPT/arg de usuario; RUN de constante → rebaajar a latent/info con justificación
5. 4gl-prompt-without-validation (LOW): NO reportar uno por PROMPT — consolidar como hallazgo(s) por programa indicando cuáles PROMPTs alimentan SQL/SQLSP/RUN
6. Secrets (gitleaks + 4gl-hardcoded-*): SIEMPRE ofuscado (ubicación+tipo+fingerprint, NUNCA el valor); CRITICAL confirmados → checkpoint humano critical-findings ANTES de continuar (manifiesto)
7. Cada finding lleva evidence file:line (archivo bajo src/ o reporte en artifacts/) y justification cuando no es confirmed
8. Gate: `python3 toolbox/gates/validate_facts.py facts` → exit 0
9. Terminar con workflow_result {summary, facts_written:["facts/sast.json"]}

## Pitfalls
- El eje CVE-por-dependencia es N/A en 4GL (no hay jars/nuget): NO crear facts/vulnerabilities.json salvo que aparezcan acompañantes binarios (avisar si se detectan)
- SELECT ... INTO var + PROMPT no es inyección por sí solo: el peligro es CONCATENAR el valor al string SQL (LET ... , var) o PREPARE sobre string armado con input
- EXECUTE PROCEDURE sp(?,?,...) con USING = parametrizado (bien); CONCATENAR parámetros al string del SP = inyección (mal)
- WHENEVER ERROR CALL no es un hallazgo: es manejo de errores estándar 4GL
- Los .per (FORMONLY) pueden capturar datos sensibles: validar NOENTRY/INVISIBLE/UPSHIFT por campo antes de marcar
- encoding latin-1: leer con errors=replace o los patrones tildados fallan

## Verification
1. validate_facts.py exit=0 (evidence no vacía en TODOS los findings)
2. Todo finding CRITICAL confirmado fue presentado al checkpoint humano antes de síntesis
3. counts por severity/status cuadran contra artifacts/semgrep-*.json + gitleaks-*.json (deduplicación explicada en justification)
4. Ningún valor de secret aparece en claro en facts/ ni .docs/
