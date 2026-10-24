# Quiet Compass — Memoria acústica para agentes personales

Fecha: 24 de octubre de 2026. Nombre provisional.

Estado: propuesta de producto e investigación técnica. No hay una implementación ni pruebas de campo acreditadas en este documento. Las APIs documentadas no demuestran que el sistema completo funcione. Los ejemplos de interacción son propuestas, no resultados.

## 1. La idea en una frase

Un agente personal que recuerda cómo sonaban los lugares por donde pasaste, aprende cuáles te resultan cómodos y te ayuda a encontrar una alternativa cuando necesitás menos ruido, sin perder de vista lo que viniste a hacer.

El teléfono aporta percepción y memoria del entorno. El agente combina esa información con tus preferencias, objetivos y agenda. El primer contexto es un evento en San Francisco; la expansión a otros lugares de la ciudad vendría después.

## 2. Decisiones que surgieron de la conversación

- Foco en ruido y comodidad acústica.
- Micrófono como sensor principal; cámara y movimiento ayudan a ubicar mediciones.
- Un celular, sin exigir hardware externo.
- Investigar el iPhone 17 Pro y sus capacidades de audio espacial y LiDAR.
- Recordar el recorrido del usuario y lo que midió en cada punto.
- Guiar mientras la persona se mueve, comprobando si las condiciones mejoran.
- Conectarse con otros agentes personales mediante herramientas, no quedar limitado a una app aislada.
- Aprender preferencias individuales; no asignar automáticamente un perfil por diagnóstico.
- Diferenciar medición, recuerdo y predicción.
- No depender de que el organizador mapee previamente todo el evento. Un mapa previo puede ayudar a arrancar, pero no reemplaza la memoria del recorrido como función central.

## 3. Problema y usuarios

En un evento puede costar encontrar dónde conversar, concentrarse o descansar sin alejarse demasiado de las actividades. El volumen cambia con las charlas, la música, el movimiento de asistentes y las conversaciones. Una zona cómoda puede dejar de serlo.

Usuario inicial propuesto: una persona con sensibilidad al ruido que quiere seguir participando de un evento y necesita encontrar una pausa o un espacio adecuado con menos esfuerzo.

### Beneficios a validar

| Persona o necesidad | Beneficio que buscamos | Lo que no podemos prometer |
| --- | --- | --- |
| Persona autista con sensibilidad al sonido | Menos incertidumbre para encontrar un espacio cómodo y recuperar un lugar conocido | Detectar sobrecarga, prevenir crisis o servir de la misma manera a todas las personas autistas |
| Persona con TDAH | Reducir distracciones y decisiones necesarias para encontrar dónde trabajar | Tratar el TDAH o producir hiperfoco |
| Persona que necesita concentración | Encontrar un lugar compatible con una tarea y un tiempo disponible | Mejorar automáticamente el rendimiento |
| Persona que necesita conversar o descansar | Identificar alternativas según el objetivo del momento | Que el menor nivel sonoro siempre sea la mejor opción |

Las guías sobre diferencias sensoriales reconocen el valor de espacios tranquilos, pero eso no valida nuestro producto ni implica una preferencia universal [8]. Las adaptaciones para TDAH pueden incluir menos distracciones o sonidos ambientales; debemos personalizar [9].

## 4. Pitch

### Versión de 30 segundos

Llegás a un evento para conocer gente, aprender o trabajar. Encontrar un lugar donde puedas estar cómodo no debería convertirse en otra tarea. Quiet Compass usa el sonido y el recorrido de tu celular para recordar qué zonas eran más tranquilas y cuáles te sirvieron. Cuando necesitás una pausa, tu agente personal recupera esa memoria, te ayuda a volver y comprueba las condiciones al llegar. Queremos que puedas seguir participando del evento con menos esfuerzo.

### Versión técnica

