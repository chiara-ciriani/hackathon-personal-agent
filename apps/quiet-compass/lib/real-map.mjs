// Only published measurements may carry acoustic values. Reports remain context.
export const DEFAULT_SERVER = 'https://quiet-compass-server.onrender.com';
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

export async function loadDeviceReadings(origin = DEFAULT_SERVER, fetcher = fetch, now = new Date()) {
  const empty = state => ({state, data:emptyCollection()});
  try {
    const base = new URL(origin);
    if (base.protocol !== 'https:' || base.username || base.password || base.pathname !== '/' || base.search || base.hash) return empty('invalid_config');
    // Public read only. Never use the owner's credential to bypass contribution access.
    const response = await fetcher(`${base.origin}/v1/map/aggregates?lat=37.77&lon=-122.43&radius_m=5000&since_minutes=1440`, {
      cache:'no-store', redirect:'error', signal:AbortSignal.timeout(12000),
    });
    if ([401,403,428].includes(response.status)) return empty('access_required');
    if (!response.ok) return empty('unavailable');
    const data = deviceReadings(await response.json(), now);
    return {state:data.features.length ? 'available' : 'empty', data};
  } catch { return empty('unavailable'); }
}

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
  // Last 30 days (about 1,500 reports), matching the police-call window, so the density field is not one day's noise.
  const since = new Date(now.getTime() - 30 * 86400000).toISOString().slice(0, 10);
  const query = new URLSearchParams({
    '$select':'service_subtype,neighborhoods_sffind_boundaries,requested_datetime,lat,long',
    '$where':`service_name in ('Noise','Noise Report') AND requested_datetime >= '${since}T00:00:00' AND lat IS NOT NULL`,
    '$order':'requested_datetime DESC', '$limit':'3000',
  });
  const response = await fetcher(`https://data.sf.gov/resource/vw6y-z8j6.json?${query}`, {cache:'no-store',signal:AbortSignal.timeout(12000)});
  if (!response.ok) throw new Error('311 unavailable');
  return noiseReports(await response.json());
}

export function measurementText(p) {
  if (p.evidence === 'measured_device' && finite(p.dbfs)) return `${p.dbfs} dBFS · uncalibrated`;
  if (p.evidence === 'measured_crowdsourced' && finite(p.medianDb)) return `${p.medianDb} dB · uncalibrated phone`;
  if (p.evidence === 'measured' && finite(p.cnel)) return `${p.cnel} dB CNEL · daily average`;
  if (p.evidence === 'measured' && finite(p.maxDb)) return `${p.maxDb} dBA · maximum event`;
  return 'No sound measurement';
}
