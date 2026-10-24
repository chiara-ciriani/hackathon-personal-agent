export const sharedTools = [
  {name: 'connect_phone', purpose: 'Link phone', input: {}, returns: 'Private connection link and phone_session_id; the owner approves sensors on the phone'},
  {name: 'request_phone_measurement', purpose: 'Measure', input: {phone_session_id: 'from connect_phone'}, returns: 'One 30-second request for the connected phone'},
  {name: 'phone_measurement_status', purpose: 'Read result', input: {phone_session_id: 'from connect_phone'}, returns: 'Phone state, actual summary and contribution access receipt'},
  {name: 'send_phone_recommendation', purpose: 'Advise', input: {phone_session_id: 'from connect_phone', message: 'Short recommendation', action: 'move | stay | unknown', area_id: 'measured destination for a move'}, returns: 'Recommendation queued for the connected phone'},
  {name: 'submit_observation', purpose: 'Contribute', input: {
    id: 'UUID', schema_version: '0.1', area_id: 'registered zone or outdoor cell',
    lat: 'number; with lon for an unregistered area', lon: 'number',
    time_bucket: 'ISO 8601 with timezone; last 15 minutes', duration_seconds: '5–600',
    measurement: {kind: 'relative_uncalibrated', rms_dbfs: 'number ≤ 0', frame_level_spread_db: '0–60', peaks_per_min: 'number ≥ 0 or null', calibrated: false},
    quality: {capture_profile: 'device and capture mode', clipping_detected: false},
    source: 'device', share_consent: true,
  }, returns: 'status, access_receipt, access_expires_at; withheld can still grant access'},
  {name: 'query_sound_map', purpose: 'Read', input: {lat: 'number', lon: 'number', radius_m: '50–5000; default 500', since_minutes: '5–1440; default 60', access_receipt: 'from submit_observation'}},
  {name: 'find_suitable_places', purpose: 'Read', input: {goal: 'talk | rest | work', lat: 'number', lon: 'number', max_walk_minutes: '1–60; default 10', max_age_minutes: '5–1440; default 30', return_by: 'optional ISO 8601 with timezone', access_receipt: 'from submit_observation'}},
];

export function connectionGuide(endpoint) {
  return {
    name: 'quiet-compass-shared', transport: 'streamable-http',
    endpoint: endpoint || 'Deploy the server, then use https://YOUR-SERVER/mcp/shared',
    headers: {Authorization: 'Bearer <QC_SHARED_API_TOKEN>'},
    access_window_seconds: 900,
    workflow: 'To use a phone: call connect_phone and show the user its link. After phone-side approval, call request_phone_measurement and poll phone_measurement_status. Use its receipt with find_suitable_places, then send_phone_recommendation to return advice. For an existing summary: ask for permission to share a real acoustic summary. Submit it with share_consent=true. Use the returned access_receipt for shared queries until access_expires_at. After 15 minutes, contribute a new measurement. Retries never renew access. Never invent measurements.',
    tools: sharedTools,
    excluded: ['raw_audio', 'personal_routes', 'health_data', 'identity'],
  };
}

/** Public capability check only. Never proxy readings or credentials to the browser. */
export async function exchangeStatus(origin, fetcher = fetch) {
  if (!origin) return {state: 'not_configured', endpoint: null};
  try {
    const base = new URL(origin);
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname);
    if ((base.protocol !== 'https:' && !(local && base.protocol === 'http:')) ||
        base.username || base.password || base.search || base.hash || base.pathname !== '/') {
      return {state: 'invalid_config', endpoint: null};
    }
    const response = await fetcher(`${base.origin}/v1/exchange/status`, {
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(5000),
    });
    if (response.status === 404) return {state: 'incompatible', endpoint: null};
    if (!response.ok) return {state: 'unavailable', endpoint: null};
    const data = await response.json();
    if (data.protocol !== 'contribution-window-v1' || data.access_window_seconds !== 900 ||
        data.mcp_path !== '/mcp/shared' || !Array.isArray(data.tools) ||
        sharedTools.some(tool => !data.tools.includes(tool.name))) return {state: 'incompatible', endpoint: null};
    if (data.shared_endpoint_enabled !== true) return {state: 'disabled', endpoint: null};
    return {state: 'available', endpoint: `${base.origin}/mcp/shared`, ...(data.phone_measurement?.protocol === 'phone-bridge-v1' ? {phoneReady: true} : {})};
  } catch {
    return {state: 'unavailable', endpoint: null};
  }
}
