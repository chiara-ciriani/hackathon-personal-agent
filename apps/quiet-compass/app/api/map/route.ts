import {env} from 'cloudflare:workers';
import {DEFAULT_SERVER,loadDeviceReadings} from '../../../lib/real-map.mjs';

export const dynamic = 'force-dynamic';
export async function GET() {
  const settings = env as unknown as {QC_SERVER_URL?:string};
  const device = await loadDeviceReadings(settings.QC_SERVER_URL || DEFAULT_SERVER);
  return Response.json({device:device.data,deviceState:device.state}, {headers:{'Cache-Control':'no-store'}});
}
