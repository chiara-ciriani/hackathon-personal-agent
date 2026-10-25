import {env} from 'cloudflare:workers';
import {DEFAULT_SERVER,loadDeviceReadings} from '../../../lib/real-map.mjs';

export const dynamic = 'force-dynamic';
export async function GET(request: Request) {
  const settings = env as unknown as {QC_SERVER_URL?:string};
  const token = request.headers.get('cookie')?.split(';').map(value=>value.trim()).find(value=>value.startsWith('qc_map_access='))?.slice('qc_map_access='.length) || null;
  const device = await loadDeviceReadings(settings.QC_SERVER_URL || DEFAULT_SERVER, fetch, new Date(), token);
  return Response.json({device:device.data,deviceState:device.state}, {headers:{'Cache-Control':'no-store'}});
}
