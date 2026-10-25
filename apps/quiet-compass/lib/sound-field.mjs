// Live sound field for /venue from the server's public GET /v1/venue/sound_field, measured by one phone in its AR session.
// Positions are floor-plane metres (x right, z forward, arbitrary yaw). Levels are relative dBFS from that phone, never
// dB SPL or dBA, so the page only says quieter or louder. A cell with level_db null is unknown and is never drawn as quiet.
/** @typedef {{x:number,z:number}} XZ */
/** @typedef {{x:number,z:number,level_db:number|null,confidence:number}} FieldCell */
/** @typedef {{x:number,z:number,level_db:number,confidence:number,age_min:number,distance_m:number|null}} QuietSpot */
/** @typedef {{session_id:string|null,generated_at:string,cell_m:number|null,origin:XZ|null,cols:number,rows:number,level_range_db:[number,number]|null,cells:FieldCell[],samples:{x:number,z:number,level_db:number,age_min:number}[],path:XZ[],places:{id:string,label:string,x:number,z:number}[],user:XZ|null,quiet_spots:QuietSpot[],message:string|null}} SoundField */
/** @typedef {(x:number,y:number)=>[number,number]} ToLngLat */
/** @typedef {{type:'FeatureCollection',features:{type:'Feature',geometry:{type:'Point'|'LineString'|'Polygon',coordinates:any},properties:Record<string,any>}[]}} Features */

export const FIELD_PATH='/v1/venue/sound_field';
export const POLL_MS=10000;
const fin=v=>typeof v==='number'&&Number.isFinite(v);
const ok=p=>!!p&&fin(p.x)&&fin(p.z);
const list=v=>Array.isArray(v)?v:[];

/** Server origin from NEXT_PUBLIC_QC_SERVER_URL, or `?server=`. Null means no server: there is no field to show, and nothing is drawn in its place.
 * @param {string|undefined} env @param {string} search @returns {string|null} */
export function serverBase(env,search){
 for(const v of [new URLSearchParams(search||'').get('server'),env]){if(!v)continue;try{const u=new URL(v);if(u.protocol==='https:'||u.protocol==='http:')return (u.origin+u.pathname).replace(/\/+$/,'')}catch{/* not a URL */}}
 return null;
}
/** @param {unknown} j @returns {j is SoundField} */
export function isField(j){
 const f=/** @type {any} */(j);
 return !!f&&typeof f==='object'&&Array.isArray(f.cells)&&Array.isArray(f.samples)&&(!f.cells.length||fin(f.cell_m)&&f.cell_m>0);
}
/** Something to draw: a measured or unknown cell, a sample, the walked path or the user. @param {SoundField} f */
export const hasData=f=>f.cells.length>0||f.samples.length>0||list(f.path).length>0||ok(f.user);
/** The field, or null when the server does not serve it (404), fails or answers something else.
 * @param {string} base @param {typeof fetch} [get] @returns {Promise<SoundField|null>} */
export async function loadField(base,get=fetch){
 try{const r=await get(base+FIELD_PATH,{cache:'no-store',signal:AbortSignal.timeout(8000)});if(!r.ok)return null;const j=await r.json();return isField(j)?j:null}catch{return null}
}

/** 0 = quietest measured, 1 = loudest measured, -1 = unknown. A single reading (flat range) sits at .5.
 * @param {number|null|undefined} db @param {[number,number]|null|undefined} range */
export function relLevel(db,range){
 if(!fin(db))return -1;
 if(!range||!fin(range[0])||!fin(range[1])||range[1]-range[0]<.01)return .5;
 return Math.min(1,Math.max(0,(db-range[0])/(range[1]-range[0])));
}
/** @param {number|null|undefined} min */
export const ago=min=>!fin(min)?'':min<1?'just now':min<60?Math.round(min)+' min ago':Math.round(min/60)+' h ago';
/** @param {XZ} c */
export const cellKey=c=>'cell:'+c.x+','+c.z;
/** @param {XZ} s */
export const spotKey=s=>'spot:'+s.x+','+s.z;
const near=(rows,x,z)=>{let best=null,d=Infinity;for(const r of rows){const q=Math.hypot(r.x-x,r.z-z);if(ok(r)&&q<d){best=r;d=q}}return best?{...best,d}:null};