Construimos una memoria acústica y espacial consultable por agentes personales. Una app nativa registra características del sonido y las vincula con posiciones y momentos del recorrido. El agente consulta esa memoria, considera preferencias y agenda, recomienda espacios conocidos y actualiza su recomendación con nuevas mediciones. La estimación direccional del ruido es una capacidad experimental que podría mejorar la exploración.

### Frases posibles

- Tu agente conoce tu agenda. Ahora también puede recordar los espacios donde estuviste cómodo.
- Un agente que recuerda dónde había menos ruido y te ayuda a volver.
- Encontrar un lugar donde estar cómodo no debería ser la razón por la que terminás yéndote.

## 5. Experiencia principal

1. El usuario activa una sesión de acompañamiento y autoriza los sensores necesarios.
2. Recorre el evento. La app registra sonido, posición relativa, orientación, hora y calidad de seguimiento.
3. Puede marcar un lugar como cómodo para descansar, conversar o trabajar.
4. Pide: «Necesito diez minutos de tranquilidad y volver antes de las demos».
5. El agente busca entre espacios conocidos y accesibles, considera la antigüedad de los datos y propone una alternativa.
6. La app muestra el recorrido registrado de vuelta, sujeto a que siga siendo transitable.
7. Al llegar vuelve a medir, informa cambios y permite confirmar si el lugar sirve.
8. Con autorización e integración de calendario, ayuda a coordinar el regreso.

Ejemplo de respuesta:

> El pasillo por el que pasaste hace cuatro minutos tenía menos ruido y menos picos. Podemos volver allí. No tengo una medición actual de ese lugar; al llegar compruebo si sigue igual.

Primera visita sin memoria: reconocer que todavía no hay suficientes puntos. Puede ofrecer registrar un recorrido voluntario o consultar espacios autorizados por el evento. No inventar una zona tranquila.

## 6. Tecnologías del celular y límites

| Tecnología | Uso propuesto | Límite importante |
| --- | --- | --- |
| Micrófonos y captura de audio | Intensidad relativa, variación y características espectrales | Ganancia, procesamiento, orientación, funda y obstrucciones afectan la señal |
| Audio espacial FOA | Investigar dirección de llegada del sonido dominante | No equivale a cuatro micrófonos físicos crudos ni garantiza localizar fuentes |
| Cámara y ARKit | Asociar mediciones al recorrido y orientación relativa | Necesita una sesión y condiciones visuales adecuadas; deriva y pérdida de seguimiento posibles |
| LiDAR | Geometría aproximada del entorno | No mide sonido, no descubre niveles detrás de paredes ni identifica por sí solo absorción acústica |
| Procesamiento local | Extraer métricas y, si se valida, clases de sonido | Clasificar voces o música no demuestra comodidad ni estado emocional |
| Ubicación exterior | Vincular observaciones con lugares de la ciudad | No sustituye posicionamiento preciso dentro de edificios |

Apple documenta captura espacial, componentes FOA y acceso a buffers en iOS 26 [1]. Las especificaciones del iPhone 17 Pro incluyen audio espacial y LiDAR [2]. ARKit permite seguimiento visual-inercial y reconstrucción geométrica [3, 4]. Debemos comprobar soporte real del modo de audio y compatibilidad de captura simultánea con ARKit en el dispositivo y versión de sistema usados.

El soporte del 17 Pro no debe extrapolarse a un iPhone 14 Pro Max u otro modelo. Si falta FOA, la memoria de mediciones puede seguir siendo útil, pero la dirección acústica requiere otra validación o debe desactivarse.

## 7. Cómo estimar de dónde viene el ruido

FOA representa el campo sonoro mediante una componente omnidireccional y tres direccionales. Una técnica de investigación es calcular un vector de pseudointensidad a partir de la relación entre componentes. Puede producir una dirección aproximada de llegada por intervalos y bandas de frecuencia [5].

Pipeline experimental:

