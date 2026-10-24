const ACTIONS = new Set(['status', 'consent', 'poll', 'result', 'disconnect']);

// Browser capability only, never a shared or owner API key. Fixed upstream routes.
// No credentials in URLs, no public server credential, no persistent browser storage.
export async function relayPhone(request, origin, action, fetcher = fetch) {
  const reply = (body, status) => Response.json(body, {status, headers: {'Cache-Control': 'no-store'}});
  if (!ACTIONS.has(action)) return reply({error: 'Invalid action.'}, 404);
  let base;
  try {
    base = new URL(origin);
    if ((base.protocol !== 'https:' && !(base.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname))) ||
        base.pathname !== '/' || base.search || base.hash || base.username || base.password) throw new Error();
  } catch { return reply({error: 'Server connection needs configuration.'}, 503); }
  const token = request.headers.get('authorization');
  if (!token || !/^Bearer [A-Za-z0-9_-]{43}$/.test(token)) return reply({error: 'Open the connection link from your agent.'}, 401);
  if (request.headers.get('origin') && request.headers.get('origin') !== new URL(request.url).origin) return reply({error: 'Origin not allowed.'}, 403);
  if (!(request.headers.get('content-type') || '').startsWith('application/json')) return reply({error: 'Unsupported format.'}, 415);
  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) throw new Error();
    const chunks = []; let size = 0;
    while (true) {
      const {value, done} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); return reply({error: 'Summary exceeds the size limit.'}, 413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch { return reply({error: 'Invalid request.'}, 422); }
  try {
    const response = await fetcher(base.origin + '/v1/phone/' + action, {
      method: 'POST', headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: JSON.stringify(body), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(12000),
    });
    if ([401, 403, 410].includes(response.status)) return reply({error: 'This link expired or disconnected. Ask your agent for a new one.'}, response.status);
    if ([404, 503].includes(response.status)) return reply({error: 'Server update needed before phones can connect.'}, 503);
    if (!response.ok) return reply({error: 'Could not complete the request. Check your connection and try again.'}, response.status >= 500 ? 502 : 409);
    const result = await response.json();
    if (!['ready', 'offline', 'waiting_for_phone', 'measure', 'waiting', 'complete', 'failed', 'disconnected'].includes(result.status)) throw new Error();
    // Only phone-facing fields; never expose agent-side results or capabilities here.
    return reply({status: result.status, expires_at: result.expires_at,
      ...(action === 'poll' && result.recommendation ? {recommendation: result.recommendation} : {}),
      ...(action === 'poll' && result.status === 'measure' ? {request_id: result.request_id, duration_seconds: result.duration_seconds} : {})}, 200);
  } catch { return reply({error: 'Server unavailable. Your phone will disconnect and turn off the microphone.'}, 502); }
}
