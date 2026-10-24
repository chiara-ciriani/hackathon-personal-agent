import { cookies } from 'next/headers';
import { getChatGPTUser } from '../../../chatgpt-auth';
import { env } from 'cloudflare:workers';
import { seal, unseal } from '../../../../lib/seal.mjs';

export const dynamic = 'force-dynamic';
const prefix = '__Host-qc_';
function settings() { return env as unknown as {SESSION_ENCRYPTION_KEY?: string; APP_ORIGIN?: string}; }
function json(value: unknown, status = 200) { return Response.json(value, {status, headers: {'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}}); }
async function context(req: Request, mutation = false) {
  const user = await getChatGPTUser();
  if (!user) throw new Error('AUTH');
  const cfg = settings();
  if (!cfg.SESSION_ENCRYPTION_KEY || !cfg.APP_ORIGIN) throw new Error('CONFIG');
  if (mutation && req.headers.get('origin') !== cfg.APP_ORIGIN) throw new Error('ORIGIN');
  return {uid:user.userId,key:cfg.SESSION_ENCRYPTION_KEY,origin:cfg.APP_ORIGIN,jar:await cookies()};
}
type Ctx = Awaited<ReturnType<typeof context>>;
async function read(c:Ctx, name:string) { const v=c.jar.get(prefix+name)?.value; return v ? unseal(v,c.key,c.uid) : null; }
async function write(c:Ctx,name:string,value:object,seconds:number) {
 const v=await seal({...value,uid:c.uid,exp:Date.now()+seconds*1000},c.key);
 if(v.length>3800) throw new Error('SIZE');
 c.jar.set(prefix+name,v,{httpOnly:true,secure:true,sameSite:'lax',path:'/',maxAge:seconds});
}
function clear(c:Ctx,name:string) {c.jar.set(prefix+name,'',{httpOnly:true,secure:true,sameSite:'lax',path:'/',maxAge:0});}
function redirect(c:Ctx,path:string) {return new Response(null,{status:303,headers:{Location:c.origin+path,'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});}
function fail(e:unknown) { const code=e instanceof Error?e.message:''; return json({error:code==='AUTH'?'Sign in to connect Oura.':code==='ORIGIN'?'Request not authorized.':code==='CONFIG'?'Server configuration is incomplete.':'The request could not be completed. Try again.'},code==='AUTH'?401:code==='ORIGIN'?403:503); }
export async function POST(req:Request,{params}:{params:Promise<{action:string}>}) {
 try {
 const c=await context(req,true); const {action}=await params;
 if(action==='config') {
  if(Number(req.headers.get('content-length')||0)>6000)return json({error:'The submitted form is too large.'},400);
  const body=await req.text();if(body.length>6000)return json({error:'The submitted form is too large.'},400);
  const b=JSON.parse(body);const id=String(b.clientId||'').trim(),secret=String(b.clientSecret||'').trim();
  if(!/^[A-Za-z0-9_-]{4,256}$/.test(id)||secret.length<8||secret.length>512)return json({error:'Check your Oura Client ID and Client Secret.'},400);
  await write(c,'config',{clientId:id,clientSecret:secret},86400*7);clear(c,'session');clear(c,'oauth');return json({ok:true});
 }
 if(action==='disconnect'){for(const n of ['session','oauth','config'])clear(c,n);return json({ok:true});}
 return json({error:'Unknown route'},404);
 }catch(e){return fail(e);}
}
export async function GET(req:Request,{params}:{params:Promise<{action:string}>}) {
 try {
 const c=await context(req);const {action}=await params;
 if(action==='status') {const cfg=await read(c,'config'),session=await read(c,'session');return json({configured:!!cfg,connected:!!session,redirectUri:c.origin+'/api/oura/callback'});}
 if(action==='login') {
  const cfg=await read(c,'config');if(!cfg)return redirect(c,'/connections?setup=1');
  const state=crypto.randomUUID();const verifier=Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url');
  const challenge=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))).toString('base64url');
  await write(c,'oauth',{state,verifier},600);
  const url=new URL('https://cloud.ouraring.com/oauth/authorize');url.search=new URLSearchParams({response_type:'code',client_id:cfg.clientId,redirect_uri:c.origin+'/api/oura/callback',scope:'daily',state,code_challenge:challenge,code_challenge_method:'S256'}).toString();
  return new Response(null,{status:303,headers:{Location:url.toString(),'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
 }
 if(action==='callback') {
  const pending=await read(c,'oauth');clear(c,'oauth');const url=new URL(req.url);
  if(!pending||url.searchParams.get('state')!==pending.state)return redirect(c,'/connections?error=state');
  if(url.searchParams.has('error'))return redirect(c,'/connections?error=denied');
  const cfg=await read(c,'config'),code=url.searchParams.get('code');if(!cfg||!code)return redirect(c,'/connections?error=config');
  const r=await fetch('https://api.ouraring.com/oauth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',client_id:cfg.clientId,client_secret:cfg.clientSecret,code,code_verifier:pending.verifier,redirect_uri:c.origin+'/api/oura/callback'}),signal:AbortSignal.timeout(15000)});
  if(!r.ok)return redirect(c,'/connections?error=exchange');const t=await r.json() as {access_token?:string;expires_in?:number};
  if(!t.access_token)return redirect(c,'/connections?error=exchange');
  await write(c,'session',{accessToken:t.access_token},Math.min(Number(t.expires_in)||3600,43200));
  return redirect(c,'/connections?connected=1');
 }
 if(action==='data') {
  const s=await read(c,'session');if(!s)return json({error:'Connect Oura to access your data.'},401);
  const end=new Date().toISOString().slice(0,10),start=new Date(Date.now()-8*86400000).toISOString().slice(0,10);
  const kinds=['daily_sleep','daily_readiness','daily_activity','sleep'];
  const results=await Promise.all(kinds.map(async kind=>{
   try {const r=await fetch(`https://api.ouraring.com/v2/usercollection/${kind}?start_date=${start}&end_date=${end}`,{headers:{Authorization:`Bearer ${s.accessToken}`},signal:AbortSignal.timeout(12000)});
   if(!r.ok)return {kind,status:r.status,rows:[]};const b=await r.json() as {data?:Record<string,unknown>[]};return {kind,status:200,rows:b.data||[]};}catch{return {kind,status:503,rows:[]};}
  }));
  if(results.some(r=>r.status===401)){clear(c,'session');return json({error:'Your authorization expired. Reconnect Oura.'},401);}
  const get=(kind:string)=>results.find(r=>r.kind===kind)?.rows||[];
  const last=(rows:Record<string,unknown>[])=>[...rows].sort((a,b)=>String(b.day).localeCompare(String(a.day)))[0];
  const sleep=last(get('daily_sleep')),readiness=last(get('daily_readiness')),activity=last(get('daily_activity'));
  const nights=get('sleep').filter(r=>r.type==='long_sleep');const night=last(nights);
  return json({source:'oura',fetchedAt:new Date().toISOString(),sleep:sleep?{day:sleep.day,score:sleep.score}:null,readiness:readiness?{day:readiness.day,score:readiness.score}:null,activity:activity?{day:activity.day,steps:activity.steps}:null,night:night?{day:night.day,totalSleepSeconds:night.total_sleep_duration}:null,history:get('daily_sleep').map(r=>({day:r.day,score:r.score})).sort((a,b)=>String(a.day).localeCompare(String(b.day))),warnings:results.filter(r=>r.status!==200).map(r=>({metric:r.kind,message:r.status===403?'Permission or active membership required.':r.status===429?'Oura rate limit reached. Try again later.':'This metric could not be retrieved.'}))});
 }
 return json({error:'Unknown route'},404);
 }catch(e){return fail(e);}
}
