// Fábrica de análisis legacy 4GL — workflow pi-extensible-workflows (file-backed).
//
// Adaptación 4GL del legacy-analysis-factory original (Java EE):
// - Host SIN Docker: gates/extractores/render corren con python3 local
//   (jsonschema + jinja2 presentes — ver AGENTS.md §4).
// - Fase A usa los extractores *_4gl.py; el eje CVE/trivy/osv se elimina
//   (N/A para core 4GL — la seguridad vive en semgrep-4gl + gitleaks).
// - Fase B usa las skills legacy-4gl-* del repo (.agents/skills/).
// - Render → render_out del manifiesto (.docs para este cliente).
//
// Ejecución (desde el repo del cliente, árbol limpio):
//   workflow --scriptPath toolbox/workflows/legacy-analysis-factory.wf.js \
//            --name fabrica-legacy --args '{"apps":["AF009"]}'
//
// Contrato: fases deterministas (extractores) → agentes paralelos con
// skills legacy-4gl-* (emiten SOLO facts/*.json) → gates → síntesis → render
// determinista → verificación byte-identical. Cache first-run-wins: si
// facts/<dominio>.json ya existe y pasa el gate, el agente se omite salvo
// force. Checkpoint humano obligatorio ante CRITICAL confirmados.
//
// args: { apps: string[], force?: boolean }

const MANIFEST_PATH = "legacy-analysis.yaml";
const RENDER_OUT = ".docs"; // default; se sobreescribe con manifest.render_out si existe
// El runtime puede entregar args como objeto (tool) o string JSON (CLI --args):
let ARGS = args;
if (typeof ARGS === "string") {
  try {
    ARGS = JSON.parse(ARGS);
  } catch {
    ARGS = {};
  }
}
const APPS = ARGS.apps || [];
const FORCE = ARGS.force === true;

if (!APPS.length) {
  return { ok: false, error: "args.apps vacío — indicar al menos un id de aplicación" };
}

phase("bootstrap");
const manifestRaw = await tools.read({ path: MANIFEST_PATH });
log(`manifiesto cargado (${manifestRaw.length} bytes) — apps: ${APPS.join(", ")}`);
const mRender = manifestRaw.match(/^render_out:\s*(\S+)/m);
const OUT = mRender ? mRender[1] : RENDER_OUT;

// Gate de arranque: el toolbox debe ser determinista antes de empezar
// (host sin docker: python3 local con jinja2/jsonschema ya instalados).
const det = await shell(
  `python3 toolbox/render.py --facts facts --templates toolbox/templates --out ${OUT} --check`,
  { env: { LC_ALL: "C" } }
);
if (det.exitCode !== 0) {
  return { ok: false, error: "toolbox no determinista o facts inválidos", detail: det.stderr };
}
log(`gate determinismo OK (render → ${OUT})`);

const results = {};

