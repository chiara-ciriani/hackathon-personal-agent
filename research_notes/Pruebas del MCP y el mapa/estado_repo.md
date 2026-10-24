# Estado del repo Quiet Compass para pruebas del MCP y del mapa (snapshot 2026-10-24)

Repo: /home/user/hackathon-personal-agent (HEAD 175288a "docs: add Quiet Compass product brief"; antes a2ecb13 "Add Quiet Compass map and Oura integration"). App en apps/quiet-compass. Todo lo citado son archivos locales (rutas relativas a apps/quiet-compass salvo indicación). Los resultados de comandos fueron ejecutados por mí el 2026-10-24 en Node v22.22.0, npm 10.9.4, pnpm 11.25.0; no se modificó ningún archivo fuente (git status limpio salvo research_notes/).

## 1. Cómo se construye y ejecuta (comandos, variables, secretos)

### Takeaway
La app es un starter "Sites/vinext" (Next-API sobre Vite + Cloudflare Worker) que instala, compila y arranca en local sin secretos. Solo la ruta Oura exige SESSION_ENCRYPTION_KEY y APP_ORIGIN; el mapa no necesita ninguno, pero sí red hacia tiles.openfreemap.org.

### Cited Findings
- Scripts: `install:ci` (bash scripts/install-pnpm.sh), `dev` (node scripts/run-framework.mjs dev), `build`, `start` (wrangler dev --local sobre dist/server/wrangler.json, 127.0.0.1), `lint` (eslint . --ignore-pattern dist --ignore-pattern .next), `db:generate` (drizzle-kit). No existe script `test` ni `typecheck`. — package.json:8-15
- Engines node >=22.13.0; packageManager pnpm@11.25.0; name "site-creator-vinext-starter"; deps clave: maplibre-gl 6.14.0, ol 10.6.1 (fallback 2D), next 16.3.4, vinext 1.0.0-beta.5, vite 8.0.13, wrangler 4.92.0, zod 3.25.76, json-rpc-2.0 1.7.1 (devDependency). — package.json:6-7, 28-31, 42, 56, 62-64, 72
- NO hay SDK MCP (@modelcontextprotocol/sdk) ni dependencia de servidor MCP; `json-rpc-2.0` solo la usa el preview de conectores del starter (scripts/connector-preview/protocol.mjs:37 y host-binding.mjs:163 mencionan "MCP results" en el contexto de conectores nativos de Sites, no del contrato Quiet Compass). — package.json; grep "mcp" en scripts/
- Variables server-only: `SESSION_ENCRYPTION_KEY` (64 hex) y `APP_ORIGIN` (origen exacto), "configuradas en el alojamiento"; Oura Client ID/Secret se pegan en la UI y se guardan cifrados en cookie (no en env). — CONFIGURACION.md:21 (sección Desarrollo), app/api/oura/[action]/route.ts:8,14-15
- Pruebas documentadas: `node --test tests/*.test.mjs` y `npx tsc --noEmit`. OAuth real "no se puede certificar sin conectar su cuenta". — CONFIGURACION.md (sección Desarrollo)
- Perfil portable: `npm run dev` => `vinext dev` en puerto 5173 con login simulado solo en loopback (`/signin-with-chatgpt?return_to=/` => usuario local_seedy). — README.md:29,33
- `.openai/hosting.json`: `{"d1": null, "r2": null, "project_id": "appgprj_6add..."}`: sin base de datos ni bucket; db/schema.ts "starts intentionally empty" (README.md:53). No existe almacenamiento de observaciones.
- Worker de producción: worker/index.ts (30 líneas) solo delega a `vinext/server/fetch-handler` envolviendo el binding de conectores (worker/index.ts:1-27). No enruta nada propio, no hay handler MCP.

