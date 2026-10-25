// Real San Francisco layers from DataSF, mirrored from server/quiet_compass/sf_layers.py.
// Every layer carries an `evidence` label: measured | measured_crowdsourced | proxy | unmeasured_candidate.
// Only the SFO monitors (CNEL and aircraft exceedance events) are sensor measurements; NoiseCapture cells are
// crowdsourced, uncalibrated phone measurements. Nothing here is a reading from this app's phone.
// Dataset ids were checked against the live Socrata API on 2026-10-24.
export const BASE='https://data.sf.gov/resource';
export const DATASETS={popos:'65ik-7wqd',libraries:'fhhu-wqa7',entertainment:'86e8-rfem',nightNoise:'e7pr-36bt',closures:'8x25-yybr',streetWork:'x8nh-xzn6',sfo:'qxw2-ncq3',sfoEvents:'tiju-qyvs',parks:'gtr9-ntp6',cad:'2zdj-bwza'};
export const NOISECAPTURE_URL='/data/noisecapture-sf.json';
export const PARK_TYPES=['Neighborhood Park or Playground','Mini Park','Regional Park','Civic Plaza or Square','Parkway','Community Garden'];
export const CAVEATS={
 candidate:'Unmeasured candidate from a city inventory. Nobody has measured its sound; check hours and conditions.',
 entertainment:'Active entertainment permit: a proxy for possible amplified sound, not a level.',
 nightNoise:'Night-work permit scheduled today or tomorrow: a proxy for temporary noise, not a level.',
 closure:'SFMTA street closure in effect now: a proxy, not a sound level.',
 streetWork:'Public Works permit for excavation, boring, street or sewer work, valid today. Permits often span weeks or months, so work may not be happening right now: a proxy for possible daytime construction noise, not a level.',
 sfoEvents:'Aircraft noise exceedance events at an SFO monitor (max level in dBA per event, last 365 days). Only events above that monitor\'s own threshold are published, so this is the loud events, not the typical level. Measured at the monitor, published monthly; read it with its date. The portal declares no license for this dataset.',
 park:'Unmeasured candidate from a city inventory. Nobody has measured its sound; parks and play areas can be busy and loud at times.',
 cad:'Closed police dispatches classified NOISE NUISANCE at this published (masked) intersection, last 24 hours: complaints, not measurements. The city publishes closed calls about a day late, so the newest may be missing.',
 crowd:'Crowdsourced NoiseCapture phone measurements, mostly uncalibrated (several dB of error), 2017-2025, where volunteers walked; not live. Contains information from the NoiseCapture / Noise-Planet community, ODbL 1.0.',
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
export const REFERENCE_NOTE='Ldn in dBA from a 2016 environmental review, Central SoMa only (main streets averaged 75, alleys 63-67). Old, area-specific context: not today\'s level.';

const num=v=>{if(v===null||v===undefined||typeof v==='boolean'||String(v).trim()==='')return null;const n=Number(v);return Number.isFinite(n)?n:null};
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
// SF local timestamp (Socrata floating time), e.g. 2026-10-23T17:00:00.
const sfLocal=d=>new Date(d.toLocaleString('en-US',{timeZone:'America/Los_Angeles'})).toLocaleString('sv-SE').replace(' ','T');
export function parseNightNoise(row,now){
 const c=fromPoint(row),status=String(row.nnp||'').trim().toUpperCase();
 const start=String(row.start_date||'').slice(0,10),end=String(row.end_date||'').slice(0,10);
 if(!c||!start||!end||['DENIED','WITHDRAWN','PENDING'].includes(status))return null;
 const today=localDate(now),tomorrow=localDate(new Date(now.getTime()+86400000));
 if(Number(end.slice(0,4))>2100||start>tomorrow||end<today)return null; // the source has bogus far-future end dates
 const detail=[row.type_of_work,`${start} to ${end}`,row.start_end_time_each_day].filter(Boolean).join(' · ');
 return feature(c,{evidence:'proxy',kind:'Night-work permit',label:String(row.address||'Night work permit'),detail,caveat:CAVEATS.nightNoise,dataset:DATASETS.nightNoise});
}
// Street-use permit types that mean digging or heavy street work. NightNoise is left out: e7pr-36bt covers night work.
export const STREET_WORK_TYPES={Excavation:'Excavation',ExcStreet:'Street excavation',Boring:'Boring',StrtImprov:'Street improvement',SideSewer:'Sewer work'};
export function parseStreetWork(row,now){
 const c=fromPoint({point:row.location}),kind=STREET_WORK_TYPES[row.permit_type];
 const start=String(row.permit_start_date||'').slice(0,10),end=String(row.permit_end_date||'').slice(0,10),today=localDate(now);
 if(!c||!kind||!start||!end||start>today||end<today)return null;
 const street=String(row.streetname||'').trim(),crosses=[row.cross_street_1,row.cross_street_2].filter(Boolean).map(x=>String(x).trim());
 const label=street?(crosses.length===2?`${street} between ${crosses[0]} and ${crosses[1]}`:crosses.length?`${street} at ${crosses[0]}`:street):'Street work';
 return feature(c,{evidence:'proxy',kind:'Street work permit',label,detail:`${kind} · until ${end}`,caveat:CAVEATS.streetWork,dataset:DATASETS.streetWork});
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

export function parsePark(row){
 const lat=num(row.latitude),lng=num(row.longitude),name=String(row.property_name||'').trim(),type=String(row.propertytype||'').trim();
 if(!name||!PARK_TYPES.includes(type)||!inSf(lat,lng))return null;
 const acres=num(row.acres);
 return feature([lng,lat],{evidence:'unmeasured_candidate',source:'seed',kind:'Park',label:name,detail:[type,acres===null?null:`${acres.toFixed(1)} acres`].filter(Boolean).join(' · '),caveat:CAVEATS.park,dataset:DATASETS.parks});
}
const median=a=>{const s=[...a].sort((x,y)=>x-y),m=s.length>>1;return s.length%2?s[m]:(s[m-1]+s[m])/2};
/** Per-monitor summary of exceedance events. Coordinates come from the qxw2-ncq3 monitor rows; no coordinates, no point. */
export function sfoEventMonitors(monitors,events,windowDays=365){
 const coords=new Map();
 for(const m of monitors){const id=String(m.location_id||''),lat=num(m.latitude),lng=num(m.longitude);if(id&&inSf(lat,lng))coords.set(id,[lng,lat])}
 const levels=new Map(),latest=new Map();
 for(const e of events){const id=String(e.location_id||''),lvl=num(e.max_level),when=String(e.max_date_time||'');
  if(!coords.has(id)||lvl===null||!when)continue;
  (levels.get(id)||levels.set(id,[]).get(id)).push(lvl);if(when>(latest.get(id)||''))latest.set(id,when)}
 return [...levels].sort((a,b)=>a[0].length-b[0].length||a[0].localeCompare(b[0])).map(([id,v])=>{const on=latest.get(id).slice(0,10);
  return feature(coords.get(id),{evidence:'measured',kind:'SFO exceedance events',label:`SFO noise monitor ${id}`,count:v.length,maxDb:Math.round(Math.max(...v)*10)/10,medianDb:Math.round(median(v)*10)/10,observedOn:on,detail:`${v.length} events in the last ${windowDays} days; latest ${on}`,caveat:CAVEATS.sfoEvents,dataset:DATASETS.sfoEvents})});
}
/** NOISE NUISANCE dispatches counted per published (masked) intersection; sensitive and duplicate rows are dropped. */
export function cadNoiseAreas(rows,windowHours=24){
 const seen=new Set(),groups=new Map();
 for(const r of rows){if(r.sensitive_call===true)continue;
  const cad=String(r.cad_number||''),c=fromPoint({point:r.intersection_point});
  if(!c||(cad&&seen.has(cad)))continue;seen.add(cad);
  const k=c.map(v=>v.toFixed(5)).join(',');(groups.get(k)||groups.set(k,{c,items:[]}).get(k)).items.push([String(r.received_datetime||'').slice(0,10),String(r.intersection_name||'').trim()])}
 return [...groups.values()].map(({c,items})=>{const last=items.map(i=>i[0]).sort().at(-1);
  return feature(c,{evidence:'proxy',kind:'Noise-nuisance calls',label:(items.find(i=>i[1])?.[1]||'Intersection').replace(/\\/g,'/'),count:items.length,observedOn:last,detail:`${items.length} calls in the last ${windowHours} hours (masked intersection); latest ${last}`,caveat:CAVEATS.cad,dataset:DATASETS.cad})});
}
/** Cells produced offline by server/quiet_compass/noisecapture.py (ODbL). Cells without numbers are skipped. */
export function noisecaptureCells(collection){
 const out=[];
 for(const f of collection?.features||[]){const c=f?.geometry?.coordinates,p=f?.properties||{};
  if(!Array.isArray(c)||c.length<2)continue;
  const lng=num(c[0]),lat=num(c[1]),med=num(p.median_window_db),laeq=num(p.laeq_db);
  if(!inSf(lat,lng)||med===null||laeq===null)continue;
  const split=Object.entries(p.periods||{}).map(([k,v])=>`${k} ${v.laeq_db} dB`).join(', ');
  out.push(feature([lng,lat],{evidence:'measured_crowdsourced',quality:'measured_crowdsourced_uncalibrated',kind:'NoiseCapture cell',label:`NoiseCapture cell (~${p.cell_m||100} m)`,medianDb:med,laeqDb:laeq,windows:p.windows,tracks:p.tracks,observedOn:String(p.last_date||''),detail:`${p.windows} five-minute windows from ${p.tracks} tracks, ${p.first_date} to ${p.last_date}${split?'; '+split:''}`,caveat:CAVEATS.crowd,dataset:'noise-planet.org/dump'}))}
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
 * Result sources: candidates (POPOS, libraries, parks), proxies (permits, closures), measured (SFO CNEL),
 * sfoEvents (SFO exceedance summaries), cad (noise-nuisance call counts), crowd (NoiseCapture cells).
 * @param {(url:string)=>Promise<{ok:boolean,status?:number,json:()=>Promise<unknown>}>} [fetchFn]
 * @param {Date} [now]
 * @returns {Promise<{candidates:any,proxies:any,measured:any,sfoEvents:any,cad:any,crowd:any,failed:string[]}>}
 */
export async function loadSfLayers(fetchFn=(url)=>fetch(url,{cache:'no-store',signal:AbortSignal.timeout(12000)}),now=new Date()){
 const today=localDate(now),tomorrow=localDate(new Date(now.getTime()+86400000));
 const utc=now.toISOString().slice(0,19);
 const since=new Date(now.getTime()-120*86400000).toISOString().slice(0,10);
 const eventsSince=localDate(new Date(now.getTime()-365*86400000)),cadSince=sfLocal(new Date(now.getTime()-24*3600000));
 /** @type {string[]} */const partial=[];
 const jobs={
  candidates:async()=>{
   const [popos,libs,parks]=await Promise.allSettled([
    rows(fetchFn,'popos',{$select:'name,latitude,longitude,type,hours_type,indoor',$limit:'500'}),
    rows(fetchFn,'libraries',{$select:'common_name,latitude,longitude',$where:"common_name like '%Library%' OR common_name like '%Branch%'",$limit:'200'}),
    rows(fetchFn,'parks',{$select:'property_name,latitude,longitude,propertytype,acres',$where:`propertytype in(${PARK_TYPES.map(t=>`'${t}'`).join(',')})`,$limit:'500'})]);
   if([popos,libs,parks].every(x=>x.status==='rejected'))throw new Error('all candidate datasets failed');
   [['popos',popos],['libraries',libs],['parks',parks]].forEach(([n,x])=>{if(x.status==='rejected')partial.push(n)});
   const ok=(x,f)=>x.status==='fulfilled'?x.value.map(f):[];
   return collection([...ok(popos,parsePopos),...ok(libs,parseLibrary),...ok(parks,parsePark)]);
  },
  proxies:async()=>{
   const [ent,night,closures,work]=await Promise.allSettled([
    rows(fetchFn,'entertainment',{$select:'dba_name,license_type,point',$where:"permit_status='Active' AND point IS NOT NULL",$limit:'2000'}),
    rows(fetchFn,'nightNoise',{$select:'nnp,type_of_work,start_date,end_date,start_end_time_each_day,address,point',$where:`start_date <= '${tomorrow}T23:59:59' AND end_date >= '${today}T00:00:00' AND point IS NOT NULL`,$limit:'1000'}),
    rows(fetchFn,'closures',{$select:'type,loc_desc,street,veh_imp,shape',$where:`status='Permitted' AND start_utc <= '${utc}' AND end_utc >= '${utc}'`,$limit:'1000'}),
    rows(fetchFn,'streetWork',{$select:'permit_type,streetname,cross_street_1,cross_street_2,permit_start_date,permit_end_date,location',$where:`permit_type in(${Object.keys(STREET_WORK_TYPES).map(t=>`'${t}'`).join(',')}) AND permit_start_date <= '${today}T23:59:59' AND permit_end_date >= '${today}T00:00:00' AND location IS NOT NULL`,$limit:'6000'})]);
   if([ent,night,closures,work].every(x=>x.status==='rejected'))throw new Error('all proxy datasets failed');
   [['entertainment',ent],['nightNoise',night],['closures',closures],['streetWork',work]].forEach(([n,x])=>{if(x.status==='rejected')partial.push(n)});
   const ok=(x,f)=>x.status==='fulfilled'?x.value.map(f):[];
   return collection([...ok(ent,parseEntertainment),...ok(night,r=>parseNightNoise(r,now)),...ok(closures,parseClosure),...ok(work,r=>parseStreetWork(r,now))]);
  },
  measured:async()=>collection(latestSfoMonitors(await rows(fetchFn,'sfo',{$select:'date,location_id,latitude,longitude,aircraft_cnel,community_cnel,total_cnel',$where:`location='San Francisco' AND date >= '${since}'`,$order:'date DESC',$limit:'2000'}))),
  sfoEvents:async()=>{
   // Coordinates are joined from the qxw2-ncq3 monitor rows; if they cannot be joined there is nothing to plot.
   const monitors=await rows(fetchFn,'sfo',{$select:'location_id,latitude,longitude',$where:"location='San Francisco'",$group:'location_id,latitude,longitude',$limit:'100'});
   const ids=[...new Set(monitors.map(m=>String(m.location_id||'')).filter(Boolean))].sort();
   if(!ids.length)throw new Error('no SF monitors with coordinates');
   const events=await rows(fetchFn,'sfoEvents',{$select:'location_id,max_date_time,max_level',$where:`location_id in(${ids.map(i=>`'${i}'`).join(',')}) AND max_date_time >= '${eventsSince}T00:00:00'`,$order:'max_date_time DESC',$limit:'5000'});
   return collection(sfoEventMonitors(monitors,events));
  },
  cad:async()=>collection(cadNoiseAreas(await rows(fetchFn,'cad',{$select:'cad_number,received_datetime,intersection_name,intersection_point,sensitive_call',$where:`call_type_final_desc='NOISE NUISANCE' AND intersection_point IS NOT NULL AND received_datetime >= '${cadSince}'`,$limit:'5000'})))
  ,
  crowd:async()=>{
   const r=await fetchFn(NOISECAPTURE_URL);
   if(!r.ok)throw new Error(`NoiseCapture cells ${r.status}`);
   return collection(noisecaptureCells(await r.json()));
  },
 };
 /** @type {Record<string,any>} */const out={};/** @type {string[]} */const failed=[];
 await Promise.all(Object.entries(jobs).map(async([name,job])=>{try{out[name]=await job()}catch{out[name]=collection([]);failed.push(name)}}));
 const order=Object.keys(jobs);
 failed.sort((a,b)=>order.indexOf(a)-order.indexOf(b));
 return {candidates:out.candidates,proxies:out.proxies,measured:out.measured,sfoEvents:out.sfoEvents,cad:out.cad,crowd:out.crowd,failed:[...failed,...partial]};
}
