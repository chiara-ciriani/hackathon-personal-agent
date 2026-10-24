import {env} from 'cloudflare:workers';
import {relayPhone} from '../../../../lib/phone-relay.mjs';

export const dynamic = 'force-dynamic';
export async function POST(request: Request, context: {params: Promise<{action: string}>}) {
  const {action} = await context.params;
  const settings = env as unknown as {QC_SERVER_URL?: string};
  return relayPhone(request, settings.QC_SERVER_URL || 'https://quiet-compass-server.onrender.com', action);
}
