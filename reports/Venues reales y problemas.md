# Venues reales y problemas de Quiet Compass

Consulta: 24 de octubre de 2026, America/Los_Angeles. Alcance: los cinco venues del mapa, fuentes públicas y revisión estática del código. Las mediciones propias con celular quedan para una fase posterior.

Hay información real suficiente para crear fichas de lugares y zonas. En esta búsqueda no se encontró una medición acústica actual y verificable para cada uno de los cinco venues. Su nivel actual debe permanecer desconocido.

## Datos verificados para las fichas

| Venue actual | Información que podemos utilizar | Lo que todavía falta |
| --- | --- | --- |
| Moscone Center | Planos oficiales separados para North/South y West, por planta. El lobby North/South tiene descargas PDF y CAD y salas identificadas: por ejemplo, South 101 mide 43 × 37 pies. [Planos](https://www.moscone.com/guidelines/floor-plans), [lobby](https://www.moscone.com/floorplans/moscone-north-south-lobby-level-floor-plan). | Edificio, planta, configuración del evento, salas habilitadas y permiso de acceso de la persona. El plano no demuestra circulación disponible ni ruido. |
| Fort Mason Center | Dirección del campus: 2 Marina Boulevard. Los horarios de organizaciones y actividades varían; 9–17 de lunes a viernes corresponde a la oficina. [Visita](https://fortmason.org/visit/). Gallery 308 publica plano, recorrido 3D y dimensiones de 78 × 47 pies. [Gallery 308](https://fortmason.org/our-venues/gallery-308/). | Elegir un edificio concreto; no aplicar el horario administrativo ni la acústica de una sala al campus entero. |
| Ferry Building | One Ferry Building; edificio abierto diariamente 6–22, con excepciones festivas y horarios propios por comercio. Hay bancos en el paseo, asientos exteriores, baños accesibles y WiFi público. [Visita](https://www.ferrybuildingmarketplace.com/visit/). Mercado: martes y jueves 10–14; sábados 8–14. [Farmers Market](https://www.ferrybuildingmarketplace.com/farmers-market/). | Distinguir interior, explanada y comercios. El mercado aporta contexto temporal, pero no permite calcular decibelios ni asegurar ocupación. |
| Yerba Buena Gardens | 750 Howard Street; acceso gratuito al jardín, todos los días 6–22; baños 9–17; mapa de accesibilidad publicado. [Información](https://yerbabuenagardens.org/visit/general-information/), [mapa ADA de octubre de 2025](https://yerbabuenagardens.org/wp-content/uploads/2025/10/ADA-Map-Oct-2025.pdf). El sitio enlaza la programación de conciertos. [Sitio oficial](https://yerbabuenagardens.org/). | Separar jardín y zonas de eventos. El ID actual `ybca` conviene revisarlo: Yerba Buena Center for the Arts es una entidad distinta, enlazada por el propio sitio. |
| Chase Center | Hay documentación histórica de espacios sensoriales: el informe 2022–23 de Warriors describe una sala en la sexta planta, disponible durante partidos, conciertos y eventos. [Informe del operador](https://cdn.warriors.com/impact-report/CR%20Impact%20Report%2022-23.pdf). | Verificar acceso, ubicación y disponibilidad vigentes. La [página actual de accesibilidad](https://www.chasecenter.com/plan-your-visit/accessible-services/) no devolvió contenido legible con la herramienta de consulta. No cargar posiciones de salas como confirmadas para 2026. |

Los enlaces a planos son referencias verificadas en las páginas del operador; no se extrajo geometría ni se validó ningún recorrido físicamente. Las coordenadas del catálogo existente tampoco fueron reverificadas como entradas peatonales.

## Mediciones publicadas de otros establecimientos

SoundPrint publica promedios de mediciones aportadas por usuarios. Tres ejemplos visibles al consultar su [listado de San Francisco](https://www.soundprint.co/locations/us/ca/san-francisco/all):

| Lugar | Valor publicado |
| --- | --- |
| The Garden Court | 68 dBA |
| Umi | 72 dBA |
| Greens Restaurant | 76 dBA |

El listado explica que son promedios aproximados de los SoundChecks del lugar. No se verificaron aquí fecha de cada muestra, cantidad de contribuciones ni estado comercial actual. Son referencias de investigación, no lecturas actuales ni mediciones de Quiet Compass. No se verificó API o autorización de reutilización masiva; no se importó su base de datos.

Un promedio de un restaurante no debe asignarse a todo el edificio o campus que lo contiene.

## Problemas encontrados en el proyecto

Estos hallazgos provienen de lectura del código; no se ejecutó una prueba de interfaz ni una visita física.

| Prioridad | Hallazgo y evidencia | Consecuencia | Cambio propuesto |
| --- | --- | --- | --- |
| Alta | Un único plano ficticio define Courtyard, Room B, Main stage, Hallway, Entrance y Food area para todos los venues. `apps/quiet-compass/app/venue/page.tsx:9`, `:89`, `:111`. | La vista lleva el nombre de un lugar real, pero su distribución no corresponde a él. | Identificar visiblemente el plano de demostración. Crear zonas reales solo cuando haya una fuente espacial. |
| Alta | Todos los venues tienen `score` y `bias` obligatorios; no tienen fecha, fuente o estado desconocido. `apps/quiet-compass/lib/venues.ts:2`. Los colores del mapa usan ese score: `apps/quiet-compass/app/page.tsx:81`. | No hay forma de representar en ese catálogo un venue real todavía sin medir. | Permitir ausencia de medición y mostrarla como desconocida. Conservar simulación identificada para la demo. |
| Alta | La ficha del venue solo contiene identidad, coordenadas y valores simulados. No incluye horarios, entradas, acceso, planta o evento. `apps/quiet-compass/lib/venues.ts:2`. | No permite comprobar si la persona puede llegar y entrar a una zona en el momento necesario. | Añadir datos de acceso con fuente, alcance y fecha de comprobación; permitir “por confirmar”. |
| Media | `venueById` devuelve Moscone cuando el ID es inválido. `apps/quiet-compass/lib/venues.ts:10`. | Un enlace incorrecto muestra otro venue sin avisar. | Devolver estado de lugar no encontrado para IDs desconocidos. |
| Media | El mismo lugar puede tener scores simulados diferentes en dos catálogos: Ferry Building 0,79 en `app/page.tsx:19` y 0,64 en `lib/venues.ts:7`; Yerba Buena Gardens 0,60 frente a 0,52. | Una misma ubicación transmite dos niveles distintos sin observación que explique el cambio. | Unificar identidad y procedencia; separar expresamente los escenarios de simulación. |

También hay problemas en las fuentes: la página de [alquileres de Fort Mason](https://fortmason.org/venues/) dice 11 opciones de venue en la introducción y 12 en sus preguntas frecuentes. Conviene identificar las salas por sus fichas individuales en vez de guardar ese total como un hecho consistente.

## Problemas de las personas que conviene validar

Son hipótesis derivadas de lo anterior, no resultados de entrevistas:

1. **“Sé el nombre del venue, pero no dónde puedo hacer una pausa.”** Probar si una sala o zona precisa, con instrucciones de acceso, resuelve mejor la necesidad que un score del edificio.
2. **“Encuentro un lugar, pero no sé si puedo entrar o volver a mi evento a tiempo.”** Validar restricciones, horarios, trayecto y tiempo disponible antes de recomendarlo.
3. **“Dice tranquilo, pero al llegar cambió.”** Mostrar fecha y alcance de la evidencia, y comprobar las condiciones al llegar cuando exista captura desde el teléfono.

## Campos para preparar ahora y mediciones después

**Ficha del lugar:** ID estable, nombre oficial, edificio/planta/zona, dirección, entrada verificada, horario y zona horaria, restricciones, servicios, enlace al plano, fuente y fecha de comprobación. Cada campo desconocido queda vacío o explícitamente pendiente.

**Observación posterior del teléfono:** referencia a la zona, momento, duración, perfil de captura, unidad, valor y controles de calidad. El contrato existente ya contempla `area_id`, `time_bucket`, `duration_seconds`, `measurement` y `quality.capture_profile`; aprovecharlo antes de inventar otro formato. Véase `contracts/quiet-compass.schema.json:304` y `server/quiet_compass/shared_contracts.py`.

Los niveles del teléfono se definen actualmente como dBFS relativos sin calibrar. Mantenerlos separados de dBA externos y comparar solo perfiles compatibles. La ausencia de observaciones nunca se representa con cero.

Para una primera ficha pública, Ferry Building ofrece datos claros de horarios y servicios. Para reemplazar el plano interior ficticio, un edificio y planta concretos de Moscone o Gallery 308 tienen mejores referencias espaciales. Esta es una elección de implementación basada en la documentación encontrada, no una recomendación de tranquilidad.


## Implementación realizada — 24 de octubre de 2026

- Las cinco fichas incorporan dirección, horario, acceso, servicios, fuentes, fecha de revisión y zona horaria. Los datos que no pudieron verificarse quedan explícitamente pendientes.
- Se muestran tres planos originales de los operadores: lobby North/South de Moscone, Gallery 308 en Fort Mason y mapa de accesibilidad de Yerba Buena Gardens. Cada uno conserva su alcance y enlace al PDF; no implica navegación interior ni observaciones acústicas.
- Los cinco venues siguen sin medición vinculada. Los datos de visita y planos no generan un score de ruido. El mapa utiliza el mismo catálogo y la misma identidad que las fichas.
- Los IDs inexistentes muestran un estado de lugar no encontrado. El antiguo enlace `ybca` sigue resolviendo a Yerba Buena Gardens mediante un alias; no se confunde con Yerba Buena Center for the Arts.
- Comprobaciones completadas: 13 pruebas de venues/datos reales, tipos y compilación; revisión en escritorio y móvil, selector, botón Atrás, ID inválido y enlace antiguo. Se corrigió la etiqueta accesible del selector en móvil.
- Las mediciones con celular, la verificación de entradas sobre el terreno y la validación física de rutas quedan pendientes.

### Estado de publicación

Cambios terminados en el espacio de trabajo. La copia aislada del sitio privado también compiló correctamente; su commit local es `f0ce9ea`. La publicación no se completó: primero falló la resolución de red y luego la revisión automática rechazó el envío con credenciales por falta de autorización explícita del usuario para publicar. No se reintentó por otra vía.


### Sincronización con main

A pedido del usuario, se incorporaron los 6 commits de `origin/main` hasta `6bda8e0` a la rama actual, conservando los cambios locales. Se resolvieron los cruces del mapa y de iOS; la nueva capa de obras conserva el aviso cuando falla una fuente. Comprobación posterior: tipos y 27 pruebas web correctas. Se conserva una copia de seguridad y el stash `0ed30938b33fe87d693852347b60b391d5c19186`. No se continuó la publicación del sitio.


### Revisión de compatibilidad con main actualizado

Se incorporaron los dos commits nuevos de `origin/main` hasta `a5c9a87`. La comparación detectó que nuestra copia antigua del mapa reemplazaba mejoras ya integradas por el equipo. La combinación final toma el mapa de main como base y añade únicamente el catálogo de visitas en sus dos representaciones de puntos.

| Elemento | Resultado combinado |
| --- | --- |
| Estilo y controles del mapa | Se conserva main, incluidos campos violetas de densidad de reportes, puntos oscuros de mediciones fechadas y lugares grises sin medición. |
| Panel MCP | Se conservan las pestañas, instrucciones y control de disponibilidad de main. |
| Capas de datos | Se conservan main, la nueva fuente de obras y el reporte de fallos parciales. |
| Fichas de venues | Se añaden las cinco fichas con fuentes, tres planos oficiales y estado sin medición. |
| Identidad y navegación | Catálogo compartido, alias del enlace antiguo de Yerba Buena y estado para ID inválido. |

La revisión en navegador confirmó el acceso desde el mapa a las fichas y que el panel MCP mantiene sus pestañas. El servidor MCP sigue apareciendo no disponible en la vista local; no se considera verificada una conexión externa. Pasaron las 28 pruebas web y la comprobación de tipos. Los cambios locales de iOS se mantienen separados del envío de venues; se quitó un método de feedback duplicado por la combinación anterior.

La compilación de producción con la configuración de Vercel (`VERCEL=1 next build`) también pasó, incluida la generación de todas las rutas.

El cambio de venues quedó guardado en un commit local sobre `a5c9a87`. La revisión automática bloqueó el push directo a main y solicitó confirmación explícita para ese envío concreto. No se intentó otra vía.
