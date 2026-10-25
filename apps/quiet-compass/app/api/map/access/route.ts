import {env} from 'cloudflare:workers';
import {activateMapAccess} from '../../../../lib/community.mjs';
export async function POST(request:Request){
 const settings=env as unknown as {QC_SERVER_URL?:string};
 return activateMapAccess(request,settings.QC_SERVER_URL);
}
