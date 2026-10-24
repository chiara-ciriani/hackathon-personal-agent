# Otras fuentes de datos sonoros para un mapa de sonido de San Francisco (fecha de verificación: 2026-10-24)

Convención: VERIFICADO = comprobado en vivo desde la sandbox el 2026-10-24 (curl/API). BÚSQUEDA = solo visto en resultados de búsqueda/fetch. NO VERIFICADO = no se pudo comprobar; no usar sin revisar. Ranking de valor: medido > modelado > proxy.

## 1. Mapas de ruido modelados u oficiales (US DOT BTS, Caltrans, SFO, SF Planning, EIR, Puerto)

### Takeaway
El mejor insumo modelado cubre todo SF y es el National Transportation Noise Map de BTS, con 2016, 2018 y 2020 (carretera, ferrocarril, aviación). Sus servicios ArcGIS existen, pero el raster no respondió a identify/export en la prueba, y BTS prohíbe usarlo para ubicaciones concretas. El mapa oficial de SF Planning (Map 1, 2009) es un PDF, no un dato. Los EIR dan mediciones puntuales ricas pero solo en PDF.

### Cited Findings
- BTS: la página oficial tiene una sección "Noise Map Data Files for Download" con archivos por modo y por estado. Avisa que el mapa se hizo para análisis nacional con modelado simplificado, para seguir tendencias, y que no debe usarse para evaluar niveles en ubicaciones o momentos concretos — [BTS](https://www.bts.gov/geospatial/national-transportation-noise-map) (BÚSQUEDA; la página devuelve 403 "Access Denied" a curl y WebFetch desde la sandbox, así que no pude listar los enlaces de descarga ni confirmar la licencia).
- Edición 2020 con datos a octubre de 2022; la cadencia anunciada cambió entre "anual" (2017) y "bianual" (página actual) — [BTS](https://www.bts.gov/geospatial/national-transportation-noise-map) (BÚSQUEDA). No encontré una edición posterior a 2020.
- Metadatos en data.gov: para servicios web, ir a `https://geo.dot.gov/server/rest/services/Hosted` y buscar nombres que empiecen por "Noise" — [data.gov](https://catalog-old.data.gov/dataset/noise-data-20201) (BÚSQUEDA). Contacto de datos: ntad@dot.gov.
- VERIFICADO: el directorio `https://geo.dot.gov/server/rest/services/Hosted?f=json` (ArcGIS Server 11.5) lista estos MapServer de ruido: `NTAD_Noise_2020_CONUS_Road`, `..._CONUS_Rail`, `..._CONUS_Aviation`, `..._CONUS_Aviation_Road`, `..._CONUS_Aviation_Road_Rail`, y también `Noise_road_CONUS_2016`, `Noise_road_CONUS_2018`, `Noise_aviation_CONUS_2016/2018`, `Noise_aviation_road_CONUS_2016/2018`. Ruta de ejemplo: `https://geo.dot.gov/server/rest/services/Hosted/NTAD_Noise_2020_CONUS_Road/MapServer`.
- VERIFICADO: el servicio 2020 Road tiene la capa 0 "CONUS_road_noise_2020" (mosaic), con subcapas 1 Boundary, 2 Footprint y 3 Image (raster). El raster está en EPSG:102039 (Albers USA), con extent en 3857 que incluye SF. Capacidades "Map,Query"; `maxRecordCount` 1000.
- VERIFICADO: leyenda de la capa 3, en clases de dBA: 45.0–49.9, 50.0–54.9, 55.0–59.9, 60.0–69.9, 70.0–79.9, 80.0–89.9, >90.0. Es decir, bandas gruesas, no valores continuos.
- VERIFICADO (problema): sobre un punto de SF, `identify` (capas `all`, `all:3`, SR 4326 y 3857) y `export` (varias bbox, con y sin `layers=show:`) devolvieron `HTTP 500 "Error performing identify/exporting map"`. El endpoint `ImageServer` pide token (error 499). El servicio responde en lo demás (metadatos, leyenda). Podría ser un fallo temporal o del backend del mosaico; reintentar antes de depender de él.
- VERIFICADO: existen también FeatureServer/VectorTileServer `West_Coast_noise_2022_6` y `AGE_Vector_Tile_Noise_2022_EEZ` en el mismo directorio. No pude comprobar qué son (probablemente aviación, "AGE" parece una iniciativa de aviación; NO VERIFICADO). No usarlos sin leer sus metadatos.
- Copia de terceros en ArcGIS Online: `https://services8.arcgis.com/rGGrs6HCnw87OFOT/ArcGIS/rest/services/NoiseLevelsCategorized/FeatureServer`, overlay 2020 de carretera, ferrocarril y aviación derivado de datos USDOT — [resultado de búsqueda](https://services8.arcgis.com/rGGrs6HCnw87OFOT/ArcGIS/rest/services/NoiseLevelsCategorized/FeatureServer) (BÚSQUEDA; no es fuente oficial; no probado).
- SF Planning, Environmental Protection Element (Noise Element): la Policy 11.1 dice que el desarrollo nuevo se compara con los niveles del sitio y, si exceden las guías para ese uso, debe incluir aislamiento o no seguir. El único mapa es "Map 1, Background Noise Levels (2009)", un PDF. Los niveles son estimaciones "based on both traffic data and on a sample of sound level readings". La Land Use Compatibility Chart es una imagen (dwg17-1.gif), así que no obtuve los umbrales — [SF General Plan](https://generalplan.sfplanning.org/I6_Environmental_Protection.htm) (VERIFICADO el acceso; la página tiene 130k caracteres y solo leí los primeros 100k).
- Elemento de ruido de transporte en el Plan General desde 1972, Objetivos 9–11 — [SF DPH](https://sfdph.org/dph/EH/Noise/noiseresponse.asp) (BÚSQUEDA). DPH enlaza guías de monitoreo y cumplimiento del Artículo 29 (Noise Ordinance, enmendado en 2008).
- El EIR de Central SoMa ya está en uso. Muestra que el formato típico de los EIR de SF es Ldn con tablas de mediciones de corta y larga duración — [Central SoMa DEIR cap. noise](https://sfmea.sfplanning.org/CentralSoMaPlanDEIR_11-iv-e-noise.pdf) (BÚSQUEDA). Los DEIR/FEIR de Mission Bay, Civic Center, Embarcadero, Dogpatch, Mission y Chinatown siguen el mismo patrón en sfmea.sfplanning.org, pero NO los abrí ni verifiqué URLs concretas.
- Contornos de SFO: la norma federal (14 CFR Parte 150) exige contornos DNL 65, 70 y 75 dB; California usa CNEL — [14 CFR App. A Part 150](https://www.law.cornell.edu/cfr/text/14/appendix-A_to_part_150) (BÚSQUEDA). No encontré descarga GIS del contorno SFO vigente; no confirmé que haya Parte 150 reciente. En DataSF sí existe `qxw2-ncq3` (Aircraft Noise Climates), ya usado.

### Inferences
- Para un mapa de calles, el raster BTS solo sirve como capa de fondo "orden de magnitud" (bandas de 5–10 dB, modelo simplificado, solo tráfico regional). Dado el aviso de BTS, mostrarlo como "estimación modelada, no medición" y nunca como valor del punto.
- Si el REST no funciona, el camino robusto es descargar el ráster/GDB del sitio BTS/data.gov con un navegador (la sandbox recibe 403) y recortar a SF una vez, empaquetando teselas.
- Los EIR son la única fuente de medidas reales por barrio, pero requieren digitalización manual (PDF); valor alto para validar, esfuerzo alto.

### Gaps
- URL real del ZIP/GeoTIFF de descarga BTS y licencia explícita (página bloqueada con 403). Probable dominio público federal, pero NO VERIFICADO.
- Si el 500 de identify/export de geo.dot.gov es permanente.
- Umbrales numéricos de la Land Use Compatibility Chart de SF (imagen).
- Datos de Caltrans (modelos de ruido de autopistas, mediciones) y del Puerto de SF: no encontré datasets GIS; no investigué a fondo. Caltrans publica informes de ruido por proyecto en PDF (NO VERIFICADO para SF).
- URLs de los EIR de Mission Bay, Civic Center, Embarcadero, Dogpatch, Mission y Chinatown.

## 2. Datos colaborativos (NoiseCapture, Hush City, Freesound, estudios universitarios)

### Takeaway
NoiseCapture es la única fuente colaborativa abierta y descargable con licencia clara (ODbL) y volcado diario por país. La cobertura en SF no se pudo medir desde la sandbox. Hush City y Freesound son de baja utilidad para integración directa.

### Cited Findings
- NoiseCapture: datos "distributed in a open way under the ODbL"; sin audio, solo medidas anónimas con traza GPS — [Noise-Planet](https://noise-planet.org/noisecapture.html) (VERIFICADO vía fetch). Aviso del propio proyecto: orientada a usuarios con conocimiento técnico; mirar los resultados con espíritu crítico; uso principal científico.
- Descarga: `http://data.noise-planet.org/dump/` — un `.zip` por país con mediciones; cada zip incluye un `README.html` y `.geojson` por región; actualización "nightly" a las 03:30 UTC — [Noise-Planet data](https://noise-planet.org/noisecapture_data.html) (VERIFICADO). El índice respondió HTTP 200 a una petición HEAD; no listé el contenido (curl falló al escribir la salida), así que no confirmé el nombre del zip de EE. UU. ni su tamaño.
- Campos: descritos en el README de cada zip (no leído).
- Zenodo (Université Gustave Eiffel): registros 6563518 y 6536129, archivos .Rds de un análisis de las etiquetas de fuente de ruido de los 3 primeros años — [Zenodo 6563518](https://zenodo.org/records/6563518) (BÚSQUEDA). No son un volcado geográfico utilizable.
- Zenodo 19456021 (2026-04-07, CC-BY-4.0): "Citizen Science in Acoustics dataset", seis datasets de NoiseCapture y OpeNoise para una tesis de la Universidad de São Paulo — [Zenodo](https://zenodo.org/records/19456021) (VERIFICADO vía API). Probablemente centrado en Brasil (NO VERIFICADO), poca relevancia para SF.
- Cantidad de contribuyentes: cerca de 80.000 en el mundo — [Reflex Science](https://reflexscience.univ-gustave-eiffel.fr/en/read/articles/noisecapture-an-application-to-evaluate-the-sound-environment) (BÚSQUEDA).
- Hush City (Antonella Radicchi): mapa de "zonas tranquilas" con más de 2000 áreas en el mundo; cada envío puede incluir audio con nivel de presión sonora, foto y opinión; el código iba a publicarse con licencia Creative Commons sin versión concreta — [Public Lab](https://PublicLab.org/notes/Hush_City_Mobile_Lab/05-06-2019/map-the-quiet-places-near-you-using-hushcity-platform) (BÚSQUEDA). No encontré la licencia de la base de datos ni una API de exportación; presencia en SF NO VERIFICADA.
- Freesound: la API de búsqueda sin token devolvió respuesta vacía; requiere clave (no probada). Licencias CC por archivo (NO VERIFICADO en esta sesión). Valor: audio de referencia con geoetiqueta, sin niveles calibrados.
- Estudios de UC Berkeley, SF State o Stanford: búsqueda de Zenodo por soundscape/"San Francisco" no devolvió nada relevante — [Zenodo API](https://zenodo.org/api/records?q=soundscape%20%22San%20Francisco%22) (VERIFICADO). No investigué repositorios universitarios.

### Inferences
- Plan realista: descargar el zip de EE. UU. de NoiseCapture, filtrar por bbox de SF y contar puntos por celda. Si la cobertura es escasa (probable, SF no es zona fuerte de la app), usar solo como validación cualitativa en celdas con ≥N mediciones.
- Los teléfonos no están calibrados; promediar por celda y marcar la incertidumbre.

### Gaps
- Número real de mediciones NoiseCapture en SF y nombre exacto del archivo de EE. UU. (no pude descargar ni listar).
- Licencia de Hush City y existencia de datos en SF; datos de Freesound en SF; proyectos académicos.

## 3. Eventos y actividad como predictores de ruido

### Takeaway
El dataset de permisos de uso de calle es el mejor predictor de eventos y está activo (por eso lo usan ya: `8x25-yybr`). Ticketmaster Discovery API aporta recintos grandes (Oracle Park, Chase Center) con cuota gratuita.

### Cited Findings
- VERIFICADO: `8x25-yybr` "Temporary Street Closures" tiene filas futuras (p. ej. "San Francisco Half Marathon and 5K", inicio 2027-02-07, tipo "Special Event"), actualizado 2026-10-24. Los demás conjuntos relacionados (catálogo data.sf.gov): `7p5y-sxmu` Temp Street Closure Intersections, `4ftp-yz2f` cierres en formato WZDx, `itv4-r6g6` Special Event or Evening Meter Areas (2024-01-18; zonas de parquímetro por eventos, útil para ubicar recintos), `b6tj-gt35` Street-Use Permits (1,23 M filas, con lat/long, `permit_purpose`, fechas), `bpc9-7sus` Active and upcoming street surface permits (5.053 filas, ODbL-like PDDL, lat/long). Todos en DataSF, licencia Open Data Commons PDDL salvo indicación.
- `8i3s-ih2a` "Our415 Events and Activities" (actualizado 2026-10-24) es de programas juveniles; poco útil para ruido (solo por nombre, no revisado).
- Ticketmaster Discovery API v2: requiere `apikey`; cuota por defecto 5.000 llamadas/día y 5 req/s; paginación limitada (size×page < 1000); filtro por `geoPoint`+`radius`, `dmaId`, ciudad, código postal, `venueId`; devuelve fechas, estado, clasificación (segmento/género) y sede con lat/long — [Ticketmaster Developer](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) (VERIFICADO vía fetch; texto truncado). Restricciones de caché/visualización: en los Términos de uso, no leídos. La API devolvió HTTP 503 a un HEAD sin clave (no prueba nada).
- Calendarios de Oracle Park, Chase Center, Moscone, SF Travel, sf.gov: NO investigados ni verificados.

### Inferences
- Combinar `8x25-yybr` (hora/lugar de cierre) con la capacidad del recinto da un "índice de evento"; Ticketmaster solo añade conciertos y partidos con venta de entradas.

### Gaps
- Términos de Ticketmaster sobre almacenamiento; calendarios de recintos; si SF tiene un feed oficial de eventos.

## 4. Construcción y uso del suelo

### Takeaway
Hay tres conjuntos DataSF grandes y actualizados a diario para obras, más uso del suelo por parcela. OSM sería ideal para bares y parques, pero Overpass quedó bloqueado desde la sandbox.

### Cited Findings
- VERIFICADO: `i98e-djp9` Building Permits, 1.297.376 filas, 55 columnas (permit_type, status, filed/issued/completed_date, `description`, `estimated_cost`, bloque/lote, dirección), actualizado 2026-10-24, PDDL. Se georreferencia por bloque/lote o dirección; no vi lat/long entre las primeras 30 columnas. Es un "filter view"; Socrata permite consultar igualmente.
- VERIFICADO: `b6tj-gt35` Street-Use Permits (excavación, andamios, etc.) con `latitude`, `longitude`, `permit_start_date`, `permit_end_date`, `analysis_neighborhood`; y `smdf-6c45` Utility Excavation Permits (existe en el catálogo, no consultado).
- VERIFICADO: `c5ge-t6pj` San Francisco Land Use, 153.765 parcelas, campos `resunits`, `retail`, `pdr`, `visitor`, `total_comm`, `open_space`, `cie`, `med`, `mips`; CC0; actualizado 2026-08-17.
- VERIFICADO: lista de DataSF `Parking Meters` (`8vzz-qzz9`) y Muni Stops (`i28k-bkz6`)/rutas (`9exe-acju`) como proxies de tráfico/transporte (solo existencia en catálogo).
- OSM/Overpass: consulta a `overpass-api.de` falló con "Connection reset by peer" (bloqueo del proxy). Etiquetas que habría que extraer (por conocimiento, NO VERIFICADO en esta sesión): `amenity=bar|pub|nightclub`, `leisure=playground`, `amenity=school`, `railway=tram|subway|rail`. Alternativa: Geofabrik/BBBike extract de California o recortes OSM descargables, sin comprobar acceso. Licencia ODbL.

### Inferences
- Para obras: filtrar `i98e-djp9` por `status` activo y descripciones de demolición/estructura nueva, fusionar con permisos de calle con coordenadas para ponderar por distancia y duración.
- Uso del suelo `c5ge-t6pj` sirve para estimar densidad nocturna (retail+visitor) cuando no hay datos de bares.

### Gaps
- Conteos OSM de bares/clubes/parques en SF (sin acceso a Overpass).
- Si Building Permits tiene geometría directa o requiere unir con otro dataset de direcciones.

## 5. Parques (Rec & Park) con coordenadas en tabla

### Takeaway
Hay un reemplazo verificado: `gtr9-ntp6` "Recreation and Parks Properties" (tabular, lat/long, 255 filas, actualizado 2026-10-24). `wkn6-jn8k` es un mapa (view) que devuelve filas vacías vía `/resource`, y `3nje-yn2u` es un RPD Parks antiguo (polígonos, sin lat/long).

### Cited Findings
- VERIFICADO: DataSF ahora vive en `data.sf.gov` (`data.sfgov.org` redirige con HTML meta-refresh, por lo que `curl` sin `-L` ni parser no sigue). Usar `https://data.sf.gov/resource/<id>.json`.
- VERIFICADO: `wkn6-jn8k` es "Recreation and Parks Properties" tipo map; `/resource/wkn6-jn8k.json` devuelve objetos `{}` vacíos (solo metadatos de sistema). Por eso aparecía vacío. `3nje-yn2u` "RPD Parks": MultiPolygon, datos de 2016 (`rowsUpdatedAt` 2016-07-13), campo `map_park_n`.
- VERIFICADO: `gtr9-ntp6` — columnas `property_id`, `property_name`, `longitude`, `latitude`, `acres`, `propertytype`, `address`, `zipcode`, `analysis_neighborhood`, `supdist`, `shape`, `data_as_of`; 255 filas; PDDL. Tipos: Neighborhood Park or Playground 146, Mini Park 47, Regional Park 22, Community Garden 15, Civic Plaza or Square 10, Library 7, Parkway 2, otros. Ejemplo: Glen Canyon Park, 37.74017042, -122.44268074, 70,7 acres.
- VERIFICADO complementarios (tabulares, lat/long, PDDL, actualizados 2026-10-24): `ib5c-xgwu` Recreation and Parks Facilities (2.678 filas; `facility_type` incluye Children's Play Area 129, Basketball Court 78, Tennis Court 59, Picnic Area 99, Restroom 77); `e3jj-mbb3` Assets Maintained (9.348 filas; Play Structure 233, Athletic Accessories 227, Bench 3.293...); `38b7-6db3` Functional Areas (7.489 filas; Lawn 304, Path 418...); `8du2-b837` Park Sections (9 filas). Existe `fjzq-yb2u` mapa de zonas para perros (no consultado).
- `r33y-seqv` Annual Park Evaluation Scores (FY15-now), actualizado 2025-12-09 (catálogo; no consultado).

### Inferences
- `gtr9-ntp6` + `ib5c-xgwu` (filtrando Children's Play Area y canchas) bastan para capas "parques" y "zonas de juego/deporte ruidosas" sin geometría poligonal. Para polígonos, usar el campo `shape` de `gtr9-ntp6` (GeoJSON) o la geometría de `3nje-yn2u` solo como respaldo.
- Nota: la biblioteca está incluida como `propertytype` Library (7), lo cual duplica la fuente `fhhu-wqa7`.

### Gaps
- Si `shape` de `gtr9-ntp6` contiene polígonos completos (no abrí el campo).

## 6. Ranking por valor y facilidad de integración

| # | Fuente | Tipo | Facilidad | Nota |
|---|---|---|---|---|
| 1 | NoiseCapture dump (EE. UU. filtrado a SF) | Medido (móvil) | Media (zip + GeoJSON, ODbL) | Cobertura SF sin medir |
| 2 | BTS NTNM 2020 (carretera/ferrocarril/aviación) | Modelado | Media-baja (REST dio 500; descarga bloqueada con 403) | Bandas de 5–10 dBA; no usar en punto |
| 3 | EIR de SF Planning (mediciones por barrio) | Medido (consultoras) | Baja (PDF) | Mejor para validar |
| 4 | SF Planning Map 1 (2009) | Modelado | Baja (PDF) | Antiguo |
| 5 | `8x25-yybr`/`b6tj-gt35`/`bpc9-7sus` (eventos y obras) | Proxy | Alta (Socrata JSON) | Ya hay uno en uso |
| 6 | `i98e-djp9` permisos de obra | Proxy | Alta | Sin lat/long visible |
| 7 | `gtr9-ntp6`, `ib5c-xgwu` parques y juegos | Proxy/uso del suelo | Alta | Reemplazo verificado |
| 8 | `c5ge-t6pj` uso del suelo | Proxy | Alta | CC0 |
| 9 | Ticketmaster Discovery | Proxy | Media (clave, 5k/día) | Términos sin revisar |
| 10 | OSM (bares, escuelas, vías) | Proxy | Media (Overpass bloqueado aquí) | ODbL |
| 11 | Hush City / Freesound | Colaborativo | Baja | Licencia/cobertura no verificadas |

### Gaps globales
- No se pudo leer la página BTS (403), consultar Overpass (reset del proxy), listar el índice de NoiseCapture ni ver los términos de Ticketmaster.
- Caltrans, Puerto de SF, calendarios de recintos y estudios universitarios no se investigaron o no dieron resultados.
