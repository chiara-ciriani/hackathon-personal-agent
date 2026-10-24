'use client';
import {useEffect,useRef,useState} from 'react';
import {Building2,Check,Compass,Copy,Layers,Plug,Users,Minus,Plus,RotateCcw,X} from 'lucide-react';
import type {StyleSpecification} from 'maplibre-gl';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';
import {loadSfLayers} from '../lib/sf-layers.mjs';
import {venues} from '../lib/venues';

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
const heatRamp:import('maplibre-gl').ExpressionSpecification=['interpolate',['linear'],['heatmap-density'],0,'rgba(230,220,255,0)',.15,'#e6dcff',.4,'#b996f5',.65,'#8a45e8',.85,'#5a14b0',1,'#2b0a63'];
const mapStyle:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},focus:{type:'geojson',data:{type:'FeatureCollection',features:[]}},venuepts:{type:'geojson',data:{type:'FeatureCollection',features:venues.map(v=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[v.lng,v.lat]},properties:{id:v.id,name:v.name,score:v.score}}))}},sound:{type:'geojson',data:soundData},reports:{type:'geojson',data:{type:'FeatureCollection',features:[]}},measured:{type:'geojson',data:{type:'FeatureCollection',features:[]}},sfoEvents:{type:'geojson',data:{type:'FeatureCollection',features:[]}},crowd:{type:'geojson',data:{type:'FeatureCollection',features:[]}},cad:{type:'geojson',data:{type:'FeatureCollection',features:[]}},proxies:{type:'geojson',data:{type:'FeatureCollection',features:[]}},candidates:{type:'geojson',data:{type:'FeatureCollection',features:[]}}},
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
  // Real data first: smooth fields of where people actually reported noise (311 and noise-nuisance calls). Density of reports, not a sound level.
  {id:'cad-heat',type:'heatmap',source:'cad',paint:{'heatmap-weight':['interpolate',['linear'],['coalesce',['get','count'],1],1,.5,16,1.4],'heatmap-intensity':['interpolate',['linear'],['zoom'],10,.7,15,1.6],'heatmap-radius':['interpolate',['linear'],['zoom'],10,16,13,30,16,56],'heatmap-opacity':.82,'heatmap-color':heatRamp}},
  {id:'reports-heat',type:'heatmap',source:'reports',paint:{'heatmap-weight':1,'heatmap-intensity':['interpolate',['linear'],['zoom'],10,.8,15,1.8],'heatmap-radius':['interpolate',['linear'],['zoom'],10,16,13,30,16,56],'heatmap-opacity':.82,'heatmap-color':heatRamp}},
  // Venues: ink-ringed points filled with their simulated noise level. Click one to open its 3D floor plan.
  {id:'venue-halo',type:'circle',source:'venuepts',paint:{'circle-color':noiseRamp,'circle-radius':['interpolate',['linear'],['zoom'],11,16,15,34],'circle-blur':1,'circle-opacity':.45}},
  {id:'venue-points',type:'circle',source:'venuepts',paint:{'circle-color':noiseRamp,'circle-radius':['interpolate',['linear'],['zoom'],11,7,15,10],'circle-stroke-color':'#171717','circle-stroke-width':2.2}},
  {id:'venue-labels',type:'symbol',source:'venuepts',minzoom:12,layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':12,'text-offset':[0,1.5],'text-anchor':'top'},paint:{'text-color':'#171717','text-halo-color':'#ffffff','text-halo-width':1.6}},
  {id:'focus-ring',type:'circle',source:'focus',paint:{'circle-radius':16,'circle-color':'#ffffff00','circle-stroke-color':'#171717','circle-stroke-width':2,'circle-pitch-alignment':'viewport'}},
  // Real layers stay out of the violet scale: ink for measured, grays for the rest. Violet is reserved for the synthetic sound score.
  {id:'proxy-context',type:'circle',source:'proxies',minzoom:13,layout:{visibility:'none'},paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],13,1.8,17,4],'circle-stroke-color':'#ffffff','circle-stroke-width':1,'circle-opacity':.85}},
  {id:'candidate-places',type:'circle',source:'candidates',minzoom:12,paint:{'circle-color':'#ffffff','circle-radius':['interpolate',['linear'],['zoom'],12,3,17,6],'circle-stroke-color':'#171717','circle-stroke-width':1.5}},
  {id:'noise-reports',type:'circle',source:'reports',minzoom:15,paint:{'circle-color':'#52525b','circle-radius':['interpolate',['linear'],['zoom'],13,1.6,17,3.4],'circle-opacity':.6}},
  {id:'cad-calls',type:'circle',source:'cad',minzoom:15,paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],12,['+',2,['*',.25,['min',['get','count'],16]]],17,['+',3,['*',.6,['min',['get','count'],16]]]],'circle-stroke-color':'#71717a','circle-stroke-width':1.4,'circle-opacity':.8}},
  {id:'crowd-cells',type:'circle',source:'crowd',paint:{'circle-color':'#17171799','circle-radius':['interpolate',['linear'],['zoom'],11,4,16,9],'circle-stroke-color':'#171717','circle-stroke-width':1.5}},
  {id:'measured-sfo-events',type:'circle',source:'sfoEvents',paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],11,9,16,15],'circle-stroke-color':'#171717','circle-stroke-width':2.2}},
  {id:'measured-sfo',type:'circle',source:'measured',paint:{'circle-color':'#171717','circle-radius':['interpolate',['linear'],['zoom'],11,5,16,9],'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
 ]
};
// A contribution carries only a coarse zone, a level and a rounded time. No agent id, no audio, no route.
// Evidence labels stay separate: measured / measured crowdsourced / proxy / unmeasured candidate / synthetic. Unknown is not quiet.
type LayerKey='simulated'|'measured'|'sfoEvents'|'crowd'|'proxies'|'cad'|'candidates'|'reports';
const layerRows:{key:LayerKey;label:string;tag:string;swatch:string;mapIds:string[];hint:string}[]=[
 {key:'measured',label:'Airport monitors',tag:'measured',swatch:'measured',mapIds:['measured-sfo'],hint:'Daily CNEL in dB at 6 SFO monitors inside SF. Not live, not at your spot.'},
 {key:'sfoEvents',label:'Airport loud events',tag:'measured',swatch:'events',mapIds:['measured-sfo-events'],hint:'Aircraft noise exceedance events per SFO monitor, last 365 days: count, median and max dBA, latest date. Only events above each monitor threshold are published. No license declared.'},
 {key:'crowd',label:'NoiseCapture cells',tag:'crowdsourced',swatch:'crowd',mapIds:['crowd-cells'],hint:'About 20 cells of ~100 m with 3+ volunteer tracks, 2017-2025. Uncalibrated phones, several dB of error, not dBA. ODbL, NoiseCapture / Noise-Planet.'},
 {key:'proxies',label:'Permits & closures',tag:'indirect',swatch:'proxy',mapIds:['proxy-context'],hint:'Entertainment permits, night work today or tomorrow, street closures now. Possible noise, not levels.'},
 {key:'cad',label:'Noise-nuisance calls',tag:'indirect',swatch:'cad',mapIds:['cad-calls','cad-heat'],hint:'Police dispatches classified NOISE NUISANCE per masked intersection, last 30 days. Complaints, not measurements.'},
 {key:'candidates',label:'Parks, POPOS & libraries',tag:'unmeasured',swatch:'candidate',mapIds:['candidate-places'],hint:'Places from city inventories that might be calm (parks and playgrounds can be loud). Nobody has measured them.'},
 {key:'reports',label:'311 complaints',tag:'reports',swatch:'report',mapIds:['noise-reports','reports-heat'],hint:'Recent reports. A complaint is not a measurement.'},
 {key:'simulated',label:'Simulated noise',tag:'simulated',swatch:'simulated',mapIds:['sound-fields'],hint:'Invented scores for illustration. Not measurements.'},
];
// Contributions come from agents through the MCP server; none are made up here.
type Entry={id:number;t:number;zone:string;level:Level};
const bucket=(t:number)=>{const m=Math.max(0,Math.round((Date.now()-t)/300000))*5;return m<5?'just now':m<60?m+' min ago':Math.round(m/60)+' h ago'};
type Level='quiet'|'moderate'|'loud';
const levelOf=(score:number):Level=>score>.65?'loud':score>.35?'moderate':'quiet';
const filters:{id:Level|'all';label:string}[]=[{id:'all',label:'All'},{id:'quiet',label:'Quiet'},{id:'moderate',label:'Moderate'},{id:'loud',label:'Loud'}];
const home={center:[-122.44,37.768] as [number,number],zoom:12.6,pitch:48,bearing:-12};
const MCP_URL='https://quiet-compass-server.onrender.com/mcp';
const mcpTools=[
 {name:'quiet_sf_layers',what:'Real noise layers around a point in San Francisco'},
 {name:'query_sound_map',what:'Reported noise levels in an area'},
 {name:'find_suitable_places',what:'Calm places that fit what you need'},
 {name:'submit_observation',what:'Send a noise reading, with consent'},
];
const snippets:Record<'code'|'app'|'json'|'prompt',{label:string;text:string}>={
 code:{label:'Claude Code',text:'claude mcp add --transport http quiet-compass '+MCP_URL+' --header "Authorization: Bearer YOUR_TOKEN"'},
 app:{label:'Claude app',text:'Settings > Connectors > Add custom connector\nName: Quiet Compass\nURL: '+MCP_URL+'\nHeader: Authorization: Bearer YOUR_TOKEN'},
 json:{label:'JSON',text:JSON.stringify({mcpServers:{'quiet-compass':{url:MCP_URL,headers:{Authorization:'Bearer YOUR_TOKEN'}}}},null,2)},
 prompt:{label:'Prompt',text:'Use the Quiet Compass tools to pick calm places: query_sound_map for an area, find_suitable_places for what I need. Say when data is simulated or only reported by people, never invent sound levels, and never ask for raw audio or my route.'},
};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;easeTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
export default function CityMap(){
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),markers=useRef<{marker:{remove:()=>unknown};button:HTMLButtonElement}[]>([]),focusRef=useRef<(i:number|null)=>void>(()=>{}),simRef=useRef(false),glMap=useRef<import('maplibre-gl').Map|null>(null),filterRef=useRef<(f:Level|'all')=>void>(()=>{});
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[mcp,setMcp]=useState(false),[shown,setShown]=useState<Record<LayerKey,boolean>>({simulated:false,measured:true,sfoEvents:false,crowd:true,proxies:false,cad:true,candidates:false,reports:true}),[failedLayers,setFailedLayers]=useState<string[]>([]),[layersOpen,setLayersOpen]=useState(false),[copied,setCopied]=useState<string|null>(null),[tab,setTab]=useState<'code'|'app'|'json'|'prompt'>('code'),[selected,setSelected]=useState<number|null>(null),[venueSel,setVenueSel]=useState<string|null>(null),[hist,setHist]=useState(false),[entries]=useState<Entry[]>([]),[filter,setFilter]=useState<Level|'all'>('all');
 useEffect(()=>{
  let disposed=false;
  const fallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');
   if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,points,()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}});
   if(!result)return;
   map.current=result.controls;markers.current=result.markers;
  };
  const start=async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...home,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;glMap.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true,customAttribution:'NoiseCapture / Noise-Planet community (ODbL 1.0) · DataSF'}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','Map of San Francisco. Drag to explore. Darker violet means higher simulated sound levels, not measurements. Ripples represent fictional contributions. Real layers, labelled by what they are: filled and ringed dark dots are SFO noise monitors (measured), semi-filled dark dots are NoiseCapture phone cells (crowdsourced, uncalibrated), small gray dots are permits and closures and gray rings are noise-nuisance call counts (proxies), white rings are unmeasured candidate places, tiny gray dots are 311 noise complaints.');
   instance.on('load',()=>{
    if(disposed)return;setReady(true);setFailed(false);
    void loadSfLayers().then(r=>{if(disposed)return;const set=(id:string,data:unknown)=>(instance.getSource(id) as import('maplibre-gl').GeoJSONSource|undefined)?.setData(data as Parameters<import('maplibre-gl').GeoJSONSource['setData']>[0]);set('candidates',r.candidates);set('proxies',r.proxies);set('measured',r.measured);set('sfoEvents',r.sfoEvents);set('crowd',r.crowd);set('cad',r.cad);setFailedLayers(r.failed)}).catch(()=>{if(!disposed)setFailedLayers(['measured','sfoEvents','crowd','proxies','cad','candidates'])});
    loadReports().then(data=>{
     if(disposed)return;
     (instance.getSource('reports') as import('maplibre-gl').GeoJSONSource|undefined)?.setData(data);
     // Real complaints raise the field around them, so live data shapes what you see.
     (instance.getSource('sound') as import('maplibre-gl').GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:[...soundData.features,...data.features.map(f=>({...f,properties:{score:.85}}))]});
    }).catch(()=>{});
   });
   const ids=['measured-sfo','measured-sfo-events','crowd-cells','cad-calls','proxy-context','candidate-places','noise-reports'];
   instance.on('click','noise-reports',e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {kind:string;place:string;at:string};new lib.Popup({closeButton:false,className:'report-popup'}).setLngLat(e.lngLat).setText('311 noise report · '+p.kind+(p.place?' · '+p.place:'')+' · '+ago(p.at)).addTo(instance)});
   for(const id of ['measured-sfo','measured-sfo-events','crowd-cells','cad-calls','proxy-context','candidate-places']){
    instance.on('click',id,e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {evidence:string;kind:string;label:string;detail?:string;cnel?:number;count?:number;medianDb?:number;maxDb?:number;laeqDb?:number;observedOn?:string;caveat:string};
     const head=p.evidence==='measured_crowdsourced'?'MEASURED, CROWDSOURCED, UNCALIBRATED · '+p.kind+' · median 5-min '+p.medianDb+' dB (energy mean '+p.laeqDb+')':p.evidence==='measured'?(p.cnel!==undefined?'MEASURED · '+p.kind+' · CNEL '+p.cnel+' dB ('+p.observedOn+')':'MEASURED · '+p.kind+' · '+p.count+' events, median '+p.medianDb+' dBA, max '+p.maxDb+' dBA, latest '+p.observedOn):p.evidence==='proxy'?'PROXY · '+p.kind:'UNMEASURED CANDIDATE · '+p.kind;
     new lib.Popup({closeButton:false,className:'report-popup',maxWidth:'280px'}).setLngLat(e.lngLat).setText(head+' · '+p.label+(p.detail?' · '+p.detail:'')+' · '+p.caveat).addTo(instance)});
    instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});
    instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''});
   }
   for(const id of [...ids,'venue-points']){instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''})}
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   focusRef.current=i=>(instance.getSource('focus') as import('maplibre-gl').GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:i===null?[]:toFeatures([points[i]])});
   filterRef.current=f=>{if(instance.getLayer('sound-fields'))instance.setFilter('sound-fields',f==='all'?null:f==='quiet'?['<=',['get','score'],.35]:f==='moderate'?['all',['>',['get','score'],.35],['<=',['get','score'],.65]]:['>',['get','score'],.65])};
   instance.on('click',e=>{
    if(instance.queryRenderedFeatures(e.point,{layers:ids}).length)return;
    const vf=instance.queryRenderedFeatures(e.point,{layers:['venue-points']})[0];
    if(vf){const id=vf.properties.id as string;const v=venues.find(q=>q.id===id);setVenueSel(id);setSelected(null);if(v)instance.flyTo({center:[v.lng,v.lat],zoom:Math.max(instance.getZoom(),14.2),duration:1000});return}
    setVenueSel(null);
    if(!simRef.current){setSelected(null);return}
    let best=-1,nearest=80;points.forEach((p,i)=>{const s=instance.project([p.lng,p.lat]);const d=Math.hypot(s.x-e.point.x,s.y-e.point.y);if(d<nearest){nearest=d;best=i}});
    if(best<0){setSelected(null);return}
    setVenueSel(null);setSelected(best);instance.flyTo({center:[points[best].lng,points[best].lat],zoom:Math.max(instance.getZoom(),14.8),duration:1200});
   });
  }catch{try{await fallback()}catch{if(!disposed)setFailed(true)}}};
  void start();
  return()=>{disposed=true;markers.current.forEach(m=>m.marker.remove());markers.current=[];map.current?.remove();map.current=null};
 },[]);
 useEffect(()=>{if(!hist)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setHist(false)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[hist]);
 useEffect(()=>{simRef.current=shown.simulated;const gl=glMap.current;if(gl?.getLayer('venue-points')){gl.setPaintProperty('venue-points','circle-color',shown.simulated?noiseRamp:'#ffffff');gl.setPaintProperty('venue-halo','circle-opacity',shown.simulated?.45:0)}for(const row of layerRows){for(const id of row.mapIds){if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',shown[row.key]?'visible':'none')}}},[shown,ready]);
 useEffect(()=>{focusRef.current(selected)},[selected,ready]);
 useEffect(()=>{filterRef.current(filter)},[filter,ready]);
 useEffect(()=>{if((selected===null&&!venueSel)||mcp)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape'){setSelected(null);setVenueSel(null)}};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[selected,venueSel,mcp]);
 useEffect(()=>{
  if(!mcp)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{
   if(e.key==='Escape'){setMcp(false);mcpButton.current?.focus()}
   if(e.key==='Tab'){const buttons=dialog.current?.querySelectorAll<HTMLButtonElement>('button');if(!buttons?.length)return;const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}
  };document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 function reset(){map.current?.flyTo({...home,duration:1000});setSelected(null);setVenueSel(null);setFilter('all')}
 async function copyText(key:string,text:string){try{await navigator.clipboard.writeText(text);setCopied(key);setTimeout(()=>setCopied(c=>c===key?null:c),1800)}catch{setCopied(null)}}
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset San Francisco view" aria-label="Reset San Francisco view"><Compass size={25} strokeWidth={1.4}/></button>
  <button className="quiet-mcp" ref={mcpButton} onClick={()=>{setMcp(true);setCopied(null)}} aria-haspopup="dialog"><Plug size={14} strokeWidth={1.5}/>MCP</button>
  {shown.simulated&&<div className="quiet-filters" role="group" aria-label="Filter places by sound level">{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>}
  {venueSel&&(()=>{const v=venues.find(q=>q.id===venueSel);if(!v)return null;const lv=levelOf(v.score);return <aside className="quiet-card" key={v.id} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close venue details" onClick={()=>setVenueSel(null)}><X size={16}/></button>
   <strong>{v.name}</strong>
   {shown.simulated?<><span className={'quiet-card-level '+lv}>{lv} · simulated</span>
   <div className="quiet-card-bar" role="img" aria-label={'Simulated level '+Math.round(v.score*100)+' out of 100'}><span style={{width:Math.round(v.score*100)+'%'}}/></div></>:<span className="quiet-card-level quiet-card-none">No measurements yet</span>}
   {/* A plain anchor: next/link breaks under this project's vinext dev server. */}
   <a className="quiet-share quiet-open" href={'/venue?v='+v.id}>Open 3D floor plan</a>
  </aside>})()}
  {selected!==null&&<aside className="quiet-card" key={selected} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close place details" onClick={()=>setSelected(null)}><X size={16}/></button>
   <strong>{points[selected].name}</strong>
   <span className={'quiet-card-level '+levelOf(points[selected].score)}>{levelOf(points[selected].score)} · simulated</span>
   <div className="quiet-card-bar" role="img" aria-label={'Simulated level '+Math.round(points[selected].score*100)+' out of 100'}><span style={{width:Math.round(points[selected].score*100)+'%'}}/></div>
  </aside>}
  <a className="quiet-venue-btn quiet-icon" href="/venue" title="Event venue in 3D" aria-label="Event venue in 3D"><Building2 size={18} strokeWidth={1.5}/></a>
  <button className="quiet-history-btn quiet-icon" aria-label="Open agent contributions" title="Agent contributions" aria-expanded={hist} onClick={()=>setHist(v=>!v)}><Users size={18} strokeWidth={1.5}/></button>
  {hist&&<aside className="quiet-history" aria-label="Agent contributions">
   <div className="quiet-history-head"><strong>Contributions</strong><button className="quiet-icon" aria-label="Close contributions" onClick={()=>setHist(false)}><X size={16}/></button></div>
   {entries.length===0?<div className="quiet-history-empty"><strong>No contributions yet</strong><p>Agents that connect through MCP report new noise here.</p><button className="quiet-share" onClick={()=>{setHist(false);setMcp(true)}}>Connect your agent</button></div>
   :<ul>{entries.map((e,i)=><li key={e.id} style={{animationDelay:Math.min(i,6)*40+'ms'}}><span>{e.zone}</span><b className={e.level}>{e.level}</b><time>{bucket(e.t)}</time></li>)}</ul>}
  </aside>}
  <div className="quiet-map-controls">
   <button className="quiet-icon" title="Zoom in" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button>
   <button className="quiet-icon" title="Zoom out" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button>
  </div>
  <section className="quiet-layers" aria-label="Map layers">
   <button className="quiet-layers-head" aria-expanded={layersOpen} onClick={()=>setLayersOpen(!layersOpen)}><Layers size={14}/>Layers</button>
   {layersOpen&&<ul>{layerRows.map(r=><li key={r.key}><label title={r.hint}><input type="checkbox" checked={shown[r.key]} onChange={()=>setShown({...shown,[r.key]:!shown[r.key]})}/><i className={'quiet-swatch swatch-'+r.swatch} aria-hidden="true"/><span>{r.label}</span><em>{r.tag}</em></label></li>)}</ul>}
   {layersOpen&&failedLayers.length>0&&<p className="quiet-layers-warn" role="status">Couldn&apos;t load {failedLayers.join(', ')}. Unknown, not quiet.</p>}
  </section>
  <div className="quiet-intensity" role="img" aria-label="Lighter violet means fewer noise reports or lower simulated levels; darker violet means more reports or higher levels." title="Darker violet = more noise reports (311 and noise-nuisance calls). Simulated levels use the same scale when that layer is on."><em>{shown.simulated?'Quiet':'Fewer reports'}</em><span/><em>{shown.simulated?'Loud':'More reports'}</em></div>
  {mcp&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <div className="quiet-mcp-heading"><strong id="mcp-title">MCP</strong><button ref={closeButton} className="quiet-icon" aria-label="Close MCP" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><X size={18}/></button></div>
   <p className="quiet-mcp-lead">Give any personal agent live noise data for San Francisco.</p>
   <label className="quiet-mcp-label" htmlFor="mcp-url">Server URL</label>
   <div className="quiet-field"><input id="mcp-url" readOnly value={MCP_URL} onFocus={e=>e.currentTarget.select()}/><button className="quiet-icon" aria-label={copied==='url'?'URL copied':'Copy server URL'} title="Copy" onClick={()=>copyText('url',MCP_URL)}>{copied==='url'?<Check size={16}/>:<Copy size={16}/>}</button></div>
   <div className="quiet-tabs" role="tablist" aria-label="How to connect">{(Object.keys(snippets) as (keyof typeof snippets)[]).map(k=><button key={k} role="tab" aria-selected={tab===k} className={tab===k?'is-active':''} onClick={()=>setTab(k)}>{snippets[k].label}</button>)}</div>
   <div className="quiet-snippet"><pre tabIndex={0}>{snippets[tab].text}</pre><button className="quiet-share" onClick={()=>copyText('snippet',snippets[tab].text)}>{copied==='snippet'?<><Check size={14}/>Copied</>:'Copy'}</button></div>
   <p className="quiet-mcp-hint">Replace YOUR_TOKEN with your server&apos;s access token.</p>
   <ul className="quiet-tools">{mcpTools.map(t=><li key={t.name}><code>{t.name}</code><span>{t.what}</span></li>)}</ul>
  </div></div>}
 </main>;
}
