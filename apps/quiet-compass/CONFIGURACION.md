# Quiet Compass · Oura

Aplicación privada para conectar Oura y mostrar sueño, recuperación y actividad. El mapa acústico, la captura FOA, las reservas y un agente externo todavía NO están implementados. La recomendación es una simulación por reglas basada en preferencias explícitas. El modo ejemplo está marcado y usa datos ficticios.

## Configurar tu cuenta

1. Abrí Oura y sincronizá el anillo. Gen3 y posteriores necesitan membresía activa para acceso API.
2. Abrí https://cloud.ouraring.com/oauth/applications y registrá una app llamada Quiet Compass.
3. Homepage: https://quiet-compass-oura-martin.martin-puli.chatgpt.site
4. Redirect URI exacta: https://quiet-compass-oura-martin.martin-puli.chatgpt.site/api/oura/callback
5. En la app web, elegí **Conectar Oura** y pegá Client ID y Client Secret. No los mandes por chat.
6. Guardá la configuración y pulsá **Autorizar en Oura**. Autorizá el permiso daily.
7. Volvé a Mi día. La app consulta los últimos ocho días y muestra fecha de cada métrica. No es una transmisión en vivo.

Se necesita una cuenta con registros previos para mostrar una noche real. Si no hay datos, usar **Explorar con datos de ejemplo** sin presentarlos como mediciones reales.

## Sesiones y privacidad

Sitio privado protegido por autenticación de Sites. Las rutas verifican identidad. Credenciales y access token se guardan cifrados con AES-GCM en cookies Secure, HttpOnly, SameSite=Lax, ligadas al usuario. OAuth usa state y PKCE. Las operaciones POST validan Origin. No se solicitan pulso, correo ni datos personales. No se guarda audio ni registros de salud en la base de datos.

La configuración se conserva siete días en este navegador; el acceso vence a más tardar en doce horas. No almacenamos refresh tokens: reautorizar al vencer. Desconectar borra credenciales y sesión locales; para revocar el grant, hacerlo también en Oura. No usar la simulación como diagnóstico o detector de sobrecarga.

## Desarrollo

Instalar dependencias y ejecutar `npm run dev` en un entorno compatible con el starter Sites/Vinext. Variables server-only: `SESSION_ENCRYPTION_KEY` (64 caracteres hex aleatorios) y `APP_ORIGIN` (origen exacto). Configuradas en el alojamiento; nunca incluir secretos en el repo. Las cookies Secure requieren HTTPS y las rutas requieren identidad de Sites. No simular autenticación en producción.

Pruebas: `node --test tests/*.test.mjs`. Typecheck: `npx tsc --noEmit`. OAuth real requiere credenciales y autorización del titular; no se puede certificar sin conectar su cuenta.

Fuentes: https://cloud.ouraring.com/docs/authentication y https://cloud.ouraring.com/v2/docs

## Simulación visual del agente — actualización

La ruta `/` ahora es una historia interactiva centrada en el agente personal: conversación preparada, mapa SVG ficticio, cuatro etapas del recorrido y una capa colectiva simulada. `/connections` conserva la integración Oura real. No existe todavía un servidor de contribuciones, un modelo conectado, sensores activos ni garantías de anonimato. El botón de tres contribuciones modifica únicamente estado React local.

### Arquitectura colectiva propuesta y evidencia

Separar memoria privada (recorrido, preferencias, feedback, agenda y Oura) de observaciones compartidas del ambiente. Publicar resúmenes por zona y ventana temporal con participación explícita; no publicar trazas, audio, identificadores de cuenta o salud. No confundir quitar nombres con anonimato: la ubicación temporal permite inferencias. El servidor y sus proveedores todavía pueden observar metadatos de red; minimizar logs y retención es parte del diseño.

Primera versión: acceso restringido al evento, zonas predefinidas identificadas por QR o selección manual. Un QR simple identifica una zona, pero no alinea por sí solo un mapa AR completo. Compartir coordenadas AR requiere un origen común/relocalización, no concatenar coordenadas de teléfonos distintos. Apple documenta experiencias multiusuario con ARWorldMap; compartir mapas espaciales también requiere control de acceso.

Contribuciones: medir localmente durante una sesión autorizada, producir resúmenes acotados, limitar aportes por participante/ventana y rechazar duplicados. La cuenta puede servir para cuotas en una capa de admisión separada; conservar tokens por evento implica seudonimización, no anonimato. Evitar perfiles de sensores tan detallados que vuelvan identificable al participante. Validar compatibilidad/calibración antes de combinar niveles absolutos; las métricas relativas de teléfonos diferentes no son automáticamente comparables.

Para mostrar un agregado, exigir un mínimo configurable de participantes diferentes, usar ventanas fijas, suprimir grupos pequeños, redondear recuentos y evitar consultas arbitrarias que permitan restar agregados. El umbral de tres de la simulación es ilustrativo, no una garantía de privacidad. Privacidad diferencial y agregación segura son opciones posteriores que requieren modelo de amenazas, límites de contribución y presupuesto de privacidad; no basta con añadir ruido al azar. Con poca participación, aceptar que algunas zonas no tengan datos.

Presupuesto ilustrativo externo, no precio de Sites: 50 usuarios durante 4 horas, una subida cada 2 minutos y una consulta por minuto = 6.000 subidas + 12.000 consultas = 18.000 solicitudes API antes de extras. Un resumen de 500 bytes supone 3 MB de payload de subida, sin headers/TLS. Suponiendo tres filas escritas por aporte: 18.000 escrituras base, más índices y otros registros. Consultas indexadas y agregados cacheados evitan escanear toda la tabla. No hay necesidad de mandar cada muestra a un LLM: estadísticas en el teléfono, agregación SQL, modelo solo al conversar o decidir.

