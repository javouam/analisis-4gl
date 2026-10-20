# AGENTS.md — Guía para agentes de IA en este repositorio

> **Idioma de trabajo:** español. Toda la documentación generada para el cliente se escribe en español.
> **Audiencia:** equipo de arquitectura de Softtek y equipos técnicos y de negocio de SURA.

## 1. Misión de este repositorio

Nuestro cliente **SURA** nos compartió una aplicación **Informix 4GL** (fuentes `.4gl`/`.per`, proyecto `safre_af`, módulo EXCB*/EXCC*) y nos pide generar su documentación completa —**funcional, técnica y de seguridad**— a partir del fuente, sin garantía de documentación previa confiable.

La documentación debe permitir:

1. **Evaluar implicaciones de modernización** (migración de plataforma/lenguaje, o reemplazo).
2. **Simplificar el mantenimiento** correctivo y evolutivo.
3. **Resolver vulnerabilidades** asistida por agentes de IA (identificar, priorizar y remediar).

El entregable final es un conjunto de documentos en `.docs/` generados determinísticamente (fábrica facts→render, ver §5). El eje CVE-por-dependencia es **N/A** para el core 4GL (no hay librerías terceras empaquetadas): la seguridad se sostiene con reglas semgrep custom + escaneo de secrets.

## 2. Estado del artefacto (sondeo preliminar 2026-10-19 — verificar y refinar)

| Aspecto | Detalle conocido |
|---|---|
| Aplicación | **AF009 fuentes 4GL** en `src/AF009_pgmas/` — proyecto `safre_af` (cabeceras), dominio AFORE/pensiones México: *devolución de pagos en exceso* (batch + interacción por terminal) |
| Volumen | 13 archivos: **9 programas `.4gl`** (7.984 líneas) + **4 forms `.per`** (114 líneas) = 8.098 líneas totales |
| Estructura | Cada programa = `MAIN` + FUNCTIONs (94 funciones en total); 1 `REPORT` (`listado_ctas` en EXCB100) |
| Compartidos | `EXCB136.4gl` es **módulo de validación de importes** incluido vía `GLOBALS "EXCB136.4gl"` por EXCB102 y EXCB103 |
| Bases de datos | `safre_af` (núcleo), `safre_seg` (seguridad/logs), `safre_tmp` (transitoria) — conmutación con `DATABASE <nombre>` (sin credenciales en el fuente: identidad del proceso OS). Además `safre_ing` (catálogos institucionales) accedida cross-database con prefijo `safre_ing:` (EXCB102.4gl:243, EXCB103.4gl:236/611, EXCB136.4gl:250) |
| SQL dinámico | `PREPARE`/`EXECUTE` con `EXECUTE PROCEDURE` a SPs: `fn_precio_dia`, `Carga_Parametros_sca`, `sp_sca_valida`, `sp_graba_logs_err`, `graba_log` |
| Menús/UI | `MENU "PROCESOS BATCH"` (EXCB001, EXCB007, EXCC001), `PROMPT` para capturas; forms `.per` FORMONLY de captura de archivo |
| Shell | `RUN` de comandos: `sh /safre/est/shells/env_mail_gral.sh` (EXCB100) y `RUN ejecuta` con variable en varios programas |
| Logs | `STARTLOG "/safre/exc/logs/<PRG>.log"` + `WHENEVER ERROR CALL graba_logs_err` → SPs de log en `safre_seg` |
| Perfilamiento | `Sca_Valida(origen)` + `sp_sca_valida` + tabla `seg_modulo` (parámetros de seguridad por módulo) |
| Encoding | **ISO-8859-1 (Latin-1)** con CRLF — leer SIEMPRE con `errors="replace"` (o latin-1) o los acentos se corrompen |
| Edad | Cabeceras 2001–2015 (RQ19435_PJF, RQ25372_PJF, rq175739) — código original ~2001, últimos cambios 2015 |
| Herramientas | `scc` NO reconoce `.4gl`/`.per` (cuenta 0 archivos) — LOC por conteo directo por extensión; no existe decompilador 4GL (si llegara `.4go`/r-code: documentar limitación) |

Documento del cliente en `input/`:
- `Anexo 1. Formato Preguntas y Aclaraciones.xlsx` (formato de Q&A con el cliente — incluir glosario de negocio 4GL)

