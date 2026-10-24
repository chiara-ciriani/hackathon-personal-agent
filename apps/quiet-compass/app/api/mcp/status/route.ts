import { env } from 'cloudflare:workers';
import { exchangeStatus } from '../../../../lib/mcp-exchange.mjs';

export const dynamic = 'force-dynamic';
export async function GET() {
  const settings = env as unknown as {QC_SERVER_URL?: string};
  return Response.json(await exchangeStatus(settings.QC_SERVER_URL || 'https://quiet-compass-server.onrender.com'), {
    headers: {'Cache-Control': 'no-store'},
  });
}
