# Captura, aprendizaje personal y alojamiento

Decisión de implementación: 24 de octubre de 2026. Este documento diferencia el
código recibido de `main` de lo que todavía debemos conectar y validar.

## Dónde corre cada parte

| Parte | Ubicación elegida | Estado |
| --- | --- | --- |
| Micrófono, características acústicas y clasificación | iPhone, procesamiento local | Código de captura y DSP presente; validar en dispositivo |
| Recorrido y guía | iPhone, ARKit y memoria local | Integración nativa compilada; validación en dispositivo pendiente |
| Mapa web e integración Oura existente | Sitio actual en Sites | Mantener su alojamiento; este cambio no publica el sitio |
| API de ingestión y servidor MCP | Un servicio Python en Render | Código presente; Blueprint preparado, despliegue pendiente |
| Observaciones, feedback y destino de guía | SQLite en disco persistente del servicio | Implementado para una instancia de demo |
| Conversación y elección de herramientas | Agente personal conectado, inicialmente Claude | Requiere configurar el conector y probar el flujo |
| Acciones proactivas | Futuro proceso de eventos y ejecución del agente | Pendiente; conectar MCP no activa vigilancia |

Se mantiene Python y SQLite porque ya existen en el servidor. El archivo
[`render.yaml`](../render.yaml) configura una instancia y un disco de 1 GB. Render
requiere un servicio de pago para ese disco. Crear la infraestructura es un paso
separado; no se ha contratado ni desplegado desde este cambio.

## Cómo extraemos información del ambiente

Durante una sesión visible y autorizada:

1. La app recibe bloques de audio del micrófono.
2. El procesamiento local calcula nivel relativo, variabilidad, picos y bandas
   de frecuencia. Un clasificador puede aportar etiquetas de sonido.
3. La app vincula los resultados con hora, lugar o zona y calidad de seguimiento.
4. Agrega características en observaciones y envía los campos del contrato a
   `/v1/observations`. Conserva los reintentos pendientes localmente.
5. El agente obtiene esos resúmenes mediante `quiet_get_context`.

No se necesita enviar conversaciones ni audio crudo al agente. Un clasificador
puede reconocer posibles voces sin transcribirlas. Su puntuación no mide por sí
sola cuánto tiempo habló alguien. Los niveles dBFS son relativos a la captura;
una comparación entre equipos requiere validación adicional. La dirección de
llegada del sonido sigue siendo experimental.

El código de DSP está en `ios/Packages/QuietCore/Sources/QuietCore/Audio`; la captura
nativa está en `ios/QuietCompass/Audio`. Su presencia no prueba funcionamiento
físico ni una integración completa de permisos, sincronización y seguimiento.

## Qué aprende hoy y qué falta

El servidor ya guarda `Feedback` por sesión, lugar y objetivo (`talk`, `rest`,
`work`). `personal_band` en `server/quiet_compass/scoring.py` usa valoraciones para
ajustar una banda de niveles preferidos y volver a ordenar los lugares. Es una
heurística provisional, limitada a la sesión activa y su perfil de captura.

Límites actuales:

- Las valoraciones se relacionan con la lectura más reciente del lugar, no con
  una instantánea inmutable de las condiciones cuando se dio el feedback.
- No existe un perfil de preferencias asociado a una persona entre sesiones.
- Cada invocación de feedback crea un registro; hay que evitar duplicar una
  respuesta al reintentar una llamada cuya confirmación se perdió.
- No se aprende automáticamente que irse de un lugar significa incomodidad.

La siguiente ampliación debe guardar una experiencia con identidad privada,
objetivo, observaciones concretas y fecha, respuesta explícita y procedencia.
Actualizará un perfil editable por actividad, con evidencia y número de ejemplos.
Una preferencia declarada tendrá prioridad sobre una inferencia. Las preferencias
semánticas pueden persistir entre sesiones; los umbrales acústicos seguirán
separados por condiciones de captura compatibles.

Prueba de aceptación de esa ampliación: registrar una experiencia, reiniciar el
servicio, iniciar otra sesión de la misma persona y demostrar que la preferencia
cambia una recomendación manteniendo las demás condiciones comparables. Probar
también que otra persona no puede leer esa experiencia. Esta prueba todavía no
demuestra una capacidad implementada hoy.

## Cómo el agente usa lo aprendido

Las [instrucciones del agente](../server/agent_instructions.md) definen el ciclo:
consultar contexto → buscar candidatos → explicar evidencia → iniciar guía cuando
la persona decida ir → verificar una medición nueva → guardar feedback explícito.

La memoria reside en la base de datos, no solo en el historial del chat. El MCP
expone operaciones para consultarla y actualizarla. Una llamada de consulta no
activa el micrófono ni produce una nueva observación.

## Integración de wearables

El servidor tiene un flujo propio de Oura: autorización ligada al navegador,
credenciales cifradas, renovación, sincronización cada 15 minutos y desconexión.
La app de iPhone lee resúmenes de Apple Health con permiso por tipo de dato y
muestra una vista previa antes de compartirlos. `quiet_get_personal_context`
devuelve estos resúmenes al agente con fuente y fechas. No importa cookies de Sites.

Son opcionales y privados para la única persona de esta instalación. No entran en
capas públicas. Una puntuación de recuperación no mide el ambiente ni diagnostica
estrés. Falta verificar cuentas y hardware reales; ver
[configuración y pruebas](WEARABLES_AND_PHONE.md).

## Cómo activaremos ayuda proactiva

Un modo explícito de acompañamiento delimitará duración, sensores y tipos de
sugerencia. La app detectará cambios sostenidos; un proceso de eventos podrá
invocar al agente cuando haya información nueva que cambie una decisión.

El ejecutor necesita estado persistente de la sesión, deduplicación de eventos,
límites de frecuencia, entrega de notificaciones y un control de pausa. Un evento
no autoriza sensores nuevos ni acciones fuera del alcance elegido. El cálculo de
características corre localmente; las invocaciones al modelo se reservan para
peticiones o cambios relevantes. Este ejecutor no está implementado.

## Límite de la primera instalación

El backend actual usa un token compartido y selecciona una sesión activa. Es una
instalación para una persona de demo; no hay aislamiento entre cuentas. Para
varias personas hacen falta propiedad y permisos en cada consulta, además del
perfil persistente. El mapa web tampoco debe publicar las filas privadas de este
servicio como si fueran agregados anónimos.

La guía práctica, variables y comprobaciones de alojamiento están en
[`server/README.md`](../server/README.md).
