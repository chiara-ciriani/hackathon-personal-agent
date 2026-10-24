// Real San Francisco layers from DataSF, mirrored from server/quiet_compass/sf_layers.py.
// Every layer carries an `evidence` label: measured | proxy | unmeasured_candidate.
// Only the SFO CNEL monitors are sensor measurements. Nothing here is a phone reading.
// Dataset ids were checked against the live Socrata API on 2026-10-24.
export const BASE='https://data.sf.gov/resource';
export const DATASETS={popos:'65ik-7wqd',libraries:'fhhu-wqa7',entertainment:'86e8-rfem',nightNoise:'e7pr-36bt',closures:'8x25-yybr',sfo:'qxw2-ncq3'};
export const CAVEATS={
 candidate:'Unmeasured candidate from a city inventory. Nobody has measured its sound; check hours and conditions.',
 entertainment:'Active entertainment permit: a proxy for possible amplified sound, not a level.',
 nightNoise:'Night-work permit scheduled today or tomorrow: a proxy for temporary noise, not a level.',
 closure:'SFMTA street closure in effect now: a proxy, not a sound level.',
 sfo:'Daily CNEL (A-weighted dB, 24 h) at an SFO community noise monitor, published monthly. Measured at the monitor, not at your spot, and not live.',
};
// Published measured levels with citation. The source gives street names only, so they are listed, not plotted.
const EIR_URL='https://sfmea.sfplanning.org/CentralSoMaPlanDEIR_11-iv-e-noise.pdf';
export const REFERENCE_LEVELS=[
 {location:'Folsom St at Mabini St (main street)',ldn:78,note:'24 h; fire apparatus route',date:'2014-05-29'},
 {location:'Second and Bryant Sts (main street, near I-80)',ldn:76,note:'10 min, p.m. peak',date:'2014-05-20'},
 {location:'Fourth St south of Bryant St (main street)',ldn:74,note:'24 h',date:'2014-05-29'},
 {location:'Fourth and Howard Sts (main street)',ldn:74,note:'10 min, p.m. peak',date:'2014-05-19'},
 {location:'Harrison St, Fifth to Sixth (main street)',ldn:72,note:'10 min, p.m. peak',date:'2014-05-19'},
 {location:'Fifth St, Folsom to Harrison (main street)',ldn:69,note:'10 min, p.m. peak',date:'2014-05-19'},
 {location:'Minna St west of Sixth St (interior alley)',ldn:67,note:'10 min, p.m. peak',date:'2014-05-19'},
 {location:'Bluxome St east of Fifth St (interior alley)',ldn:66,note:'10 min, p.m. peak',date:'2014-05-20'},
 {location:'Clementina St, Fifth to Sixth (interior alley)',ldn:63,note:'41 h',date:'2011-09-27',table:'Table IV.E-3'},
].map(r=>({...r,evidence:'reference_measured',source:`Central SoMa Plan Draft EIR (Dec 2016), ${r.table||'Table IV.E-2'}`,sourceUrl:EIR_URL}));
export const REFERENCE_NOTE='Ldn in dBA from a 2016 environmental review, Central SoMa only (main streets averaged 75, alleys 63-67). Old, area-specific context: not today\'s level and not comparable to the demo scores.';

const num=v=>{const n=Number.parseFloat(String(v));return Number.isFinite(n)?n:null};
const inSf=(lat,lng)=>lat!==null&&lng!==null&&lat>=37.6&&lat<=37.85&&lng>=-122.55&&lng<=-122.3;
const fromPoint=row=>{const c=row?.point?.coordinates;if(!Array.isArray(c)||c.length<2)return null;const [lng,lat]=c.map(Number);return inSf(lat,lng)?[lng,lat]:null};
const feature=(coords,properties)=>({type:'Feature',geometry:{type:'Point',coordinates:coords},properties});

