import {DEFAULT_SERVER,loadDeviceReadings} from './real-map.mjs';

// One fixed public submission route. No owner or shared account credential is used.
export async function shareCommunity(request,origin=DEFAULT_SERVER,fetcher=fetch){
 const reply=(body,status)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
 try{
  const base=new URL(origin);
  if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash)return reply({error:'Sharing needs server setup.'},503);
  if(request.headers.get('origin')&&request.headers.get('origin')!==new URL(request.url).origin)return reply({error:'Origin not allowed.'},403);
  const reader=request.body?.getReader();if(!reader)return reply({error:'Missing summary.'},422);
  const parts=[];let size=0;
  while(true){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();return reply({error:'Summary exceeds the size limit.'},413)}parts.push(value)}
  const bytes=new Uint8Array(size);let offset=0;for(const p of parts){bytes.set(p,offset);offset+=p.byteLength}
  const body=JSON.parse(new TextDecoder().decode(bytes));
  const response=await fetcher(base.origin+'/v1/community/contributions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',cache:'no-store',signal:AbortSignal.timeout(12000)});
  if(!response.ok)return reply({error:response.status===429?'Sharing limit reached. Try again later.':'Could not share. Check location, permissions and server version.'},response.status===429?429:502);
  const result=await response.json();
  if(!['accepted','withheld','rejected'].includes(result.status))throw Error();
  return reply({status:result.status,reason:result.reason,access_receipt:result.access_receipt,access_expires_at:result.access_expires_at},200);
 }catch{return reply({error:'Could not reach the community server. Try again.'},502)}
}

export async function activateMapAccess(request,origin=DEFAULT_SERVER,fetcher=fetch){
 const headers={'Cache-Control':'no-store'};
 if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Origin not allowed.'},{status:403,headers});
 try{
  const text=await request.text();if(text.length>256)throw Error();
  const {receipt}=JSON.parse(text);
  if(typeof receipt!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(receipt))throw Error();
  const result=await loadDeviceReadings(origin,fetcher,new Date(),receipt);
  if(!['available','empty'].includes(result.state))return Response.json({error:'Map access expired. Share a new measurement.'},{status:403,headers});
  return Response.json({ok:true},{headers:{...headers,'Set-Cookie':`qc_map_access=${receipt}; HttpOnly; Secure; SameSite=Strict; Path=/api/map; Max-Age=900`}});
 }catch{return Response.json({error:'Invalid map access link.'},{status:422,headers})}
}