1. Confirmar que el dispositivo entrega buffers FOA y verificar orden de canales, normalización y ejes.
2. Dividir la señal en ventanas de análisis.
3. Estimar direcciones por bandas y buscar consistencia temporal.
4. Convertir la dirección relativa al teléfono al sistema de coordenadas del mapa usando su orientación sincronizada.
5. Mostrar dirección aproximada y confianza; abstenerse si hay incoherencia.

No usar un simple promedio de direcciones como prueba de una fuente real: dos fuentes pueden producir una dirección intermedia engañosa. Ecos y ruido difuso complican el problema. Las técnicas publicadas no validan automáticamente el procesamiento de Apple para nuestra aplicación.

**Dirección de llegada del ruido no es dirección hacia el silencio.** La primera orienta una hipótesis de exploración; la segunda requiere mediciones y un destino transitable.

## 8. Cómo guía mientras caminás

El ciclo propuesto es: estimar → observar movimiento → medir otra vez → actualizar la memoria → revisar la recomendación.

- Si el ruido disminuye de manera sostenida en un tramo, guardar evidencia de mejora.
- Si aparecen nuevos picos, actualizar el perfil del lugar.
- Si existe un punto conocido más adecuado, priorizarlo frente a una predicción sin verificar.
- Si el seguimiento se pierde o la dirección es incierta, dejar de mostrar una guía precisa.
- Si el teléfono queda en el bolsillo, no prometer la misma precisión espacial que con cámara activa.

Cambios de orientación, ganancia y actividad de la fuente pueden parecer mejoras por desplazamiento. Las pruebas deben separar esas causas. El mapa no debe inducir a atravesar obstáculos ni tratar la malla LiDAR como certificación de accesibilidad o permiso de paso.

## 9. Memoria acústica

Cada observación guardaría, como propuesta:

```json
{
  "session_id": "event-session",
  "place_id": "corridor-b",
  "position_local_m": [2.1, 0.0, 4.5],
  "measured_at": "ISO-8601 timestamp",
  "level_metric": "relative_uncalibrated",
  "level_value": null,
  "variability": null,
  "spectral_features": {},
  "direction_estimate": null,
  "direction_confidence": null,
  "tracking_quality": "unknown",
  "device_profile": "capture configuration",
  "user_feedback": null
}
```

Los valores nulos son campos pendientes, no resultados. Registrar configuración de captura para no mezclar métricas incompatibles.

No etiquetar dBFS como dBA o nivel de presión sonora. Para afirmar valores absolutos se necesita un método calibrado y validación. En el MVP, priorizar comparaciones relativas consistentes con el mismo equipo.

La interfaz debe distinguir:

- Medido recientemente.
- Medido anteriormente, con hora visible.
- Estimado, con incertidumbre.
- Desconocido.

Un mapa continuo de colores puede sugerir más conocimiento del que existe. Empezar con puntos y tramos observados; no colorear zonas inaccesibles como si estuvieran medidas.

## 10. Aprendizaje y predicción

### Nivel 1: memoria

Recuperar lugares medidos y feedback explícito. Es la función principal del MVP y no requiere entrenar una red neuronal.

### Nivel 2: personalización

Aprender preferencias por objetivo: conversar, descansar o trabajar. Usar feedback breve y opcional. Permanecer en un lugar o abandonarlo no demuestra por sí solo comodidad o incomodidad.

### Nivel 3: patrones temporales

Con observaciones repetidas, estimar cómo cambia un lugar según la hora o fase del evento. El programa puede aportar contexto; no sustituye mediciones actuales.

### Nivel 4: espacios no recorridos

Explorar predicciones usando geometría y fuentes estimadas. ANAVI estudia predicción acústica a partir de información visual para navegación robótica [6]. Es una referencia de investigación: no demuestra que una foto de un evento permita saber dónde habrá silencio ni ofrece una solución lista para el celular.

## 11. Arquitectura y conexión con agentes

### App nativa iOS

Captura autorizada, extracción local de características, seguimiento espacial, mapa de sesión, feedback y guía. Swift, AVFoundation/AVFAudio y ARKit son candidatos; la selección final depende de las pruebas de compatibilidad.