### Resultados reales de ejecución
- `pnpm install --frozen-lockfile`: OK en 14.4 s (no fallos; no hizo falta npm_config_cache).
- `node --test tests/*.test.mjs`: 1 test, 1 pass, 0 fail (tests/seal.test.mjs).
- `npx tsc --noEmit`: exit 0, sin errores.
- `pnpm run lint`: FALLA con exit 1: "1090 problems (5 errors, 1085 warnings)". Desglose por archivo: public/maplibre-gl-worker.mjs 0 errores / 1082 warnings (bundle vendorizado de MapLibre, ruido `no-unused-expressions`; debería ignorarse); app/connections/page.tsx 4 errores (react-hooks/set-state-in-effect en 11:360 de la línea del fichero indicado, @next/next/no-html-link-for-pages x2, @typescript-eslint/no-explicit-any) + 2 warnings; app/event/page.tsx 1 error (no-html-link-for-pages 14:62) + 1 warning. app/page.tsx (el mapa) y app/api/oura NO tienen errores de lint. Los errores son de las pantallas de Oura/evento, no del mapa.
- `pnpm run build` (vinext build): OK. Rutas: `/`, `/connections`, `/event` (clasificadas "?" por análisis estático) y `/api/oura/:action` (λ API). Solo advertencia de tamaño de chunk. Genera dist/ (ignorado por git).
- `pnpm run dev -- --port 5199` arrancó OK en ~12 s. Sondeos HTTP en dev: `/`=200, `/connections`=200, `/event`=200, `/api/oura/status`=401 `{"error":"Sign in to connect Oura."}` (sin cookie de login simulado), `/mcp`=404, `/api/mcp`=404, `/.well-known/mcp`=404; `POST /mcp` con JSON-RPC `tools/list` devolvió la página HTML 404 de Next. Servidor detenido después.
- Red: `https://tiles.openfreemap.org/planet` respondió 200 desde este sandbox, así que los tiles vectoriales se pueden alcanzar.
- No hay navegador en el sandbox (sin chromium/google-chrome, sin ~/.cache/ms-playwright): no se renderizó el mapa ni se hicieron capturas; WebGL2 no verificado.

### Inferences
- Un CI mínimo viable hoy sería: pnpm install --frozen-lockfile, tsc --noEmit, node --test, vinext build. El lint no puede ser puerta de calidad sin excluir public/maplibre-gl-worker.mjs y arreglar 5 errores.
- Para pruebas locales no se necesitan secretos si no se toca Oura.

### Gaps
- No se probó `npm start` (wrangler sobre dist) ni `install:ci` (bash scripts/install-pnpm.sh); solo pnpm directo.
- No se verificó el despliegue en https://quiet-compass-oura-martin.martin-puli.chatgpt.site/ (QUIET_COMPASS_IDEA.md:292) ni que el push a main del repo del equipo exista (QUIET_COMPASS_IDEA.md:250 dice que no está verificado).

## 2. ¿Existe algún endpoint/ruta/código MCP? Qué es solo UI

### Takeaway
No existe ningún servidor MCP, ruta ni código de herramientas. El "contrato" son un objeto JS literal en el cliente y texto en la documentación; el botón MCP solo abre un diálogo y copia ese JSON al portapapeles.

### Cited Findings
- El propio brief lo dice: "These names are a proposed contract. There is no working MCP endpoint in the current prototype." — QUIET_COMPASS_IDEA.md:96; tabla "What exists today": "MCP button and tool contract: Implemented UI; server not connected" — QUIET_COMPASS_IDEA.md:241; también "Status: ... a working MCP server remain[s] to be built" — QUIET_COMPASS_IDEA.md:7.
- Único lugar con el contrato en código: constante `contract` en app/page.tsx:63, con `status:'proposal'`, `connected:false`, `data:'simulated'`, tres tools y `excluded:['raw_audio','personal_routes','health_data']`:
  - `query_sound_map` input `{bounds:'[west,south,east,north]', max_age_minutes:'number'}`
  - `find_suitable_places` input `{area:'coarse zone', preference:'user-selected acoustic preference'}`
  - `submit_observation` input `{zone_id, time_bucket:'rounded time', acoustic_summary:'aggregated calibrated indicators'}`, `requires:'explicit contribution consent'`
  Los valores de los inputs son cadenas descriptivas, no JSON Schema/zod; no hay output ni errores definidos.
