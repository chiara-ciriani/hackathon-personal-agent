// Reported-noise density: REAL 311 noise complaints + police NOISE NUISANCE dispatches (DataSF), counted per grid area.
// This is a count of reports, not a sound level: no dB, no loudness. Areas with no reports are absent from the
// output (unknown, not quiet). Reports follow where people call, so the density also follows population and phone use.

export const WINDOW_HOURS=24; // same window the 311 and police-call loaders use
export const CELL_LAT=0.0025; // ~278 m
export const CELL_LNG=0.0032; // ~283 m at SF latitude
export const FIELD_NOTE='Reported noise: 311 noise complaints plus police NOISE NUISANCE calls, last 24 hours, counted per ~280 m area at the locations as published (calls use masked intersections). Counts of reports, not dB and not measured loudness. Areas without colour have no reports: unknown, not quiet.';
export const FILTER_NOTE='Splits the coloured areas into thirds by number of reports in the last 24 hours. It ranks areas against each other; it says nothing about decibels. Areas with no reports are unknown and never count as quiet.';
export const FIELD_SOURCES='Real data: DataSF (311 cases, SFPD dispatch, permits, parks), SFO monitors, shared phone readings.';

const num=v=>{const n=Number.parseFloat(String(v));return Number.isFinite(n)?n:null};
const inSf=(lat,lng)=>lat!==null&&lng!==null&&lat>=37.6&&lat<=37.85&&lng>=-122.55&&lng<=-122.3;
const localDate=d=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Los_Angeles'}).format(d);

const cellKey=(lng,lat)=>`${Math.floor(lng/CELL_LNG)},${Math.floor(lat/CELL_LAT)}`;
const quantile=(sorted,p)=>sorted[Math.min(sorted.length-1,Math.max(0,Math.ceil(sorted.length*p)-1))];

/**
 * Counts reports per grid cell. `reports` are 311 point features (weight 1 each); `cadAreas` are the cadNoiseAreas()
 * features (weight = their `count` of calls at that masked intersection). Cells with zero reports are not emitted.
 * Level is relative: terciles of the non-empty cells (few / some / many). `t` (0..1) drives the colour ramp.
 * @returns {{collection:{type:string,features:any[]},total:number,cells:number,thresholds:[number,number],cap:number}}
 */
export function buildReportField(reports,cadAreas=[]){
 const cells=new Map();
 const add=(f,kind,w)=>{const c=f?.geometry?.coordinates;if(!Array.isArray(c))return;const lng=num(c[0]),lat=num(c[1]);if(!inSf(lat,lng)||!(w>0))return;
  const k=cellKey(lng,lat),cell=cells.get(k)||cells.set(k,{ix:Math.floor(lng/CELL_LNG),iy:Math.floor(lat/CELL_LAT),r311:0,cad:0}).get(k);cell[kind]+=w};
 for(const f of reports||[])add(f,'r311',1);
 for(const f of cadAreas||[])add(f,'cad',Math.max(0,Math.round(Number(f?.properties?.count)||0)));
 const list=[...cells.values()].map(c=>({...c,n:c.r311+c.cad})).filter(c=>c.n>0);
 const total=list.reduce((s,c)=>s+c.n,0);
 if(!list.length)return {collection:{type:'FeatureCollection',features:[]},total:0,cells:0,thresholds:[0,0],cap:1};
 const sorted=list.map(c=>c.n).sort((a,b)=>a-b);
 const t1=quantile(sorted,1/3),t2=quantile(sorted,2/3),cap=Math.max(1,quantile(sorted,.95));
 const features=list.map(c=>{
  const w=c.ix*CELL_LNG,s=c.iy*CELL_LAT,e=w+CELL_LNG,nn=s+CELL_LAT;
  const level=c.n<=t1?'few':c.n<=t2?'some':'many';
  return {type:'Feature',geometry:{type:'Polygon',coordinates:[[[w,s],[e,s],[e,nn],[w,nn],[w,s]]]},properties:{n:c.n,r311:c.r311,cad:c.cad,level,t:Math.round(Math.min(1,Math.sqrt(c.n/cap))*1000)/1000,hours:WINDOW_HOURS}};
 });
 return {collection:{type:'FeatureCollection',features},total,cells:list.length,thresholds:[t1,t2],cap};
}

/** Short text for a field-cell popup. Always says what the number is, and what it is not. */
export function describeCell(p){
 const parts=[];if(p.r311)parts.push(`${p.r311} 311 complaint${p.r311===1?'':'s'}`);if(p.cad)parts.push(`${p.cad} police noise-nuisance call${p.cad===1?'':'s'}`);
 return `REPORTED NOISE · ${p.n} report${p.n===1?'':'s'} in this ~280 m area, last ${p.hours||WINDOW_HOURS} hours (${parts.join(' + ')}). Complaints and calls, not dB and not measured loudness; they follow where people report.`;
}