### Servicio de memoria

Guarda observaciones y preferencias permitidas. Para una demo puede empezar local; un servicio remoto permite compartir información seleccionada con agentes externos.

### API y servidor MCP propuestos

| Herramienta | Función |
| --- | --- |
| get_current_sound_context | Devolver métricas recientes, calidad y estado de la sesión |
| find_suitable_space | Buscar espacios conocidos según objetivo y restricciones |
| get_space_observations | Devolver mediciones, fechas y confianza |
| get_recorded_route | Recuperar un recorrido conocido, sin garantizar transitabilidad actual |
| record_comfort_feedback | Guardar una preferencia explícita |
| watch_space | Informar cambios únicamente cuando existan mediciones activas |

MCP conecta al agente con el servicio; no concede acceso directo a sensores del teléfono. Las herramientas, autenticación y permisos están por implementar. Una integración web que solo entregue volumen, grabaciones o fotos no equivale a capturar FOA y seguimiento espacial nativo.

El agente externo interpreta objetivos y restricciones y explica decisiones. No debe inventar niveles acústicos, disponibilidad de salas ni rutas. Reservar una sala requiere una integración real y autorización; no es una capacidad inherente al mapa.

### Selección de candidatos

Combinar compatibilidad acústica personal, antigüedad de datos, confianza, distancia, accesibilidad conocida y tiempo disponible. Primero excluir espacios no autorizados o que incumplan restricciones; después ordenar. Si ningún candidato sirve, decirlo.

## 12. Privacidad y experiencia

- Sesión explícita, indicador de micrófono y control de pausa.
- Procesar características localmente cuando sea viable.
- No conservar audio crudo por defecto ni transcribir conversaciones para esta función.
- Compartir con agentes solo información autorizada y necesaria.
- Permitir borrar recorrido y feedback.
- Contribución al mapa colectivo separada y opcional.
- Explicar que mapa, horarios y preferencias también pueden revelar información personal.
- Evitar alertas constantes; elegir intervenciones breves y configurables.

## 13. MVP para Puentes

Contexto tomado de la descripción del evento aportada por el usuario: personal agents para mejorar la vida en San Francisco, sprint de un día y demos presenciales. No se identificaron tracks de sponsors confirmados en ese texto; no prometer premios específicos.

### Alcance esencial

Un teléfono, un evento, una sesión y unos pocos espacios. Registrar ruido relativo y recorrido, recuperar un punto conocido, integrar una consulta del agente y verificar al llegar.

### Capacidad experimental

Dirección de llegada con FOA. Solo entra en la demo como función operativa si las pruebas la sostienen; de lo contrario se muestra claramente como investigación pendiente.

### Fuera de alcance inicial

- Mapa completo y actualizado de SF.
- Monitorear zonas remotas con un único teléfono.
- Diagnóstico o detección automática de sobrecarga.
- Guiado preciso permanente desde el bolsillo.
- Localizar todas las fuentes simultáneamente.
- Garantizar que siempre existe un espacio cómodo.
- Reservar espacios sin un sistema real conectado.

### Plan propuesto para un sprint de 10 horas

| Bloque | Entregable |
| --- | --- |
| Hora 0–1 | Verificar hardware, permisos, captura y métricas; decidir si FOA es viable |
| Horas 1–3 | Registrar observaciones y recorrido; si falla seguimiento, usar zonas identificadas manualmente y declarar la limitación |
| Horas 3–5 | Memoria, preferencias y recomendación de puntos conocidos |
| Horas 5–6 | Herramienta API/MCP y consulta de un agente |
| Horas 6–8 | Pruebas acústicas y recorridos; eliminar funciones poco fiables |
| Horas 8–10 | Demo reproducible, documentación de límites y presentación |

La planificación es estimativa; no garantiza implementar audio espacial y ARKit simultáneos en ese plazo.

## 14. Demo propuesta de tres minutos

