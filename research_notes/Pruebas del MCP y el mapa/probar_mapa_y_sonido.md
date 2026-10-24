# Cómo probar un mapa MapLibre GL JS interactivo y un flujo de medición de sonido con el micrófono del móvil (2026)

Nota de método: las citas provienen de documentación oficial (Playwright, MDN, W3C, MapLibre, Chromium, NIOSH/CDC) y del bug tracker de WebKit. Cuando una afirmación no pude verificarla en una fuente, está en Inferencias o Vacíos, no en Hallazgos. No se verificaron números de versión exactos de maplibre-gl, Playwright ni axe-core; hay que fijarlos con `npm ls` en el repo.

## 1. E2E y pruebas visuales del mapa con Playwright (WebGL headless, esperar idle, consultar features, screenshots)

### Takeaway
Usar Chromium con WebGL por software (SwiftShader, que en Chrome 139+ exige opt-in explícito), esperar a que el mapa termine de renderizar antes de cada captura, y asertar sobre datos (`queryRenderedFeatures`) más que sobre píxeles; los screenshots solo como complemento con tolerancias y baselines por plataforma.

### Cited Findings
- Chromium documenta SwiftShader como herramienta para probar sitios en sistemas headless o sin GPU soportada; el fallback de WebGL a SwiftShader está deprecado y requiere el opt-in `--enable-unsafe-swiftshader`. Combinación documentada para WebGL por software: `--use-gl=angle --use-angle=swiftshader-webgl` — [Chromium: Using Chromium with SwiftShader](https://chromium.googlesource.com/chromium/src.git/+/refs/tags/98.0.4758.21/docs/gpu/swiftshader.md) (búsqueda web resumió el contenido de varias revisiones del doc)
- Desde Chrome/Edge M139, la creación de contexto WebGL falla si usaría SwiftShader sin el flag — [Samsung Internet policy page / resumen de política](https://developer.samsung.com/browser/policy/enable-unsafe-swift-shader.html) (fuente secundaria; verificar en release notes de Chromium)
- Un commit de terceros indica que `--disable-gpu` rompe WebGL en Chrome 130+ y que Playwright usa `--enable-unsafe-swiftshader` para render por CPU — [chrome-use commit](https://gitea.oimcloud.myaddr.tools/oimwiodev/chrome-use/src/commit/486e1b341fbe1e1a6bbf9bfc885ec0e2d34eb45c/cli) (fuente de baja autoridad)
- Firefox no soporta WebGL en headless según un reporte para Mapbox GL en CI (workaround: xvfb-run); el repo de OpenStreetMap usa Xvfb para pruebas de navegador — [createit](https://www.createit.com/?p=3319) y [openstreetmap rails entrypoint](https://git.openstreetmap.org/rails.git/blob/3f6708f4f1c8f4ba7ff258de4dd00a338b231c34:/docker/entrypoint.sh) (fuentes secundarias)
- La clase `Map` de MapLibre expone `queryRenderedFeatures`, `querySourceFeatures`, `project`/`unproject`, `jumpTo`/`easeTo`/`flyTo`/`fitBounds`, y accesores de depuración (`showTileBoundaries`, `showCollisionBoxes`, `repaint`, `version`) — [MapLibre Map API](https://maplibre.org/maplibre-gl-js/docs/API/classes/Map/)
- Opciones de `Map` relevantes: `fadeDuration` (def. 300 ms; fade de colisión de etiquetas, no afecta transiciones de estilo en runtime), `canvasContextAttributes` (def. `preserveDrawingBuffer:false`, `failIfMajorPerformanceCaveat:false`, `antialias:false`, contextType `webgl2`), `cooperativeGestures` (def. false; Ctrl/Cmd en escritorio, dos dedos en móvil), `keyboard` (def. true) — [MapLibre MapOptions](https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/MapOptions/)
- `expect(page).toHaveScreenshot()` espera dos capturas consecutivas iguales antes de comparar; `animations` por defecto "disabled" (CSS animations/transitions/Web Animations; las infinitas se reinician); opciones `mask` (locators, color rosa por defecto, `maskColor`), `maxDiffPixels`, `maxDiffPixelRatio`, `threshold` (0.2 por defecto, espacio YIQ), `scale` ("css" por defecto), `caret` — [Playwright PageAssertions](https://playwright.dev/docs/api/class-pageassertions)
- Los nombres de snapshot incluyen navegador y plataforma (p. ej. `-chromium-darwin.png`) porque el render difiere entre plataformas/fuentes; se pueden configurar defaults en `expect.toHaveScreenshot` del config y `snapshotPathTemplate`; `stylePath` permite ocultar elementos volátiles — [Playwright Snapshots](https://playwright.dev/docs/test-snapshots)
- Playwright permite emular dispositivos (`devices['iPhone 13']`: UA, viewport, touch, `isMobile`), `colorScheme` y `context.grantPermissions()` — [Playwright Emulation](https://playwright.dev/docs/emulation)

### Inferences
- Importante: `animations: "disabled"` de Playwright solo detiene animaciones CSS/WAAPI. Los pulsos y fades dibujados en WebGL/canvas o con `requestAnimationFrame` y `setPaintProperty` NO se congelan; hay que exponer un modo de prueba (p. ej. `?test=1` o `window.__TEST__`) que fije el reloj de animación, ponga `fadeDuration: 0` y use datos sintéticos con semilla fija.
- Receta práctica: lanzar Chromium con `args: ['--use-gl=angle','--use-angle=swiftshader-webgl','--enable-unsafe-swiftshader']` (probar primero solo `--enable-unsafe-swiftshader`; los defaults de Playwright pueden bastar). Verificar en una prueba de humo que `canvas.getContext('webgl2')` no sea null.
- Esperar al mapa: exponer `window.__mapReady` que se pone en true tras `map.once('idle')` (el evento `idle` se dispara cuando no hay más renderizado pendiente; no lo pude confirmar en la página de la API que se cargó truncada, verificar en la sección Events) y esperar con `page.waitForFunction(() => window.__mapReady)`. Tras cada `jumpTo`/`flyTo` en tests, volver a esperar `idle`. Preferir `jumpTo` a `flyTo` para determinismo.
- Aserciones por datos: `page.evaluate(() => map.queryRenderedFeatures({layers:['zonas-intensidad']}).length)`, comprobar propiedades (`db_mean`, `synthetic: true`), que los marcadores existan (DOM `.maplibregl-marker` si son `Marker`; capa de símbolos si no) y que la leyenda/etiqueta "datos sintéticos" esté visible en el DOM.
- Screenshots: capturar solo el locator del canvas con `maxDiffPixelRatio` ~0.01–0.02, enmascarar controles/atribución/reloj; generar baselines en el mismo contenedor CI (Docker de Playwright) y nunca compararlos con los de la máquina local. Teselas de fondo: usar un estilo mínimo local (GeoJSON + fondo plano) para evitar red y variaciones.
- Simular móvil: proyecto con `devices['Pixel 7']` y `devices['iPhone 13']` (WebKit de Playwright no equivale a Safari iOS real, ver sección 3).

### Gaps
- No hallé guía oficial de MapLibre sobre testing con Playwright ni flags específicos de MapLibre en headless; las recomendaciones salen de docs de Chromium/Playwright.
- No verifiqué la lista exacta de eventos (`idle`, `load`, `render`) ni versiones concretas de maplibre-gl en 2026 (la página de la API devuelta fue truncada).
- No confirmé en fuente primaria (release notes de Chromium) el cambio de M139; solo una página de política secundaria.

## 2. Pruebas unitarias del DSP acústico (RMS, dispersión, L10/L90, clipping) con señales sintéticas

### Takeaway
El DSP debe ser una función pura sobre `Float32Array` (independiente de Web Audio) para probarla en Node/Vitest con señales de nivel conocido: seno de amplitud A tiene RMS A/√2 (−3.01 dBFS cuando A=1), silencio da −∞ (hay que acotar), y ruido/clipping se generan con PRNG con semilla.

### Cited Findings
- Un `AudioWorkletProcessor` recibe en `process()` bloques de 128 frames (render quantum), 128/48000 ≈ 2,67 ms a 48 kHz y ≈ 2,90 ms a 44,1 kHz; `inputs` son arrays de canales Float32; devolver `true` mantiene vivo el procesador — [MDN AudioWorkletProcessor](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletProcessor) (las cifras de tiempo y `sampleRate` las derivó la herramienta de la especificación Web Audio, no del texto de MDN)
- Apps de medición de sonido en smartphone: de 10 apps seleccionadas por NIOSH solo 4 estuvieron dentro de ±2 dB de un sonómetro tipo 1; iOS superó a Android en el piloto 2013; con micrófonos externos calibrados la exactitud mejora mucho y se pueden cumplir la mayoría de requisitos Clase 2 IEC 61672 — [NIOSH blog](https://cdc.gov/niosh/blogs/2014/sound-app.html), [CDC stacks (Kardous & Shaw)](https://stacks.cdc.gov/view/cdc/211440)
- La OSHA considera instrumentos tipo 2 con exactitud ±2 dBA (mismo resultado de búsqueda, resumen) — [NIOSH blog](https://cdc.gov/niosh/blogs/2014/sound-app.html)

### Inferences
- Casos de prueba con tolerancias (fs=48000, 1 s, Float32):
  - Seno 1 kHz amplitud 1.0 (periodos enteros): RMS = 0,70711 → −3,01 dBFS (tol. ±0,01 dB). Amplitud 0.1 → −23,01 dBFS. Amplitud 0.5 → −9,03 dBFS.
  - Silencio (ceros): RMS 0 → devolver un piso (p. ej. −120 dBFS con `Math.max(rms, 1e-6)`) y comprobar que no sale `-Infinity`/`NaN`.
  - Constante DC 0.5: RMS 0.5 → −6,02 dBFS (decidir si se filtra DC).
  - Ruido blanco uniforme en [−a, a]: RMS = a/√3 (tol. estadística ~1 % con N≥48000); gaussiano con σ: RMS = σ. Usar PRNG con semilla (mulberry32) para determinismo.
  - Clipping: seno de amplitud 1.5 recortado a ±1 → contar muestras con |x|≥0.999; esperar fracción de clipping conocida (para A=1.5: ≈ 1 − (2/π)·... calcular analíticamente en el test); y caso de nivel exactamente 1.0 sin recorte para fijar el umbral.
  - Escalón de nivel (1 s a −40 dBFS, 1 s a −20 dBFS): L10 debe ser cerca de −20 y L90 cerca de −40 (L_N = nivel superado el N % del tiempo; L10 = percentil 90 de los niveles de trama, L90 = percentil 10). Probar con distribución conocida (rampa lineal en dB: L10/L90 son valores analíticos).
  - Dispersión de tramas: señal de nivel constante → desviación/rango ≈ 0; alternando dos niveles → rango = diferencia.
  - Ventana de 30 s: probar con bloques de 128 muestras alimentados en orden (y con tamaño de bloque irregular) que el número de tramas y el resultado coinciden con el cálculo en un solo vector; probar ventana incompleta (cancelación a los 12 s → no emitir medición válida) y descarte de los primeros ms de arranque.
  - Promediar niveles: la media de dB no es la media energética (Leq); probar que el cálculo usa energía (Leq) para el resumen y percentiles sobre dB por trama.
- Distinguir siempre dBFS (relativo a fondo de escala digital) de dB SPL: sin calibración con un sonómetro de referencia, el valor es un índice relativo, no SPL (evidencia NIOSH arriba). Etiquetar en UI y tests: "dBFS relativo, no calibrado".
- Para probar el worklet en sí: probar la clase con un shim (`registerProcessor` simulado) llamando a `process()` con arrays sintéticos; el cálculo real va en un módulo compartido.

### Gaps
- No encontré una referencia oficial para fórmulas L10/L90 en contexto de apps web; las definiciones L_N provienen de acústica ambiental estándar (no citadas aquí).
- No verifiqué valores numéricos exactos del paper JASA 2016 (el resumen extraído salía corrupto).

## 3. Probar la captura de micrófono en navegadores (streams falsos, restricciones en iOS/Android, HTTPS)

### Takeaway
En CI se usa Chromium con `--use-fake-ui-for-media-stream`, `--use-fake-device-for-media-stream` y `--use-file-for-fake-audio-capture=archivo.wav` para inyectar audio de nivel conocido; en iOS Safari las restricciones de procesado no son fiables, por lo que hay que leer `track.getSettings()` y probar en dispositivos reales.

### Cited Findings
- `getUserMedia` solo funciona en contextos seguros (HTTPS, `localhost`, `file:///`); en contexto inseguro `navigator.mediaDevices` es `undefined` y la llamada lanza `TypeError`. No funciona en iframes sandbox sin `allow-same-origin`, ni en documentos `data:`/`blob:` sin origen — [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Errores: `NotAllowedError` (permiso denegado, contexto inseguro o Permissions Policy), `NotFoundError`, `OverconstrainedError` (solo con `min`/`max`/`exact`; no se pide permiso al usuario), `NotReadableError`, `AbortError`, `TypeError`; la promesa puede no resolverse nunca si el usuario ignora el aviso — [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Valores simples e `ideal` son preferencias; `exact`/`min`/`max` son obligatorios y rechazan con `OverconstrainedError` — [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Para iframes cross-origin: `<iframe allow="microphone">` y cabecera `Permissions-Policy: microphone=(self)` — [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Especificación W3C: `echoCancellation` es boolean o enum ("all", "remote-only"); `autoGainControl` y `noiseSuppression` son boolean; en capabilities, un único `false` significa no soportado, un único `true` significa que no se puede desactivar, ambos valores significan conmutable; `getSettings()` devuelve el valor realmente aplicado; `getSupportedConstraints()` lista las restricciones reconocidas — [W3C Media Capture and Streams](https://www.w3.org/TR/mediacapture-streams/)
- Flags de Chromium: `--use-file-for-fake-audio-capture=<archivo>` reproduce un archivo en lugar del pitido por defecto y debe usarse junto con `--use-fake-device-for-media-stream` (la petición original lo escribe en plural); se recomienda WAV; el dispositivo falso se configura una vez por instancia de navegador (para otro audio hay que lanzar otra instancia); solo Chromium — [Chromium code review](https://codereview.chromium.org/734993002), [QA Wolf: web audio injection](https://docs.qawolf.com/qawolf/web-audio-injection), [TIL: Playwright con audio falso](https://omarelb.substack.com/p/til-2-set-up-playwright-with-fake), [Autify](https://helpcenter.autify.com/docs/media-stream-testing)
- Se combinan con `permissions: ['microphone']` en el contexto de Playwright y `--use-fake-ui-for-media-stream` para saltar el diálogo — [guía Playwright permisos](https://qaskills.sh/blog/playwright-emulation-geolocation-permissions-guide) (fuente secundaria); `context.grantPermissions()` documentado en [Playwright Emulation](https://playwright.dev/docs/emulation) (la página no menciona micrófono específicamente)
- iOS/Safari: WebKit bug 179411 (2017) reportó que `echoCancellation/noiseSuppression/autoGainControl: false` no se aplicaban en Safari 11; bug 311451 indica que echoCancellation es la única restricción que usa Safari y que la calidad se degrada (menor frecuencia de muestreo, estéreo a mono) con o sin la restricción, problema largo de iOS/iPadOS que no afecta a Safari en macOS; bug 281978: con `echoCancellation:false` un micro mono devuelve pista estéreo con solo canal izquierdo y `channelCount` no tiene efecto (iOS 17.6.1, Safari 18); foro de Apple: persiste en Safari 26 macOS — [WebKit 179411](https://bugs.webkit.org/show_bug.cgi?id=179411), [WebKit 311451](https://bugs.webkit.org/show_bug.cgi?id=311451), [WebKit 281978](https://bugs.webkit.org/show_bug.cgi?id=281978)
- WebKit 326286: en iOS 26.2 a 27, con echoCancellation activa hay crepitar en el audio reproducido; desactivarla lo evita pero mueve la salida al auricular — [WebKit 326286](https://bugs.webkit.org/show_bug.cgi?id=326286)
- WebKit 319706: tras un reset del demonio de audio en iOS 26 queda un `NotAllowedError` permanente hasta recargar la página completa — [WebKit 319706](https://bugs.webkit.org/show_bug.cgi?id=319706)

### Inferences
- Tests automáticos (Chromium): generar WAV de calibración con el mismo generador de la sección 2 (p. ej. seno 1 kHz a −20 dBFS, 48 kHz, 16 bit, 40 s) y comprobar que el RMS medido está en ±1 dB de −20 dBFS. Con el pitido por defecto no hay nivel conocido, usar siempre archivo. Un proyecto de Playwright por archivo (silencio, −20 dBFS, ruido, clipping).
- Las restricciones deben pedirse como preferencia (`{echoCancellation:false, noiseSuppression:false, autoGainControl:false}` sin `exact`) y luego validar con `track.getSettings()`; si algún valor sigue en `true`, mostrar aviso y marcar la medición como "procesada por el SO/navegador" (baja confianza). Evitar `exact` para no bloquear dispositivos iOS con `OverconstrainedError`.
- Casos de permisos a probar con Playwright: concedido, denegado (`NotAllowedError` → mensaje y reintento), sin micrófono (`NotFoundError`; emular con `addInitScript` que reemplaza `navigator.mediaDevices.getUserMedia`), HTTP no seguro (mediaDevices undefined → mensaje de requiere HTTPS), usuario que ignora el diálogo (timeout de UI), pestaña en segundo plano/pantalla bloqueada (AudioContext suspendido; llamar `audioContext.resume()` tras gesto del usuario).
- Android Chrome: se puede depurar remotamente por USB (chrome://inspect) con la misma app sobre HTTPS (túnel tipo ngrok/cloudflared o `adb reverse` a localhost, ya que localhost cuenta como seguro). iOS: Safari Web Inspector con Mac. No cité fuentes para esto; verificar.
- WebKit de Playwright no reproduce los bugs de captura de iOS real; para iOS hace falta dispositivo físico o servicio de nube de dispositivos.

### Gaps
- No encontré tabla oficial de compatibilidad 2026 de `noiseSuppression/autoGainControl` en Android Chrome (en Chrome suelen ser conmutables, pero no lo pude citar). Revisar MDN/caniuse.
- No verifiqué en documentación oficial de Playwright que `permissions: ['microphone']` baste con los flags (hay fuente secundaria).
- No confirmé si el flag de audio falso está documentado hoy en una página de Chromium; solo code review original y guías de terceros.

## 4. Protocolo de prueba de campo con un teléfono (orientación, posición de la mano, repeticiones, app de referencia)

### Takeaway
Con un solo teléfono sin calibrar, el objetivo defendible es comparar lugares de forma relativa, con protocolo fijo y repeticiones, y validar contra una app/sonómetro de referencia; no declarar dB SPL absolutos.

### Cited Findings
- Estudios NIOSH: solo 4 de 10 apps cumplían ±2 dB frente a un sonómetro tipo 1; micrófonos externos calibrados mejoran mucho la exactitud; iOS fue más fiable que Android en el piloto — [NIOSH](https://cdc.gov/niosh/blogs/2014/sound-app.html), [CDC stacks](https://stacks.cdc.gov/view/cdc/211440)
- La app NIOSH SLM (iOS) fue calibrada contra ANSI/IEC y comparada en estudios posteriores (p. ej. con SPL Meter en iPhone 6S, con y sin micrófono externo) — [Thieme 2020](https://www.thieme-connect.com/products/ejournals/pdf/10.1055/s-0040-1719137.pdf), [Applied Acoustics 2018 vía NIOSH/ASA](https://acoustics.org/2pnsb-a-smartphone-noise-meter-app-in-every-pocket-chucri-a-kardous-peter-b-shaw/)

### Inferences
(Diseño propio; no hay fuente que lo prescriba. Verificar con un acústico si el resultado se publicará.)
- Antes del campo: (1) medir en habitación silenciosa y con ruido rosa/tono a volumen fijo desde otro altavoz, comparando contra una app de referencia (p. ej. NIOSH SLM en iPhone) con el mismo teléfono al lado; (2) obtener el offset dBFS→dB aproximado por modelo y registrarlo como "calibración informal", no como SPL; (3) confirmar en la UI que `getSettings()` reporta echo/noise/AGC en false.
- Protocolo de captura: mismo teléfono y navegador; sin funda gruesa; micrófono inferior sin tapar; sostener a la altura del pecho, brazo extendido ~30–50 cm del cuerpo, con la parte inferior del teléfono apuntando hacia la fuente o hacia el centro del espacio, siempre igual; no hablar ni moverse durante los 30 s; apartarse de paredes ≥1 m si es posible; evitar el viento (usar espuma antiviento improvisada y anotar viento).
- Repeticiones: ≥3 ventanas de 30 s por punto, en 3 horarios (pico y valle); orden aleatorizado entre puntos, o ABBA, para separar deriva temporal; descartar y repetir si hay evento anómalo (claxon, voz cercana) anotado en una hoja; registrar fecha/hora, clima, orientación, modelo, SO, navegador, versión de la app, y si hubo clipping.
- Criterios de aceptación del simulación: repetibilidad (desviación entre repeticiones del mismo punto ≲ 2–3 dB), ordenamiento correcto de lugares conocidos (biblioteca < calle residencial < avenida) y coincidencia de ordenamiento con la app de referencia; reportar L10/L90 y Leq por punto.
- Etiquetado: toda visualización de mediciones reales debe mostrar "dBFS relativo, no calibrado"; datos de demostración con insignia "datos sintéticos" visible y presente en el atributo accesible del elemento y en el export.
- Privacidad: pedir consentimiento, no grabar ni subir audio, solo agregados (RMS/percentiles); verificarlo en el test de red (Playwright intercepta requests y comprueba que ninguna lleva audio crudo).

### Gaps
- No hay un protocolo estándar citable para mediciones ambientales con teléfono único en web; el de arriba es una propuesta. Las normas ISO 1996 (ruido ambiental) e IEC 61672 no se consultaron directamente.

## 5. Accesibilidad del mapa (axe, teclado, prefers-reduced-motion)

### Takeaway
Ejecutar axe-core con `@axe-core/playwright` en estados clave (inicial, panel abierto, modal de permiso), probar el flujo por teclado manualmente en Playwright y emular `reduced-motion` para comprobar que pulsos y vuelos se desactivan; el canvas de WebGL no es accesible por sí mismo, por lo que se necesita una alternativa textual.

### Cited Findings
- `@axe-core/playwright`: `new AxeBuilder({ page }).analyze()` y aseverar `violations` vacío; `.include()`, `.exclude()`, `.withTags(['wcag2a','wcag2aa'])`, `.disableRules()`; adjuntar resultados con `testInfo.attach()`; usar fixture compartido; para problemas conocidos conviene snapshot de huella (regla + selector) — [Playwright Accessibility testing](https://playwright.dev/docs/accessibility-testing)
- Limitaciones: la automatización solo detecta una parte de los problemas, `analyze()` escanea el estado actual de la página, `exclude()` anula todas las reglas del elemento y sus hijos — [Playwright Accessibility testing](https://playwright.dev/docs/accessibility-testing)
- MapLibre: opción `keyboard` (def. true) activa atajos de teclado; `cooperativeGestures` evita atrapar el scroll en móvil/escritorio; `fadeDuration` controla el fundido de etiquetas — [MapLibre MapOptions](https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/MapOptions/)
- Playwright permite `colorScheme` vía config o `page.emulateMedia()` — [Playwright Emulation](https://playwright.dev/docs/emulation) (la página no cubre `reducedMotion`)

### Inferences
- Emular movimiento reducido: `test.use({ reducedMotion: 'reduce' })` o `page.emulateMedia({ reducedMotion: 'reduce' })` (opción existente de Playwright; no citada porque la página cargada no la cubre; comprobar en la API de `emulateMedia`). Asertar que la app lee `matchMedia('(prefers-reduced-motion: reduce)')` y: no hay pulsos, `flyTo` pasa a `jumpTo`/`duration:0`, `fadeDuration: 0`, y la intensidad se comunica por color/tamaño estático, no solo por animación. Probar también el cambio en caliente (evento `change` del MediaQueryList).
- Teclado: Tab llega a controles del mapa, filtros, lista de lugares y botón "Medir"; foco visible; las flechas y +/− mueven el zoom con `keyboard:true`; Esc cierra paneles; no hay trampa de foco; los marcadores deben ser `button`/enlaces focalizables con `aria-label` (nombre, nivel, "dato sintético").
- Alternativa no visual del canvas: tabla o lista ordenada de lugares con nivel (con encabezados), `role="img"` + `aria-label` en el contenedor del mapa o `aria-describedby` hacia un resumen, región `aria-live="polite"` para anunciar el resultado de la medición de 30 s ("Medición completa: 62 dBFS relativo").
- Contraste y no depender solo del color: comprobar con axe (`color-contrast`, no aplica al canvas, así que revisar la paleta del mapa manualmente con un verificador de contraste) y añadir patrón/etiqueta numérica; probar `forced-colors` y zoom 200 %/reflow a 320 px.
- Pruebas móviles: objetivos táctiles ≥24×24 px (WCAG 2.2 AA, 2.5.8) — no cité fuente; verificar con la especificación WCAG 2.2.

### Gaps
- No obtuve fuentes oficiales para WCAG 2.2 ni para el atributo `reducedMotion` de Playwright en esta pasada.
- axe no evalúa el contenido dentro del canvas WebGL; no encontré guía oficial de MapLibre sobre accesibilidad del canvas.
