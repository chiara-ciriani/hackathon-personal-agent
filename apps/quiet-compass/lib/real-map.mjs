// Only published measurements may carry acoustic values. Reports remain context.
export const DEFAULT_SERVER = 'https://quiet-compass-server.onrender.com';
/** @returns {{type:'FeatureCollection', features:any[]}} */
export const emptyCollection = () => ({type:'FeatureCollection', features:[]});
const finite = value => typeof value === 'number' && Number.isFinite(value);
const inSf = (lat, lon) => finite(lat) && finite(lon) && lat >= 37.6 && lat <= 37.85 && lon >= -122.55 && lon <= -122.3;

export function deviceReadings(body, now = new Date()) {
  if (!Array.isArray(body?.aggregates)) throw new Error('Invalid shared readings');
  return {type:'FeatureCollection', features:body.aggregates.flatMap(row => {
    const age = (now.getTime() - Date.parse(row.time_bucket)) / 60000;
    if (row.source !== 'device' || row.has_synthetic !== false || row.measurement_kind !== 'relative_uncalibrated' ||
        !inSf(row.lat, row.lon) || !finite(row.median_rms_dbfs) || row.median_rms_dbfs > 0 ||
        !Number.isFinite(age) || age < -5 || age > 1440 || !Number.isInteger(row.n) || row.n < 1 ||
        !row.capture_profile || !row.area_id) return [];
    return [{type:'Feature', geometry:{type:'Point', coordinates:[row.lon,row.lat]}, properties:{
      evidence:'measured_device', kind:'Device measurement', label:row.area_name || row.area_id,
      areaId:row.area_id, observedOn:row.time_bucket, dbfs:row.median_rms_dbfs,
      count:row.n, captureProfile:row.capture_profile,
      detail:`${row.n} contributions · ${row.capture_profile}`,
      caveat:'Relative, uncalibrated dBFS. Compare only within the same capture profile. Not dBA.' + (row.clipped_count > 0 ? ' Includes clipped recordings.' : ''),
    }}];
  })};
}

/** @param {string|null} [accessReceipt] */
export async function loadDeviceReadings(origin = DEFAULT_SERVER, fetcher = fetch, now = new Date(), accessReceipt = null) {
  const empty = state => ({state, data:emptyCollection()});
  if (!accessReceipt || !/^[A-Za-z0-9_-]{43}$/.test(accessReceipt)) return empty('access_required');
  try {
    const base = new URL(origin);
    if (base.protocol !== 'https:' || base.username || base.password || base.pathname !== '/' || base.search || base.hash) return empty('invalid_config');
    // Read the same released aggregates as MCP using the contributor's expiring capability.
    const response = await fetcher(`${base.origin}/v1/map/view`, {
      headers:{Authorization:`Bearer ${accessReceipt}`},
      cache:'no-store', redirect:'error', signal:AbortSignal.timeout(12000),
    });
    if ([401,403,410,428].includes(response.status)) return empty('access_required');
    if (!response.ok) return empty('unavailable');
    const data = deviceReadings(await response.json(), now);
    return {state:data.features.length ? 'available' : 'empty', data};
  } catch { return empty('unavailable'); }
}

/** @returns {{type:'FeatureCollection', features:any[]}} */
export function noiseReports(rows) {
  if (!Array.isArray(rows)) throw new Error('Invalid 311 reports');
  return {type:'FeatureCollection', features:rows.flatMap(row => {
    if (!row.lat || !row.long || !row.requested_datetime) return [];
    const lat = Number(row.lat), lon = Number(row.long);
    if (!inSf(lat,lon)) return [];
    return [{type:'Feature',geometry:{type:'Point',coordinates:[lon,lat]},properties:{
      evidence:'report',kind:'311 noise complaint',label:(row.service_subtype || 'Noise').replaceAll('_',' '),
      detail:row.neighborhoods_sffind_boundaries || '',observedOn:row.requested_datetime,
      caveat:'Reported to 311. This is not a sound measurement. Source timestamp is San Francisco local time.',
      dataset:'vw6y-z8j6',
    }}];
  })};
}

/** @param {(url:string, options?:any)=>Promise<any>} [fetcher] */
export async function loadNoiseReports(fetcher = fetch, now = new Date()) {
  // DataSF timestamps use San Francisco local time without a timezone suffix.
  const localStamp=date=>{
    const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(date).map(p=>[p.type,p.value]));
    return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}`;
  };
  const since=localStamp(new Date(now.getTime()-24*3600000)),until=localStamp(now);
  const query = new URLSearchParams({
    '$select':'service_subtype,neighborhoods_sffind_boundaries,requested_datetime,lat,long',
    '$where':`service_name in ('Noise','Noise Report') AND requested_datetime >= '${since}' AND requested_datetime <= '${until}' AND lat IS NOT NULL`,
    '$order':'requested_datetime DESC', '$limit':'3000',
  });
  const response = await fetcher(`https://data.sf.gov/resource/vw6y-z8j6.json?${query}`, {cache:'no-store',signal:AbortSignal.timeout(12000)});
  if (!response.ok) throw new Error('311 unavailable');
  const body=await response.json();
  if(!Array.isArray(body))throw new Error('Invalid 311 reports');
  return noiseReports(body.filter(r=>{const when=String(r.requested_datetime||'').slice(0,19);return when>=since&&when<=until}));
}

export function measurementText(p) {
  if (p.evidence === 'measured_device' && finite(p.dbfs)) return `${p.dbfs} dBFS · uncalibrated`;
  if (p.evidence === 'measured' && finite(p.cnel)) return `${p.cnel} dB CNEL · daily average`;
  if (p.evidence === 'measured' && finite(p.maxDb)) return `${p.maxDb} dBA · maximum event`;
  return 'No sound measurement';
}