// Apps procesadas secuencialmente — un checkpoint CRITICAL a la vez; el
// paralelismo real vive en fase B (3 dominios) dentro de cada app.
for (const appId of APPS) {
  phase(`analizar-${appId}`);

  const batchResults = await parallel("analizar-app", {
    [appId]: () => withWorktree(`app-${appId}`, async ({ path, branch }) => {
        log(`${appId}: worktree ${branch}`);

        // ── FASE A: tooling determinista (extractores 4GL; sin LLM) ──
        // Warn-only: los facts semilla ya pueden venir de la corrida de
        // arranque; si algo falla, fase B cubre el dominio con skills.
        const extractWarn = {};
        for (const [nombre, script] of Object.entries({
          inventario: "inventory_facts_4gl.py",
          modulos: "modules4gl_facts.py",
          callgraph: "callgraph_facts_4gl.py",
          calidad: "quality_facts_4gl.py",
        })) {
          const r = await shell(
            `cd "${path}" && python3 toolbox/extract/${script} . facts`,
            { env: { LC_ALL: "C" } }
          );
          if (r.exitCode !== 0) {
            extractWarn[nombre] = String(r.stderr || r.stdout || "error").trim().split("\n").pop().slice(0, 200);
            log(`${appId}: extractor ${nombre} falló (fase B lo cubre): ${extractWarn[nombre]}`);
          }
        }

        // ── FASE B: agentes paralelos por dominio (emiten facts) ──
        // Cache first-run-wins: un fact vigente (corrida previa) salta su agente.
        const cacheProbe = await shell(
          `for f in inventory.json modules4gl.json sast.json functional.json synthesis.json; do ` +
          `[ -f "${path}/facts/$f" ] && echo "$f" || true; done`,
          { env: { LC_ALL: "C" } }
        );
        const vigentes = new Set((cacheProbe.stdout || "").split("\n").map((s) => s.trim()).filter(Boolean));
        const cached = {
          inventario: !FORCE && vigentes.has("inventory.json") && vigentes.has("modules4gl.json"),
          sast: !FORCE && vigentes.has("sast.json"),
          funcional: !FORCE && vigentes.has("functional.json"),
        };
        for (const [dom, hit] of Object.entries(cached)) {
          if (hit) log(`${appId}: ${dom} — fact vigente, agente omitido (cache)`);
        }

        phase(`${appId}:fase-B-agentes`);
        const factsPrompt = (skill, objetivo, esquema) =>
          `Repo: ${path}. Manifiesto: ${MANIFEST_PATH}. App: ${appId}. ` +
          `Lee legacy-analysis.yaml, aplica la skill ${skill} y produce ${objetivo}. ` +
          `CONTRATO: escribe SOLO ${esquema} en facts/ (validable contra toolbox/schemas), ` +
          `con evidence file:line por hecho; NO escribas documentos. ` +
          `Termina con workflow_result {summary, facts_written[]}.`;

        const analysis = await parallel("agentes-analisis", {
          inventario: () => cached.inventario
            ? { skipped: true, cache: "facts/inventory.json + facts/modules4gl.json" }
            : agent(
                factsPrompt("legacy-4gl-inventory", "facts/inventory.json + facts/modules4gl.json",
                            "inventory/modules4gl schemas"),
                { skills: ["legacy-analysis-common", "legacy-4gl-inventory"], label: `${appId}-inventario` }
              ),
          sast: () => cached.sast
            ? { skipped: true, cache: "facts/sast.json" }
            : agent(
                factsPrompt("legacy-4gl-sast", "facts/sast.json", "sast.schema.json"),
                { skills: ["legacy-analysis-common", "legacy-4gl-sast"], label: `${appId}-sast` }
              ),
          funcional: () => cached.funcional
            ? { skipped: true, cache: "facts/functional.json" }
            : agent(
                factsPrompt("legacy-4gl-functional",
                            "facts/functional.json + facts/usecases.json + facts/br.json",
                            "functional/usecases/br schemas"),
                { skills: ["legacy-analysis-common", "legacy-4gl-functional"], label: `${appId}-funcional` }
              ),
        });

        // ── GATE: facts válidos + evidencia ──
        const gate = await shell(
          `cd "${path}" && python3 toolbox/gates/validate_facts.py facts`,
          { env: { LC_ALL: "C" } }
        );
        if (gate.exitCode !== 0) {
          return { app: appId, ok: false, stage: "gate-facts", detail: gate.stdout };
        }

        // ── CHECKPOINT humano: CRITICAL confirmados requieren aprobación ──
        const crit = await shell(
          `cd "${path}" && python3 -c ` +
          `'import json;f=json.load(open("facts/sast.json"));` +
          `print(sum(1 for x in f.get("findings",[]) ` +
          `if x.get("severity")=="CRITICAL" and x.get("status")=="confirmed"))'`,
          { env: { LC_ALL: "C" } }
        );
        const criticals = crit.exitCode === 0 ? parseInt((crit.stdout || "0").trim() || "0", 10) : 0;
        if (criticals > 0) {
          const aprobado = await checkpoint({
            name: `critical-findings-${appId}`,
            prompt: `${appId}: facts/sast.json contiene ${criticals} hallazgo(s) CRITICAL ` +
                    `confirmado(s) — típicamente secrets/credenciales en claro. ` +
                    `Regla del manifiesto: revisar con el cliente antes de sintetizar. ` +
                    `¿Continuar la corrida hacia síntesis y render?`,
            context: { app: appId, criticals, dominio: "sast" },
          });
          if (!aprobado) {
            return { app: appId, ok: false, stage: "checkpoint-critical", detail: `operador rechazó continuar con ${criticals} CRITICAL` };
          }
        }

        // ── FASE C: síntesis (agente único con facts consolidados) ──
        const faseBRan = !(cached.inventario && cached.sast && cached.funcional);
        const synthCached = !faseBRan && !FORCE && vigentes.has("synthesis.json");
        if (synthCached) log(`${appId}: síntesis — fact vigente, agente omitido (cache)`);
        phase(`${appId}:fase-C-sintesis`);
        const synthesis = synthCached
          ? { skipped: true, cache: "facts/synthesis.json" }
          : await agent(
              `Repo: ${path}. Manifiesto: ${MANIFEST_PATH}. ` +
              "Aplica legacy-docs-synthesis: consolida TODOS los facts existentes en facts/ " +
              "→ facts/synthesis.json (schema synthesis). Cada número con provenance fact.campo. " +
              "NO escribas documentos. workflow_result {summary, facts_written[]}.",
              { skills: ["legacy-analysis-common", "legacy-docs-synthesis"], label: `${appId}-sintesis` }
            );

        // ── FASE D: render determinista + verificación ──
        phase(`${appId}:fase-D-render`);
        const render = await shell(
          `cd "${path}" && python3 toolbox/render.py --facts facts ` +
          `--templates toolbox/templates --out ${OUT} --check`,
          { env: { LC_ALL: "C" } }
        );
        if (render.exitCode !== 0) {
          return { app: appId, ok: false, stage: "render", detail: render.stdout };
        }
        // (Sin docker: nada de outputs root-owned que chown-ear.)

        return {
          app: appId, ok: true, branch,
          criticals,
          extractores_fallidos: Object.keys(extractWarn),
          analysis: { inventario: analysis.inventario, sast: analysis.sast, funcional: analysis.funcional },
          synthesis: synthesis,
        };
    }),
  });

  results[appId] = batchResults[appId];
}

const failed = Object.entries(results).filter(([, r]) => !r || !r.ok);
log(`corrida completa: ${APPS.length} apps, ${failed.length} fallos`);
return {
  ok: failed.length === 0,
  apps: Object.fromEntries(Object.entries(results).map(([k, v]) => [k, v ? { ok: v.ok, branch: v.branch, stage: v.stage || null, criticals: v.criticals ?? null, extractores_fallidos: v.extractores_fallidos ?? [] } : { ok: false }])),
};
