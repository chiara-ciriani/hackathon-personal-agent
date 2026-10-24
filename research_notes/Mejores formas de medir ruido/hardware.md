# Hardware dedicado para medir ruido ambiental (consumidor a profesional, 2026)

Nota: busqueda limitada (~12 llamadas). Muchos precios vienen de minoristas sin fecha; marcados [NO VERIFICADO] cuando aplica. Las notas estan en espanol; nombres de productos y citas tecnicas en original.

## 1. Microfonos externos calibrados para telefonos

### Takeaway
Un microfono USB calibrado (iMM-6C ~US$45; UMIK-2 ~US$195-250) es la mejora mas barata sobre el microfono interno del telefono; NIOSH midio ±1 dBA contra un medidor tipo 1 con microfonos externos calibrados, pero en laboratorio, con su propia app y sin pretension de cumplimiento normativo.

### Cited Findings
- UMIK-2: ~US$195 directo de miniDSP, ~US$249 Amazon; Parts Express US$229.98 (sin stock, "precio sujeto a cambio por aranceles"); Europa ~EUR 275 con IVA; promedio Equipboard US$265. Paginas sin fecha. — [Parts Express](https://www.parts-express.com/MiniDSP-UMIK-2-Omni-directional-USB-Measurement-Calibrated-Microphone-230-3420), [Equipboard](https://equipboard.com/items/minidsp-umik-2), [Masori](https://masori.de/en/products/umik-2)
- Cada UMIK-2 trae archivo de calibracion individual (para REW, Dirac Live, etc.). — [Equipboard](https://equipboard.com/items/minidsp-umik-2)
- Dayton Audio iMM-6C (USB-C, iPhone 15+/Android): ~US$45 (Parts Express US$44.98 citado por resena); Australia AU$77. Listado: calibracion individual con archivo serializado, respuesta 18-20,000 Hz ±0.5 dB (calibrado), ruido propio ~70 dB(A) "variable segun dispositivo". — [Frieve review](https://audioreview.frieve.com/products/en/dayton-audio-imm-6c/), [Decibel Hi Fi](https://decibelhifi.com.au/calibrated-microphone-usb-c)
- El ruido propio ~70 dB(A) del iMM-6C (segun listado) implica que es poco util para ambientes silenciosos (<~70 dBA); relevante para ruido urbano de calle (60-85 dBA) pero marginal para calles residenciales nocturnas. [Inferencia a partir de la cifra del listado]
- NIOSH: app NIOSH SLM con microfonos externos calibrados, promedio dentro de ±1 dBA vs. referencia tipo 1 (ruido rosa 65-95 dBA, camara reverberante); en minas (campo) tambien ±1 dBA. NIOSH advierte que no sustituye un medidor profesional ni sirve para cumplimiento. — [NIOSH blog](https://www.cdc.gov/niosh/blogs/2017/sound-app.html), [Follow-up study (sonicfield)](https://sonicfield.org/library/evaluation-of-smartphone-sound-measurement-applications-using-external-microphon), [PMC9345572](https://pmc.ncbi.nlm.nih.gov/articles/PMC9345572)
- Solo 4 de 10 apps iOS evaluadas (SoundMeter, SPLnFFT, SPL Pro, NoiSee) quedaron dentro de ±2 dB(A) del microfono de referencia. — [NIOSH follow-up (sonicfield)](https://sonicfield.org/library/evaluation-of-smartphone-sound-measurement-applications-using-external-microphon)
- NoiseCapture (Noise-Planet): el listado de F-Droid dice que la calidad depende del telefono y su calibracion, que "nunca reemplazara un sonometro profesional", y que un microfono externo calibrado es una opcion. — [F-Droid](https://f-droid.org/de/packages/org.noise_planet.noisecapture/)
- Calibracion ciega de NoiseCapture: ~24% de puntos con calibracion distinta de 0 dB; 61% de los telefonos calibrados reportaban valores >±15 dB (implausibles); metodo hibrido en Reze (331 pares): error medio -3.4 dB, IQR 6.8 dB con 100 enlaces; en Party 22: ±7.5 dB. — [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)

### Inferences
- Para un mapa ciudadano, el apoyo de calibracion (archivo + calibrador acustico de 94/114 dB, ~US$100-300 [NO VERIFICADO, no busque precio]) importa mas que la marca del microfono.
- UMIK-1 (no verificado en esta busqueda; de memoria ~US$100-135 USB-A) no se confirmo; usar UMIK-2 o iMM-6C como referencias verificadas.

### Gaps
- Precio actual 2026 del UMIK-1 y disponibilidad; compatibilidad iOS/Android de UMIK-2 con apps de medicion (no confirmada).
- Si iMM-6C/UMIK-2 cumplen clase 2 IEC 61672 como sistema: no encontre certificacion; son microfonos, no sonometros. Celestina et al. 2018 (Applied Acoustics) evaluo iPhone+microfono contra requisitos tipo 2 pero no obtuve el resultado.
- Mic Dayton iMM-6 (Lightning) probablemente descontinuado; no verificado.

## 2. Sonometros de mano (IEC 61672 clase 1 vs clase 2)

### Takeaway
Clase 1 cuesta ~US$2,500-4,000+ (Svantek SV 971A) a ~US$2,500-3,300 (NTi XL2 + opcion de aprobacion de tipo + microfono); clase 2 de consumo (Extech SL510 ~GBP154) es 10-25x mas barato. Una persona los necesita para validar/calibrar una red o cuando se requieren datos defendibles; no para participar en un mapa ciudadano.

### Cited Findings
- NTi Audio XL2 (analizador, sin microfono): US$1,846-1,920; opcion de aprobacion de tipo (Class 1) US$735 / GBP522 + IVA; XL2-TA preinstalado US$2,546; se necesita ademas microfono de medicion (precio no obtenido). — [NTi US shop](https://us.shop.nti-audio.com/products/xl2-type-approval-option), [Markertek](https://www.markertek.com/product/nti-xl2/nti-audio-xl2-audio-and-acoustic-analyzer), [NTi XL2-TA](https://us.shop.nti-audio.com/products/xl2-ta-sound-level-meter)
- Svantek SV 971A (clase 1): reseller US US$4,035 (Levitt Safety), US$3,780 agotado (Pelican); guia de Svantek EUR 2,500-5,000 segun configuracion. Sin precio de lista oficial. — [Levitt Safety](https://www.levitt-safety.com/Product/ISVSV971A), [Pelican](https://www.pelicansalessupply.com/products/sv-971a-class-1-sound-level-meter), [Svantek](https://svantek.com/academy/choosing-class-1-sound-level-meter/)
- Extech SL510: GBP154 sin IVA (RS), listado como IEC 61672-1 clase 2; SL130W cumple IEC 61672:2013 tipo 2 (series con 'A'); SL130G ANSI tipo 2; sin precio encontrado para SL130. — [RS](https://uk.rs-online.com/web/p/sound-level-meters/0100061), [DirectIndustry](https://www.directindustry.com/prod/extech/product-14309-531810.html), [ManualsLib](https://www.manualslib.com/manual/4362438/Extech-Instruments-Sl130w.html)
- Larson Davis SoundExpert LxT esta marcado como producto legado; el fabricante recomienda el 821ENV como reemplazo. Sin precios. — [Larson Davis](https://larsondavis.com/Products/sound-level-meters/soundexpert-lxt)

### Inferences
- Costo total real de un kit clase 1 portatil (con calibrador y calibracion de laboratorio anual, tipicamente varios cientos de USD) ronda US$3,000-5,000 [estimacion, no verificado].
- Alquiler o prestamo comunitario (biblioteca, universidad, tool library) es mas razonable que comprar.

### Gaps
- Precios de Bruel & Kjaer, Casella (CEL-63x/CEL-24x), Larson Davis 821ENV, y alquiler en SF: no encontrados.
- Costo anual de recalibracion trazable (NIST/ISO 17025): no obtenido.

## 3. Sensores fijos de bajo costo para redes

### Takeaway
Un nodo MEMS I2S (ICS-43434 + Teensy/ESP32/RPi) cuesta ~EUR 40-100 y puede dar errores <2 dB en tonos de 1 kHz en laboratorio, pero la clase 2 real exige calibracion de respuesta en frecuencia y proteccion contra intemperie; Smart Citizen y SONYC son los casos documentados.

### Cited Findings
- TU Delft sensor abierto de sonido urbano: ~EUR 55 por unidad (segun cantidad); desviacion <2 dB a 1 kHz contra sonometro calibrado (solo tono, no ponderacion A completa). — [TU Delft repository](https://repository.tudelft.nl/file/File_58f2b1f7-9410-4db2-b295-15ea060a98e8)
- SONYC (NYU): dispositivo estatico de bajo costo con MEMS calibrado al nivel clase/tipo 2 (Mydlarz, Salamon, Bello 2016, Applied Acoustics); detalles en arXiv. Precio por unidad no encontrado. — [SONYC blog](https://wp.nyu.edu/sonyc/?p=100), [arXiv 1605.08450](https://arxiv.org/pdf/1605.08450)
- Smart Citizen Kit 2.0: microfono I2S MEMS ICS43432; docs citan piso de ruido ~30 dBA, respuesta corregida en tiempo real y validacion de doble punto contra sonometro clase 1 (cifras de error no obtenidas). — [Smart Citizen forum](https://forum.smartcitizen.me/t/the-mems-i2s-microphone-in-smart-citizen-kit-2-0/922)
- DNMS (Sensor.community / bertrik fork): ICS-43434 por I2S, firmware Teensy 3.6/4.0, tambien HAT para Raspberry Pi; LAeq minimo ~30 dBA (T4.0) / ~32 dBA (T3.6); verificado con HFT Stuttgart en laboratorio ("buen resultado", sin informe); licencia GPL-3.0; sin afirmacion IEC 61672. — [GitHub bertrik/dnms](https://github.com/bertrik/dnms)
- LoRaSoundkit (ICS-43434 en tubo de media pulgada con resina, LoRaWAN): costo ~EUR 40. — [GitHub meekm/LoRaSoundkit](https://github.com/meekm/LoRaSoundkit)
- Prototipo suizo MEMS (<100 CHF) comparado con clase 1. — [Boulandet 2021 (HES-SO)](https://arodes.hes-so.ch/record/9652/files/Boulandet_2021_implementation_performance_assessment_MEMS-based_sound_level_meter.pdf) (no pude abrir el PDF; 403, solo snippet de busqueda)
- Revision de literatura sobre sensores de bajo costo para redes de ruido urbano. — [PMC7218845](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7218845/)

### Inferences
- Adafruit ICS-43434 (breakout ~USD 4-7 [NO VERIFICADO]) + ESP32 es la ruta de menor costo y abierta; requiere calibrar con calibrador de 94 dB y verificar respuesta en frecuencia; reportar como "indicativo", no clase 2.
- Los pisos de ruido de ~30 dBA son aceptables para trafico y eventos, no para ambientes tranquilos.

### Gaps
- Precio actual del Smart Citizen Kit 2.0 y de sensores Bosch/TDK/Sensirion de ruido: no encontrado (Sensirion no tiene sensor de ruido que yo pueda confirmar).
- Cifras de error de SCK, SONYC y SPH0645 vs. clase 1: no obtenidas.
- Estabilidad a largo plazo / deriva y robustez a intemperie/viento: no evaluada.

## 4. Mejor precision por dolar para un barrio/evento en San Francisco

### Takeaway
Segun lo encontrado: (a) microfono USB calibrado (~US$45-250) + app validada para voluntarios, (b) nodos ICS-43434 de ~EUR 40-100 para puntos fijos, calibrados contra (c) un sonometro clase 1/2 prestado o un calibrador acustico como ancla. Comprar clase 1 (>US$2,500) solo si se necesitan datos formales.

### Cited Findings
- Los datos de telefonos sin calibrar son muy ruidosos (ver NoiseCapture arriba, ±7.5 dB o peor tras calibracion ciega). — [PMC10891730](https://pmc.ncbi.nlm.nih.gov/articles/PMC10891730)
- NIOSH recomienda explicitamente no usar su app para cumplimiento. — [NIOSH](https://www.cdc.gov/niosh/blogs/2017/sound-app.html)
- Tabla de referencia (precios arriba): iMM-6C ~US$45 | UMIK-2 ~US$195-250 | Extech SL510 ~GBP154 | nodo DIY ~EUR 40-55 | NTi XL2+TA ~US$2,546+mic | SV 971A ~US$3,800-4,000.

### Inferences
- Mejor precision/costo: iMM-6C o UMIK-2 + app NIOSH SLM/SPL (Android solo si el microfono es compatible; verificar) para recorridos; nodo DIY calibrado para puntos fijos 24h. Un Extech SL510 clase 2 es un ancla barata para comparar.
- Para un evento corto, 3-5 nodos o un microfono calibrado por voluntario con protocolo comun es mas informativo que un solo clase 1.

### Gaps
- Nada especifico de San Francisco (programas municipales, ordenanza de ruido, alquiler local): mi busqueda no encontro resultados relevantes.
- Compatibilidad de NIOSH SLM app con Android: no verificada (app historicamente iOS).
