# Panel MCP — verificación del 24 de octubre de 2026

Integrado `origin/main` en `codex/mcp-panel-polish` hasta `ceda23f` (merge `50cf19f`). Los conflictos se resolvieron conservando el nuevo mapa de main y los datos de lugares de la rama local. Los cambios locales de iOS y archivos ajenos al panel se conservaron.

## Cambios

- Panel centrado de 680 px en escritorio; en móvil, ancho adaptable y cabecera siempre visible.
- Introducción separada de la configuración, botón para medir con el teléfono y aviso de conexión con reintento.
- Pestañas con navegación por flechas/Home/End y un bloque de configuración con copia integrada.
- Prompt con texto legible y saltos de línea naturales; lista de siete herramientas desplegable.
- Confirmación de copia, error si falla el portapapeles, retorno del foco al cerrar y conservación del foco al reintentar.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run build` | PASS. Avisos existentes de tamaño de bundles y clasificación de rutas de vinext. |
| `node --test tests/*.test.mjs` | PASS: 46 pruebas. |
| Tipos de fuentes TypeScript | PASS, con una configuración temporal que excluye únicamente `.next/types/validator.ts`. El chequeo normal encuentra cuatro errores en ese archivo generado de Next, incompatible con los tipos generados por vinext. No se cambió la configuración del proyecto. |
| ESLint de `app/page.tsx` | Un error previo persiste: `react-hooks/set-state-in-effect` en la carga inicial del mapa (`refresh`). El panel ya no introduce el segundo error que existía en la comprobación MCP. |
| Playwright, 320/390/768/1440 px | PASS: cuatro pestañas sin desbordamiento horizontal. Capturas inspeccionadas en escritorio y móvil. |
| Portapapeles | PASS: URL y las cuatro configuraciones coinciden exactamente con el texto mostrado. Fallo de copia muestra recuperación. |
| Teclado | PASS: flechas, Home/End, Tab/Shift+Tab dentro del diálogo, Escape y retorno al botón MCP. Reintento conserva el foco en el campo URL. |
| Estados de conexión | PASS con respuestas simuladas: disponible, incompatible, deshabilitado, sin configurar y reintento a disponible. |
| `git diff --check` | PASS. |

La conexión real de la vista local devolvió «Server unavailable». Las pruebas de interfaz con respuestas simuladas no prueban la disponibilidad del servidor ni una medición física. No se alteraron contratos, credenciales ni protocolos MCP.

## Integración en main

Por indicación del usuario, el trabajo se dejó en `main` y se combinó con `origin/main` hasta `3104755`, manteniendo el nuevo panel, la carga progresiva del mapa y los datos de lugares. Después de resolver los conflictos: compilación PASS, 47 pruebas PASS, ESLint de `app/page.tsx` PASS y `git diff --check` PASS. La actualización de main también resuelve el error de lint previo descrito arriba. Los cambios locales pendientes de iOS y archivos ajenos se conservaron sin agregarlos al commit.
