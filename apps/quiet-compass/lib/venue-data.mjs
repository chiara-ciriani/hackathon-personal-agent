// Venue sound state from REAL released observations only. The server's public shared sound layer (consented device
// contributions, relative uncalibrated dBFS) reaches the page through /api/map as GeoJSON points that carry an `areaId`.
// A venue is "venue:<venue id>" and a zone inside it "venue:<venue id>:<zone>". Anything else is not a venue reading.
// No layout, level or zone is invented here: a venue or zone with no released observation is `none` (grey, "No measurements yet").

export const AREA_PREFIX='venue:';
const fin=v=>typeof v==='number'&&Number.isFinite(v);

/** Fetch the released device readings. Never throws and never returns a made-up value. @returns {Promise<{state:'ok'|'failed',features:any[]}>} */
export async function loadVenueReadings(fetchFn=(u,o)=>fetch(u,o)){
 try{
  const res=await fetchFn('/api/map',{cache:'no-store'});
  if(!res.ok)throw new Error('http '+res.status);
  const body=await res.json();
  const features=Array.isArray(body?.device?.features)?body.device.features:[];
  return{state:'ok',features};
 }catch{return{state:'failed',features:[]}}
}

/** Readings for one venue (the venue itself and its zones), newest bucket per area and capture profile.
 * @param {string} venueId @param {any[]} features @returns {{zone:string,name:string,dbfs:number,n:number,profile:string,observedOn:string}[]} */
export function venueReadings(venueId,features){
 const own=AREA_PREFIX+venueId;
 const latest=new Map();
 for(const f of features||[]){
  const p=f?.properties;
  if(!p||typeof p.areaId!=='string'||!fin(p.dbfs)||p.evidence!=='measured_device'||typeof p.captureProfile!=='string')continue;
  if(p.areaId!==own&&!p.areaId.startsWith(own+':'))continue;
  const key=p.areaId+'\u0000'+p.captureProfile;
  const prev=latest.get(key);
  if(!prev||Date.parse(p.observedOn)>Date.parse(prev.observedOn))latest.set(key,p);
 }
 return[...latest.values()].map(p=>({zone:p.areaId.slice(own.length+1),name:String(p.label||p.areaId),dbfs:p.dbfs,n:Number.isFinite(p.count)?p.count:1,profile:p.captureProfile,observedOn:String(p.observedOn)}));
}

/** status: none | single (measured, nothing to compare against) | ranked (relative 0 = quietest, 1 = loudest, same capture profile only).
 * Readings made with a different capture profile are listed but never compared. */
export function rankReadings(readings){
 if(!readings.length)return{status:'none',profile:null,zones:[]};
 const byProfile=new Map();
 for(const r of readings){if(!byProfile.has(r.profile))byProfile.set(r.profile,[]);byProfile.get(r.profile).push(r)}
 let profile=null,best=null;
 for(const [p,list] of byProfile){
  const newest=Math.max(...list.map(r=>Date.parse(r.observedOn)||0));
  if(!best||list.length>best.n||(list.length===best.n&&newest>best.newest)){best={n:list.length,newest};profile=p}
 }
 const chosen=byProfile.get(profile),levels=chosen.map(r=>r.dbfs),lo=Math.min(...levels),hi=Math.max(...levels);
 const zones=readings.map(r=>r.profile!==profile?{...r,status:'single',otherProfile:true}:chosen.length>=2?{...r,status:'ranked',relative:hi===lo?.5:(r.dbfs-lo)/(hi-lo)}:{...r,status:'single'});
 zones.sort((a,b)=>(a.relative??2)-(b.relative??2)||a.name.localeCompare(b.name));
 return{status:chosen.length>=2?'ranked':'single',profile,zones};
}

export const levelOf=r=>r>.65?'higher':r>.35?'middle':'lower';

/** Map pin for a venue: grey (no measurement) unless a released reading exists for it. Adds a value only from that reading. */
export function venuePin(base,venueId,features){
 const own=venueReadings(venueId,features).filter(r=>r.zone==='');
 if(!own.length)return base;
 const r=own.reduce((a,b)=>Date.parse(b.observedOn)>Date.parse(a.observedOn)?b:a);
 return{...base,evidence:'measured_device',kind:'Device measurement',dbfs:r.dbfs,count:r.n,captureProfile:r.profile,observedOn:r.observedOn,
  detail:`${r.n} contributions · ${r.profile}`,caveat:'Relative, uncalibrated dBFS. Compare only within the same capture profile. Not dBA.'};
}