1. Mostrar una sesión vacía y explicar qué se está midiendo.
2. Recorrer tres puntos con condiciones acústicas diferentes y guardar la memoria real.
3. Marcar uno como cómodo.
4. Pedir al agente una pausa antes de una actividad del calendario de demo.
5. Mostrar por qué eligió un punto: medición, hora, feedback y recorrido.
6. Volver y comprobar condiciones.
7. Cambiar el ruido de ese punto y mostrar que la nueva medición actualiza la recomendación.

No simular mediciones como si fueran reales. Si el calendario, la disponibilidad o una fuente de ruido son preparados para la demo, decirlo. El cambio de una zona solo se conoce cuando se vuelve a medir o alguien autorizado aporta una medición.

## 15. Pruebas y criterios de decisión

### Validación técnica

- Girar el teléfono frente a un parlante fijo: comprobar estabilidad de la dirección en coordenadas del salón.
- Repetir con dos fuentes y reverberación: comprobar que la confianza baja cuando corresponde.
- Comparar tramos con orientación y configuración consistentes.
- Repetir posiciones para separar movimiento del teléfono y cambios temporales de la fuente.
- Medir errores de seguimiento, latencia, batería y calentamiento.
- Comprobar pérdida y recuperación del mapa.
- Validar captura simultánea y sincronización de audio y pose.

Registrar error angular contra direcciones conocidas, porcentaje de abstenciones, consistencia de comparaciones y errores de recomendación. Definir umbrales después de observar una línea base; no inventar precisión.

### Validación con usuarios

Comparar contra un plano con espacios tranquilos o consultar al organizador. Medir tiempo para encontrar un espacio adecuado, esfuerzo percibido, recomendaciones que no sirvieron y comodidad reportada. No forzar exposición a ruido molesto para probar la app.

La pregunta central es: ¿ayuda a encontrar una alternativa con menos esfuerzo y a seguir participando?

## 16. Crítica fuerte de la idea

| Objeción | Implicación | Respuesta o prueba necesaria |
| --- | --- | --- |
| La persona ya sabe que hay ruido | Una alarma sola aporta poco | Demostrar que recupera una alternativa útil |
| Dirección del ruido no es dirección del silencio | Una flecha puede inducir a error | Guiar hacia puntos medidos; validar dirección aparte |
| Hay que explorar para que aprenda | Aumenta esfuerzo en la primera visita | Medir fricción y ofrecer información inicial cuando exista |
| El mapa envejece | Un destino puede haber cambiado | Mostrar antigüedad y verificar; reconocer el costo del viaje fallido |
| Menos ruido no alcanza | Puede recomendar un sitio inutilizable | Incluir acceso, asientos, objetivo y restricciones |
| Es una app, no un agente | Débil encaje con el hackathon | Resolver pausa, elección y regreso con memoria y agenda |
| Se agrupan diagnósticos distintos | Personalización superficial | Empezar por sensibilidad al ruido y preferencias explícitas |
| Sostener el teléfono es molesto | Puede impedir uso habitual | Probar sesiones breves; no prometer precisión desde el bolsillo |
| Ya existen mapas de ruido | Diferenciación insuficiente | Probar el valor del recorrido personal y la coordinación de tareas |

SoundPrint ya permite buscar establecimientos según mediciones aportadas por usuarios; sus promedios históricos no garantizan el ambiente al llegar [7]. No asumir acceso a su base de datos o una API pública. Nuestra hipótesis diferenciadora es la memoria acústica del recorrido dentro de un evento, vinculada a preferencias y objetivos del agente; no se ha demostrado una ventaja competitiva.

## 17. Decisión recomendada

Continuar con memoria acústica personal y agentes, manteniendo la localización direccional como experimento separado. Si el registro del recorrido genera demasiado esfuerzo o la recomendación no mejora una alternativa sencilla, replantear o abandonar el producto aunque la visualización sea atractiva.

La evidencia que justificaría seguir: una persona encuentra un lugar que le sirve con menos esfuerzo y puede continuar participando. La evidencia que justificaría integrar la brújula acústica: mejora verificable de la elección de rutas o espacios, con abstención cuando no es fiable.

