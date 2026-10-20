---
name: "legacy-docs-synthesis"
description: "Síntesis ejecutiva de análisis legacy: consolidar TODOS los facts/*.json en facts/synthesis.json con números trazables (provenance fact.campo), remediation priorizada, opciones de modernización y preguntas al cliente. Usar al cerrar un análisis legacy, preparar resumen ejecutivo o recomendaciones de modernización."
version: 1
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar en la fase C de la fábrica legacy para consolidar facts → facts/synthesis.json antes del render determinista, o cuando se pida resumen ejecutivo/recomendaciones de modernización basadas SOLO en facts ya producidos. Cargar legacy-analysis-common primero.

## Procedure
1. Leer TODOS los facts/*.json existentes (inventory, jars, quality, sast, vulnerabilities, functional, usecases, br, architecture) — NO releer código: la síntesis es derivación pura de facts
2. executive.counts: derivar cada número con provenance exacta — cves=len(vulnerabilities.items), critical/high=filtros por severity, pantallas=len(functional.screens), opciones_menu=len(functional.options), reglas_negocio=len(br.rules), deuda_horas=quality.measures.debt_hours
3. executive.summary_points: 4-6 puntos ejecutivos (qué es la app, tamaño/calidad, riesgo seguridad, deuda, qué se recomienda) — cada uno con point + provenance
4. remediation[]: priorizar por impacto×esfuerzo apuntando a fix de vulnerabilities.items[] y hallazgos sast confirmados; cada action con provenance al fact que la motiva
5. modernization_options[]: 3-4 opciones reales (ej. encapsular+API, replatform contenedor, refactor por módulos, reemplazo COTS) con risk/effort comparativos y comment honesto
6. client_questions[]: lo que el artefacto NO puede responder (glosario de negocio, entorno productivo real, usuarios, datos sensibles) — evidence del intento (archivo consultado)
7. Cero fechas/timestamps; cero números sin provenance; nada citado de memoria — si un fact no existe, no se usa
8. Gate + workflow_result {summary, facts_written:["facts/synthesis.json"]}

## Pitfalls
- NO releer el artefacto para sintetizar: la fuente es facts/ — si falta un número, el pipeline anterior quedó incompleto (registrarlo como client_question, no improvisarlo)
- summary_points sin provenance = hallucinación estadística: cada cifra es fact.campo
- remediation sin apuntar a vulnerabilities/sast/quality concretos es opinión no accionable
- No recomendar big-bang: apps 2009-era con lógica embebida en Struts Actions se modernizan por strangler/encapsulamiento primero
- modernization_options: esfuerzo/riesgo comparativos entre opciones, no absolutos

## Verification
1. validate_facts.py exit=0
2. Verificación cruzada automatizable: cada provenance de executive.counts resuelve a un campo real (python: evaluar len()s contra los facts) y los números coinciden
3. Todo remediation[].provenance apunta a un id/componente existente en vulnerabilities o sast findings
4. Re-render determinista: toolbox/render.py --check no cambia (síntesis estable)