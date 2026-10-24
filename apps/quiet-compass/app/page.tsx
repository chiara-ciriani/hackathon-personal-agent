'use client';
import {useEffect,useRef,useState} from 'react';
import {Check,Compass,Copy,Layers,Plug,Users,Minus,Plus,RotateCcw,X} from 'lucide-react';
import type {StyleSpecification} from 'maplibre-gl';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';
import {loadSfLayers} from '../lib/sf-layers.mjs';

// Illustrative locations and synthetic acoustic scores; no real noise measurements.
type MapPoint={name:string;lng:number;lat:number;score:number;landmark?:boolean};
const points:MapPoint[]=[
 {name:'Washington Square',lng:-122.4102,lat:37.8007,score:.48},
 {name:'Portsmouth Square',lng:-122.4057,lat:37.7945,score:.71},
 {name:'Transamerica Pyramid',lng:-122.4030,lat:37.7952,score:.28,landmark:true},
 {name:'Sydney G. Walton Square',lng:-122.3997,lat:37.7972,score:.35},
 {name:'Ferry Building',lng:-122.3937,lat:37.7955,score:.79,landmark:true},
 {name:'Huntington Park',lng:-122.4120,lat:37.7917,score:.38},
 {name:'Union Square',lng:-122.4075,lat:37.7879,score:.92},
 {name:'Salesforce Park',lng:-122.3967,lat:37.7891,score:.32},
 {name:'Yerba Buena Gardens',lng:-122.4023,lat:37.7854,score:.60},
 {name:'Rincon Park',lng:-122.3892,lat:37.7891,score:.51},
 {name:'North Beach',lng:-122.4078,lat:37.8019,score:.69},
 {name:'Fort Mason',lng:-122.4320,lat:37.8064,score:.37},
 {name:'Marina Green',lng:-122.4377,lat:37.8055,score:.22},
 {name:'Presidio',lng:-122.4580,lat:37.7980,score:.18},
 {name:'Alamo Square',lng:-122.4346,lat:37.7764,score:.43},
 {name:'Dolores Park',lng:-122.4269,lat:37.7598,score:.64},
 {name:'Golden Gate Park',lng:-122.4662,lat:37.7694,score:.21},
 {name:'Bernal Heights',lng:-122.4147,lat:37.7431,score:.26},
 {name:'Ocean Beach',lng:-122.5093,lat:37.7594,score:.42},
 {name:'Richmond',lng:-122.4750,lat:37.7812,score:.46},
 {name:'Sunset',lng:-122.4834,lat:37.7565,score:.31},
 {name:'Civic Center',lng:-122.4178,lat:37.7793,score:.85},
 {name:'Mission',lng:-122.4194,lat:37.7580,score:.82},
 {name:'Castro',lng:-122.4350,lat:37.7624,score:.67},
 {name:'Potrero Hill',lng:-122.3985,lat:37.7574,score:.39},
 {name:'City Hall',lng:-122.4193,lat:37.7793,score:.61,landmark:true},
 {name:'Coit Tower',lng:-122.4058,lat:37.8024,score:.36,landmark:true},
 {name:'Salesforce Tower',lng:-122.3965,lat:37.7898,score:.73,landmark:true},
 {name:'Oracle Park',lng:-122.3893,lat:37.7786,score:.88,landmark:true},
 {name:'de Young Museum',lng:-122.4687,lat:37.7715,score:.24,landmark:true},
 {name:'Mission Bay',lng:-122.3895,lat:37.7721,score:.75},
];
// Extra synthetic samples around each place so the sound field reads as a continuous surface, not as dots. Seeded, so it never changes between loads.
function rng(seed:number){return()=>{seed|=0;seed=seed+0x6D2B79F5|0;let t=Math.imul(seed^seed>>>15,1|seed);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
const rand=rng(7);
const field=points.flatMap(p=>Array.from({length:16},()=>{const a=rand()*6.283,d=.0006+rand()*.0068;return{lng:p.lng+Math.cos(a)*d*1.25,lat:p.lat+Math.sin(a)*d,score:Math.min(1,Math.max(.05,p.score+(rand()-.5)*.4))}})).filter(q=>q.lng<-122.3885&&q.lng>-122.512);
const toFeatures=(rows:{lng:number;lat:number;score:number}[])=>rows.map(p=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[p.lng,p.lat]},properties:{score:p.score}}));
const soundData={type:'FeatureCollection' as const,features:toFeatures([...points,...field])};
// Real SF 311 noise complaints (DataSF). These are reports, not measurements, so they get their own neutral style.
const reportsUrl="https://data.sf.gov/resource/vw6y-z8j6.json?$where=service_name in ('Noise','Noise Report')&$order=requested_datetime DESC&$limit=100";
type NoiseReport={service_request_id:string;requested_datetime:string;service_subtype?:string;neighborhoods_sffind_boundaries?:string;lat?:string;long?:string};
async function loadReports(){
 const r=await fetch(encodeURI(reportsUrl));if(!r.ok)throw new Error('311 unavailable');
 const rows=await r.json() as NoiseReport[];
 return {type:'FeatureCollection' as const,features:rows.filter(x=>Number(x.lat)&&Number(x.long)).map(x=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[Number(x.long),Number(x.lat)]},properties:{kind:(x.service_subtype||'noise').replace(/_/g,' '),place:x.neighborhoods_sffind_boundaries||'',at:x.requested_datetime}}))};
}
function ago(at:string){const m=Math.round((Date.now()-new Date(at+'-07:00').getTime())/60000);return m<60?m+' min ago':m<1440?Math.round(m/60)+' h ago':Math.round(m/1440)+' d ago'}
const noiseRamp:import('maplibre-gl').ExpressionSpecification=['interpolate',['linear'],['get','score'],0,'#e6dcff',.3,'#b996f5',.55,'#8a45e8',.8,'#5a14b0',1,'#2b0a63'];
const mapStyle:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},focus:{type:'geojson',data:{type:'FeatureCollection',features:[]}},sound:{type:'geojson',data:soundData},reports:{type:'geojson',data:{type:'FeatureCollection',features:[]}},measured:{type:'geojson',data:{type:'FeatureCollection',features:[]}},proxies:{type:'geojson',data:{type:'FeatureCollection',features:[]}},candidates:{type:'geojson',data:{type:'FeatureCollection',features:[]}}},
 light:{anchor:'viewport',color:'#ffffff',intensity:.4,position:[1.5,205,40]},
 layers:[
  {id:'background',type:'background',paint:{'background-color':'#ffffff'}},
  {id:'land',type:'fill',source:'city','source-layer':'landcover',paint:{'fill-color':'#f3f2f5','fill-opacity':.6}},
  {id:'parks',type:'fill',source:'city','source-layer':'park',paint:{'fill-color':'#f0f0f1','fill-outline-color':'#e8e8eb'}},
  {id:'water',type:'fill',source:'city','source-layer':'water',paint:{'fill-color':'#f6f6f7'}},
  {id:'roads-edge',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#e1e1e5','line-width':['interpolate',['linear'],['zoom'],11,.3,13,.8,16,5,19,20]}},
  {id:'roads',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#ffffff','line-width':['interpolate',['linear'],['zoom'],11,.1,13,.25,16,3.6,19,17]}},
  {id:'footprints',type:'fill',source:'city','source-layer':'building',paint:{'fill-color':'#eae7ed','fill-outline-color':'#dfdbe5'}},
  {id:'structures',type:'fill-extrusion',source:'city','source-layer':'building',minzoom:12.6,filter:['!=',['get','hide_3d'],true],paint:{'fill-extrusion-color':'#f7f6f9','fill-extrusion-height':['interpolate',['linear'],['zoom'],12.6,0,14.2,['*',1.25,['coalesce',['get','render_height'],8]]],'fill-extrusion-base':['coalesce',['get','render_min_height'],0],'fill-extrusion-opacity':1,'fill-extrusion-vertical-gradient':true}},
  // Color encodes noise score, not the number of contributors. No density heatmap.
  {id:'sound-fields',type:'circle',source:'sound',paint:{'circle-color':noiseRamp,'circle-radius':['interpolate',['linear'],['zoom'],11,14,13,36,16,100,19,190],'circle-blur':1,'circle-opacity':.5,'circle-pitch-alignment':'map'}},
  {id:'place-labels',type:'symbol',source:'city','source-layer':'place',minzoom:11,filter:['in',['get','class'],['literal',['suburb','neighbourhood','quarter']]],layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],11,10,15,13],'text-letter-spacing':.08,'text-transform':'uppercase'},paint:{'text-color':'#6b6b73','text-halo-color':'#ffffff','text-halo-width':1.5}},
  {id:'focus-ring',type:'circle',source:'focus',paint:{'circle-radius':16,'circle-color':'#ffffff00','circle-stroke-color':'#171717','circle-stroke-width':2,'circle-pitch-alignment':'viewport'}},
  // Real layers stay out of the violet scale: ink for measured, grays for the rest. Violet is reserved for the synthetic sound score.
  {id:'proxy-context',type:'circle',source:'proxies',minzoom:13,layout:{visibility:'none'},paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],13,1.8,17,4],'circle-stroke-color':'#ffffff','circle-stroke-width':1,'circle-opacity':.85}},
  {id:'candidate-places',type:'circle',source:'candidates',minzoom:12,paint:{'circle-color':'#ffffff','circle-radius':['interpolate',['linear'],['zoom'],12,3,17,6],'circle-stroke-color':'#171717','circle-stroke-width':1.5}},
  {id:'noise-reports',type:'circle',source:'reports',minzoom:13,paint:{'circle-color':'#52525b','circle-radius':['interpolate',['linear'],['zoom'],13,1.6,17,3.4],'circle-opacity':.6}},
  {id:'measured-sfo',type:'circle',source:'measured',paint:{'circle-color':'#171717','circle-radius':['interpolate',['linear'],['zoom'],11,5,16,9],'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
 ]
};
// A contribution carries only a coarse zone, a level and a rounded time. No agent id, no audio, no route.
type LayerKey='demo'|'measured'|'proxies'|'candidates'|'reports';
const layerRows:{key:LayerKey;label:string;tag:string;swatch:string;mapIds:string[];hint:string}[]=[
 {key:'measured',label:'Airport monitors',tag:'measured',swatch:'measured',mapIds:['measured-sfo'],hint:'Daily CNEL in dB at 6 monitors inside SF. Not live, not at your spot.'},
 {key:'proxies',label:'Permits & closures',tag:'indirect',swatch:'proxy',mapIds:['proxy-context'],hint:'Entertainment permits, night work today or tomorrow, street closures now. Possible noise, not levels.'},
 {key:'candidates',label:'Parks & libraries',tag:'unmeasured',swatch:'candidate',mapIds:['candidate-places'],hint:'Places from city inventories that might be calm. Nobody has measured them.'},
 {key:'reports',label:'311 complaints',tag:'reports',swatch:'report',mapIds:['noise-reports'],hint:'Recent reports. A complaint is not a measurement.'},
 {key:'demo',label:'Simulated noise',tag:'demo',swatch:'demo',mapIds:['sound-fields'],hint:'Invented scores for illustration. Not measurements.'},
];
type Entry={id:number;t:number;zone:string;level:Level};
const bucket=(t:number)=>{const m=Math.max(0,Math.round((Date.now()-t)/300000))*5;return m<5?'just now':m<60?m+' min ago':Math.round(m/60)+' h ago'};
const makeEntry=(i:number,ago=0):Entry=>({id:Date.now()+Math.random(),t:Date.now()-ago*60000,zone:points[i].name,level:levelOf(points[i].score)});
type Level='quiet'|'moderate'|'loud';
const levelOf=(score:number):Level=>score>.65?'loud':score>.35?'moderate':'quiet';
const filters:{id:Level|'all';label:string}[]=[{id:'all',label:'All'},{id:'quiet',label:'Quiet'},{id:'moderate',label:'Moderate'},{id:'loud',label:'Loud'}];
const home={center:[-122.44,37.768] as [number,number],zoom:12.6,pitch:48,bearing:-12};
const contract={name:'quiet-compass',status:'proposal',connected:false,data:'synthetic-demo + real DataSF layers (labelled measured / proxy / unmeasured candidate)',tools:[{name:'quiet_sf_layers',input:{lat:'number',lon:'number',radius_m:'50-2000',include:'quiet_candidates | entertainment_permits | night_noise_permits | street_closures | sfo_cnel',include_references:'boolean'},returns:'points with evidence = measured | proxy | unmeasured_candidate (source seed), optional reference_measured table'},{name:'query_sound_map',input:{bounds:'[west,south,east,north]',max_age_minutes:'number'}},{name:'find_suitable_places',input:{area:'coarse zone',preference:'user-selected acoustic preference'}},{name:'submit_observation',input:{zone_id:'coarse zone',time_bucket:'rounded time',acoustic_summary:'aggregated calibrated indicators'},requires:'explicit contribution consent'}],excluded:['raw_audio','personal_routes','health_data']};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;easeTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
export default function CityMap(){
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),markers=useRef<{marker:{remove:()=>unknown};button:HTMLButtonElement}[]>([]),focusRef=useRef<(i:number|null)=>void>(()=>{}),glMap=useRef<import('maplibre-gl').Map|null>(null),filterRef=useRef<(f:Level|'all')=>void>(()=>{});
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[mcp,setMcp]=useState(false),[shown,setShown]=useState<Record<LayerKey,boolean>>({demo:true,measured:true,proxies:false,candidates:true,reports:true}),[failedLayers,setFailedLayers]=useState<string[]>([]),[layersOpen,setLayersOpen]=useState(false),[copied,setCopied]=useState(false),[copyFallback,setCopyFallback]=useState(false),[selected,setSelected]=useState<number|null>(null),[hist,setHist]=useState(false),[entries,setEntries]=useState<Entry[]>(()=>[3,9,17,27,41,64].map((a,k)=>makeEntry((k*5+3)%points.length,a))),[shared,setShared]=useState<number[]>([]),[filter,setFilter]=useState<Level|'all'>('all');
 const addEntry=(i:number)=>setEntries(e=>[makeEntry(i),...e].slice(0,40));
 useEffect(()=>{
  let disposed=false,index=0,interval:ReturnType<typeof setInterval>;
  const timeouts=new Set<ReturnType<typeof setTimeout>>();
  const fallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');
   if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,points,()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}});
   if(!result)return;
   map.current=result.controls;markers.current=result.markers;
   interval=setInterval(()=>{if(disposed)return;const at=(index*7+2)%points.length,next=markers.current[at];index++;addEntry(at);next.button.classList.add('is-contributing');const timer=setTimeout(()=>{next.button.classList.remove('is-contributing');timeouts.delete(timer)},2300);timeouts.add(timer)},3200);
  };
  const start=async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...home,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;glMap.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','Map of San Francisco. Drag to explore. Darker violet means higher simulated sound levels. Ripples represent fictional contributions. Gray marks are live DataSF layers: 311 noise reports, street events, entertainment venues and street construction.');
   instance.on('load',()=>{
    if(disposed)return;setReady(true);setFailed(false);
    void loadSfLayers().then(r=>{if(disposed)return;const set=(id:string,data:unknown)=>(instance.getSource(id) as import('maplibre-gl').GeoJSONSource|undefined)?.setData(data as Parameters<import('maplibre-gl').GeoJSONSource['setData']>[0]);set('candidates',r.candidates);set('proxies',r.proxies);set('measured',r.measured);setFailedLayers(r.failed)}).catch(()=>{if(!disposed)setFailedLayers(['measured','proxies','candidates'])});
    loadReports().then(data=>{
     if(disposed)return;
     (instance.getSource('reports') as import('maplibre-gl').GeoJSONSource|undefined)?.setData(data);
     // Real complaints raise the field around them, so live data shapes what you see.
     (instance.getSource('sound') as import('maplibre-gl').GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:[...soundData.features,...data.features.map(f=>({...f,properties:{score:.85}}))]});
    }).catch(()=>{});
   });
   const ids=['measured-sfo','proxy-context','candidate-places','noise-reports'];
   instance.on('click','noise-reports',e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {kind:string;place:string;at:string};new lib.Popup({closeButton:false,className:'report-popup'}).setLngLat(e.lngLat).setText('311 noise report · '+p.kind+(p.place?' · '+p.place:'')+' · '+ago(p.at)).addTo(instance)});
   for(const id of ['measured-sfo','proxy-context','candidate-places']){
    instance.on('click',id,e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {evidence:string;kind:string;label:string;detail?:string;cnel?:number;observedOn?:string;caveat:string};
     const head=p.evidence==='measured'?'MEASURED · '+p.kind+' · CNEL '+p.cnel+' dB ('+p.observedOn+')':p.evidence==='proxy'?'PROXY · '+p.kind:'UNMEASURED CANDIDATE · '+p.kind;
     new lib.Popup({closeButton:false,className:'report-popup',maxWidth:'280px'}).setLngLat(e.lngLat).setText(head+' · '+p.label+(p.detail?' · '+p.detail:'')+' · '+p.caveat).addTo(instance)});
    instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});
    instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''});
   }
   for(const id of ids){instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''})}
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   focusRef.current=i=>(instance.getSource('focus') as import('maplibre-gl').GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:i===null?[]:toFeatures([points[i]])});
   filterRef.current=f=>{if(instance.getLayer('sound-fields'))instance.setFilter('sound-fields',f==='all'?null:f==='quiet'?['<=',['get','score'],.35]:f==='moderate'?['all',['>',['get','score'],.35],['<=',['get','score'],.65]]:['>',['get','score'],.65])};
   instance.on('click',e=>{
    if(instance.queryRenderedFeatures(e.point,{layers:ids}).length)return;
    let best=-1,nearest=80;points.forEach((p,i)=>{const s=instance.project([p.lng,p.lat]);const d=Math.hypot(s.x-e.point.x,s.y-e.point.y);if(d<nearest){nearest=d;best=i}});
    if(best<0){setSelected(null);return}
    setSelected(best);instance.flyTo({center:[points[best].lng,points[best].lat],zoom:Math.max(instance.getZoom(),14.8),duration:1200});
   });
   interval=setInterval(()=>{
    if(disposed)return;
    const at=(index*7+2)%points.length;index++;addEntry(at);
    const el=document.createElement('div');el.className='quiet-ripple';
    const ripple=new lib.Marker({element:el,anchor:'center'}).setLngLat([points[at].lng,points[at].lat]).addTo(instance);
    const timer=setTimeout(()=>{ripple.remove();timeouts.delete(timer)},2300);timeouts.add(timer);
   },3200);
  }catch{try{await fallback()}catch{if(!disposed)setFailed(true)}}};
  void start();
  return()=>{disposed=true;clearInterval(interval);timeouts.forEach(clearTimeout);markers.current.forEach(m=>m.marker.remove());markers.current=[];map.current?.remove();map.current=null};
 },[]);
 useEffect(()=>{if(!hist)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setHist(false)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[hist]);
 useEffect(()=>{const gl=glMap.current;for(const row of layerRows){for(const id of row.mapIds){if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',shown[row.key]?'visible':'none')}}},[shown,ready]);
 useEffect(()=>{focusRef.current(selected)},[selected,ready]);
 useEffect(()=>{filterRef.current(filter)},[filter,ready]);
 useEffect(()=>{if(selected===null||mcp)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setSelected(null)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[selected,mcp]);
 useEffect(()=>{
  if(!mcp)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{
   if(e.key==='Escape'){setMcp(false);mcpButton.current?.focus()}
   if(e.key==='Tab'){const buttons=dialog.current?.querySelectorAll<HTMLButtonElement>('button');if(!buttons?.length)return;const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}
  };document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 function reset(){map.current?.flyTo({...home,duration:1000});setSelected(null);setFilter('all')}
 async function copy(){try{await navigator.clipboard.writeText(JSON.stringify(contract,null,2));setCopied(true)}catch{setCopied(false);setCopyFallback(true)}}
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset San Francisco view" aria-label="Reset San Francisco view"><Compass size={25} strokeWidth={1.4}/></button>
  <button className="quiet-mcp" ref={mcpButton} onClick={()=>{setMcp(true);setCopied(false);setCopyFallback(false)}} aria-haspopup="dialog"><Plug size={14} strokeWidth={1.5}/>MCP</button>
  <div className="quiet-filters" role="group" aria-label="Filter places by sound level">{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>
  {selected!==null&&<aside className="quiet-card" key={selected} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close place details" onClick={()=>setSelected(null)}><X size={16}/></button>
   <strong>{points[selected].name}</strong>
   <span className={'quiet-card-level '+levelOf(points[selected].score)}>{levelOf(points[selected].score)} · simulated</span>
   <div className="quiet-card-bar" role="img" aria-label={'Simulated level '+Math.round(points[selected].score*100)+' out of 100'}><span style={{width:Math.round(points[selected].score*100)+'%'}}/></div>
   <button className="quiet-share" disabled={shared.includes(selected)} onClick={()=>{setShared(a=>[...a,selected]);addEntry(selected)}}>{shared.includes(selected)?<><Check size={14}/>Sent</>:'Add observation'}</button>
  </aside>}
  <button className="quiet-history-btn quiet-icon" aria-label="Open agent contributions" title="Agent contributions" aria-expanded={hist} onClick={()=>setHist(v=>!v)}><Users size={18} strokeWidth={1.5}/></button>
  {hist&&<aside className="quiet-history" aria-label="Agent contributions">
   <div className="quiet-history-head"><strong>Contributions</strong><button className="quiet-icon" aria-label="Close contributions" onClick={()=>setHist(false)}><X size={16}/></button></div>
   <ul>{entries.map((e,i)=><li key={e.id} style={{animationDelay:Math.min(i,6)*40+'ms'}}><span>{e.zone}</span><b className={e.level}>{e.level}</b><time>{bucket(e.t)}</time></li>)}</ul>
  </aside>}
  <div className="quiet-map-controls">
   <button className="quiet-icon" title="Zoom in" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button>
   <button className="quiet-icon" title="Zoom out" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button>
  </div>
  <section className="quiet-layers" aria-label="Map layers">
   <button className="quiet-layers-head" aria-expanded={layersOpen} onClick={()=>setLayersOpen(!layersOpen)}><Layers size={14}/>Layers</button>
   {layersOpen&&<ul>{layerRows.map(r=><li key={r.key}><label title={r.hint}><input type="checkbox" checked={shown[r.key]} onChange={()=>setShown({...shown,[r.key]:!shown[r.key]})}/><i className={'quiet-swatch swatch-'+r.swatch} aria-hidden="true"/><span>{r.label}</span><em>{r.tag}</em></label></li>)}</ul>}
   {layersOpen&&failedLayers.length>0&&<p className="quiet-layers-warn" role="status">Couldn&apos;t load {failedLayers.join(', ')}</p>}
  </section>
  <span className="quiet-demo" title="Violet is synthetic. No agents are connected. Black, gray and ringed marks are real DataSF layers, labelled by what they are.">Demo data</span>
  <div className="quiet-intensity" role="img" aria-label="Simulated sound intensity: lighter violet means lower levels; darker violet means higher levels. White has no observations." title="Simulated sound intensity · darker violet = higher levels · white = no observations"><em>Quiet</em><span/><em>Loud</em></div>
  {mcp&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <div className="quiet-mcp-heading"><strong id="mcp-title">MCP</strong><button ref={closeButton} className="quiet-icon" aria-label="Close MCP" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><X size={18}/></button></div>
   <><div className="quiet-mcp-state"><span/>Proposed contract · not connected</div>
   <div className="quiet-tool-list">{contract.tools.map(t=><code key={t.name}>{t.name}<span>↗</span></code>)}</div>
   <button className="quiet-copy" onClick={copy} aria-label={copied?'Contract copied':'Copy proposed MCP contract'} title={copied?'Copied':'Copy contract'}>{copied?<Check size={17}/>:<Copy size={17}/>}</button>{copyFallback&&<textarea className="quiet-contract" aria-label="MCP contract for manual copying" readOnly value={JSON.stringify(contract,null,2)} onFocus={e=>e.currentTarget.select()}/>}</>
  </div></div>}
 </main>;
}