- UI MCP: botón `.quiet-mcp` (app/page.tsx:127) abre un diálogo modal (page.tsx:138-148) que muestra "Proposed contract · not connected" (146), lista los nombres de tools (147) y un botón copiar (`copy()` page.tsx:121 usa navigator.clipboard.writeText(JSON.stringify(contract,null,2)); si falla muestra un textarea fallback `.quiet-contract`, page.tsx:148, map.css:54). Gestión de foco/Escape/Tab: page.tsx:112-118.
- Rutas existentes en app/: `/` (mapa), `/connections` (Oura), `/event` (simulación antigua del agente) y `/api/oura/[action]` (config, disconnect POST; status, login, callback, data GET). — find en apps/quiet-compass/app
- Nada en lib/ es MCP: lib/ contiene canvas-map.ts, connector-*.mts (starter Sites), seal.mjs, utils.ts. No hay carpeta mcp/, ni tools/, ni schemas.
- CONFIGURACION.md "Contrato para agentes (propuesta, no servidor MCP desplegado)" define OTRA firma distinta: `query_sound_map(area, time_window)`, `find_suitable_places(goal, area, constraints)`, `submit_observation(zone_id, time_bucket, acoustic_summary, measurement_quality)`; y 7 reglas para una skill del agente; dice "La simulación no realiza estas llamadas: ilustra el contrato." — CONFIGURACION.md (sección Contrato para agentes)
- QUIET_COMPASS_IDEA.md:110-130 propone un payload de contribución con schema_version "0.1", area_id, time_bucket (ISO), duration_seconds, measurement{kind:'relative_uncalibrated', rms_dbfs, frame_level_spread_db, calibrated}, quality{capture_profile, clipping_detected}, source:'simulated'. Es una tercera variante de campos (area_id vs zone_id; bounds vs area).
- Respuestas esenciales deseadas por tool (fuente, tipo de medición, antigüedad, cobertura, calidad; candidatos con observaciones de apoyo e incertidumbre; resultado accepted/withheld/rejected) — QUIET_COMPASS_IDEA.md:90-94.
- Reglas de privacidad/negocio que un servidor debería cumplir y que serían casos de prueba: sin audio crudo, sin rutas, sin salud/Oura; consentimiento explícito; rate limiting, detección de duplicados e implausibles; ubicación gruesa (~100 m, cubos de 5 min) — QUIET_COMPASS_IDEA.md:174-186; mínimo configurable de participantes y supresión de grupos pequeños (el umbral 3 de la simulación es ilustrativo) — CONFIGURACION.md (Arquitectura colectiva).

### Inferences
- Hay tres especificaciones divergentes del contrato (page.tsx:63, CONFIGURACION.md, QUIET_COMPASS_IDEA.md). Cualquier prueba de contrato necesita primero decidir cuál es la fuente de verdad; probar hoy el objeto `contract` solo validaría un literal.
- Lo único "ejecutable" relacionado con MCP es la interacción de UI (abrir/cerrar diálogo, copiar JSON).

### Gaps
- No hay transporte (Streamable HTTP/stdio), esquema de autenticación, ni respuesta definida para ninguna tool: no se puede hacer prueba de integración con un cliente MCP real (p. ej. MCP Inspector) porque no hay servidor al que conectar.

## 3. Pruebas existentes: qué cubren y qué no

### Takeaway
Existe una sola prueba automatizada (cifrado de cookies de Oura). No hay pruebas del mapa, de datos sintéticos, del contrato MCP, de las rutas API ni de UI.

