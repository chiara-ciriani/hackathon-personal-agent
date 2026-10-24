# Cómo probar un servidor MCP (3 tools: query_sound_map, find_suitable_places, submit_observation) — estado a 2026-10

Nota de contexto: la fecha de la investigación es 2026-10-24. La revisión vigente de la especificación es **2026-07-28** (la anterior es 2025-11-25). Esta revisión cambió bastante el protocolo (ver pregunta 2); muchos tutoriales antiguos (initialize + Mcp-Session-Id + GET/SSE) describen la era "legacy".

## 1. MCP Inspector oficial: qué es y cómo usarlo (UI y CLI) contra servidor local y remoto

### Takeaway
El Inspector oficial es el paquete `@modelcontextprotocol/inspector` (Node >= 22.19.0, se ejecuta con `npx`) que ofrece tres clientes en un solo binario: Web (por defecto), CLI (`--cli`) y TUI (`--tui`). Para un servidor HTTP remoto se usa `--server-url <url> --transport http`; el CLI sirve para CI con códigos de salida estables. Hay que elegir la "protocol era" (legacy/auto/modern) según lo que implemente el servidor.

### Cited Findings
- Paquete único `@modelcontextprotocol/inspector` con tres clientes: Web (`npx @modelcontextprotocol/inspector`), CLI (`--cli`) y TUI (`--tui`); requiere Node 22.19.0 o superior y no necesita instalación — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)
- La UI web imprime una URL con un token de API por lanzamiento y abre el navegador (`MCP_AUTO_OPEN_ENABLED=false` lo evita) — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)
- Servidor HTTP remoto: `npx @modelcontextprotocol/inspector --server-url https://api.example.com/mcp --transport http` — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)
- Forma CLI de listar y llamar tools: `npx @modelcontextprotocol/inspector --cli https://api.example.com/mcp --transport http --method tools/call --tool-name get_weather --tool-arg city=Boston --format json | jq .result` — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)
- Flags del CLI: `--method` (initialize, tools/list, tools/call, resources/*, prompts/*, ...), `--tool-name`, `--tool-arg key=value` (convierte el valor a JSON si parsea y luego al tipo del schema) o `--tool-args-json '{...}'` (mutuamente excluyentes), `--format text|json`, `--config <archivo> --server <nombre>` — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)
- Códigos de salida del CLI: 0 ok; 1 error genérico; 3 requiere autenticación (401/403); 4 servidor inalcanzable; 5 error de tool (`isError: true`) o tool no encontrada; 6 `--strict` encontró problema de portabilidad del schema. En error escribe una línea JSON en stderr con `error.code` (`auth_required`, `unreachable`, `tool_not_found`, `tool_is_error`, ...) — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)
- `tools/list --strict` convierte el chequeo de portabilidad de schemas en un gate de CI (exit 6) — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)
- Para CI: `--stored-auth-only` evita OAuth interactivo y falla con `auth_required`; `--use-stored-auth` reutiliza un token que el Inspector web ya obtuvo (requiere `--server-url`). Sin TTY ni flags falla rápido en lugar de colgarse — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)
- Receta de CI oficial: `mcp-inspector --cli ... --method tools/list --format json | jq -e '.result.tools | map(.name) | index("get_weather")'` para verificar que una tool existe — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)
- "Protocol era" por servidor: `legacy` (por defecto, `initialize` simple), `auto` (prueba `server/discover` y cae a `initialize`) y `modern` (fija 2026-07-28 sin fallback). Flag `--protocol-era <legacy|auto|modern>` en CLI/TUI; en web está en Server Settings — [Protocol eras](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/protocol-eras.md)
- Una conexión modern no tiene session id; el Inspector muestra en la pestaña Network las cabeceras `Mcp-*` y en Protocol los errores tipados (-32020 HeaderMismatch, -32021, -32022 UnsupportedProtocolVersion, -32601) — [Protocol eras](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/protocol-eras.md)
- Un `-32602` en `tools/call` se muestra como panel "Unknown Tool" o "Invalid Parameters" — [Protocol eras](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/protocol-eras.md)
- Los secretos (tokens OAuth) van al keychain del SO; sin keychain se guardan en `~/.mcp-inspector/secrets.json` sin cifrar salvo que se aporte clave — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)
- Cloudflare documenta probar con `npx @modelcontextprotocol/inspector@latest`, abrir la página local (puerto 5173), poner la URL `/mcp`, Connect y List Tools; abrir `/mcp` en un navegador no funciona porque espera mensajes MCP — [Cloudflare: remote MCP server](https://developers.cloudflare.com/agents/guides/remote-mcp-server/)
- El paquete también instala `mcpdo`, cliente experimental que mantiene una conexión abierta entre comandos — [MCP Inspector docs](https://modelcontextprotocol.io/docs/tools/inspector)

### Inferences
- Para los 3 tools, una batería mínima de humo en CI sería: `tools/list` con `--strict` + `jq` comprobando los 3 nombres, y un `tools/call` por tool con `--tool-args-json`. Un caso inválido debería dar exit 5 (si el servidor devuelve `isError`) — conviene verificarlo en la práctica.
- Si el servidor se despliega con un SDK/handler que habla ambas eras, probar con `--protocol-era legacy` y `modern` por separado cubre a ambos tipos de cliente.
- `submit_observation` tiene efectos secundarios: usar un entorno/DB de pruebas o un flag dry-run para no ensuciar datos al correr smoke tests.

### Gaps
- No leí la página de la UI web (pestañas, Server Settings, panel de auth) ni la de configuración de flags (`--header`, timeouts); el nombre exacto de flag para cabeceras personalizadas (`--header`) solo aparece mencionado de pasada en la doc del CLI, sin sintaxis.
- No verifiqué en práctica el comportamiento contra un Worker real.

## 2. Transporte vigente y qué debe implementar un servidor remoto

### Takeaway
Streamable HTTP es el transporte estándar remoto (stdio para local); HTTP+SSE de 2024-11-05 está deprecado. La revisión 2026-07-28 eliminó el handshake `initialize`, las sesiones (`Mcp-Session-Id`) y el stream GET: ahora el servidor es sin estado, cada POST lleva versión/capacidades en `_meta` y cabeceras espejo. Los servidores deben implementar `server/discover`; la compatibilidad con clientes legacy (initialize + session id) es opcional pero conviene dado que muchos clientes aún la usan.

### Cited Findings
- Los bindings estándar son stdio y Streamable HTTP; el servidor expone un único endpoint (ej. `https://example.com/mcp`) que acepta POST — [Spec: transports (draft)](https://modelcontextprotocol.io/specification/draft/basic/transports) y [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Streamable HTTP se introdujo en 2025-03-26 como reemplazo de HTTP+SSE (2024-11-05); HTTP+SSE está marcado Deprecated, los nuevos desarrollos no deberían adoptarlo (SEP-2596) — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- La revisión 2026-07-28 eliminó el endpoint GET stream y las sesiones a nivel de protocolo — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Requisitos del cliente por POST: cuerpo = una única request o notificación JSON-RPC; cabecera `Accept` con `application/json` y `text/event-stream`; respuesta del servidor `application/json` o `text/event-stream` (el cliente debe soportar ambas); notificación aceptada = `202` sin cuerpo — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Cabeceras obligatorias por POST: `MCP-Protocol-Version: 2026-07-28` (debe coincidir con `_meta["io.modelcontextprotocol/protocolVersion"]`), `Mcp-Method` (siempre) y `Mcp-Name` (en tools/call, resources/read, prompts/get). Discrepancia -> `400` + error `-32020 HeaderMismatch`; versión no soportada -> `400` + `UnsupportedProtocolVersionError` (-32022) con lista `supported`; método desconocido -> `404` + `-32601` — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Cada request lleva en `_meta` `io.modelcontextprotocol/protocolVersion`, `clientInfo` y `clientCapabilities`; faltar los obligatorios da `-32602` — [Debugging guide](https://modelcontextprotocol.io/docs/2026-07-28/tools/debugging.md)
- "No hay handshake de negociación": los servidores DEBEN implementar `server/discover`; los clientes pueden llamarlo antes o no — [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning.md)
- Seguridad: el servidor DEBE validar la cabecera `Origin` (403 si es presente e inválida), en local enlazar solo a 127.0.0.1, y DEBERÍA autenticar todas las conexiones — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Un servidor solo-2026-07-28 ante tráfico antiguo: GET/DELETE -> `405`; ignorar `Mcp-Session-Id` (no emitirlo ni repetirlo); ignorar `Last-Event-ID` — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Un servidor dual-era puede servir ambas en el mismo endpoint: request con `_meta` moderno se sirve sin estado; una request `initialize` selecciona semántica legacy (con sesión HTTP) — [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning.md)
- Matriz de compatibilidad: cliente Legacy + servidor solo-Modern falla (400 por cabeceras ausentes); cliente Legacy + servidor Dual funciona — [Versioning](https://modelcontextprotocol.io/specification/draft/basic/versioning.md)
- Era legacy (2025-03-26 a 2025-11-25): `Mcp-Session-Id` asignado por el servidor (se cierra con DELETE), GET para stream SSE, resumibilidad con `Last-Event-ID` — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Sin estado de sesión: las tools con estado deben usar un "handle" explícito devuelto por una tool y pasado en llamadas siguientes — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Tools: el servidor con tools debe declarar la capability `tools` y responder `tools/list`; el orden debería ser determinista; el conjunto puede variar por autorización pero no por conexión — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Streams SSE: se recomienda enviar `X-Accel-Buffering: no`; cerrar el stream SSE de una request equivale a cancelarla — [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Cloudflare: `createMcpHandler` (paquete `agents/mcp/server`, con SDK v2) por defecto `legacy: "stateless"`: acepta clientes legacy para tools/prompts/resources, crea servidor+transport nuevo por POST, no persiste session id, GET/DELETE -> 405; `legacy: "reject"` para endpoint solo moderno; `responseMode` auto/json/sse — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)
- Cloudflare marca `McpAgent` como deprecado en su guía; recomienda empezar por el ejemplo `mcp-worker` para servidores nuevos sin estado — [Cloudflare: remote MCP server](https://developers.cloudflare.com/agents/guides/remote-mcp-server/)
- Auth (opcional en MCP, recomendada si hay datos de usuario): el servidor responde `401` con `WWW-Authenticate: Bearer realm="mcp", resource_metadata="https://.../.well-known/oauth-protected-resource"`; el documento PRM (RFC 9728) lista `authorization_servers` y scopes; el cliente descubre el AS (RFC 8414/OIDC), se registra (pre-registro o DCR, RFC 7591) y usa OAuth 2.1 + PKCE; el servidor debe validar tokens y su audiencia (RFC 8707) — [Tutorial de autorización MCP](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/authorization.md)
- Buenas prácticas de auth: no implementar validación de tokens a mano, tokens de vida corta, validar audiencia, no registrar credenciales, scopes mínimos — [Tutorial de autorización MCP](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/authorization.md)
- Cloudflare createMcpHandler no verifica tokens ni lee cabeceras por sí mismo: `authInfo` debe proveerlo middleware (p.ej. `@cloudflare/workers-oauth-provider`); CORS por defecto es comodín; Origin del navegador se valida (403 si malformado), requests sin Origin son válidas; para dominio propio configurar `allowedHostnames` — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)

### Inferences
- Si el proyecto es sin autenticación (hackathon), `createMcpHandler` en modo stateless por defecto cubre tanto clientes legacy (Claude, ChatGPT actuales probablemente) como modernos; no hace falta gestionar sesiones. No verifiqué qué era usan hoy Claude.ai/ChatGPT/Claude Code, por lo que conviene mantener el fallback legacy activo.
- `query_sound_map` y `find_suitable_places` son lecturas sin estado -> encajan perfecto con el modelo sin sesión; `submit_observation` debe ser idempotente o devolver un id de observación (patrón "handle").
- Probar con curl directo (POST con cabeceras `Accept`, `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`) es un test de contrato útil para el modo moderno.

### Gaps
- No leí el spec de `server/discover` ni el de authorization 2026-07-28 completo (solo el tutorial); detalles sobre CIMD vs DCR en esta revisión no verificados.
- Un snippet de búsqueda sugirió que ChatGPT soporta SSE y Streamable HTTP (fuente terciaria, no oficial); la doc oficial de OpenAI solo menciona streamable HTTP en `/mcp`.

## 3. Tests automatizados con el SDK oficial de TypeScript (cliente, in-memory/HTTP, zod, errores)

### Takeaway
El SDK TypeScript v2 (`@modelcontextprotocol/server` y `@modelcontextprotocol/client`, alineado con spec 2026-07-28, lanzado 2026-07-27) tiene una guía oficial "Test a server": `InMemoryTransport.createLinkedPair()` (solo instancias 2025-era), o `createMcpHandler` + `handler.fetch` inyectado como `fetch` de `StreamableHTTPClientTransport` para cubrir 2026-07-28 sin abrir puertos. Los errores de validación de input y de lógica se afirman como `isError: true`, no como excepciones.

### Cited Findings
- `main` del repo typescript-sdk es v2 ("stable release line"), apunta a la spec 2026-07-28; paquetes `@modelcontextprotocol/server` y `@modelcontextprotocol/client`; v1 (`@modelcontextprotocol/sdk`) sigue en rama `v1.x` con fixes durante al menos seis meses desde el release v2 del 2026-07-27 — [typescript-sdk README](https://github.com/modelcontextprotocol/typescript-sdk)
- Contradicción menor: un resultado de búsqueda muestra las páginas de docs v2 con el rótulo "v2 beta", mientras el README/landing dicen estable — [búsqueda de docs v2](https://ts.sdk.modelcontextprotocol.io/v2/testing.html) vs [README](https://github.com/modelcontextprotocol/typescript-sdk)
- Zod v4 se importa como `import * as z from 'zod/v4'`; los schemas usan Standard Schema (Zod v4, Valibot, ArkType) — [typescript-sdk README](https://github.com/modelcontextprotocol/typescript-sdk)
- La landing v2 indica que el SDK valida cada llamada contra `inputSchema` antes de ejecutar el handler — [Docs SDK v2](https://ts.sdk.modelcontextprotocol.io/v2)
- Ejemplo de Cloudflare: `server.registerTool("hello", { description, inputSchema: z.object({...}) }, handler)` dentro de una factoría `createServer()`; se pasa la factoría (no una instancia) a `createMcpHandler(createServer)` y se invoca desde `export default { fetch(request, env, ctx) {...} }` — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)
- Guía "Test a server" del SDK v2 (resumen): (a) `InMemoryTransport.createLinkedPair()` importado de `@modelcontextprotocol/client`, conectar server a un extremo y client al otro, `memClient.callTool(...)`; solo para instancias 2025-era; (b) para cobertura 2026-07-28, `createMcpHandler` y pasar un wrapper de `handler.fetch` como opción `fetch` de `StreamableHTTPClientTransport`, sin red; (c) Client con negociación de versión "auto"; (d) fallos de tool y de validación de schema devuelven resultado con `isError: true` (no lanzan); (e) teardown: cerrar primero el client y luego el handler en el hook de limpieza (cerrar el handler aborta llamadas en vuelo); (f) stdio: `StdioClientTransport` desde `@modelcontextprotocol/client/stdio` — [SDK v2: Test a server](https://ts.sdk.modelcontextprotocol.io/v2/testing.md) (accedido vía resumen de fetch y de búsqueda; no pude leer el código fuente literal)
- La spec distingue: errores de protocolo (tool desconocida, request mal formada -> JSON-RPC error, p.ej. `-32602`) vs errores de ejecución de tool (fallos de API, validación de input, lógica de negocio -> `isError: true` con texto accionable); el SEP-1303 trata errores de validación de input como errores de ejecución de tool — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Si hay `outputSchema`, el servidor DEBE devolver `structuredContent` conforme; y por compatibilidad DEBERÍA devolver el JSON serializado también en un bloque `text`; los clientes DEBERÍAN validarlo — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Nombres de tool: 1–128 caracteres, solo A-Z a-z 0-9 `_` `-` `.` (los tres nombres propuestos cumplen) — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Los servidores DEBEN validar todas las entradas, aplicar control de acceso, limitar tasa y sanear salidas — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Ejemplos de tests de terceros con InMemoryTransport + Vitest existen pero son de la era v1 — [Grist helper](https://glama.ai/mcp/servers/@gwhthompson/grist-mcp-server/blob/d75706c2dec283502e2bedd1cd1feae8f709f379/tests/helpers/mcp-test-client.ts)
- Cloudflare vitest-pool-workers: la página de createMcpHandler no cubre testing con Vitest/pool de Workers — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)

### Inferences
- Esbozo de test (NO verificado contra la API exacta de v2; los nombres de imports y firmas hay que contrastarlos con https://ts.sdk.modelcontextprotocol.io/v2/testing.md):
  ```ts
  // vitest
  const handler = createMcpHandler(createServer);          // agents/mcp/server
  const transport = new StreamableHTTPClientTransport(new URL("http://test/mcp"),
    { fetch: (req, init) => handler.fetch(new Request(req, init)) });
  const client = new Client({ name: "t", version: "1" } /* + versión "auto" */);
  await client.connect(transport);
  expect((await client.listTools()).tools.map(t => t.name))
    .toEqual(expect.arrayContaining(["query_sound_map","find_suitable_places","submit_observation"]));
  const bad = await client.callTool({ name: "find_suitable_places", arguments: { lat: "x" } });
  expect(bad.isError).toBe(true);
  afterEach(async () => { await client.close(); await handler.close?.(); });
  ```
- Casos a cubrir por tool: caso feliz con `structuredContent` conforme al `outputSchema`; argumento faltante/tipo erróneo/fuera de rango (lat -90..90, lon -180..180, radio > 0) -> `isError: true`; tool inexistente -> error de protocolo; errores del backend (DB caída) -> `isError: true` con mensaje legible por el LLM; y que `tools/list` sea determinista y contenga exactamente 3 tools con descripciones no vacías.
- Para Next.js, el mismo patrón (handler que recibe `Request` y devuelve `Response`) permite probar sin servidor, o levantar `next dev` y usar el Inspector CLI como test de integración.

### Gaps
- No pude obtener el texto literal de la guía "Test a server" ni de la página de Client del SDK v2 (404 en la URL que probé); el código anterior es un esbozo, no copia de la doc.
- Sin guía oficial de Vitest para Workers con McpServer; falta confirmar `@cloudflare/vitest-pool-workers` en esta combinación.
- No verifiqué la API de adaptadores para Next.js (`Express/Hono/Fastify/Node` middleware se mencionan, Next.js no).

## 4. Probar desde un cliente real (Claude connectors / Claude Code / ChatGPT): requisitos

### Takeaway
Claude (web/desktop/móvil) conecta desde la nube de Anthropic, por lo que la URL debe ser pública y alcanzable; autenticación OAuth o cabeceras fijas. Claude Code se prueba con `claude mcp add --transport http <name> <url>` y `claude mcp list`. ChatGPT necesita endpoint HTTPS público con Streamable HTTP (típicamente `/mcp`), con tools bien descritas y anotaciones; localhost requiere túnel.

### Cited Findings
- Claude conecta desde la infraestructura en la nube de Anthropic, no desde el dispositivo del usuario: el servidor debe ser alcanzable desde internet público (o permitir las IP de Anthropic); servidores en red privada/VPN/firewall no conectan — [Claude Help: custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- Autenticación en el conector: "Sign in now / when needed / No sign in"; cliente OAuth: identidad publicada de Claude, registro automático, o cliente propio; si se usa API key/bearer fijo, va en "Request headers" — [Claude Help: custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- Disponibilidad: conectores personalizados en Free (limitado a uno), Pro, Max, Team, Enterprise; en Pro/Max: Customize > Connectors > "+ Add" > Add custom connector; para editar hay que eliminar y volver a añadir — [Claude Help: custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- Claude Code: `claude mcp add --transport http <name> <url>`; con cabecera: `--header "Authorization: Bearer token"`; scopes `local` (defecto), `project` (`.mcp.json`), `user`; `claude mcp add` no valida credenciales — [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- OAuth en Claude Code: añadir el servidor, ejecutar `/mcp` y completar login; o `claude mcp login <name>`; `--callback-port` para redirect fijo; `--client-id/--client-secret` si no hay DCR — [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- Diagnóstico en Claude Code: `claude mcp list` (✔ Connected / ! Needs authentication / ✘ Failed), `claude mcp get <name>` (línea `Issue:` con estado HTTP/error), `claude --debug-file /tmp/claude-debug.log` — [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- Timeouts/límites en Claude Code: `MCP_TIMEOUT` (arranque), `MCP_TOOL_TIMEOUT` o `"timeout"` por servidor en `.mcp.json`, timeout de inactividad 5 min para remotos (`CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`); aviso de salida > 10.000 tokens, límite por defecto 25.000 (`MAX_MCP_OUTPUT_TOKENS`); resultados de texto > 50.000 caracteres se guardan en archivo — [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- Cloudflare: probar con `claude mcp add --transport http <name> <url>`, `claude mcp list`, y pedir a Claude que llame a una tool; local dev en `http://localhost:8788/mcp` — [Cloudflare: remote MCP server](https://developers.cloudflare.com/agents/guides/remote-mcp-server/)
- ChatGPT (doc OpenAI Apps SDK): el servidor debe estar en endpoint HTTPS público (o Secure MCP Tunnel) con Streamable HTTP, típicamente `/mcp`; deben existir nombres, descripciones, schemas y anotaciones de tools; el descubrimiento de auth debe funcionar si hay tools con cuenta; se añade desde ChatGPT Plugins > "Add custom MCP server", URL con `/mcp`; tras cambiar metadatos de tools hay que pulsar **Refresh** y abrir una conversación nueva — [OpenAI: connect ChatGPT](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt)
- Pruebas recomendadas por OpenAI: MCP Inspector, API Playground (Tools > Add > MCP Server), y sets de evaluación con prompts directos, indirectos, de seguimiento, de escritura y no soportados; comprobar que los resultados estructurados coinciden con los output schemas — [OpenAI: connect ChatGPT](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt)
- Fuentes secundarias: ChatGPT "Developer mode" es beta y los planes elegibles varían según la fuente (Plus/Pro/Business/Enterprise/Edu); verificar la tabla vigente de OpenAI — [búsqueda: Auth0 / Zuplo / Boomi](https://auth0.com/blog/add-remote-mcp-server-chatgpt/) (no oficial, discrepan entre sí)
- Para depurar en Claude Desktop hay logs en `~/Library/Logs/Claude` (macOS) o `%APPDATA%\Claude\logs` y DevTools con `developer_settings.json` — [Debugging guide](https://modelcontextprotocol.io/docs/2026-07-28/tools/debugging.md)

### Inferences
- Flujo práctico para el hackathon: (1) tests unitarios + Inspector CLI en local; (2) `wrangler deploy` (o Vercel) para una URL HTTPS pública; (3) Inspector web contra la URL pública; (4) `claude mcp add`; (5) conector personalizado en Claude.ai; (6) opcional ChatGPT. Para probar local con Claude.ai/ChatGPT hace falta túnel (cloudflared/ngrok); esto es una deducción de que Claude conecta desde la nube.
- Si no se usa OAuth, el modo "No sign in" simplifica el hackathon, pero `submit_observation` quedaría abierto: considerar un bearer fijo (soportado en Request headers de Claude y `--header` en Claude Code) y limitación de tasa.
- Si se usa dominio propio en Workers, configurar `allowedHostnames`/CORS en `createMcpHandler` (si no, la validación de Origin puede dar 403 a clientes de navegador).

### Gaps
- No encontré fuente oficial sobre la URL de callback OAuth de Claude ni sobre requisitos CORS específicos de Claude.ai (la página de ayuda no los cubre; el artículo 12922490 devolvió 404). Pendiente de consultar "Building custom connectors" en la documentación de Anthropic.
- La doc de Claude Help no menciona explícitamente el requisito de HTTPS (aunque en la práctica la URL es pública); no confirmado.
- Qué era del protocolo (legacy vs 2026-07-28) negocian hoy Claude.ai, Claude Code y ChatGPT: no encontrado.
- Requisitos exactos de planes/ChatGPT developer mode: sin fuente oficial leída.

## 5. Errores comunes (tool descriptions, salida estructurada, auth, timeouts)

### Takeaway
Los fallos típicos vienen de: mezclar errores de protocolo con errores de ejecución, devolver structuredContent que no cumple el outputSchema, no devolver también texto, cabeceras/Origin/CORS mal configurados, estado dependiente de sesión en un servidor sin estado, auth mal descubierta (401 sin `WWW-Authenticate`), y respuestas demasiado grandes o lentas para el cliente.

### Cited Findings
- Fallos de validación de input y de negocio deben ser `isError: true` con mensaje accionable para que el LLM se autocorrija; los errores JSON-RPC se reservan para tool desconocida, request mal formada y errores de servidor — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Si declaras `outputSchema`, `structuredContent` debe cumplirlo; añade también el JSON en un bloque text por compatibilidad — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Para tools sin parámetros usar `{ "type":"object","additionalProperties": false }`; el `inputSchema` por defecto es JSON Schema 2020-12 y no puede ser `null` — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Si se usa la extensión `x-mcp-header`, los clientes rechazan (y excluyen de `tools/list`) tools con anotaciones inválidas; no marcar parámetros sensibles — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Las anotaciones de tool no son de confianza salvo que provengan de servidores de confianza; debería haber humano en el bucle — [Spec tools 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md)
- Sin estado entre llamadas: una instancia de servidor por request no puede guardar estado en memoria (ej. una mutación en un servidor desechable es invisible a la siguiente lectura) — [Protocol eras](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/protocol-eras.md)
- En Workers las notificaciones son locales al isolate; el handler debe crearse una vez a nivel de módulo si se usan `notify`/`subscriptions/listen` — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)
- No exportar el handler directamente como `default` en Workers (Wrangler lo trata como `WorkerEntrypoint`); no loguear `authInfo.token` — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/)
- Las peticiones elicitation/sampling "pushed" fallan inmediatamente en modo stateless; en la era moderna se usan MRTR (`input_required`) — [Cloudflare createMcpHandler](https://developers.cloudflare.com/agents/api-reference/mcp-handler-api/); [Streamable HTTP](https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http.md)
- Pitfalls de auth oficiales: no validar tokens a mano; validar audiencia; devolver siempre `WWW-Authenticate` con `resource_metadata` en 401; DCR sin autenticación permite registrar cualquier cliente; no registrar credenciales; no atar autorización a `Mcp-Session-Id` — [Tutorial de autorización MCP](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/authorization.md)
- `notifications/message` (logging por protocolo) está deprecado desde 2026-07-28; usar OpenTelemetry o logs propios; stderr no lo captura el cliente en HTTP — [Debugging guide](https://modelcontextprotocol.io/docs/2026-07-28/tools/debugging.md)
- Servidores HTTP: usar curl / DevTools para inspeccionar requests y streams SSE — [Debugging guide](https://modelcontextprotocol.io/docs/2026-07-28/tools/debugging.md)
- Límites en Claude Code: salida > 25.000 tokens por defecto se corta y texto > 50.000 caracteres se vuelca a archivo; idle timeout 5 min — [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- Con ChatGPT, tras cambiar descripciones/schemas hay que "Refresh" en la configuración del conector o seguirá con metadatos cacheados — [OpenAI: connect ChatGPT](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt)
- Con Claude.ai, editar un conector implica eliminarlo y volver a crearlo — [Claude Help: custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- El CLI del Inspector coacciona `--tool-arg zip=012` a número si el schema lo declara numérico (puede ocultar bugs de tipos); `--tool-args-json` lo evita para strings — [Inspector CLI](https://modelcontextprotocol.io/docs/2026-07-28/tools/inspector/cli.md)

### Inferences
- Descripciones de tool: no encontré guía oficial dedicada a redactarlas (el índice de docs no la tiene). Práctica razonable: decir cuándo usar cada tool vs las otras dos (query_sound_map = consulta de datos existentes; find_suitable_places = recomendación; submit_observation = escritura), describir unidades y rangos en cada campo zod (`.describe()`), y evaluar con prompts reales (como sugiere OpenAI) que el modelo elige la tool correcta.
- Marcar `submit_observation` como no solo-lectura y las otras dos como de solo lectura (annotations de la spec: `readOnlyHint` etc.). La spec indica que `annotations` existe pero no leí la lista exacta de campos en estas fuentes.
- Riesgo de hackathon: servicio externo lento (consulta al mapa de sonido) puede sobrepasar los límites de tiempo de Workers/cliente; conviene timeouts internos y respuestas resumidas para no pasar de ~25.000 tokens.

### Gaps
- No encontré fuente oficial sobre límites de tiempo de CPU/subrequest en Cloudflare Workers para MCP, ni sobre los timeouts de Claude.ai/ChatGPT.
- No encontré lista oficial de "pitfalls" de descripciones de tools; lo anterior es inferencia.
- No verifiqué en esta sesión los nombres exactos de las annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) en la spec 2026-07-28.