## 18. Expansión eventual a la ciudad

Después de validar un evento, explorar bibliotecas, coworkings, cafés y espacios de descanso. Requeriría contribuciones voluntarias, compatibilidad entre teléfonos, controles de calidad, horarios, acceso y antigüedad de datos. No basta con extender el mapa de una sesión AR a toda SF.

Visión: que agentes personales puedan consultar condiciones acústicas y alternativas utilizables en la ciudad. No afirmar que SF es una de las ciudades más silenciosas del mundo: no se estableció evidencia para esa comparación.

## 19. Fuentes y alcance de la investigación

Las fuentes sustentan capacidades concretas o antecedentes. Ninguna demuestra por sí sola que Quiet Compass funcione. Los enlaces se consultaron durante la conversación; el documento no pretende ser una revisión sistemática de toda la literatura.

1. [Apple — Enhance your app’s audio recording capabilities, WWDC25](https://developer.apple.com/videos/play/wwdc2025/251/). Captura espacial, FOA y acceso a buffers.
2. [Apple — iPhone 17 Pro, especificaciones](https://support.apple.com/en-by/125090). Capacidades del dispositivo; verificar soporte efectivo de APIs en ejecución.
3. [Apple — Understanding World Tracking](https://developer.apple.com/documentation/arkit/understanding-world-tracking). Seguimiento mediante cámara y movimiento.
4. [Apple — Visualizing and interacting with a reconstructed scene](https://developer.apple.com/documentation/arkit/visualizing-and-interacting-with-a-reconstructed-scene). Reconstrucción geométrica con LiDAR.
5. [University of Southampton — Direction of arrival estimation in the spherical harmonic domain using subspace pseudointensity vectors](https://eprints.soton.ac.uk/437939/). Referencia para estimación direccional y dificultad con fuentes múltiples/reverberación.
6. [Jain, Veerapaneni y Bisk — ANAVI, proceedings de CoRL](https://proceedings.mlr.press/v270/jain25a.html). Predicción acústica para navegación robótica; [proyecto](https://anavi-corl24.github.io/). No es un buscador de silencio en eventos para iPhone.
7. [SoundPrint — How the app works](https://www.soundprint.co/how-to-use-app) y [Quiet Lists](https://www.soundprint.co/quiet-lists). Antecedente de búsqueda por nivel de ruido y límites de promedios históricos.
8. [National Autistic Society — Accessible environments](https://www.autism.org.uk/learn/knowledge-hub/guides-and-resources/accessible-environments). Diferencias sensoriales y espacios de descanso.
9. [NHS Inform — Managing ADHD symptoms in work and education](https://www.nhsinform.scot/illnesses-and-conditions/adhd/managing-adhd-symptoms-in-work-and-education). Adaptaciones ambientales; no prueba de eficacia de nuestro producto.
10. [Apple — Capturing Spatial Audio in your iOS app](https://developer.apple.com/documentation/avfoundation/capturing-spatial-audio-in-your-ios-app). Ejemplo de implementación y requisitos.
11. [Pertilä et al. — Mobile Microphone Array Speech Detection and Localization in Diverse Everyday Environments](https://arxiv.org/abs/2106.14787). Antecedente de detección y localización de voz con formato móvil; no demuestra navegación hacia lugares tranquilos con un iPhone comercial.

## 20. Próximos pasos

1. Confirmar qué iPhone y versión de sistema están disponibles.
2. Probar captura FOA y seguimiento simultáneo antes de comprometer la demo.
3. Registrar tres puntos y recuperar una ruta de vuelta.
4. Conectar una herramienta real al agente personal.
5. Probar utilidad con participantes voluntarios y comparar con la alternativa simple.
6. Decidir con resultados si la dirección acústica suma valor o distrae del producto.

**Principio del proyecto: medir, recordar, recomendar y verificar; predecir solo cuando haya evidencia suficiente.**