## 3. Estructura y convenciones del repositorio

```
input/               Documentos que entrega el cliente (SOLO LECTURA)
src/AF009_pgmas/     Fuentes 4GL tal como llegaron (SOLO LECTURA — nunca editar)
.docs/               Salida: documentación generada por el render (gitignored)
  01-funcional/      Casos de uso, flujos, reglas de negocio
  03-tecnica/        Inventario 4GL, módulos/includes, métricas
  04-seguridad/      Hallazgos SAST/secrets priorizados
toolbox/             Fábrica: schemas, extract, gates, render, templates, workflows
tools/               Herramientas locales (scc/)
facts/               Hechos estructurados validables (versionados)
artifacts/           Salidas crudas de herramientas (scc, semgrep, secrets)
```

Reglas:

- **Nunca modificar** `src/` ni `input/`. Toda escritura va en `facts/`, `artifacts/`, `.docs/` o `toolbox/`.
- Reportes crudos en `artifacts/` con nombre `<herramienta>-<fecha>.<ext>`; en `.docs/` solo síntesis priorizadas y accionables.
- Cada afirmación debe rastrearse a evidencia (archivo:línea o reporte en `artifacts/`). Inferencias marcadas **"[inferencia]"**.
- **Confidencialidad**: material del cliente SURA. Secrets reportados ofuscados (ubicación + tipo, nunca el valor).

## 4. Caja de herramientas (y limitaciones del host)

Entorno local: **sin Docker, sin semgrep/gitleaks instalados**; sí `python3` (+jsonschema, jinja2) y binario estático `tools/scc/scc`.

### 4.1 LOC/complejidad

`scc` no reconoce el dialecto → conteo por extensión (extractor determinista `toolbox/extract/quality_facts_4gl.py`); reporte crudo igualmente a `artifacts/scc-<fecha>.json` (documenta el vacío).

### 4.2 SAST/secrets (patrones, sin herramientas externas)

Reglas custom 4GL en `tools/semgrep-4gl.yml` (modo generic): credenciales en `CONNECT TO ... USER ... WITH PASSWORD`, SQL por concatenación, `RUN`/shell con input de usuario, datos sensibles en forms. Se ejecutan con el **motor local** `tools/pattern_scan.py` (mismas reglas + reglas estilo gitleaks: keys de API, URLs con credenciales, llaves privadas, entropy) → `artifacts/semgrep-<fecha>.json` y `artifacts/gitleaks-<fecha>.json`. Si el host llega a tener semgrep/gitleaks, usarlos y sustituir los reportes.

### 4.3 N/A para 4GL

SBOM/CVE por dependencia (syft/trivy/osv), decompilación (Vineflower), DAST (ZAP) — sin acompañantes binarios ni runtime. No invertir tiempo ahí.

## 5. Metodología de análisis (fábrica facts→render)

1. **Fase A determinista**: extractores `toolbox/extract/*_4gl.py` (inventario, módulos/includes, calidad, call-graph) → `facts/*.json` semilla. Gate: `python3 toolbox/gates/validate_facts.py facts` → exit 0.
2. **Fase B agentes**: skills `legacy-4gl-inventory`, `legacy-4gl-sast`, `legacy-4gl-functional` enriquecen los facts (SIN escribir documentos).
3. **Fase C síntesis**: `legacy-docs-synthesis` consolida todo en `facts/synthesis.json` con números trazables.
4. **Fase D render**: `toolbox/render.py` es el ÚNICO escritor de `.docs/` (determinista, `--check` byte-identical).
5. Checkpoint humano obligatorio ante CRITICAL confirmados (`human_checkpoints` del manifiesto).

## 6. Reglas para agentes

1. No editar ni borrar nada bajo `src/` ni `input/` — son evidencia del cliente.
2. Leer fuentes 4GL con encoding latin-1/errors=replace (ver §2).
3. Cada hallazgo cita evidencia archivo:línea; la corrida se registra en `run-metadata.json` (raíz), jamás dentro de `facts/`.
4. Ante hallazgos CRÍTICOS de seguridad: checkpoint humano primero (secrets/credenciales en claro).
5. Si el artefacto excede lo descrito en §2 (más programas, forms, BDs), actualizar este archivo.
