# NoiseCapture: cobertura real en San Francisco (verificado 2026-10-24)

Comprobado desde la sandbox; todo lo de abajo se ejecutó, nada es supuesto.

## Acceso

- `https://data.noise-planet.org/dump/` (https) devuelve el índice de archivos (227 zips). La misma ruta por `http://` devuelve una página de Metabase, no el índice: usar https.
- El archivo es `United States.zip`: 1,02 GB (`Content-Length: 1098078043`), `Last-Modified: 14-Jul-2025`, con `Accept-Ranges: bytes`. Es decir, el volcado de EE. UU. tiene más de un año de antigüedad a esta fecha, aunque la web diga que se actualiza cada noche.
- Dentro hay un trío de GeoJSON por condado (7452 entradas). San Francisco: `United States_California_San Francisco.{points,tracks,areas}.geojson` (puntos 142 MB descomprimidos, 7,5 MB en el zip). Con peticiones HTTP Range solo se descargan esos miembros (unos 7,8 s), sin bajar el zip entero. Lo hace `server/quiet_compass/noisecapture.py`.
- Licencia: ODbL (según la página de datos de Noise-Planet); hay que atribuir.

## Cobertura en la caja de SF (lat 37,70-37,83; lon -122,52 a -122,35)

- 408 382 puntos de 1 s en el archivo de SF; 408 322 dentro de la caja; 560 trazas.
- Por año: 2017: 3 836; 2018: 48 520; 2019: 32 593; 2020: 30 990; 2021: 258 953; 2022: 16 837; 2023: 1 221; 2024: 7 740; 2025: 7 632. Más de la mitad de los puntos son de 2021.
- Precisión GPS <= 15 m: 322 068 de 408 322 puntos. Nivel 0,0 dB aparece como valor centinela. `gain_calibration` por traza (está en `tracks`, no en `points`): 474 de 560 son 0 (sin calibrar), el resto tiene valores de 0,1 a 100 dB, varios implausibles.

## Qué queda tras los filtros

Filtros: precisión <= 15 m, 30-120 dB, traza con `gain_calibration` entre -15 y +15 dB (la ganancia no se aplica: el volcado no dice si `noise_level` ya la incluye), ventanas de 5 min por traza y celda de ~100 m con al menos 5 s (un segundo no es una muestra independiente), celdas con al menos 3 trazas y 5 ventanas.

- 279 913 puntos conservados (86 254 descartados por precisión, 39 555 por nivel, 2 600 por traza, 60 fuera de la caja).
- 1 487 ventanas de 5 min; 237 celdas candidatas, solo 20 publicables. La cobertura es escasa y desigual: concentrada en Mission/SoMa/Tenderloin y poco más. No es un mapa de la ciudad.
- Las celdas con energía media alta y mediana baja (por ejemplo 83,7 dB frente a 45,0 dB) muestran que la media energética es sensible a valores atípicos; por eso se publican ambas y la mediana de ventanas es la cifra principal.

Resultado: `server/quiet_compass/data/noisecapture_sf_cells.json` (copia web en `apps/quiet-compass/public/data/noisecapture-sf.json`), etiquetado `measured_crowdsourced` / `measured_crowdsourced_uncalibrated`, con atribución ODbL. Para regenerar: `python -m quiet_compass.noisecapture --out <archivo>` desde `server/`.

## Límites

- Teléfonos sin calibrar: errores de varios dB (ver notas de "Mejores formas de medir ruido"). No comparable con los dBFS relativos de la app ni con los CNEL de SFO.
- Sesgo de dónde y cuándo caminó la gente; sin audio, solo LAeq por segundo.
- Los datos llegan hasta 2025 como máximo; mostrar siempre `last_date`.