export function parsePopos(row){
 const lat=num(row.latitude),lng=num(row.longitude),name=String(row.name||'').trim();
 if(!name||!inSf(lat,lng))return null;
 const detail=[row.type,row.hours_type,row.indoor===true?'indoor':null].filter(Boolean).join(' · ');
 return feature([lng,lat],{evidence:'unmeasured_candidate',source:'seed',kind:'POPOS',label:name,detail,caveat:CAVEATS.candidate,dataset:DATASETS.popos});
}
export function parseLibrary(row){
 const lat=num(row.latitude),lng=num(row.longitude),name=String(row.common_name||'').trim();
 if(!name||/support services/i.test(name)||!inSf(lat,lng))return null;
 return feature([lng,lat],{evidence:'unmeasured_candidate',source:'seed',kind:'Library',label:name,detail:'public library',caveat:CAVEATS.candidate,dataset:DATASETS.libraries});
}
export function parseEntertainment(row){
 const c=fromPoint(row),name=String(row.dba_name||'').trim();
 return c&&name?feature(c,{evidence:'proxy',kind:'Entertainment permit',label:name,detail:row.license_type||'',caveat:CAVEATS.entertainment,dataset:DATASETS.entertainment}):null;
}
const localDate=d=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles'}).format(d);
export function parseNightNoise(row,now){
 const c=fromPoint(row),status=String(row.nnp||'').trim().toUpperCase();
 const start=String(row.start_date||'').slice(0,10),end=String(row.end_date||'').slice(0,10);
 if(!c||!start||!end||['DENIED','WITHDRAWN','PENDING'].includes(status))return null;
 const today=localDate(now),tomorrow=localDate(new Date(now.getTime()+86400000));
 if(Number(end.slice(0,4))>2100||start>tomorrow||end<today)return null; // the source has bogus far-future end dates
 const detail=[row.type_of_work,`${start} to ${end}`,row.start_end_time_each_day].filter(Boolean).join(' · ');
 return feature(c,{evidence:'proxy',kind:'Night-work permit',label:String(row.address||'Night work permit'),detail,caveat:CAVEATS.nightNoise,dataset:DATASETS.nightNoise});
}
export function parseClosure(row){
 const coords=row?.shape?.coordinates;if(!Array.isArray(coords)||!coords.length)return null;
 const mid=coords[Math.floor(coords.length/2)],lng=num(mid?.[0]),lat=num(mid?.[1]);
 if(!inSf(lat,lng))return null;
 return feature([lng,lat],{evidence:'proxy',kind:'Street closure',label:String(row.loc_desc||row.street||'Street closure'),detail:[row.type,row.veh_imp].filter(Boolean).join(' · '),caveat:CAVEATS.closure,dataset:DATASETS.closures});
}
export function latestSfoMonitors(rows){
 const latest=new Map();
 for(const r of rows){const id=String(r.location_id||''),date=String(r.date||'');
  if(id&&num(r.total_cnel)!==null&&date>String(latest.get(id)?.date||''))latest.set(id,r)}
 const out=[];
 for(const [id,r] of [...latest].sort((a,b)=>a[0].localeCompare(b[0],undefined,{numeric:true}))){
  const lat=num(r.latitude),lng=num(r.longitude),cnel=num(r.total_cnel);
  if(!inSf(lat,lng)||cnel===null)continue;
  const parts=[['aircraft_cnel','aircraft'],['community_cnel','community']].map(([k,n])=>num(r[k])===null?null:`${n} CNEL ${num(r[k])}`).filter(Boolean);
  out.push(feature([lng,lat],{evidence:'measured',kind:'SFO noise monitor',label:`SFO noise monitor ${id}`,cnel,observedOn:String(r.date).slice(0,10),detail:parts.join(' · '),caveat:CAVEATS.sfo,dataset:DATASETS.sfo}));
 }
 return out;
}

const q=(params)=>Object.entries(params).map(([k,v])=>`${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
async function rows(fetchFn,dataset,params){
 const r=await fetchFn(`${BASE}/${DATASETS[dataset]}.json?${q(params)}`);
 if(!r.ok)throw new Error(`DataSF ${DATASETS[dataset]} ${r.status}`);
 const body=await r.json();
 if(!Array.isArray(body))throw new Error(`DataSF ${DATASETS[dataset]} unexpected payload`);
 return body;
}
const collection=features=>({type:'FeatureCollection',features:features.filter(Boolean)});

/**
 * Loads every layer independently; a failing dataset is reported in `failed` and the rest still render.
 * @param {(url:string)=>Promise<{ok:boolean,status?:number,json:()=>Promise<unknown>}>} [fetchFn]
 * @param {Date} [now]
 * @returns {Promise<{candidates:any,proxies:any,measured:any,failed:string[]}>}
 */
export async function loadSfLayers(fetchFn=(url)=>fetch(url),now=new Date()){
 const today=localDate(now),tomorrow=localDate(new Date(now.getTime()+86400000));
 const utc=now.toISOString().slice(0,19);
 const since=new Date(now.getTime()-120*86400000).toISOString().slice(0,10);
 const jobs={
  candidates:async()=>collection([
   ...(await rows(fetchFn,'popos',{$select:'name,latitude,longitude,type,hours_type,indoor',$limit:'500'})).map(parsePopos),
   ...(await rows(fetchFn,'libraries',{$select:'common_name,latitude,longitude',$where:"common_name like '%Library%' OR common_name like '%Branch%'",$limit:'200'})).map(parseLibrary)]),
  proxies:async()=>{
   const [ent,night,closures]=await Promise.allSettled([
    rows(fetchFn,'entertainment',{$select:'dba_name,license_type,point',$where:"permit_status='Active' AND point IS NOT NULL",$limit:'2000'}),
    rows(fetchFn,'nightNoise',{$select:'nnp,type_of_work,start_date,end_date,start_end_time_each_day,address,point',$where:`start_date <= '${tomorrow}T23:59:59' AND end_date >= '${today}T00:00:00' AND point IS NOT NULL`,$limit:'1000'}),
    rows(fetchFn,'closures',{$select:'type,loc_desc,street,veh_imp,shape',$where:`status='Permitted' AND start_utc <= '${utc}' AND end_utc >= '${utc}'`,$limit:'1000'})]);
   if([ent,night,closures].every(x=>x.status==='rejected'))throw new Error('all proxy datasets failed');
   const ok=(x,f)=>x.status==='fulfilled'?x.value.map(f):[];
   return collection([...ok(ent,parseEntertainment),...ok(night,r=>parseNightNoise(r,now)),...ok(closures,parseClosure)]);
  },
  measured:async()=>collection(latestSfoMonitors(await rows(fetchFn,'sfo',{$select:'date,location_id,latitude,longitude,aircraft_cnel,community_cnel,total_cnel',$where:`location='San Francisco' AND date >= '${since}'`,$order:'date DESC',$limit:'2000'}))),
 };
 /** @type {Record<string,any>} */const out={};/** @type {string[]} */const failed=[];
 await Promise.all(Object.entries(jobs).map(async([name,job])=>{try{out[name]=await job()}catch{out[name]=collection([]);failed.push(name)}}));
 return {candidates:out.candidates,proxies:out.proxies,measured:out.measured,failed};
}