El presupuesto Free publicado de Cloudflare Workers incluye 100.000 solicitudes/día, con límites de CPU; D1 incluye 100.000 filas escritas/día, 5 millones leídas/día y 5 GB. El ejemplo podría entrar si respeta todos los límites; no es una garantía ni incluye IA, autenticación adicional, distribución iOS, mantenimiento o coste del teléfono. El intervalo de reporte de 2 minutos y consulta de 1 minuto puede introducir unos 3 minutos de retraso, más sincronización y espera del mínimo de participantes. No anunciarlo como tiempo real.

Referencias consultadas el 24/10/2026:

- NoiseCapture, datos y agregación: https://noise-planet.org/noisecapture_exploit_data.html
- Calibración de ruido con celulares (2024): https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730/
- Apple, AR multiusuario: https://developer.apple.com/documentation/ARKit/creating-a-multiuser-ar-experience
- Pyrgelis, Troncoso y De Cristofaro (2017), privacidad de agregados de ubicación: https://arxiv.org/abs/1703.00366
- Apple, privacidad diferencial y agregación segura (2023): https://machinelearning.apple.com/research/scenes-differential-privacy
- Costos D1: https://developers.cloudflare.com/d1/platform/pricing/
- Costos Workers: https://developers.cloudflare.com/workers/platform/pricing/

## Mapa de San Francisco — simulación visual

La portada muestra un plano esquemático de SF en blanco, negro y violeta. Los nombres de lugares son reales, pero ubicaciones aproximadas, métricas, contribuciones y antigüedad son de ejemplo. Se puede buscar, filtrar, seleccionar lugares, evaluar por reglas, guardar preferencias en memoria de sesión y simular lotes de contribuciones. La ruta `/event` conserva la simulación del evento. La ruta `/connections` conserva Oura.

### Contrato para agentes (propuesta, no servidor MCP desplegado)

- `query_sound_map(area, time_window)` devuelve agregados por zona, antigüedad, compatibilidad y calidad. Sin trazas o identidades de contribuyentes.
- `find_suitable_places(goal, area, constraints)` devuelve candidatos con evidencia y datos faltantes. Preferencias sensibles se aplican localmente cuando sea posible.
- `submit_observation(zone_id, time_bucket, acoustic_summary, measurement_quality)` acepta contribuciones autorizadas, valida unidades y aplica cuotas, controles contra duplicados y agregación. No aceptar audio, conversaciones, Oura ni recorridos.

Instrucciones que debería contener una skill del agente:

1. Pedir el objetivo de la persona y respetar preferencias explícitas. No inferir diagnóstico o sobrecarga.
2. Consultar solo la zona y ventana necesarias. Distinguir medidas, datos históricos y estimaciones.
3. No recomendar como tranquilo un lugar sin datos. Explicar incertidumbre y confirmar horarios/acceso si son relevantes.
4. Separar permiso de consulta y permiso de contribución. No condicionar la asistencia a compartir salud o ubicación.
5. Contribuir solo desde un sensor autorizado y compatible, con confirmación previa del alcance de participación. Un LLM no inventa observaciones.
6. Conservar memoria personal aparte; el mapa recibe únicamente los campos del contrato permitido.
7. Si no hay evidencia suficiente, abstenerse o sugerir verificar al llegar.

La simulación no realiza estas llamadas: ilustra el contrato. Una futura implementación necesita API/MCP autenticado, validación de sensores, protección de ubicación y pruebas de utilidad.


## Mapa mínimo (actualización visual)

La portada ahora ocupa toda la pantalla con cartografía vectorial real de San Francisco. Los valores acústicos, pulsos y aportes siguen siendo ficticios. El violeta codifica la intensidad relativa simulada; el blanco indica ausencia de observaciones. Los iconos cuadrados identifican edificios y lugares importantes. El botón de ayuda contiene un instructivo breve; MCP expone un contrato propuesto copiable, no un servidor conectado.

Se aplicaron las superficies blancas, bordes neutros de 1 px, controles pequeños y sombras leves del documento de diseño Vercel aportado por el usuario. No se incorporaron logos ni assets de esa marca.

MapLibre renderiza el mapa y las estructuras 3D en navegadores con WebGL2. OpenLayers ofrece un mapa vectorial 2D con el mismo proveedor OpenFreeMap si WebGL2 no está disponible; el control 3D se oculta en ese caso. Se mantienen atribuciones a OpenFreeMap, OpenMapTiles y OpenStreetMap. Los mapas requieren red; no se solicita geolocalización ni micrófono. No se envían datos Oura al proveedor cartográfico.

## Mapa de San Francisco — solo datos reales (actualización)

La portada `/` ya no muestra valores simulados, puntos escritos a mano ni contribuciones ficticias. El violeta es la densidad de reportes reales (quejas de ruido 311 + llamadas de policía NOISE NUISANCE, últimos 30 días, por área de ~280 m, en las ubicaciones publicadas): es un conteo de reportes, no dB ni volumen medido. Sin color = sin reportes = desconocido, no silencioso. El filtro Fewer/Mid/Most divide las áreas con reportes en tercios por conteo. Si DataSF no responde, el mapa lo dice y no muestra nada inventado. Las notas anteriores sobre valores ficticios aplican solo a `/venue`, que conserva su etiqueta "Demo venue".
