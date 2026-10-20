---
name: "legacy-4gl-functional"
description: "Recuperación funcional de aplicación legacy Informix 4GL sin documentación: menús MENU/COMMAND, capturas PROMPT, forms .per, flujos MAIN→FUNCTION→REPORT y reglas de negocio desde el código → facts/functional.json + usecases.json + br.json. Usar al documentar qué hace una app 4GL, sus pantallas y reglas, en un repo con manifiesto stack: 4gl."
version: 1
created: "2026-10-19"
updated: "2026-10-19"
---
## When to Use
Usar para poblar facts/functional.json, facts/usecases.json y facts/br.json de un repo con manifiesto legacy-analysis.yaml (stack: 4gl): reconstrucción de menús, opciones, capturas, casos de uso y reglas desde fuentes .4gl/.per. Cargar legacy-analysis-common primero.

## Procedure
1. Partir de la estructura ya extraída (fase A): facts/inventory.json (módulos, entry points) y facts/modules4gl.json (funciones por módulo, SPs llamados)
2. Reconstruir la navegación: por programa con MENU — cada COMMAND es una option de functional.json: id (PRG-CMD-n), title (label del COMMAND), screen (form .per usado o 'terminal'), help del COMMAND como pista de intención; menu_source = programa y línea del MENU
3. Screens: cada .per es una screen — campos del bloque ATTRIBUTES (FORMONLY.campo TYPE) con title del SCREEN; para capturas sin .per (PROMPT), screen = "PROMPT <texto>" referenciando archivo:línea
4. Casos de uso: flujo MAIN → MENU/COMMAND → FUNCTION(s) → SPs/REPORT: main steps con actor usuario/sistema, alternates (INTERRUPT/ON ACTION, WHENEVER ERROR), postconditions (tablas escritas: INSERT/UPDATE visibles), rules referenciando br[]
5. Reglas de negocio (br.json): validaciones (IF ... THEN con mensajes al usuario), cálculos (fn_precio_dia, validación de importes), controles de proceso (dis_ctrl_proceso: semáforos/hora_inicial), perfilamiento (Sca_Valida/sp_sca_valida) — statement en lenguaje de negocio, status confirmed (evidencia directa) o inferred
6. Glosario de negocio 4GL: términos del dominio en cabeceras/mensajes (devolución de pagos en exceso, reverso, liquidación, siefore, FOVISSSTE/ISSSTE) — alimenta el xlsx de preguntas del cliente
7. Todo con evidence file:line bajo src/; inferencias marcadas [inferencia] en el texto
8. Gate: `python3 toolbox/gates/validate_facts.py facts` → exit 0
9. Terminar con workflow_result {summary, facts_written:[...]}

## Pitfalls
- NO hay struts-config/web.xml: la única fuente de navegación son MENU/COMMAND/PROMPT en el código — leer el MAIN completo de cada programa interactivo antes de escribir options
- Los programas batch (sin MENU, con ARG_VAL) son casos de uso con actor "operador/scheduler": documentar sus argumentos (ARG_VAL(0)=programa, sesión, módulo) como precondiciones
- Un COMMAND puede llevar a un sub-flujo largo (CALL cadena): seguir el call-graph de facts/architecture.json para no cortar el flujo
- Los mensajes PROMPT ("Desea ejecutar el proceso [S/N]") son confirmaciones de paso, no pantallas — modelarlas dentro del flujo del caso de uso
- EXCB136-style librerías compartidas NO son opciones de menú: son reglas/servicios comunes (br con evidence en la librería)
- encoding latin-1: los textos de menú/mensajes con acentos deben leerse con errors=replace o saldrán corruptos en los facts

## Verification
1. validate_facts.py exit=0 (evidence no vacía en options y rules)
2. Cada MENU del inventario tiene sus COMMANDs reflejados en functional.options (conteo cruzado con inventory.counts.menu_commands)
3. Cada usecase referencia funciones que existen en modules4gl (nombres verificables)
4. Ningún documento escrito directamente — solo facts/ (el render es el único escritor)