### Cited Findings
- Único archivo: tests/seal.test.mjs (14 líneas), runner nativo `node:test`. Cubre `seal`/`unseal` de lib/seal.mjs (AES-GCM): solo el dueño abre el token antes de expirar, uid distinto => null, expirado => null, clave distinta => null, byte alterado => null, el texto plano no aparece en el token. — tests/seal.test.mjs:5-13; lib/seal.mjs:1-15
- No hay config de Vitest/Jest/Playwright/Cypress en package.json ni archivos *.test.* fuera de tests/seal.test.mjs; no existe script `test` en package.json:8-15.
- Sin cobertura: app/api/oura/[action]/route.ts (validación de Origin, límites de tamaño 6000, regex de clientId, PKCE/state, expiración, rutas desconocidas => 404; route.ts:10-17, 31-37, 46-79), lib/canvas-map.ts, toda la lógica de app/page.tsx, app/event y app/connections.
- Lo no verificado según el propio brief: "A successful end-to-end test with a real authorized account has not been verified" (Oura) — QUIET_COMPASS_IDEA.md:196.

### Inferences
- `route.ts` importa `cloudflare:workers` (línea 3), lo que complica probarlo con node:test sin mock/miniflare; las funciones puras (seal) sí son testeables.
- Los datos del mapa (`points`) no se exportan de page.tsx (componente 'use client' con `export default`), por lo que no se pueden importar en pruebas sin refactor.

### Gaps
- No se midió cobertura de código; no hay configuración de CI en el repo (no se encontró .github/workflows dentro de apps/quiet-compass; no se revisó la raíz en profundidad).

## 4. Cómo obtiene datos el mapa y cómo verificar datos/capas

### Takeaway
Los datos acústicos son 100% sintéticos y están hardcodeados: 31 puntos con score 0..1 en un array dentro de app/page.tsx, convertidos a un GeoJSON en memoria. El mapa base viene de OpenFreeMap en vivo. Los pulsos son un setInterval cíclico determinista que añade una clase CSS, sin lectura de ninguna API.

