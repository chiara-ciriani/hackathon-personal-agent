import {env} from 'cloudflare:workers';
import {shareCommunity} from '../../../lib/community.mjs';
export async function POST(request:Request){
 const settings=env as unknown as {QC_SERVER_URL?:string};
 return shareCommunity(request,settings.QC_SERVER_URL);
}
