# Apps y sensores de smartphone/smartwatch para medir ruido ambiental (estado a oct-2026)

Nota de alcance: se hicieron ~14 llamadas de búsqueda/lectura. La evidencia revisada por pares más sólida sobre apps genéricas sigue siendo 2014-2018 (Kardous y Shaw); la evidencia 2020-2024 es escasa y se limita a los estudios citados abajo. No encontré estudios de 2025-2026 sobre apps de ruido (ver Gaps).

## 1. ¿Qué apps tienen validación independiente? Errores en dB, iOS vs Android, ponderación, Leq/Lmax/percentiles, duración

### Takeaway
La mejor evidencia independiente favorece a la app NIOSH Sound Level Meter (solo iOS): error de aprox. ±0,5 dB(A) frente a un SLM tipo 2 en 2023, mientras que Decibel X y SoundMeter X subestiman de forma consistente (hasta -3 a -4 dB(A)). En Android no hay ninguna app con validación independiente comparable; NoiseCapture (Android, abierta) requiere calibración por dispositivo, y con calibración muestra errores medios de aprox. -0,6 ± 1,2 dB(A) en un estudio de 8 teléfonos.

### Cited Findings
- Kardous y Shaw (JASA, 2014) examinaron 192 apps de smartphone; solo 10 (iOS) cumplieron criterios de selección y solo 4 quedaron dentro de ±2 dB(A) de un SLM tipo 1: SoundMeter, SPLnFFT, SPL Pro y NoiSee. De 62 apps Android descargadas, solo 4 cumplieron parcialmente los criterios — [NIOSH Science Blog](https://blogs.cdc.gov/niosh-science-blog/?p=4994); [CDC Stacks](https://stacks.cdc.gov/view/cdc/203723)
- Las apps iOS eran más avanzadas en funciones y rendimiento que las Android; en Android hubo gran variación entre dispositivos para la misma app — [NIOSH Science Blog](https://blogs.cdc.gov/niosh-science-blog/?p=4994); [Use of smartphone sound measurement apps for occupational noise assessments](https://stacks.cdc.gov/view/cdc/203723)
- Seguimiento Kardous y Shaw (2016): con micrófonos externos calibrados (MicW i436, Dayton Audio iMM-6) las 4 apps iOS quedaron dentro de ±1 dB(A) del SLM tipo 1 — [Sonic Field library](https://sonicfield.org/library/evaluation-of-smartphone-sound-measurement-applications-using-external-microphon); [NIOSH Science Blog](https://blogs.cdc.gov/niosh-science-blog/?p=4994)
- NIOSH SLM app: desarrollada con EA LAB (memorando feb-2015), sometida a los mismos criterios de prueba; solo iOS — [NIOSH Science Blog](https://blogs.cdc.gov/niosh-science-blog/?p=4994)
- Huyan et al., JMIR mHealth uHealth 2023;11:e46846 (referencia: Brüel & Kjær 2250, LAeq de 30 s; ruido blanco 60-85 dB en laboratorio y 20 muestras por sitio en biblioteca, centro de actividades y taller): NIOSH SLM ~0,5 dB(A) de diferencia (P=.78), aunque con mayor variabilidad en campo; Decibel X subestimó >2 dB(A) en laboratorio y ~-4 dB(A) en 45-50 dB y >-3 dB(A) en 60-85 dB en campo (P<.001 en campo); SoundMeter X subestimó de forma consistente (~-2 dB(A) a nivel bajo, con valores atípicos >-4 dB(A)). Valores aproximados reportados por el artículo — [PMC10686533](https://pmc.ncbi.nlm.nih.gov/articles/PMC10686533)
- Estudio de 100 teléfonos en cámara reverberante (Applied Acoustics, 2016): apps iOS superiores a Android y relación significativa entre antigüedad del teléfono y exactitud; la app SLA Lite quedó dentro de ±1 dB en cuatro condiciones — [Univ. of Galway record](https://research.universityofgalway.ie/en/publications/testing-the-accuracy-of-smartphones-and-sound-level-meter-applica-5/) (el detalle proviene del resumen de búsqueda, no del artículo completo)
- NIOSH advierte que los smartphones no se diseñaron para cumplir normas de SLM; usar las apps como herramienta de cribado, no de cumplimiento — [CDC Stacks](https://stacks.cdc.gov/view/cdc/203723)
- NoiseCapture (Android, abierta): los autores indican que la calibración del par app/teléfono es necesaria para sesgo mínimo — [Boumchich et al., Sensors 2024, PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730). Calibración mutua teléfono-referencia en 8 teléfonos frente a SLM clase 1 en 6 puntos: error medio -0,6 ± 1,2 dB(A) (descrito por la búsqueda para Aumond et al.; no confirmé que sea específicamente NoiseCapture) — [Applied Acoustics 2020 (Aumond et al.)](https://dehesa.unex.es/bitstream/10662/19302/1/j_apacoust_2020_107337_AMM.pdf)
- Calibración ciega de NoiseCapture sobre datos reales (Rezé): error medio de la deriva estimada de aprox. -6 dB con el método básico, -3,4 dB con umbral de 100 enlaces; el híbrido NGM-SMM en celdas hexagonales de 15 m dio -1,2 a -4,8 dB. Solo datos Android — [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)
- NoiseCapture solo transmite al servidor valores LAeq (un valor por segundo); otros indicadores (p. ej. LA50 por celda) se derivan de ellos — [Bocher et al. 2017, PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)
- Duración: Huyan et al. usaron mediciones de 30 s de LAeq; no encontré una recomendación formal de duración mínima en las fuentes — [PMC10686533](https://pmc.ncbi.nlm.nih.gov/articles/PMC10686533)

### Inferences
- Para un mapa de ruido ciudadano en iOS, la NIOSH SLM es la opción con mejor respaldo (aunque es una app orientada a ocupación y no geoetiqueta, ver sección 3). En Android, NoiseCapture es la única opción abierta con flujo de calibración y mapa, pero su exactitud depende de calibrar cada teléfono.
- Los sesgos negativos de Decibel X (-3 a -4 dB(A)) indican que sin calibración sus datos no son comparables entre sitios o con otras apps.

### Gaps
- No encontré validación independiente de Decibel X, SoundMeter, Sound Analyzer ni otras apps para 2024-2026; tampoco el artículo original de Kardous y Shaw 2014 completo (solo resúmenes NIOSH). Los PDF de CDC Stacks no se pudieron leer (binarios).
- No encontré cifras de error por ponderación A vs C/Z, ni por Lmax o percentiles en apps; solo LAeq.
- Falta un estudio de validación específico y publicado de NoiseCapture frente a SLM (con cifras por modelo de teléfono) que pudiera verificar directamente.

## 2. Sensores de plataforma: Apple Watch Noise, AirPods/HealthKit, equivalentes Android

### Takeaway
La app Noise del Apple Watch lee ~0,5 dBA menos que un SLM clase 1 en campo (Series 6, rango 35-110 dBA), con límites de acuerdo de -3,0 a +4,0 dBA, y peor en niveles bajos y bajas frecuencias. HealthKit permite a terceros leer exposición de auriculares y eventos ambientales, pero no escribirlos; no confirmé acceso a niveles ambientales continuos por API ni equivalentes Android.

### Cited Findings
- Fischer et al., Frontiers in Neurology 2022;13:856219: Apple Watch Series 6 (watchOS 8.1) vs NTi Audio XL2 clase 1; 13 entornos (35-110 dBA), 12 bloques de 5 min por entorno; sesgo ~-0,5 dBA; límites de acuerdo 95% aprox. -3,0 a +4,0 dBA (objetivo ±2 dBA superado en casi todos los entornos); ICC 0,99, mínimo 0,65 en club musical. Conclusión: útil para concienciación y estudios exploratorios, no para mediciones legales — [PMC9009441](https://pmc.ncbi.nlm.nih.gov/articles/PMC9009441/)
- Informe técnico DTIC (8 Apple Watch Series 5 en cámara reverberante): 3,4 dB(A) menos que SLM con ruido rosa, 0,1 dB(A) menos con ruido de transporte grabado y 1,3 dB(A) menos con ruido de fábrica; posible menor exactitud en ambientes silenciosos y bajas frecuencias — [DTIC AD1165991](https://apps.dtic.mil/sti/trecms/pdf/AD1165991.pdf) (cifras tomadas del resumen de búsqueda; no leí el PDF)
- Roberts et al., JASA 2022;152(1):547-552 (dispositivos de ruido de consumo, 18.449 mediciones en bandas de octava): el smartwatch lee bajo de 125 a 1000 Hz, similar a 2000 Hz, alto a 4000 Hz y bajo a 8000 Hz; no cumple los criterios ANSI de SLM, pero puede servir para exposición personal prolongada — [CDC Stacks 249539](https://stacks.cdc.gov/view/cdc/249539) (resumen de búsqueda)
- HealthKit: `headphoneAudioExposure` es un tipo de cantidad en dB(A) (unidad `decibelAWeightedSoundPressureLevel()`) — [Apple Developer](https://developer.apple.com/tutorials/data/documentation/healthkit/hkquantitytypeidentifier/headphoneaudioexposure.md)
- `environmentalAudioExposureEvent` se guarda cuando el nivel medio alcanza el umbral del usuario durante 3 minutos; Apple Watch no graba sonido; las apps pueden pedir permiso de lectura pero no de escritura — [Apple Developer](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/environmentalaudioexposureevent.md)
- Un estudio JAMA Otolaryngology comparó la app Noise con un SLM clase 1 y afirma que no había evaluaciones formales previas; no pude recuperar sus resultados — [enlace vía proxy universitario](https://jamanetwork-com.libproxy.ajou.ac.kr/journals/jamaotolaryngology/fullarticle/2801969)

### Inferences
- Como los eventos ambientales solo se generan tras 3 min por encima de un umbral y son de solo lectura, el Apple Watch es útil para exposición personal, no para un mapa de puntos con muestras puntuales controladas.
- Dado el sesgo bajo y las diferencias por banda, el Watch es más fiable para ruidos de banda ancha de nivel medio-alto.

### Gaps
- No verifiqué si existe un tipo de cantidad HealthKit para nivel ambiental continuo accesible a terceros (una búsqueda sugirió `environmentalAudioExposure`, pero solo en un wrapper de React Native no oficial), ni el límite de 8 horas.
- No encontré datos sobre AirPods como sensores de ruido ambiental, ni sobre Samsung Galaxy Watch/Wear OS, ni sobre equivalentes Android (p. ej. Digital Wellbeing, Health Connect); no se verificaron.
- Resultados numéricos del estudio JAMA Otolaryngology no recuperados; año no confirmado.
- Pasos para exportar datos del app Salud (XML) no verificados.

## 3. Exportación geoetiquetada (CSV/GeoJSON), mapa y apps abiertas

### Takeaway
NoiseCapture es la opción abierta (GPL-3.0, en F-Droid) con exportación documentada en GeoJSON (tracks, puntos por segundo con coordenadas, y hexágonos de 15 m) y mapa comunitario. No verifiqué exportación geoetiquetada para NIOSH SLM, Decibel X ni SoundMeter.

### Cited Findings
- Los datos abiertos de NoiseCapture se distribuyen en zip por país con `*.tracks.geojson`, `*.points.geojson` y `*.areas.geojson` (EPSG:4326), actualizados diariamente; puntos: LAeq dB(A) por segundo, GPS (x, y, z), velocidad, orientación y precisión; tracks: `gain_calibration`, noise_level, tags, pleasantness; áreas: hexágonos de 15 m con LA50, laeq, measure_count — [Bocher et al. 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)
- Limitaciones de los datos: el GPS no siempre fija cada segundo; velocidad y orientación pueden ser imprecisas; `pk_track` puede cambiar entre actualizaciones (usar `track_uuid`); datos anónimos, sin audio — [PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)
- La ganancia de calibración del usuario ya se aplica a los niveles de cada track — [PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040)
- Calibración automática: un teléfono ya calibrado actúa como "Transmitter" y los demás como "Receiver" — resultados de búsqueda sobre la app: [F-Droid](https://f-droid.org/en/packages/org.noise_planet.noisecapture/) y [repositorio](https://github.com/Picaut/NoiseCapture)
- Código abierto GPL-3.0 (Universite Gustave Eiffel); existe un repositorio Kotlin multiplataforma (Android, iOS, Web) con 27 issues abiertos, sin detalle de madurez — [NoiseCaptureKotlin](https://github.com/nicolas-f/NoiseCaptureKotlin/blob/main/README.md)
- NoiseCapture solo está en Android según Boumchich et al. 2024 — [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)

### Inferences
- Para un mapa propio se pueden descargar los GeoJSON de la zona y recalcular LAeq por celda con la ganancia de calibración; el hexágono de 15 m ya trae LA50.
- La exportación desde la app (CSV en el dispositivo) existe probablemente, pero no la verifiqué.

### Gaps
- No verifiqué exportación CSV/GeoJSON local de NoiseCapture, ni disponibilidad actual del mapa comunitario y su licencia exacta (el artículo no nombra la licencia de los datos).
- No verifiqué exportación ni geoetiquetado de NIOSH SLM, Decibel X, SoundMeter, ni apps abiertas adicionales en F-Droid/GitHub.
- No confirmé el estado de la versión iOS de NoiseCapture a 2026.

## 4. Consejos prácticos que más reducen el error

### Takeaway
Las medidas de mayor efecto con respaldo: micrófono externo calibrado (error a ±1 dB(A)), calibrar la app contra una referencia, y desactivar o evitar el procesado automático (AGC, supresión de ruido), aunque en Android esto último varía por fabricante.

### Cited Findings
- Micrófono externo calibrado mejora exactitud y precisión (±1 dB(A)) — [Sonic Field library](https://sonicfield.org/library/evaluation-of-smartphone-sound-measurement-applications-using-external-microphon)
- Calibrar contra una referencia: en NoiseCapture se usa ganancia de calibración o un teléfono ya calibrado; la calibración ciega estadística reduce el sesgo pero deja errores de varios dB — [PMC5648040](https://pmc.ncbi.nlm.nih.gov/articles/PMC5648040); [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)
- Android: la fuente `UNPROCESSED` solo se aplica "si está disponible" y si no se comporta como DEFAULT; la plataforma puede insertar AGC por defecto según la fuente de audio, por lo que conviene comprobar `AutomaticGainControl.getEnable()`; un foro de 2014 (anecdótico) describe limitadores cerca de 80 dB — [Android MediaRecorder.AudioSource](https://Developer.android.com/reference/kotlin/android/media/MediaRecorder.AudioSource); [Android AutomaticGainControl](https://developer.android.google.cn/reference/android/media/audiofx/AutomaticGainControl?authuser=4)
- Antigüedad y modelo del teléfono influyen en la exactitud (Applied Acoustics 2016) — [Univ. of Galway](https://research.universityofgalway.ie/en/publications/testing-the-accuracy-of-smartphones-and-sound-level-meter-applica-5/)
- Contexto de uso: la lectura varía con la orientación del teléfono y el contexto del usuario (bolsillo, mano) — [Ear-Phone, arXiv](https://arxiv.org/pdf/1310.4270)
- Mapa participativo con datos de calidad variable: los datos "no Party" presentan mayor varianza que las sesiones controladas — [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)

### Inferences
- Recomendación práctica coherente con las fuentes: sostener el teléfono a la distancia de brazo, micrófono apuntando a la fuente o hacia arriba según el protocolo de la app, lejos del cuerpo; evitar bolsillo o bolso; verificar con un calibrador acústico (94 dB / 1 kHz) o con una referencia; usar medidas de al menos decenas de segundos (Huyan usó 30 s). Estas son prácticas habituales, no todas con cita directa aquí.
- Para protector antiviento, orientación del micrófono y distancia al cuerpo no hallé estudios citables en esta pasada.

### Gaps
- No se encontró fuente específica sobre pantallas antiviento, orientación óptima del micrófono (incidencia aleatoria vs frontal) ni sobre tiempos mínimos de medición para smartphones.
- No se verificó el efecto de desactivar la supresión de ruido en iOS (el sistema no ofrece control directo; no verificado).
- Recomendación sobre calibrador acústico barato compatible con smartphone: no verificada.
