# Fuentes de datos sobre el ambiente sonoro de San Francisco, CA (verificado el 2026-10-24)

Nota de método: los datasets de DataSF se verificaron consultando en vivo la API Socrata (`https://data.sfgov.org/api/views/<ID>.json` y `/resource/<ID>.json`) el 2026-10-24. El portal redirige a `data.sf.gov` (301). Las consultas devolvieron datos reales; los conteos son de esa fecha. El catálogo se listó con `https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&q=...`.

## 1. DataSF / SF Open Data: quejas 311 de ruido, permisos, eventos, obras, cierres de calle

### Takeaway
Hay datos abiertos, con coordenadas, actualizados a diario y con licencia PDDL (dominio público): quejas 311 de ruido (~100k registros desde 2015), permisos de entretenimiento, permisos de ruido nocturno, cierres temporales de calle/eventos y permisos de obra. Todos son proxies de fuentes de ruido o de molestia percibida, no mediciones en dB. Ojo: en 311 el nombre de categoría cambió de "Noise Report" a "Noise" el 2024-06-13.

### Cited Findings
**311 Cases (dataset `vw6y-z8j6`)**
- Ficha: nombre "311 Cases", licencia PDDL (Open Data Commons Public Domain Dedication and License), "actualiza cada noche, ~6am Pacific", casos desde 2008-07-01 — [API views](https://data.sfgov.org/api/views/vw6y-z8j6.json); FAQ del dataset: [sfdigitalservices gitbook](https://sfdigitalservices.gitbook.io/dataset-explainers/311-cases)
- Endpoint SODA: `https://data.sfgov.org/resource/vw6y-z8j6.json` (también `.csv`; admite SoQL `$where`, `$select`, `$group`) — [consulta de verificación](https://data.sfgov.org/resource/vw6y-z8j6.json?$limit=1)
- Campos útiles: `service_request_id`, `requested_datetime`, `closed_date`, `updated_datetime`, `status_description`, `status_notes`, `agency_responsible`, `service_name`, `service_subtype`, `service_details`, `address`, `street`, `supervisor_district`, `analysis_neighborhood`, `police_district`, `lat`, `long`, `point`/`point_geom`, `source`, `media_url`, `data_as_of`, `data_loaded_at` — [API views](https://data.sfgov.org/api/views/vw6y-z8j6.json)
- Filtro de ruido: `service_name in ('Noise Report','Noise')`. "Noise Report" cubre 2015-08-25 a 2024-06-11 (62,018 filas); "Noise" cubre 2024-06-13 a 2026-10-23 (35,675 filas). Conteo anual combinado: 2016: 3,798; 2017: 5,388; 2018: 6,630; 2019: 7,520; 2020: 11,238; 2021: 7,324; 2022: 7,340; 2023: 8,259; 2024: 9,864; 2025: 11,893; 2026 (hasta 10-23): 17,542 — consultas SoQL propias sobre [vw6y-z8j6](https://data.sfgov.org/resource/vw6y-z8j6.json)
- Valores de `service_subtype` (los mayores, ambas categorías): `other_excessive_noise`, `entertainment`, `construction_private_property`, `construction_public`, `amplified_sound_electronics`, `mechanical_equipment`, `garbage_recycling_collection`, `major_event_venue`, `traffic`, `delivery_service_business`, `vehicle_car_alarm`, `sirens`, `home_improvement_maintenance`, `public_speech`, `protest_speech_bullhorns`, `mobile_food_facility`, `tour_bus`, `emergency_equipment`, `hospital`, `vehicle_repair`, `rv_oversize_vehicle`, `delivery_service_vehicle`, `delivery_service_construction`, `construction_emergency`, `other_reallocate`. En "Noise Report" aparecen además valores sucios (p. ej. "Noise Issue" 11,900 filas, y texto libre en el subtipo) — [conteo SoQL propio](https://data.sfgov.org/resource/vw6y-z8j6.json?$select=service_name,service_subtype,count(*)&$where=service_name%20like%20%27%25oise%25%27&$group=service_name,service_subtype)
- `agency_responsible` en ruido: "Noise Report Queue" 24,234; "311 Supervisor Queue" 12,736; "Entertainment Commission - G" 6,521; "DBI Inspection Services Queue" 6,329; "DPW BSM Queue" 3,436; "DPH - Environmental Health - Noise Queue" 2,398 (top 6, solo categoría "Noise Report") — consulta propia
- Georreferenciación: 0 de las "Noise Report" sin lat; 7 de las "Noise" sin lat — consulta propia
- Existe `media_url` (foto adjunta, no relevante a audio) y los campos `:@computed_region_*` (polígonos de distrito/barrio precalculados)

**Entretenimiento / ruido nocturno**
- Active Entertainment Permits `86e8-rfem` (PDDL, actualizado diario; 740 filas). Campos: `permit_number`, `permit_status`, `poe_class_code`, `license_type`, `dba_name`, `street_address`, `point`, `analysis_neighborhood`, `supervisor_district`, `police_district`. Gestionado por la Entertainment Commission. Mapa derivado: `58df-6jka`. Vista "Places of Entertainment" `76g9-59eq` — [ficha](https://data.sfgov.org/api/views/86e8-rfem.json)
- Night Noise Permits `e7pr-36bt` (PDDL; 1,078 filas desde 2019-08-01; actualizado 2026-10-15). Campos: `nnp`, `type_of_work`, `start_date`, `end_date`, `start_end_time_each_day`, `address`, `block`, `lot`, `supervisor_district`, `analysis_neighborhood`, `point`. Mapa: `4wma-tkjg`. Ojo: hay un `max(end_date)` = 2219-11-22, es un dato erróneo de origen (filtrar fechas absurdas) — [ficha](https://data.sfgov.org/api/views/e7pr-36bt.json)

**Cierres de calle y eventos**
- Temporary Street Closures `8x25-yybr` (PDDL, SFMTA, actualizado diario). Solo cierres permitidos por SFMTA (no los de Public Works ni Policía). Tipos: "Roadway Shared Spaces" 2,959; "Special Event" 1,094; "Special Traffic Permit" 226. Campos: `case_num`, `case_name`, `type`, `status`, `start_dt`, `end_dt`, `loc_desc`, `cnn`, `street`, `from_st`, `to_st`, `veh_imp`, `shape` (LineString), `start_utc`, `end_utc`. Incluye eventos futuros (p. ej. media maratón 2027-02-07). Mapa de eventos: `nb2q-m4if`/`v9cz-kk5i`; intersecciones: `7p5y-sxmu`; WZDx: `4ftp-yz2f` (2022, desactualizado) — [ficha](https://data.sfgov.org/api/views/8x25-yybr.json)
- Special Event or Evening Meter Areas `itv4-r6g6` (última actualización 2024-01-18; es de parquímetros, no de ruido) — [catálogo](https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&q=special%20events)

**Obras**
- Building Permits `i98e-djp9` (PDDL; desde 12/2024 solo publica filas nuevas/actualizadas; usar `data_as_of`). Campos: `permit_number`, `permit_type_definition`, `filed_date`, `issued_date`, `completed_date`, `status`, `description`, `estimated_cost`, `proposed_use`, `location`, `neighborhoods_analysis_boundaries` — [ficha](https://data.sfgov.org/api/views/i98e-djp9.json)
- Street-Use Permits `b6tj-gt35` (Public Works, desde 1996; incluye `permit_purpose`, `permit_start_date`, `permit_end_date`, `latitude`, `longitude`, `status`) — [ficha](https://data.sfgov.org/api/views/b6tj-gt35.json)
- Parking Signs / Street Space Permits `sftu-nd43` (obras que ocupan calzada/acera; `startdate`, `enddate`, `starttime`, `endtime`, `_24hourenforcement`, `latitude`, `longitude`) — [ficha](https://data.sfgov.org/api/views/sftu-nd43.json)
- Otros listados en catálogo: Utility Excavation Permits `smdf-6c45`, DPW permits `fxfq-npa9`, DPW projects `btxj-k9uh` — [catálogo](https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&q=public%20works%20permits)

### Inferences
- Una queja 311 mide molestia percibida y propensión a denunciar, no nivel sonoro; está sesgada por demografía, conocimiento del sistema 311 y densidad de población. Para el mapa conviene normalizar (por población/área) y suavizar (kernel/hexágonos), y etiquetar como "quejas", no como dB.
- El cambio de nombre de categoría en 2024-06 obliga a unir ambas categorías; el aumento 2025-2026 puede ser en parte cambio de formulario/etiquetado (no verificado).
- Los permisos y cierres futuros permiten una capa "ruido previsto/temporal" (eventos, obras nocturnas); los permisos de entretenimiento dan puntos de fuente fija.

### Gaps
- No verifiqué la fecha exacta ni el motivo del cambio de "Noise Report" a "Noise" en 311 (solo observé los rangos de fechas).
- No encontré un dataset de "special events permits" distinto del de cierres temporales de calle (la Entertainment Commission no parece publicar uno aparte; no verificado exhaustivamente).
- No verifiqué la tabla de Public Works "Active Street-Use Permits" mencionada en la nota del dataset (ID no confirmado).

## 2. Mapas de ruido municipales, estatales y federales (DPH, Plan General, Caltrans, BTS, SFO, Muni/BART/Caltrain)

### Takeaway
No encontré un mapa de ruido de SF en datos abiertos con coordenadas. Lo más usable: el mapa federal BTS (modelado, aviación + carretera + ferrocarril de pasajeros, solo tendencias) y los datos medidos del Aeropuerto SFO (29 monitores comunitarios, CNEL, publicados en DataSF), de los cuales solo ~6 están dentro de SF.

### Cited Findings
**BTS National Transportation Noise Map**
- Contiene capas de inventario de ruido para aviación, carreteras y ferrocarril de pasajeros; se ofrece como servicios web (WMS) para GIS y hay sección de archivos para descarga; BTS dice que sirve para seguir tendencias y que no debe usarse para evaluar niveles en ubicaciones/momentos concretos — [BTS (vía búsqueda; la página devolvió 403 a mi acceso directo)](https://www.bts.gov/geospatial/national-transportation-noise-map)
- Cadencia: BTS habla de actualización bienal (el anuncio de 2017 decía anual); primera actualización bienal en noviembre de 2020 — [Volpe](https://www.volpe.dot.gov/news/enhancing-bts-national-transportation-noise-map)
- Documentación metodológica en PDF (fechada 2020-11-01); el registro menciona una versión "Release Year: 2026" en documentos relacionados; futuras versiones podrían añadir carga ferroviaria y marítima — [ROSAP DOT 53773](https://rosap.ntl.bts.gov/view/dot/53773)
- Existen "stories" de BTS: [ri89-bhxh](https://data.bts.gov/stories/s/ri89-bhxh) y FAQ [t9hk-f4es](https://data.bts.gov/stories/s/t9hk-f4es)
- Una capa de terceros en ArcGIS Online (no oficial BTS) replica el mapa 2020 categorizado — [servicio](https://services8.arcgis.com/rGGrs6HCnw87OFOT/ArcGIS/rest/services/NoiseLevelsCategorized/FeatureServer)
- Intento de usar `geo.dot.gov/server/rest/services/NTAD` desde mi entorno: redirigió a login (no accesible anónimamente desde aquí) — verificación propia

**SFO (Aeropuerto Internacional de San Francisco) en DataSF** (todos actualizados hasta 2026-08-31, publicación 2026-09-22; mensual)
- Aircraft Noise Climates `qxw2-ncq3`: PDDL; 99,386 filas, 2017-03-01 a 2026-08-31, 32 `location_id` distintos (29 monitores comunitarios según la ficha; la diferencia no la verifiqué). Campos: `date`, `location_id`, `location`, `longitude`, `latitude`, `elevation`, `aircraft_cnel`, `sfo_cnel`, `non_sfo_cnel`, `community_cnel`, `total_cnel`, `uptime`, `point`. La ficha dice que el CNEL anual de aeronaves valida el contorno de 65 dB (modelado). Solo 6 puntos tienen `location = San Francisco` (aprox. 37.711,-122.399; 37.726,-122.411; 37.729,-122.466; 37.740,-122.433; 37.748,-122.467; 37.792,-122.437) — [ficha](https://data.sfgov.org/api/views/qxw2-ncq3.json) y consulta propia
- Aircraft Noise Exceedances `tiju-qyvs`: 258,672 eventos 2019-08 a 2026-08; campos `location_id`, `max_date_time`, `sel`, `max_level`, `duration`, `day_night`, `operation_type`, `runway_name`, `aircraft_type`, `airline`. Sin licencia declarada en la ficha (`licenseId` = None) — [ficha](https://data.sfgov.org/api/views/tiju-qyvs.json)
- Aircraft Noise Reports `peaa-dyr3`: 7,597,785 quejas 2019-08 a 2026-08; campos `disturbance_date_time`, `report_method`, `report_city`, `report_postal_code`, `runway_name`, `aircraft_type`. Muy concentradas en Palo Alto (1.73 M), Portola Valley, Santa Cruz (pocos reportantes repetidos; sesgo fuerte) — consulta propia
- Aircraft Noise Report Summary `q3xd-hfi8` (conteos mensuales por comunidad), Noise Exceedance Rating `5m6g-bqm4` (por aerolínea) — [catálogo](https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&q=noise)
- Contexto normativo: Título 21 de California usa el contorno CNEL 65 dB como "noise impact boundary"; monitores validan los extremos del contorno — [SFO Roundtable](https://sforoundtable.org/wp-content/uploads/2019/08/20190807_Title21-Presentation.pdf)

**Marco municipal (DPH / Plan General)**
- SF DPH gestiona la respuesta al Artículo 29 (Police Code, regulación de ruido) y enlaza el Elemento de Protección Ambiental del Plan General (transporte/ruido; incorporado en 1972, Objetivos 9–11) — [DPH](https://www.sfdph.org/dph/eh/Noise), [búsqueda sobre Artículo 29](https://www.sf.gov/sites/default/files/2024-02/21_CACOSF_2023_Article29RegulationofNoiseGuidelines.pdf)
- Artículo 29: límites de fuente fija por zonificación y hora (ej. 50 dBA noche en R-1, hasta 75 dBA en M-2), piso de ambiente 35 dBA interior / 45 dBA exterior para medición; responsabilidad compartida DPH, Policía, DBI, Public Works, Planning, Rec&Park, Entertainment Commission — [nonoise.org copia de ordenanza](https://nonoise.org/regulation/ordinance/San%20Francisco,%20California.pdf)

### Inferences
- El monitor SFO sirve como validación puntual de la señal de aviación en el sur/oeste de SF, no como cobertura de ciudad. Para el resto, el único modelo disponible es el de BTS (resolución gruesa, solo tendencias).
- Los límites del Artículo 29 podrían usarse como umbrales de referencia en etiquetas ("límite legal de fuente fija en zona X"), pero no como niveles medidos.

### Gaps
- No encontré/verifiqué el mapa de ruido del Plan General (Elemento de Protección Ambiental, Mapa de ruido de transporte, 1974-2000s) en formato digital; la búsqueda no lo devolvió. Posiblemente solo PDF/imagen y antiguo (no verificado).
- No encontré un mapa de ruido de DPH con coordenadas ni mediciones sistemáticas de DPH (hay un "Citywide Enforcement Guidance" y guías de evaluación de impacto de ruido de 2011 según la página de DPH, sin datos espaciales).
- No verifiqué datos de Caltrans (ni Caltrans Traffic Noise / TNM contornos) para SF: sin evidencia en esta sesión.
- No verifiqué datos de ruido de Muni, BART o Caltrain (se ha de asumir inexistentes como datos abiertos hasta confirmar; BART/Caltrain publican estudios de EIR en PDF, no verificado).
- Las URLs `bts.gov` devolvieron 403 al acceso directo desde este entorno; capas exactas, métrica (LAeq 24 h u otra), umbral mínimo y año de datos NO quedaron verificados. No hay IDs/URLs de servicio ArcGIS oficiales confirmados.

## 3. Crowdsourced: NoiseCapture, Hush City, NoiseTube, Freesound, SONYC

### Takeaway
NoiseCapture es la única fuente colaborativa de la lista con datos abiertos (ODbL) por usuarios, pero no pude verificar su cobertura en SF ni el endpoint de descarga actual. SONYC es una red de sensores de NYC, sin relevancia directa para SF. Hush City, NoiseTube y Freesound: no verificados.

### Cited Findings
- NoiseCapture: app Android (código GPLv3) que calcula indicadores acústicos sin grabar audio; resultados anónimos se envían a una base comunitaria y se procesan para un mapa; mapa en onomap.noise-planet.org (hoy redirige a noise-planet.org/map_noisecapture) — [GitHub Picaut/NoiseCapture](https://github.com/Picaut/NoiseCapture), [F-Droid](https://f-droid.org/de/packages/org.noise_planet.noisecapture/)
- Datos: la Universidad Gustave Eiffel lista un dataset agosto 2017 – agosto 2020 bajo ODbL con DOI 10.25578/J5DG3W — [resumen de búsqueda sobre la ficha](https://reflexscience.univ-gustave-eiffel.fr/en/read/articles/noisecapture-an-application-to-evaluate-the-sound-environment); mi intento de abrir `doi.org/10.25578/J5DG3W` falló por certificado TLS en este entorno
- Un paquete Python de Noise-Planet documenta cómo un estudio en Lyon descargó datos desde un dashboard público `dashboard.noise-planet.org/public/question/...` (ruta de descarga por consulta, ejemplo de una sola ciudad) — [noiseplanet.readthedocs.io](https://noiseplanet.readthedocs.io/en/latest/pages/welcome.html)
- SONYC: red de ~60 sensores en NYC; el dataset público "Urban Sound Tagging" en Zenodo es un subconjunto pequeño con ubicación cuantizada a manzana y tiempo a hora — [Zenodo 3966543](https://zenodo.org/record/3966543), [NYU](https://engineering.nyu.edu/news/sensor-networks-help-fight-floods-and-noise-pollution)

### Inferences
- La cobertura de NoiseCapture en SF probablemente es dispersa (apps de este tipo concentran datos en pocas ciudades), pero esto es una inferencia, no un hecho comprobado. Habría que descargar el dataset y filtrar por bbox (aprox. lon -122.52 a -122.35, lat 37.70 a 37.83) para contar mediciones. Mediciones de teléfono no están calibradas por defecto: etiquetar como "indicativas".
- SONYC no aporta datos de SF; solo es referencia metodológica (cuantización de privacidad espacial/temporal).

### Gaps
- Cobertura NoiseCapture en SF: no medida. Endpoint de exportación vigente (2026) y licencia de datos recientes (post-2020): no verificado.
- Hush City (app de áreas silenciosas): una búsqueda no devolvió nada; no verificado si existe dataset abierto.
- NoiseTube y Freesound geoetiquetado (API de Freesound requiere token; licencias CC por sonido): no investigados en esta sesión.

## 4. Inventario de espacios tranquilos: parques, POPOS, bibliotecas

### Takeaway
DataSF ofrece parques (polígonos), 81 POPOS con coordenadas y atributos de ambiente, y bibliotecas con coordenadas, todos con licencia PDDL y actualizados el 2026-10-24 (salvo la capa RPD Parks antigua). "Tranquilo" no está medido: es una categoría de uso del suelo.

### Cited Findings
- POPOS `65ik-7wqd`: 81 filas; mapa `33jz-gqck`. Campos: `name`, `popos_address`, `hours`, `hours_type`, `type`, `indoor`, `landscaping`, `seating_no`, `food_service`, `art`, `restrooms`, `accessibility`, `description`, `latitude`, `longitude`, `point`, `year`. Ejemplo: 135 Main St, "Indoor Park", landscaping "Waterfall on glass, some white noise effect" (descripción cualitativa que menciona ruido). Fuente de atributos con texto libre (p. ej. horarios "Unknown") — [ficha](https://data.sfgov.org/api/views/65ik-7wqd.json), [consulta](https://data.sfgov.org/resource/65ik-7wqd.json?$limit=1)
- Recreation and Parks Properties `wkn6-jn8k` (PDDL; actualizado 2026-10-24; parques, campos de golf, campings). Es un "visualization_canvas_map" cuya vista `/resource/wkn6-jn8k.json` devolvió `[{}]` (sin columnas tabulares accesibles), por lo que hay que localizar la tabla/vista hija o GeoJSON de exportación — [ficha](https://data.sfgov.org/api/views/wkn6-jn8k.json); sin verificar el ID de la vista de datos subyacente
- RPD Parks `3nje-yn2u`: polígonos (`the_geom`, `acres`, `map_park_n`), pero última actualización 2016-07-13 (obsoleta) — [ficha](https://data.sfgov.org/api/views/3nje-yn2u.json)
- Annual Park Evaluation Scores `r33y-seqv` (actualizado 2025-12-09), puntuaciones de parques — [catálogo](https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&q=recreation%20park)
- Bibliotecas públicas: City Facilities – Public Library `fhhu-wqa7` (PDDL; `facility_id`, `common_name`, `address`, `latitude`, `longitude`, `supervisor_district`) — [ficha](https://data.sfgov.org/api/views/fhhu-wqa7.json)

### Inferences
- Parques y POPOS pueden marcarse como "candidatos a refugio sonoro" solo si se cruzan con proximidad a fuentes (carreteras, bares, obras) y se rotulan como "estimado". El campo `landscaping` de POPOS y `indoor` aportan señales cualitativas útiles.

### Gaps
- El ID de la capa tabular/geoespacial de parques de RPD actual (distinta de `3nje-yn2u`) no quedó confirmado.
- No verifiqué bibliotecas de la SFPL por separado (horarios) ni espacios como jardines comunitarios o cementerios.

## 5. Qué se puede derivar (proxies) vs. medido, y requisitos de honestidad

### Takeaway
En lo verificado, lo único medido en dB en SF son los 6 monitores de SFO (CNEL de aeronaves, tiempo real/mensual). El resto son proxies (quejas, permisos, cierres) o modelos gruesos (BTS). El mapa debe rotular cada capa por tipo de evidencia y no presentar una cifra en dB donde solo hay un índice.

### Cited Findings
- BTS declara que su mapa modelado no debe usarse para evaluar niveles en ubicaciones concretas — [BTS](https://www.bts.gov/geospatial/national-transportation-noise-map) (vía resultados de búsqueda)
- Los datos de quejas aeronáuticas están dominados por pocos reportantes repetidos (Palo Alto, Portola Valley, Santa Cruz concentran la mayor parte de 7.6 M reportes), no es medida de exposición — [peaa-dyr3](https://data.sfgov.org/resource/peaa-dyr3.json?$select=report_city,count(*)&$group=report_city&$order=count%20DESC&$limit=5)
- Los límites legales de Artículo 29 son umbrales reglamentarios, no medidas — [Art. 29](https://www.sf.gov/sites/default/files/2024-02/21_CACOSF_2023_Article29RegulationofNoiseGuidelines.pdf)

### Inferences (propuesta de etiquetado, no una norma verificada)
- Clasificar cada capa en: (A) Medido (SFO CNEL, 6 puntos SF); (B) Modelado (BTS: aviación/carretera/ferrocarril de pasajeros, solo tendencias); (C) Proxy de molestia (quejas 311); (D) Proxy de fuente (permisos entretenimiento, ruido nocturno, obras, cierres); (E) Inventario de refugios (parques, POPOS, bibliotecas, con riesgo de que no sean realmente silenciosos).
- Mostrar fecha de datos (`data_as_of`), ventana temporal y tamaño de muestra; no mezclar en un solo "dB score" sin declarar que es un índice compuesto; sustituir los puntajes sintéticos por conteos/densidades normalizadas y mostrar incertidumbre; en áreas sin datos, mostrar "sin datos", no un valor interpolado.
- Para quejas, aplicar agregación espacial (barrio/hexágono) por privacidad y estabilidad; el campo `source` y `agency_responsible` permiten analizar sesgo.

### Gaps
- No existe (en lo verificado) un estándar de etiquetado oficial para mapas de ruido compuestos; la propuesta anterior es mía.
- Sin verificar la guía de la Directiva Europea de Ruido (END) u OMS como referencia de clasificación en este alcance.
