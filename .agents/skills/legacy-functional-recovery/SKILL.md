---
name: "legacy-functional-recovery"
description: "Recuperación funcional de aplicación legacy Java EE sin documentación: reconstruir pantallas, opciones de menú, privilegios, casos de uso y reglas de negocio desde struts-config/JSPs/capas actions-blogic-dao → facts/functional.json + usecases.json + br.json. Usar al documentar qué hace la aplicación, sus flujos y reglas."
version: 1
created: "2026-10-13"
updated: "2026-10-13"
---
## When to Use
Usar para poblar facts/functional.json, facts/usecases.json y facts/br.json en un repo con manifiesto legacy-analysis.yaml: documentación funcional de app legacy Struts/JSP (u otro framework MVC Java), matriz pantalla-acción, glosario de negocio. Cargar legacy-analysis-common primero.

## Procedure
1. Partir del struts-config ACTIVO (WEB-INF/struts-config.xml): mapear action path ↔ form-bean ↔ forwards ↔ JSP destino — NO usar copias divergentes (WEB-INF/config/)
2. Registrar screens[] desde WebContent/ JSPs: title (bundle/properties), fields, buttons, kind (forma/consulta/pop-up), file — evidence al JSP
3. Registrar options[] (menú) y privileges[] desde el generador de menú/seguridad (ej. SCA GeneraMenu SOAP según perfil; jars de seguridad decompilados ayudan) — evidence file:line
4. Reconstruir usecases[]: id, name, actors (de actions/privilegios), screen, privileges, preconditions, main (pasos numerados cortos), alternates (incluye reversos del flujo), postconditions, rules[] (refs a br.json), mail_template si aplica — evidence a action/JSP/blogic
5. Destilar br.json rules[]: id (BR-NN), domain (devoluciones/validaciones/seguridad/...), statement (una oración verificable), status (confirmed|needs_validation), evidence file:line OBLIGATORIA (el gate la exige no vacía)
6. Flujos típicos AFORE/financieros: carga → previo → definitivo → liquidación (+ reversos) — seguir la cadena de actions/blogic para confirmar el orden real con evidence
7. Layouts posicionales (ej. util/layout*.properties) y constantes de negocio: documentar ubicación como evidence de la regla
8. Marcar TODA inferencia funcional como [inferencia] y acumular preguntas al cliente (se materializan en synthesis.client_questions vía el xlsx de input/ si existe)
9. Gate + workflow_result {summary, facts_written:["facts/functional.json","facts/usecases.json","facts/br.json"]}

## Pitfalls
- No describir pantallas inventadas: solo JSPs referenciados por forwards/links reales; los huérfanos van con evidence y nota
- reglas de negocio sin evidence file:line rompen el gate — mejor regla menos elegante con evidencia que redacción sin rastro
- Los textos de UI suelen venir de properties/bundles: citar el bundle como evidence del título, no solo el JSP
- Términos de negocio dudosos (nombres funcionales tipo DevPagosExc) → validar con cliente vía preguntas; mientras tanto [inferencia]
- mail_template: solo si existe plantilla/archivo real de correo; no deducir

## Verification
1. validate_facts.py exit=0 y ninguna rules[*].evidence vacía (regla dura del gate)
2. Cobertura: todo action del struts-config activo aparece en usecases (main/alternates) o queda listado como pendiente con evidence
3. Cada usecase.screen apunta a un screens[].file existente; cada rules[] ref existe en br.json
4. Recuento br.json == synthesis.executive.counts.reglas_negocio (consistencia entre facts)