/** GeoJSON for each live source. `ll` is the page's metres-to-map conversion, so the field and the map share one.
 * @param {SoundField} f @param {ToLngLat} ll @returns {Record<'cells'|'path'|'samples'|'places'|'user'|'spots',Features>} */
export function fieldLayers(f,ll){
 const h=(f.cell_m||0)/2,range=f.level_range_db,path=list(f.path).filter(ok);
 /** @returns {Features} */
 const fc=features=>({type:'FeatureCollection',features});
 const pt=(x,z,properties)=>({type:'Feature',geometry:{type:'Point',coordinates:ll(x,z)},properties});
 return{
  cells:fc(f.cells.filter(ok).map(c=>({type:'Feature',geometry:{type:'Polygon',coordinates:[[ll(c.x-h,c.z-h),ll(c.x+h,c.z-h),ll(c.x+h,c.z+h),ll(c.x-h,c.z+h),ll(c.x-h,c.z-h)]]},properties:{key:cellKey(c),score:relLevel(c.level_db,range),confidence:fin(c.confidence)?Math.min(1,Math.max(0,c.confidence)):0}}))),
  path:fc(path.length>1?[{type:'Feature',geometry:{type:'LineString',coordinates:path.map(p=>ll(p.x,p.z))},properties:{}}]:[]),
  samples:fc(f.samples.filter(ok).map(s=>pt(s.x,s.z,{score:relLevel(s.level_db,range)}))),
  places:fc(list(f.places).filter(ok).map(p=>pt(p.x,p.z,{name:String(p.label||'Place')}))),
  user:fc(ok(f.user)?[pt(f.user.x,f.user.z,{})]:[]),
  spots:fc(list(f.quiet_spots).filter(ok).slice(0,3).map((s,i)=>pt(s.x,s.z,{key:spotKey(s),rank:String(i+1)}))),
 };
}
/** [[west,south],[east,north]] around the grid, the path, the places and the user; null when there is nothing.
 * @param {SoundField} f @param {ToLngLat} ll @returns {[[number,number],[number,number]]|null} */
export function fieldBounds(f,ll){
 const h=(f.cell_m||0)/2,xz=[...f.cells.filter(ok).flatMap(c=>[{x:c.x-h,z:c.z-h},{x:c.x+h,z:c.z+h}]),...f.samples,...list(f.path),...list(f.places),...(f.user?[f.user]:[])].filter(ok);
 if(!xz.length)return null;
 const a=ll(Math.min(...xz.map(p=>p.x)),Math.min(...xz.map(p=>p.z))),b=ll(Math.max(...xz.map(p=>p.x)),Math.max(...xz.map(p=>p.z)));
 return [a,b];
}
/** Bottom-left label and its tooltip. @param {SoundField} f */
export function liveLabel(f){
 const n=f.samples.length;
 return{label:n?'Live · measured '+n+(n===1?' spot':' spots'):'Live · no measurements yet',title:'Measured by one phone as it walked; refreshes every 10 s. Levels are relative to this phone, not calibrated dB. Grey = not measured.'+(f.message?' '+f.message:'')};
}
/** What the card says about a tapped cell or quiet spot, or null when the key is gone after a refresh.
 * @param {SoundField} f @param {string} key */
export function describe(f,key){
 const spots=list(f.quiet_spots),i=spots.findIndex(s=>spotKey(s)===key);
 if(i>=0){const s=spots[i];return{title:'Quiet spot '+(i+1),score:relLevel(s.level_db,f.level_range_db),confidence:s.confidence,detail:['measured '+ago(s.age_min),fin(s.distance_m)?Math.round(s.distance_m)+' m from you':''].filter(Boolean).join(' · ')}}
 const c=f.cells.find(q=>cellKey(q)===key);if(!c)return null;
 const place=near(list(f.places),c.x,c.z),sample=near(f.samples,c.x,c.z);
 return{title:place&&place.d<=3?String(place.label):'This spot',score:relLevel(c.level_db,f.level_range_db),confidence:fin(c.confidence)?c.confidence:0,detail:sample?'nearest reading '+ago(sample.age_min):''};
}
