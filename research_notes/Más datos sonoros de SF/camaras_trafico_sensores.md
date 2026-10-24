# Proxies urbanos (cámaras, sensores, flujos, aviación) del entorno sonoro de San Francisco

Fecha de verificación: 2026-10-24. Los endpoints marcados "verificado en vivo" se probaron con curl a través del proxy en esta sesión. Nota: el portal DataSF ahora vive en data.sf.gov; data.sfgov.org redirige. La API Socrata es `https://data.sf.gov/resource/<id>.json` (SoQL con `$query=`).

## 1. Cámaras de tráfico públicas (Caltrans, SFMTA/511, SFO, puerto): APIs, términos, audio, límites legales

### Takeaway
Caltrans publica gratis un catálogo JSON/CSV/XML de cámaras del distrito 4 con imagen JPG fija y stream HLS, sin clave y sin audio declarado en el stream que inspeccioné. Sirven como proxy visual de volumen de tráfico, pero no como sensor acústico. No encontré ninguna API pública de cámaras de SFMTA, SFO ni del Puerto.

### Cited Findings
- Caltrans CWWP2 ofrece cámaras (CCTV) por distrito en CSV, JSON, TXT y XML; "There is no charge for the use of this data"; sujeto a las Conditions of Use; "Caltrans traffic camera video footage and still images are neither retained nor archived". Actualización del archivo de catálogo: "as necessary" — [CWWP2 CCTV](https://cwwp2.dot.ca.gov/documentation/cctv/cctv.htm)
- Catálogo D4 (verificado en vivo): `https://cwwp2.dot.ca.gov/data/d4/cctv/cctvStatusD04.json` (también `.csv`). Contiene 764 entradas de D4; 33 con county = San Francisco, todas `inService: true` (rutas I-280, US-101, I-80, SR-1, etc.). Sin clave de API. — [cctvStatusD04.json](https://cwwp2.dot.ca.gov/data/d4/cctv/cctvStatusD04.json)
- Cada cámara trae lat/lon, ruta, dirección, `currentImageURL` (JPG, `currentImageUpdateFrequency` = 5 min), 12 imágenes previas (`referenceImage1..12UpdatesAgoURL`, frecuencia 60 min según el campo) y `streamingVideoURL` (HLS .m3u8). Ejemplo verificado: TV327 I-280 John Daly Blvd, stream `https://wzmedia.dot.ca.gov/D4/S280_at_John_Daly_Bl.stream/playlist.m3u8` — [cctvStatusD04.json](https://cwwp2.dot.ca.gov/data/d4/cctv/cctvStatusD04.json)
- Frescura: la cabecera HTTP del JPG de ejemplo mostró `Last-Modified` de hace ~2 min respecto a la hora del servidor (2026-10-24 21:51 GMT), con `Access-Control-Allow-Origin: *`. Pero los `recordTimestamp` dentro del JSON de catálogo son de enero de 2026 (el catálogo de metadatos no se refresca con cada imagen) — verificado en vivo.
- Audio: el master playlist HLS del ejemplo declara `CODECS="avc1.4d401e"` (solo H.264 vídeo, 720x480, ~581 kbps), sin códec de audio (mp4a). Verificado solo en UN stream; no examiné los 33 — [playlist.m3u8](https://wzmedia.dot.ca.gov/D4/S280_at_John_Daly_Bl.stream/playlist.m3u8)
- Términos de uso de Caltrans (fechados 19-jul-2021): rigen el uso de sus sitios; incluyen cláusulas de limitación de responsabilidad y propiedad; no vi un límite numérico de peticiones en la documentación CWWP2 — [Conditions of Use](https://dot.ca.gov/conditions-of-use)
- Caltrans también publica cierres de carril en el mismo portal (HTTP 200 verificado): `https://cwwp2.dot.ca.gov/data/d4/lcs/lcsStatusD04.json` — contenido no inspeccionado en detalle.
- 511.org: su API cubre incidentes/eventos de tráfico, WZDx (obras), GTFS, GTFS-RT, peajes; el FAQ oficial no documenta cámaras, ni velocidad/volumen de tráfico — [511 FAQ](https://511.org/open-data/faqs)
- Datos de cámaras de DataSF: "Red Light Camera Citations" (uzmr-g2uc) y "Automated Speed Enforcement Citations" (d5uh-bk84, conteo diario de avisos/multas por cámara, 22 592 filas, actualizado 2026-08-25, licencia ODC PDDL; verificado) — son datos de infracción, no vídeo.

### Inferences
- Un pipeline razonable: descargar el JPG cada ~5 min por cámara de SF, contar vehículos (detector tipo YOLO) y usar el conteo como covariable de ruido vial en autopistas (I-280, US-101, I-80). Las 33 cámaras solo cubren autopista/accesos, no calles residenciales.
- Como el stream HLS no declara audio, no hay vía legítima para obtener ruido directo de estas cámaras.
- Contar vehículos de forma agregada y sin identificar personas o matrículas reduce el riesgo de privacidad; guardar imágenes sí implica retención que Caltrans no hace.

### Gaps
- No pude verificar si hay límite de tasa en cwwp2 (ni en documentación ni probando).
- No encontré cámaras públicas con API de SFMTA, SFO, Puerto de SF ni 511 (511 tiene mapa, pero no verifiqué una API de cámaras). Posibles webcams turísticas privadas no evaluadas.
- Audio: verificado solo en 1 de 33 streams; no puedo afirmar que ninguno lo tenga.
- Marco legal: no investigué en fuentes primarias la ordenanza de vigilancia de SF (Admin Code 19B) ni la CCPA/CPRA para analítica de vídeo; solo es recomendable consultar asesoría. Los datos de ShotSpotter (ver sección 3) sí aparecen en informes de vigilancia de la ciudad.

## 2. Conteos y flujos (SFMTA/DataSF, PeMS, 511, Muni, BART/Caltrain, parquímetros, micromovilidad)

### Takeaway
DataSF tiene buenos datasets de contexto (límites de velocidad, choques, cierres de calle, quejas 311 de ruido, transacciones de parquímetros), pero NO encontré un dataset abierto vigente de conteos de tráfico o peatones por calle: los conteos SFMTA son PDF históricos (1993-2015) y los de bicicleta son manuales (2009-2017). Para volumen continuo en autopista la vía es PeMS (cuenta gratuita), y para transporte, GTFS-RT vía 511 (60 peticiones/h por defecto).

### Cited Findings
**DataSF (todos con licencia Open Data Commons PDDL salvo indicación; verificados vía API de metadatos y SoQL):**
- Temporary Street Closures `8x25-yybr`: cierres por Shared Spaces (2 959), Special Event (1 094), Special Traffic Permit (226); 4 279 filas; actualizado 2026-10-24; campos start_dt/end_dt, calle, tipo, geometría — proxy de eventos/multitudes y desvíos de tráfico. Fuente: [data.sf.gov 8x25-yybr](https://data.sf.gov/resource/8x25-yybr.json)
- SF311 Cases `vw6y-z8j6`: 9 016 261 filas, actualización nocturna (~6 am PT). En 2026 (hasta la fecha de la consulta): servicio "Noise" 17 542 casos; subtipos: other_excessive_noise 10 452, amplified_sound_electronics 1 585, entertainment 1 343, major_event_venue 831, construction_private_property 830, construction_public 664, mechanical_equipment 385 — [311 Cases](https://data.sf.gov/resource/vw6y-z8j6.json)
- Law Enforcement Dispatched Calls for Service: Closed `2zdj-bwza` (7 983 086 filas, actualizado 2026-10-24; ubicaciones enmascaradas a intersección). En 2026: NOISE NUISANCE 13 970, SHOTS FIRED 648, SHOT SPOTTER 469 — [CAD calls](https://data.sf.gov/resource/2zdj-bwza.json)
- Night Noise Permits `e7pr-36bt` (obras nocturnas autorizadas, 1 078 filas desde ago-2019, actualizado 2026-10-15) — [dataset](https://data.sf.gov/resource/e7pr-36bt.json)
- Speed Limits per Street Segment `3t7b-gebn` (16 083 segmentos, actualizado 2026-10-24) — covariable estática (velocidad de diseño ↔ ruido de rodadura).
- Traffic Crashes Resulting in Injury `ubvf-ztfx` (actualizado 2026-10-07; verificado respuesta SoQL con coordenadas); Fatality `dau3-4s8f`; High Injury Network `enwt-3u8m`.
- SFMTA Parking Meter Detailed Revenue Transactions `imvp-dq3v`: 215 221 875 filas, actualizado 2026-10-24; campos transmission_datetime, post_id, street_block, session_start/end. Los campos de fecha vienen como texto con formato irregular (mis consultas min/max devolvieron valores sin sentido) — hay que parsear. Parking Meters `8vzz-qzz9` (38 775 medidores; incluye `sensor_flag`). Proxy de actividad comercial/ocupación por bloque.
- Bike Volume – Manual Counts `v4v2-5x7s`: 119 filas, 2009-2017, contados en septiembre; sin actualizar desde 2024-01-18. Los campos de coordenadas parecen mal formateados (ej. `cnn` contiene la latitud, `time` la longitud) — [dataset](https://data.sf.gov/resource/v4v2-5x7s.json)
- SFMTA Mobility Data Specification `h5q5-vfti` solo contiene geografías (63 filas), no viajes — verificado columnas. Bike and Scooter 311 Complaints `24s2-n3bu` (40 542 filas desde feb-2022).
- Transit Vehicle Location History (Current Year) `x344-v6h6`: 470 470 157 filas, pero el último registro es 2021-12-30: está estancado, no es un feed vigente (verificado).
- SFMTA Traffic Count Data 1993-2015: lista PDF de conteos de 24 h por segmento (calle, cruce, dirección, fecha, volumen; versión 2016 con picos AM/PM) — [PDF SFMTA](https://www.sfmta.com/sites/default/files/reports/2016/SFMTA%20Traffic%20Count%20Data%201993-2015%20with%20cover%20sheet.pdf). La búsqueda no confirmó un portal de conteos vigente.
- SFMTA Traffic Calming: Mid-Block Traffic Calming Areas `abhw-ffzx`, Intersection-Level Devices `bp3t-bd4t`, Slow Streets `hkz3-itiu` aparecen en el catálogo (no inspeccionados).

**511 / transporte:**
- 511 Open Data API: clave gratuita; "The default limit is 60 requests per 3600 seconds per API key" (se puede pedir más a transitdata@511.org con caso de uso). Endpoints: GTFS regional (operator_id=RG), GTFS-RT TripUpdates/VehiclePositions/ServiceAlerts (agency=RG), Traffic Events (incidentes y eventos planificados), WZDx en `api.511.org/traffic/wzdx`, peajes; GTFS histórico mensual (`historic=yyyy-mm`) y archivos "stop observation" desde marzo 2022. La licencia no figura en el FAQ (remite a /about/terms, que no pude leer) — [511 FAQ](https://511.org/open-data/faqs). Sin clave, `api.511.org` responde 401 "The API key is not provided" (verificado en vivo).
- BART publica GTFS-RT (página oficial) — [BART GTFS-RT](https://www.bart.gov/schedules/developers/gtfs-realtime); el endpoint `api.bart.gov/gtfsrt/tripupdate.aspx` devolvió HTTP 200 en mi sonda (contenido no decodificado). Caltrain: vía feed regional 511 (no verifiqué un feed propio).
- Caltrans PeMS: ~40 000 detectores en todo California, archivo de más de 10 años, incluye detectores, incidentes, cierres de carril, conteos y clasificación de vehículos; cuenta gratuita, aprobación en 1-2 días hábiles — [PeMS Data Source](https://dot.ca.gov/programs/traffic-operations/mpr/pems-source). El detalle de resolución (5 min) y la cobertura exacta en SF no los verifiqué (requiere cuenta).
- GBFS: Bay Wheels (Lyft) `https://gbfs.lyft.com/gbfs/1.1/bay/gbfs.json` (verificado, station_status en tiempo real con `last_reported` reciente); Lime SF `https://data.lime.bike/api/partners/v2/gbfs/san_francisco/gbfs.json` (v2.2, verificado 200); Spin SF `https://mds.bird.co/gbfs/v2/public/provider/spin/san_francisco/gbfs.json` (listado en el catálogo, no sondeado) — [MobilityData systems.csv](https://raw.githubusercontent.com/MobilityData/gbfs/master/systems.csv)
- SFpark histórico: no encontré dataset activo con ese nombre en DataSF; los equivalentes vigentes son los de parquímetros arriba.

### Inferences
- Ruido vial por calle: combinar límite de velocidad (3t7b-gebn) + clasificación de calle + PeMS para autopistas + posiciones/frecuencia de Muni (GTFS-RT) da un modelo grosero; el conteo local real por calle no está abierto.
- Multitudes/ocio nocturno: cierres de calle (8x25-yybr), transacciones de parquímetros por bloque y llamadas "NOISE NUISANCE" son proxies de actividad humana; las quejas 311 miden molestia percibida, con sesgo hacia quien reporta.
- Micromovilidad GBFS da disponibilidad de vehículos (proxy de actividad), no trayectorias; los viajes MDS no son públicos en tiempo real.

### Gaps
- Dataset SFMTA de conteos de tráfico/velocidad y de peatones vigente: no encontrado. Tampoco verifiqué contadores automáticos de bicis (p. ej. Market St) ni conteos peatonales automáticos.
- Licencia de 511: no verificada. Límites de tasa de GTFS-RT de BART: no verificados.
- No verifiqué en vivo PeMS (requiere cuenta) ni el Traffic Events API con clave.
- Tránsito de Muni en tiempo real: solo via 511 (no verifiqué si SFMTA tiene feed GTFS-RT propio).

## 3. Sensores acústicos (ShotSpotter, redes municipales/universitarias, sensores ciudadanos, grabaciones geoetiquetadas)

### Takeaway
La fuente acústica real más valiosa y abierta es la red de monitores de ruido de SFO (Aircraft Noise Exceedances en DataSF, con niveles dB medidos), pero cubre la península bajo las rutas de SFO, no el centro de SF. ShotSpotter no tiene datos abiertos de audio ni de sensores; solo llamadas CAD con ubicación enmascarada.

### Cited Findings
- SFO Aircraft Noise Exceedances `tiju-qyvs`: 258 672 eventos, 2019-08-01 a 2026-08-31, 30 ubicaciones de monitor distintas (`location_id`), campos `max_level` (dB, nivel máximo), `sel` (nivel de exposición sonora), `duration`, `classification`, `day_night`, correlados con operación de vuelo (aeronave, aerolínea, pista). Sin licencia declarada en los metadatos de ese dataset (otros SFO usan ODC PDDL). Actualizado 2026-09-22 (verificado vía SoQL). Ojo: `max_level` es texto (mis `min/max` salieron lexicográficos). Son solo eventos que superan umbral y están correlados con un vuelo — [dataset](https://data.sf.gov/resource/tiju-qyvs.json)
- Una noticia de CBS cita 29 monitores permanentes a lo largo de la Península; una diapositiva del SFO Roundtable numera sitios permanentes 1-29 y portátiles ≥900 — [CBS](https://www.cbsnews.com/amp/sanfrancisco/news/web-app-track-airplane-noise-sfo); [Roundtable 2023](https://sforoundtable.org/wp-content/uploads/2023/09/Roundtable-Portable-to-Permanent-Portable-Program-22Sep2023v2.pdf). Discrepancia menor: el dataset tiene 30 `location_id` distintos (puede incluir portátiles/otros); no resuelto. No encontré tabla de coordenadas de monitores.
- Noise Exceedance Rating `5m6g-bqm4` (por aerolínea/mes, 9 389 filas) y Nighttime High Power Run-ups `aqb8-9r2r` (898 filas) — verificados.
- ShotSpotter/SoundThinking en SF: sensores en seis distritos policiales (Southern, Bayview, Mission, Northern, Ingleside, Tenderloin) según un informe de vigilancia de DEM de 2025; las llamadas usan el código 216S en DataSF, ubicaciones enmascaradas a intersección, y DEM dice que no puede publicar direcciones exactas. SFPD comparte con socios hora, ubicación, número de disparos y "un breve fragmento de audio" — [DEM Biannual Report 2025](https://media.api.sf.gov/documents/DEM_Gunshot_Detection_Hardware__Services_Biannual_Surveillance_Report_2025-1.pdf); [SFPD annual report 2024](https://sf.gov/sites/default/files/2024-10/POL%20Shotspotter%20Audio%20Recorder%20Annual%20Surveillance%20Report%202024.pdf). Mis consultas SoQL confirman la etiqueta "SHOT SPOTTER" en `2zdj-bwza` (469 llamadas en 2026).
- Solicitudes de registros públicos de datos crudos de ShotSpotter a SFPD en 2022 no devolvieron archivos — [MuckRock](https://www.muckrock.com/foi/san-francisco-141/shotspotter-data-san-francisco-police-department-128545/)
- Freesound: sonidos con licencias Creative Commons, token de API; los sonidos geotagueados se filtran por radio (`geofilt`) o rectángulo (`geotag:[...]`) según la documentación citada en un buscador — [Freesound API (resources)](https://freesound.org/docs/api/resources_apiv2.html). Mi acceso directo a la documentación devolvió 403, así que no pude verificar límites de tasa ni contar cuántos sonidos hay en SF.
- Night-time ruido humano: Night Noise Permits (e7pr-36bt) y NOISE NUISANCE (CAD) y 311 Noise (sección 2).

### Inferences
- Tiju-qyvs permite calibrar un modelo de ruido aeronáutico con dB reales, pero solo para eventos de avión; no sirve para ruido ambiental general.
- ShotSpotter es un indicador de impulsos (disparos), no de ruido ambiental; con ubicaciones enmascaradas solo sirve a escala de distrito/intersección. El audio no está disponible públicamente.
- Freesound serviría para ejemplos de clase de sonido, no para medición continua (grabaciones puntuales, sesgo de quien sube).

### Gaps
- No encontré redes acústicas municipales o universitarias activas en SF (p. ej., sensores tipo SONYC); no es evidencia de que no existan, solo que no las localicé.
- PurpleAir: mi conocimiento es que mide material particulado, no ruido; no lo verifiqué en esta sesión.
- No pude verificar ni contar grabaciones geoetiquetadas en SF en Freesound u otras plataformas.
- Coordenadas de los monitores de SFO y licencia de tiju-qyvs sin verificar.

## 4. Aviación y helicópteros (SFO/OAK, OpenSky, ADS-B Exchange, policía/Guardia Costera)

### Takeaway
SFO publica en DataSF las operaciones de vuelo (radar FAA) y quejas de ruido hasta 2026-08-31, lo que es la mejor fuente histórica abierta. Para tráfico aéreo casi en tiempo real, OpenSky responde sin clave (verificado) pero con cuota anónima baja; ADS-B Exchange es de pago.

### Cited Findings
- SFO Flight Operations `43zc-xw3x`: 2 832 282 operaciones, 2019-08-01 a 2026-08-31; campos tipo de operación (llegada/salida), pista, tipo de aeronave, categoría, aerolínea, altitud, desviación del eje, `gate_penetration_time`; licencia ODC PDDL; actualizado 2026-09-22. Las categorías incluyen H (1 970 operaciones en 2026, probablemente helicópteros — significado no verificado) y J (239 989 en 2026) — [dataset](https://data.sf.gov/resource/43zc-xw3x.json)
- Aircraft Noise Reports `peaa-dyr3`: 7 597 785 reportes (2019-08-01 a 2026-08-31), con ciudad, código postal, método y vuelo correlacionado — proxy de molestia percibida. Aircraft Noise Report Summary `q3xd-hfi8` (mensual por comunidad). Late Night Aircraft Departures `855n-xpnm` (30 144 filas, 1-5 am).
- OpenSky (verificado en vivo): `https://opensky-network.org/api/states/all?lamin=37.5&lomin=-122.6&lamax=37.9&lomax=-122.2` devolvió estados sin autenticación (incluye SFO). Documentación citada (espejo): anónimos 400 créditos/día, solo estados más recientes, resolución de 10 s; registrados 4 000; feeders 8 000; el coste depende del área. Desde 18-mar-2026 el cliente oficial indica que la autenticación básica ya no funciona (OAuth2 client credentials) — [espejo de docs](https://git.carrubanet.duckdns.org/VALLONGOL/SXXXXXXX_FlightMonitor/src/commit/894eb20e1d18849fce2bfc9bd15b82e175d90979/opensky-api-master/docs/free/rest.rst); [cliente oficial](https://github.com/openskynetwork/opensky-api). Fuente de segunda mano para las cifras; no pude abrir la documentación en vivo.
- ADS-B Exchange: API "Community" vía RapidAPI para uso no comercial ($10/mes, 10 000 peticiones, según su página); cualquier uso comercial (incluso interno) requiere licencia; archivo histórico a 5 s desde marzo 2020 con muestras gratis del primer día de cada mes — [Developer Hub](https://www.adsbexchange.com/api-lite/); [soporte](https://support.adsbexchange.com/hc/en-us/articles/37363886073613-I-m-building-a-project-for-my-company-but-we-aren-t-making-money-off-of-it-can-I-get-a-free-API-key). Un comparador de terceros (fecha 2026-09-02) dice que no hay acceso gratis autoservicio y cita adsb.lol como alternativa con volcados históricos — [FlyItalyADSB](https://flyitalyadsb.com/en/dati/confronto/) (fuente secundaria).
- Drones SFPD: SFPD Drone Flight Logs `giw5-ttjs` (10 010 filas, actualizado 2026-10-22; duración, motivo, ubicación) — [dataset](https://data.sf.gov/resource/giw5-ttjs.json). Es dron, no helicóptero.

### Inferences
- Combinar `43zc-xw3x` (+ `tiju-qyvs` para dB) con OpenSky permite estimar exposición aeronáutica por hora; para el centro de SF, el efecto es menor que en la Península bajo las trayectorias.
- Helicópteros de policía/Guardia Costera: ADS-B público a menudo no los muestra si usan transpondedor desactivado (no verificado); no encontré datos abiertos de Air Operations de SFPD ni de la Guardia Costera.

### Gaps
- Cobertura de OAK: no investigada. Significado de los códigos de `aircraft_category` (H, J, R, B, etc.) no verificado.
- Cuotas actuales de OpenSky solo desde fuente secundaria. Datos de helicópteros policiales/Guardia Costera: no encontrados.
- Historial de OpenSky (Trino/"impala") no investigado.