### Cited Findings
- Comentario explícito: "Illustrative locations and synthetic acoustic scores; no real noise measurements." — app/page.tsx:9. Tipo `MapPoint={name,lng,lat,score,landmark?}` — page.tsx:10. Array `points` de 31 entradas — page.tsx:11-43 (verificable: líneas 12 a 42 inclusive). Landmarks (`landmark:true`): Transamerica Pyramid, Ferry Building, City Hall, Coit Tower, Salesforce Tower, Oracle Park, de Young Museum = 7 (page.tsx:14,16,37,38,39,40,41). Scores van de 0.18 (Presidio) a 0.92 (Union Square).
- GeoJSON: `soundData` FeatureCollection con `id:i`, geometría Point [lng,lat], propiedades `{score}` — page.tsx:44. Los nombres no se incluyen en las propiedades del GeoJSON (solo score).
- Estilo MapLibre inline (StyleSpecification), page.tsx:45-61: fuente vectorial `city` = `https://tiles.openfreemap.org/planet` (47) y fuente geojson `sound`. Capas: background, land, parks, water, roads-edge, roads, footprints, structures (fill-extrusion, minzoom 13.5, filtro hide_3d, 57), y `sound-fields` (circle, 59) con color interpolado por `score`: 0 #d9c7fa, .5 #ae77ee, 1 #6720c4; radio por zoom 16/43/120/220 en zooms 11/13/16/19; circle-blur .85; opacity .48. Comentario: "Color encodes noise score, not the number of contributors. No density heatmap." (58).
- Vista inicial `home` center [-122.447,37.776] zoom 12.75 (page.tsx:62); minZoom 10, maxZoom 19 (86); `lib.setWorkerUrl('/maplibre-gl-worker.mjs')` (85) usa el worker vendorizado en public/.
- Marcadores DOM: un `<button class="sound-point [landmark-point]">` por punto, con aria-label "Nombre · sound level high|moderate|low simulated" (umbrales >.65 / >.35, page.tsx:95), `aria-pressed`, color `--point-color` por tramos .75/.5/.3 (96), etiqueta de nombre (97). Click: selecciona (is-selected/aria-pressed, 98) y `easeTo` a zoom >=15.4 en 900 ms. Nota: los umbrales de la etiqueta (.65/.35) y del color del marcador (.75/.5/.3) son distintos entre sí.
- Pulsos: `setInterval` cada 1300 ms elige `markers[(index*7+2)%points.length]`, añade `is-contributing` y la quita a los 2300 ms (page.tsx:102-107); respeta pausa vía `playRef` (botón play/pause, 130). Con 31 puntos y paso 7 (coprimo con 31) recorre los 31 puntos de forma determinista. CSS de animación `quiet-signal` en map.css:26; `prefers-reduced-motion` desactiva animaciones/transiciones (map.css:28). Son simulados: la ayuda dice "A pulse illustrates a new contribution" (page.tsx:143).
- Etiquetas de honestidad: badge "SIMULACIÓN" fijo (page.tsx:136, map.css:12), leyenda de intensidad con role="img" (137, map.css:13-14), aria-label del canvas dice "Darker violet means higher simulated sound levels. Pulses represent fictional contributions." (89), nota "Visual simulación · synthetic levels and contributions. MCP is not connected." (145).
- Controles: reset (reset(), 119), 3D toggle pitch 54/bearing -24 (tilt(), 120; solo si supports3D), zoom +/- (133-134), play/pause (130).
- Fallback 2D si MapLibre/WebGL2 falla: `catch` en start (108) llama `fallback()` que importa lib/canvas-map.ts (74-81): OpenLayers + MVT sobre el mismo TileJSON (fetch a tiles.openfreemap.org/planet, canvas-map.ts:16-18); crea los mismos marcadores como overlays (canvas-map.ts:34-42); NO dibuja la capa violeta `sound-fields` (solo un `.fallback-glow` por punto en CSS, map.css:30) y oculta el 3D (`setSupports3D(false)`, page.tsx:79). Hay un desfase de zoom +1 entre OL y MapLibre (canvas-map.ts:33,43).
- Estados de error: spinner `.quiet-loading` hasta evento 'load'; `.quiet-map-error` con botón de reintento (page.tsx:124-125; onerror 91 solo marca fallo si el estilo no cargó).
- Dependencia de red: sin red no hay mapa base ni fallback (ambos fetch a OpenFreeMap). CONFIGURACION.md indica que "los mapas requieren red; no se solicita geolocalización ni micrófono".
- Ninguna API alimenta el mapa: no hay fetch a /api para puntos; el endpoint /api/oura/* no se usa en `/`.

### Cómo se podría verificar (propuestas derivadas, no existentes hoy)
- Datos: extraer `points`/`soundData` a un módulo (p. ej. lib/sound-points.ts) para testear con node:test: 31 puntos, lng/lat dentro del bbox de SF, score en [0,1], nombres únicos, 7 landmarks, GeoJSON ids únicos.
- Capas: con navegador (Playwright) esperar 'load' y consultar `map.getStyle().layers` (ids: background, land, parks, water, roads-edge, roads, footprints, structures, sound-fields), `map.querySourceFeatures('sound')` (31), `map.getPaintProperty('sound-fields','circle-color')`; mock de tiles OpenFreeMap para pruebas deterministas/offline; probar fallback forzando fallo de WebGL2.
- UI/accesibilidad: 31 botones `.sound-point`, 7 con `.landmark-point`; click => `.is-selected` y `aria-pressed="true"` únicos; pulso => clase `.is-contributing` en secuencia (index*7+2)%31 cada 1300 ms (usar fake timers); pausa detiene; reduced-motion; diálogo MCP: foco, Escape, trampa de Tab, copiar JSON == `contract`.

### Inferences
- Como el mapa lee un literal, "verificar datos" hoy equivale a verificar un fixture; cuando exista el MCP, el mapa debería consumir `query_sound_map` para que prueba de contrato y prueba de mapa coincidan.
- Riesgos de prueba: la dependencia de tiles externos (flakiness), WebGL2 en CI headless (necesita flags/swiftshader), y los timers del pulso.

### Gaps
- No se pudo renderizar el mapa (sin navegador): comportamiento visual, rendimiento de 31 marcadores DOM y el fallback OL no se verificaron en ejecución. Solo lectura de código.
- No se verificó que las capas source-layer del estilo (landcover, park, water, transportation, building) existan con esos nombres en el esquema OpenMapTiles remoto.

## 5. Brechas concretas que bloquean probar el MCP y el mapa

### Takeaway
Para el MCP el bloqueo es total (no hay servidor ni esquema ni datos compartidos). Para el mapa se puede probar ya la UI contra un fixture, pero faltan harness de navegador, extracción de datos y una decisión sobre contrato único.

### Cited Findings (brechas)
MCP
1. No existe servidor/endpoint MCP (404 en /mcp, /api/mcp, /.well-known/mcp en dev; ningún código; QUIET_COMPASS_IDEA.md:96,241). Ni SDK MCP en package.json.
2. Contrato sin esquema: inputs como cadenas descriptivas (page.tsx:63); sin outputs, errores, ni versionado, aunque el brief propone `schema_version:"0.1"` (IDEA:111-129).
3. Tres definiciones inconsistentes (page.tsx:63 bounds/max_age_minutes/preference; CONFIGURACION.md area/time_window/goal/constraints/measurement_quality; IDEA area_id/time_bucket/measurement/quality/source).
4. Sin almacenamiento: hosting.json d1:null, r2:null; db/schema.ts vacío; no hay ingestión ni agregación; `submit_observation` no tiene destino. El brief marca "Shared observation database and ingestion: Not implemented" (IDEA:244).
5. Sin autenticación/cuotas/validación para agentes externos; el sitio completo está detrás de auth de Sites y las rutas usan getChatGPTUser (route.ts:11-12), que no es válido para clientes MCP de terceros.
6. Sin lógica de privacidad testeable: umbral mínimo de contribuyentes, supresión, redondeo, rate-limit, duplicados: todo "Proposed" (IDEA:245; CONFIGURACION.md).
7. Sin skill de agente (reglas listadas en IDEA:100-108 y CONFIGURACION.md, pero no hay archivo de skill).
Mapa
8. Sin runner de UI/E2E ni script `test`; solo 1 prueba unitaria no relacionada (tests/seal.test.mjs).
9. Datos y estilo embebidos en un componente cliente; no importables; `points`, `soundData`, `mapStyle` no exportados (page.tsx:11,44,45).
10. Dependencia de tiles externos OpenFreeMap (page.tsx:47, canvas-map.ts:16) y de WebGL2; sin mock ni modo offline.
11. El fallback OL no tiene capa violeta: la verificación visual de "intensidad violeta" no es equivalente en ambos motores.
12. Lint rojo (5 errores en /connections y /event; 1082 warnings por bundle vendorizado) impide usar `pnpm lint` como compuerta.
13. Los datos sintéticos no tienen marcas de edad/antigüedad, cobertura, calidad ni tipo de medición, que el brief exige que el mapa muestre ("Selectable points revealing measurement type, age, and uncertainty", IDEA:209); el click solo hace zoom, no abre ficha. Tampoco existe indicador de "unknown coverage" por zona más allá del color blanco.
14. La UI aún dice "MCP is not connected"; cualquier prueba de integración mapa<->MCP no tiene qué verificar.

### Inferences
- Primer paso de bajo costo: elegir un contrato canónico (zod ya está instalado) y exportar fixtures; con eso se pueden escribir pruebas de contrato con node:test sin servidor y pruebas de mapa con Playwright + tiles mockeados.
- Una ruta Next `app/api/mcp/route.ts` (o Worker handler) sería el punto natural para el servidor, pero chocaría con el requisito de auth de Sites; hay que decidir si el endpoint MCP será público/anónimo para la simulación.

### Gaps
- No se investigó la raíz del repo más allá de QUIET_COMPASS_IDEA.md (carpeta reports/ vacía; research_notes/ solo contiene este directorio).
- No se revisaron en detalle app/event/page.tsx ni app/connections/page.tsx (presentaciones/UI de Oura, fuera del alcance MCP/mapa) ni app/chatgpt-auth.ts.
- Referencias externas del brief (MCP architecture, NIOSH, NoiseCapture, SONYC-UST-V2, YAMNet; IDEA:286-290) no se re-verificaron; no son necesarias para el estado del repo.
