# Protocolos de medición y métodos para convertir mediciones de ruido en un mapa de ruido participativo

Nota de método: búsquedas hechas el 2026-10-24. Las normas ISO están de pago; solo se usaron resúmenes oficiales/secundarios. Varias páginas (OnoMap wiki, paper Aumond/Can en HAL, repositorio Griffith) devolvieron 403/404/Anubis y no pude leerlas. Lo no verificado queda marcado como tal en Inferencias o Brechas.

## 1. Estándares y protocolos (ISO 1996, ISO 12913, END, FHWA/HUD/EPA): duración, indicadores, cobertura horaria

### Takeaway
La END usa Lden/Lnight como promedios anuales (día 12 h, tarde 4 h con +5 dB, noche 8 h con +10 dB). Las prácticas de campo de tráfico (FHWA) usan muestras de 10 a 30+ min según la variabilidad, con repetición y regla de ±3 dB. ISO 1996-2 deja el esfuerzo de medición al usuario y exige reportar la incertidumbre. ISO 12913-2 es el marco para soundscape (percepción + binaural + cuestionario), complementario y no sustituto de Lden.

### Cited Findings
- END: Lden penaliza tarde +5 dB y noche +10 dB; Lnight es el promedio de 8 h nocturnas; ambos se evalúan sobre un año completo; las horas exactas pueden variar por Estado miembro — [Wikipedia Lden](https://en.wikipedia.org/wiki/Day%E2%80%93evening%E2%80%93night_noise_level); [Geoportail Luxemburgo](https://geocatalogue.geoportail.lu/geonetwork/geoportail-lu/api/records/0015e212-a7e5-42f6-ba94-3fdb5014513c)
- Horarios por defecto de la END: día 07-19, tarde 19-23, noche 23-07 (los Estados pueden acortar la tarde 1-2 h); Lday/Levening/Lnight son niveles A promedio de largo plazo sobre todos los periodos de un año, con referencia a ISO 1996-2 — [Anexo I Directiva 2002/49/CE (cita en foro; verificar en EUR-Lex)](https://www.avnirvana.com/threads/measuring-lden-lnight.6469/); [ejemplo de variación nacional: Austria día desde 06:00](https://gesetzefinden.at/bundesrecht/verordnungen/bundes-larmv/para-3)
- ISO 1996-2:2017: cubre determinación de niveles por medición directa o extrapolación por cálculo; el usuario decide el esfuerzo de medición y por tanto la incertidumbre, que debe determinarse y reportarse; no fija un máximo permitido de incertidumbre — [iTeh ISO 1996-2:2017](https://iteh.eu/catalog/standards/iso/61f39833-035d-40b6-9b0c-6a03458b88e7/iso-1996-2-2017); [preview ANSI](https://webstore.ansi.org/preview-pages/ISO/preview_ISO+1996-2-2017.pdf)
- Incertidumbre expandida con factor de cobertura 2 (~95 %); depende de fuente, intervalo de medición, condiciones de operación, suelo/clima, distancia, instrumentación y ruido residual (estudio sobre la edición 2007) — [Univ. Alicante](https://observatorio-cientifico.ua.es/documentos/5f0500da2999524666433adc?lang=en)
- Un artículo de 2018 sostiene que ISO 1996-2 es ambigua sobre cuánto medir y propone un criterio cuantitativo basado en la incertidumbre de LAeq (validado en tráfico) — [IRIS Salerno](https://www.iris.unisa.it/handle/11386/4708292)
- ISO/TS 12913-2:2018: requisitos de recolección y reporte de datos de soundscape; cláusula 5 incluye soundwalks, cuestionarios, entrevistas guiadas, taxonomía de fuentes y mediciones binaurales; Anexo D (normativo) = medición binaural — [iTeh ISO/TS 12913-2](https://iteh.es/catalog/standards/iso/449267f1-380f-4de3-a5d4-761a28f7f12b/iso-ts-12913-2-2018)
- Protocolo SSID (basado en 12913-2): cuestionario in situ + grabación binaural de 30 s + sonómetro + video 360° — [Mitchell et al. 2020 Applied Sciences (PDF UCL)](https://discovery-pp.ucl.ac.uk/10094493/1/applsci-10-02397.pdf); [resumen en búsqueda iTeh arriba]
- FHWA Noise Measurement Handbook: duración según rango esperado min-max del nivel en la hora más ruidosa: ≤10 dB ≈ 10 min; 10-30 dB ≈ 15-20 min; >30 dB ≥ 30 min; extender si el Leq acumulado no se estabiliza; descriptor requerido en 23 CFR 772: Leq(h) o L10(h); L50, L90 y Lmax como apoyo/diagnóstico — [FHWA handbook](https://www.fhwa.dot.gov/Environment/noise/measurement/handbook.cfm)
- FHWA: repetir la medición en otro momento/día; si los dos Leq difieren ≤3 dB se promedian; si >3 dB se toma una tercera y se promedian los dos más cercanos; 12-14 h en un sitio representativo ayuda a hallar la hora pico — [FHWA handbook](https://www.fhwa.dot.gov/Environment/noise/measurement/handbook.cfm)
- Práctica DOT: mínimo 15 min por sitio en hora pico y valle con conteo de tráfico concurrente; procedimiento antiguo FHWA: registro cada 10 s durante 15 min en respuesta "slow" (verificar vigencia) — [Michigan DOT](https://www.michigan.gov/documents/mdot/Appendix_F-FordRd_I-275_Final_Noise_Analysis_Report_456578_7.pdf); [FHWA-HEP-18-065](https://www.fhwa.dot.gov/Environment/noise/measurement/fhwahep18065.pdf)
- HUD 24 CFR 51 Subpart B: DNL = promedio de 24 h con +10 dB entre 22:00 y 07:00; aceptable ≤65 DNL; "normalmente inaceptable" >65 a 75; inaceptable >75; meta interior 45 DNL — [24 CFR 51 (chanrobles)](https://chanrobles.com/usa/uslaws/cfr/title24/24-1.1.1.1.31.2.69.4.php); [Indiana IHCDA 2024](https://secure.in.gov/ihcda/files/Appendix-11.-Noise-Abatement-and-Control-2024.pdf)
- EPA 1974 (Levels Document): 70 dB (24 h) sin pérdida auditiva medible de por vida; 55 dB Ldn exterior y 45 dB interior para evitar molestia/interferencia — [EPA archive](https://epa.gov/archive/epa/aboutepa/epa-identifies-noise-levels-affecting-health-and-welfare.html)

### Inferences
- Un mapa participativo con una persona/teléfono NO puede producir Lden/Lnight/DNL regulatorios (requieren promedio anual o 24 h); lo honesto es reportar LAeq por franja horaria y, si acaso, un "Lden indicativo" modelado (marcado como estimación). Esto se infiere de las definiciones anteriores.
- Para un recorrido corto, adaptar la lógica FHWA (repetir y comparar con umbral de 3 dB) como control de calidad interno es razonable, aunque FHWA lo define para tráfico vial con sonómetro, no para teléfono.
- ISO 1996-2 pide reportar incertidumbre sin fijar un máximo: refuerza que el mapa debe mostrar incertidumbre en lugar de ocultarla.

### Gaps
- No pude leer el texto de ISO 1996-1/-2 (paywall): reglas de meteorología (viento, inversión térmica), altura de micrófono (convencionalmente 1,2-1,5 m; no verificado aquí) y distancias a fachadas quedan sin verificar.
- No verifiqué el texto oficial EUR-Lex del Anexo I; la cita proviene de un foro. Verificar antes de publicar.
- Cláusulas exactas de ISO 12913-2 (escalas de cuestionario, método A/B/C de la serie) no verificadas; 12913-3 no consultada.
- Cifras de Lmax/L10/L90 "recomendadas" por duración corta en ISO no encontradas; solo la guía FHWA.

## 2. Prácticas de mapeo participativo (NoiseCapture/Noise-Planet, Hush City, SONYC): filtros y agregación

### Takeaway
NoiseCapture mide LAeq por segundo y agrega puntos en hexágonos de 15 m con media de LAeq, LA50, conteo y tiempos; los problemas de calidad documentados son GPS, calibración, relojes y falta de protocolo, y el filtro explícito conocido es precisión GPS ≤15 m. Hush City se centra en percepción de áreas tranquilas, y SONYC usa sensores fijos calibrados más etiquetado ciudadano.

### Cited Findings
- NoiseCapture: la persona camina con registro continuo; cada punto es un LAeq de 1 s; solo se envía LAeq al servidor (LA10/LA50/LA90 se derivan); ofrece calibración acústica en la app con ganancia aplicada a toda la traza; no se guardan audios ni datos identificables; GPS se toma del siguiente fix disponible y se registra la precisión en metros — [Data paper NoiseCapture (PMC5648040)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)
- Agregación abierta: hexágonos de 15 m de radio con media de LAeq, LA50, pleasantness media (puede ser nula), conteo de mediciones, primera/última fecha; un hexágono puede combinar trazas distintas — [PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040); [resumen de búsqueda sobre el dataset](https://pmc.ncbi.nlm.nih.gov/articles/PMC9697211/)
- Calidad en datos NoiseCapture ("NC parties", eventos organizados): ~96,3 % de puntos con ubicación pero solo ~82 % con precisión ≤15 m; el filtro de precisión elimina puntos con GPS >15 m; mediciones interiores mal posicionadas (ej. 6.309 puntos de El Cairo cayeron sobre el Nilo); problemas de sincronización de reloj (fechas 1994/1999/2000); calibraciones sospechosas (40 dB; 0 dB en todas las trazas de un grupo); solo ~87 % de puntos dentro del área definida y ~91 % dentro del tiempo del evento — [Clustering NoiseCapture, PMC9697211](https://pmc.ncbi.nlm.nih.gov/articles/PMC9697211/)
- Los autores señalan que la mayoría de los métodos de control de calidad necesitan una base de referencia y que los datos de eventos organizados (usuarios entrenados, teléfonos calibrados) se consideran de mejor calidad — [PMC9697211](https://pmc.ncbi.nlm.nih.gov/articles/PMC9697211/)
- Existe un "índice de confianza" y generación de mapas de 24 h a partir de mediciones distribuidas en el día en la infraestructura asociada (solo mencionado en abstracts, no leído) — [Aumond/Can, HAL](https://halshs.archives-ouvertes.fr/halshs-01565214v1)
- Hush City: app gratuita (2017, piloto en Berlín) para identificar y evaluar áreas tranquilas; combina soundscape + ciencia ciudadana; adoptada por Berlín (2018) y Limerick (2019-) para planes de áreas tranquilas; Radicchi (2021) propone 15 recomendaciones de diseño de apps — [Open Access BCU](https://www.open-access.bcu.ac.uk/13606); [opensourcesoundscapes.org](https://opensourcesoundscapes.org/hush-city/)
- SONYC: red de >55 nodos de bajo costo con mediciones calibradas y escucha automática; voluntarios en Zooniverse etiquetan clips de 10 s (dataset UST: 3068 grabaciones, 23 clases) — [NYU SONYC](https://wp.nyu.edu/sonyc); [CACM](https://cacm.acm.org/magazines/2019/2/234354-sonyc/fulltext); [DCASE UST](https://research.adobe.com/publication/sonyc-urban-sound-tagging-sonyc-ust-a-multilabel-dataset-from-an-urban-acoustic-sensor-network)
- Precisión de teléfonos: prueba en Pekín con sonómetro Clase 2 y 5 teléfonos: error medio tras calibración de 0,24 a 2,57 dBA (dos unidades del mismo modelo necesitaron offsets distintos); micrófono externo mejora correlación al caminar (0,84 vs 0,69) y en reposo (0,98 vs 0,90) — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/)
- Variabilidad entre dispositivos: estudio de 100 teléfonos, desviación estándar 6,81 dB entre aparatos; otro reporta diferencias medias de 12 dB vs sonómetro Tipo 1; con micrófonos externos calibrados NIOSH logró ±1 dB; con constante de corrección se reportan errores <3 dB(A); estudio de París con 60 teléfonos halló buena correlación tras calibración (secundario; resumen de búsqueda) — [NIOSH/CDC](https://stacks.cdc.gov/view/cdc/199862/cdc_199862_DS1.pdf); [arXiv 2107.03646](https://arxiv.org/pdf/2107.03646v2)
- Teléfono en bolsillo/mochila produce grandes errores — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/); lectura de teléfonos no comparable con sonómetro calibrado en tesis portuguesa — [RCAAP](https://www.rcaap.pt/vufind/PublicationRecord/run_9bbca1bfbe37ee7f855ed2a10efd8df8)

### Inferences
- Un pipeline defendible, siguiendo lo observado: (1) descartar puntos sin GPS o con precisión >15 m; (2) descartar trazas con timestamps fuera del evento/ventana; (3) descartar calibraciones implausibles (0 o ≥ ~30-40 dB de offset); (4) agregar en hexágonos/celdas con mediana o media energética y conteo; (5) exigir un mínimo de trazas/tiempo por celda (el umbral NO está documentado en lo que leí).
- Aggregation estadística: los promedios de dB deben hacerse en escala energética para LAeq, mientras que medianas de LAeq por segundo funcionan para robustez ante outliers (decisión de diseño propia, no de fuente).

### Gaps
- No pude abrir la wiki de OnoMap ni el código: filtros exactos (duración mínima de traza, conteo mínimo por hexágono, umbrales de calibración) no verificados.
- Metodología exacta de captura de Hush City (duración de la grabación) no confirmada; la cifra de 30 s es de SSID, no de Hush City.
- Proyecto "Citizen Noise" no encontrado/identificado específicamente.
- Detalles de filtros de SONYC para el mapa no verificados (sus sensores son fijos, no participativos).

## 3. Interpolación espacial y modelación (kriging/IDW, regresión de uso de suelo, NoiseModelling/CNOSSOS-EU, incertidumbre)

### Takeaway
Con muestras escasas, el kriging solo funciona bien si hay alta densidad de puntos; los métodos que usan información auxiliar (clases de uso del suelo, red viaria, simulación CNOSSOS) lo superan localmente. NoiseModelling (open source, CNOSSOS-EU) es la base natural para un modelo de tráfico al que asimilar mediciones.

### Cited Findings
- Kriging ordinario y universal evaluados sobre mediciones móviles recorriendo todas las calles del distrito XIII de París, incluida una distancia que respeta la topología de la red viaria; conclusión: se necesita alta densidad de puntos para acercarse al mapa de referencia — [Aumond et al. (Griffith/SonicField)](https://labs.sonicfield.org/library/kriging-based-spatial-interpolation-from-measurements-for-sound-level-mapping-in)
- Pekín: método regional (RNMM) con clases de uso (edificio, vía, plaza) vs kriging ordinario con 1.898 (pico) y 2.045 (valle) mediciones en 500 m x 500 m, malla de 20 m, 90/10 de entrenamiento/validación: desv. estándar 2,49 vs 3,06 dBA en pico y 3,02 vs 3,11 en valle; errores mayores en plazas por ruido de multitud aleatorio — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/)
- Regresión por uso de suelo se usa para predecir zonas sin mediciones — [MDPI Urban Sci. 2024](https://www.mdpi.com/2413-8851/8/1/13)
- Kriging con voluntarios en GIS reportado como fiable y barato (Grecia) — [FIG 2018](https://www.fig.net:443/resources/monthly_articles/2018/February_2018/Bakogiannis_etal_february_2018.pdf)
- NoiseModelling: biblioteca Java libre; implementa emisión y propagación CNOSSOS-EU (carretera y, en Francia, ferroviaria); v5.0 valida CNOSSOS y permite periodos arbitrarios; usa H2GIS/PostGIS; se puede usar con GUI — [NoiseModelling docs](https://noisemodelling.readthedocs.io/); [v5.0](https://noisemodelling.readthedocs.io/en/v5.0.0/index.html)
- Mapas por simulación son inciertos por parametrización y error de modelo; asimilación de datos (Khan, Aumond, Can, INTER-NOISE 2024) se explora con CNOSSOS (caso danés) — [INCE Proceedings](https://ince.publisher.ingentaconnect.com/content/ince/incecp/2024/00000270/00000005/art00107;jsessionid=cr8qrnbl8gfpf.x-ic-live-03?format=bib)

### Inferences
- Para un evento/recinto con ~decenas de puntos, kriging directo dará superficies engañosas lejos de las muestras; mejor modelo híbrido: superficie base (distancia a fuentes, uso del suelo o salida NoiseModelling) + kriging de residuos ("regression kriging"). Es una práctica estándar de geoestadística pero no la verifiqué en una fuente de ruido aquí.
- Incertidumbre representable con: varianza de kriging/desv. de validación cruzada (ej. ~2,5-3 dBA en los datos de Pekín como orden de magnitud), distancia a la muestra más cercana, conteo por celda.
- IDW no tiene medida de incertidumbre propia; preferir kriging o bootstrap.

### Gaps
- Sin fuente que combine explícitamente NoiseCapture + NoiseModelling + kriging en un solo flujo; solo piezas.
- No verifiqué valores de rango/variograma típicos de ruido urbano ni umbrales de densidad (puntos/km²).
- No leí el texto de Khan et al. 2024.

## 4. Protocolo mínimo viable (una persona, un teléfono) y representación de incertidumbre/desconocido

### Takeaway
Las fuentes respaldan: calibrar el teléfono contra una referencia, sostener el teléfono con micrófono expuesto (no en bolsillo), filtrar GPS >15 m, repetir mediciones y comparar (regla de 3 dB FHWA), y agregar por celda con conteos. Los números concretos del protocolo abajo son propuestas mías, no estándar.

### Cited Findings
- Bolsillo/mochila causa grandes errores; micrófono externo mejora correlación; offsets distintos por unidad — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/)
- Calibración con tono de 1 kHz durante 2 × 4 min separados por 2 min de silencio (para ~10 min), contra sonómetro Clase 2 — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/)
- Repetición y regla de 3 dB, duración de 10-30+ min según fluctuación — [FHWA](https://www.fhwa.dot.gov/Environment/noise/measurement/handbook.cfm)
- Recorridos con ventanas pico/valle: 8-9 h y 21-22 h en la campaña de Pekín; conteos concurrentes en DOT — [PMC5087480](https://pmc.ncbi.nlm.nih.gov/articles/PMC5087480/); [Michigan DOT](https://www.michigan.gov/documents/mdot/Appendix_F-FordRd_I-275_Final_Noise_Analysis_Report_456578_7.pdf)
- Filtro GPS ≤15 m y celdas hexagonales de 15 m en NoiseCapture — [PMC9697211](https://pmc.ncbi.nlm.nih.gov/articles/PMC9697211/); [PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)

### Inferences (propuesta, NO verificada por norma; ajustar)
- Calibración: antes y después del recorrido, contra un sonómetro prestado/ruido de referencia o tono 1 kHz; registrar modelo de teléfono, app y offset; probar con un segundo teléfono en un punto fijo.
- Muestreo: puntos fijos de 2-5 min (LAeq, LA10, LA90, LAmax) cada ~50-100 m a lo largo de la ruta o en una malla en el recinto, más 2-3 puntos de referencia fijos remedidos al inicio, a mitad y al final del día para detectar deriva temporal.
- Franjas: al menos 2-3 buckets (p. ej. mañana, tarde, noche o antes/durante/después del evento); no mezclar franjas en una misma celda.
- Repeticiones: 2 pasadas por franja; si difieren >3 dB, una tercera (adaptado de FHWA).
- Metadatos por muestra: precisión GPS, viento, posición del teléfono, fuentes dominantes anotadas, evento atípico (sirena, multitud).
- Mapa: tres capas visuales: (a) nivel estimado, (b) incertidumbre (desv. estándar o IC), (c) "sin datos" en gris hachurado donde la distancia a la muestra más cercana excede un alcance (rango del variograma o ~50-100 m a definir). Celdas con n < umbral se muestran como "insuficiente", no como un color. Etiquetar como "indicativo, no conforme con ISO 1996/END".

### Gaps
- No existe en las fuentes leídas un protocolo normalizado para teléfono + una persona; conteos de muestras, intervalos y umbrales son propuestas de diseño que necesitan validación (p. ej. comparando con sonómetro en 3-5 puntos).
- Altura/orientación del micrófono, protección contra viento (pantalla) y desempeño de teléfonos actuales (2025-2026) no verificados.
