'use client';
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {ArrowUpRight,Building2,Check,ChevronDown,Compass,Copy,Layers,Plug,Smartphone,Users,Minus,Plus,RefreshCw,RotateCcw,X} from 'lucide-react';
import type {PointFeature as Feature,PointCollection} from '../lib/map-types';
import type {StyleSpecification,GeoJSONSource,Map as GLMap} from 'maplibre-gl';
import {connectionGuide,sharedTools} from '../lib/mcp-exchange.mjs';
import {loadSfLayers} from '../lib/sf-layers.mjs';
import {loadNoiseReports,emptyCollection,measurementText} from '../lib/real-map.mjs';
import {buildReportField,describeCell,FIELD_NOTE,FIELD_SOURCES,FILTER_NOTE} from '../lib/noise-field.mjs';
import {venues,venueMapProperties} from '../lib/venues';
import {venuePin} from '../lib/venue-data.mjs';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';

type Level='few'|'some'|'many';
type LayerKey='device'|'measured'|'sfoEvents'|'proxies'|'cad'|'candidates'|'reports'|'field';
const layerRows:{key:LayerKey;label:string;tag:string;swatch:string;mapIds:string[];hint:string}[]=[
 {key:'device',label:'Shared phone measurements',tag:'Shared in the last 24 hours',swatch:'measured',mapIds:['device-readings'],hint:'Recent geolocated contributions from the MCP shared map. Share a phone measurement to unlock 15 minutes of access.'},
 {key:'measured',label:'Airport noise monitors',tag:'Readings from the last 30 days',swatch:'measured',mapIds:['measured-sfo'],hint:'Permanent SFO microphones. Daily average at the monitor, published about a month late.'},
 {key:'sfoEvents',label:'Loud planes',tag:'Over the noise limit, last 30 days',swatch:'events',mapIds:['measured-sfo-events'],hint:'Only planes louder than the monitor limit are counted, so this shows the loudest moments.'},
 {key:'candidates',label:'Possible quiet spots',tag:'Parks, plazas and libraries',swatch:'candidate',mapIds:['candidate-places'],hint:'Places that might be calm. Nobody has measured them, so check before you go.'},
 {key:'reports',label:'Noise complaints',tag:'Reported to 311, last 24 hours',swatch:'report',mapIds:['noise-reports'],hint:'Complaints people filed with the city. They show where noise bothers people, not how loud it is.'},
 {key:'field',label:'Reported noise density',tag:'Reports, not dB',swatch:'field',mapIds:['report-field'],hint:FIELD_NOTE},
 {key:'cad',label:'Police noise calls',tag:'Last 24 hours',swatch:'cad',mapIds:['cad-calls'],hint:'Calls police logged as a noise nuisance, shown at the nearest intersection.'},
 {key:'proxies',label:'Construction and events',tag:'Permits and street closures today',swatch:'proxy',mapIds:['proxy-context'],hint:'Street work, night work, music venues and street closures. Noise is likely, not certain.'},
];
type Properties={label?:string;name?:string;id?:string;evidence?:string;kind?:string;detail?:string;caveat?:string;observedOn?:string;dataset?:string;dbfs?:number;cnel?:number;medianDb?:number;maxDb?:number;count?:number;captureProfile?:string};
type PointFeature=Feature<Properties>;
type MapData=Record<Exclude<LayerKey,'field'>,PointCollection<Properties>>&{failed:string[];fetchedAt:string;deviceState:string};
type McpConnection={state:string;endpoint:string|null;dotEndpoint?:string|null;dotReady?:boolean};
const connectionLabels:Record<string,string>={checking:'Checking server…',available:'Shared MCP available',not_configured:'Server setup needed',invalid_config:'Check server address',unavailable:'Server unavailable',disabled:'Shared access setup needed',incompatible:'Server update needed'};
const deviceLabels:Record<string,string>={available:'Phone measurements are on the map',empty:'No one has shared a phone measurement in the last 24 hours',access_required:'The public map needs a server update',invalid_config:"Phone measurements aren't set up on the server yet",unavailable:"Couldn't load phone measurements right now"};
const home={center:[-122.44,37.768] as [number,number],zoom:12.6,pitch:48,bearing:-12};
// 921 Front Street, San Francisco. Only a camera position for the pitch (?demo=front-street); no data is added or changed.
const demoHome={...home,center:[-122.400556,37.799935] as [number,number],zoom:16.5};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
const measured=(p:Properties)=>['measured','measured_device'].includes(p.evidence||'');
// Colour = number of real reports in the area (sqrt-scaled, capped at the 95th percentile). Not a sound level.
const reportRamp:import('maplibre-gl').ExpressionSpecification=['interpolate',['linear'],['get','t'],0,'#e6dcff',.3,'#b996f5',.55,'#8a45e8',.8,'#5a14b0',1,'#2b0a63'];
const filters:{id:Level|'all';label:string;hint:string}[]=[{id:'all',label:'All',hint:'Every area with reports.'},{id:'few',label:'Fewer',hint:'Lowest third of areas by number of reports. '+FILTER_NOTE},{id:'some',label:'Mid',hint:'Middle third of areas by number of reports. '+FILTER_NOTE},{id:'many',label:'Most',hint:'Highest third of areas by number of reports. '+FILTER_NOTE}];
const mapStyle:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},field:{type:'geojson',data:{type:'FeatureCollection',features:[]}},venuepts:{type:'geojson',data:{type:'FeatureCollection',features:venues.map(v=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[v.lng,v.lat]},properties:venueMapProperties(v)}))}},...Object.fromEntries(layerRows.map(r=>[r.key,{type:'geojson' as const,data:emptyCollection() as PointCollection}]))},
 light:{anchor:'viewport',color:'#ffffff',intensity:.4,position:[1.5,205,40]},
 layers:[
  {id:'background',type:'background',paint:{'background-color':'#f7f7f8'}},
  {id:'land',type:'fill',source:'city','source-layer':'landcover',paint:{'fill-color':'#f2f2f4','fill-opacity':.5}},
  {id:'parks',type:'fill',source:'city','source-layer':'park',paint:{'fill-color':'#f0f0f1','fill-outline-color':'#e8e8eb'}},
  {id:'water',type:'fill',source:'city','source-layer':'water',paint:{'fill-color':'#e9eaee'}},
  {id:'roads-edge',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#e1e1e5','line-width':['interpolate',['linear'],['zoom'],11,.3,13,.8,16,5,19,20]}},
  {id:'roads',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#ffffff','line-width':['interpolate',['linear'],['zoom'],11,.1,13,.25,16,3.6,19,17]}},
  {id:'footprints',type:'fill',source:'city','source-layer':'building',minzoom:14,paint:{'fill-color':'#eae7ed','fill-outline-color':'#dfdbe5'}},
  {id:'structures',type:'fill-extrusion',source:'city','source-layer':'building',minzoom:12.6,filter:['!=',['get','hide_3d'],true],paint:{'fill-extrusion-color':'#f7f6f9','fill-extrusion-height':['interpolate',['linear'],['zoom'],12.6,0,14.2,['coalesce',['get','render_height'],0]],'fill-extrusion-base':['coalesce',['get','render_min_height'],0],'fill-extrusion-opacity':1,'fill-extrusion-vertical-gradient':true}},
  {id:'place-labels',type:'symbol',source:'city','source-layer':'place',minzoom:11,filter:['in',['get','class'],['literal',['suburb','neighbourhood','quarter']]],layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],11,10,15,13],'text-letter-spacing':.08,'text-transform':'uppercase'},paint:{'text-color':'#6b6b73','text-halo-color':'#ffffff','text-halo-width':1.5}},
  // Violet = how many real reports (311 + police noise-nuisance calls) fall in each ~280 m area. No reports means no fill: unknown, not quiet.
  {id:'report-field',type:'fill',source:'field',paint:{'fill-color':reportRamp,'fill-opacity':.55,'fill-outline-color':'#ffffff00'}},
  {id:'venue-points',type:'circle',source:'venuepts',paint:{'circle-color':['case',['==',['get','evidence'],'measured_device'],'#171717','#c4c4cc'],'circle-radius':['interpolate',['linear'],['zoom'],11,7,15,10],'circle-stroke-color':['case',['==',['get','evidence'],'measured_device'],'#ffffff','#8b8b94'],'circle-stroke-width':2.2}},
  {id:'venue-labels',type:'symbol',source:'venuepts',minzoom:12,layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':12,'text-offset':[0,1.5],'text-anchor':'top'},paint:{'text-color':'#171717','text-halo-color':'#ffffff','text-halo-width':1.6}},
  {id:'proxy-context',type:'circle',source:'proxies',minzoom:11,paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],13,1.8,17,4],'circle-stroke-color':'#ffffff','circle-stroke-width':1,'circle-opacity':.85}},
  {id:'candidate-places',type:'circle',source:'candidates',minzoom:11,paint:{'circle-color':'#b6b6bd','circle-radius':['interpolate',['linear'],['zoom'],12,3,17,6],'circle-stroke-color':'#8b8b94','circle-stroke-width':1.5}},
  {id:'noise-reports',type:'circle',source:'reports',minzoom:11,paint:{'circle-color':'#52525b','circle-radius':['interpolate',['linear'],['zoom'],13,1.6,17,3.4],'circle-opacity':.6}},
  {id:'cad-calls',type:'circle',source:'cad',minzoom:11,paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],12,['+',2,['*',.25,['min',['get','count'],16]]],17,['+',3,['*',.6,['min',['get','count'],16]]]],'circle-stroke-color':'#71717a','circle-stroke-width':1.4,'circle-opacity':.8}},
  {id:'measured-sfo-events',type:'circle',source:'sfoEvents',paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],11,9,16,15],'circle-stroke-color':'#171717','circle-stroke-width':2.2}},
  {id:'measured-sfo',type:'circle',source:'measured',paint:{'circle-color':'#171717','circle-radius':['interpolate',['linear'],['zoom'],11,5,16,9],'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
  {id:'device-readings',type:'circle',source:'device',paint:{'circle-color':'#171717','circle-radius':7,'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
 ]
};
export default function CityMap(){
 const initialView=useRef(home);
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),glMap=useRef<GLMap|null>(null);
 const sourceData=useRef<Partial<Record<LayerKey,PointCollection>>>({}),fieldKey=useRef<string>(''),venueKeyRef=useRef<string>(''),filterRef=useRef<(f:Level|'all')=>void>(()=>{});
 const fallbackUpdate=useRef<((features:PointFeature[])=>void)|null>(null);
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const request=useRef<AbortController|null>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[fallback,setFallback]=useState(false);
 const [data,setData]=useState<MapData|null>(null),[loading,setLoading]=useState(true),[dataError,setDataError]=useState(false);
 const [shown,setShown]=useState<Record<LayerKey,boolean>>({device:true,measured:true,sfoEvents:true,proxies:false,cad:false,candidates:true,reports:true,field:true});
 const [layersOpen,setLayersOpen]=useState(false),[filter,setFilter]=useState<Level|'all'>('all');
 const [selection,setSelection]=useState<Properties|null>(null),[hist,setHist]=useState(false),[mcp,setMcp]=useState(false);
 const [connection,setConnection]=useState<McpConnection>({state:'checking',endpoint:null,dotEndpoint:null,dotReady:false}),[copied,setCopied]=useState<string|null>(null),[tab,setTab]=useState<'dot'|'code'|'app'|'json'|'prompt'>('dot');
 const [connectionCheck,setConnectionCheck]=useState(0),[copyError,setCopyError]=useState(false);
 const MCP_URL=connection.endpoint||'https://YOUR-SERVER/mcp/shared';
 const DOT_URL=connection.dotEndpoint||'https://quiet-compass-server.onrender.com/mcp/dot';
 const displayedUrl=tab==='dot'?DOT_URL:MCP_URL;
 const guide=connectionGuide(connection.endpoint);
 const snippets:Record<'dot'|'code'|'app'|'json'|'prompt',{label:string;text:string}>={
  dot:{label:'ChatGPT Dot',text:'Name: Quiet Compass\nDescription: Use my phone to measure sound, find a calmer nearby place, and recommend whether I should move.\nServer URL: '+DOT_URL+'\nAuthentication: OAuth\n\nChoose OAuth when adding the custom MCP server. On the Quiet Compass sign-in page, enter the rotated shared server access key. Do not paste the private owner key into ChatGPT.'},
  code:{label:'Claude Code',text:'claude mcp add --transport http quiet-compass-shared '+MCP_URL+' --header "Authorization: Bearer YOUR_SHARED_TOKEN"'},
  app:{label:'Claude app',text:'Settings > Connectors > Add custom connector\nName: Quiet Compass Shared\nURL: '+MCP_URL+'\nHeader: Authorization: Bearer YOUR_SHARED_TOKEN'},
  json:{label:'JSON',text:JSON.stringify({mcpServers:{'quiet-compass-shared':{url:MCP_URL,headers:{Authorization:'Bearer YOUR_SHARED_TOKEN'}}}},null,2)},
  prompt:{label:'Prompt',text:guide.workflow},
 };
 const report=useMemo(()=>buildReportField(data?.reports.features||[],data?.cad.features||[]),[data?.reports,data?.cad]);
 const refresh=useCallback(async()=>{
  request.current?.abort();const controller=new AbortController();request.current=controller;
  setLoading(true);setSelection(null);setDataError(false);
  const initial={device:emptyCollection(),measured:emptyCollection(),sfoEvents:emptyCollection(),proxies:emptyCollection(),cad:emptyCollection(),candidates:emptyCollection(),reports:emptyCollection(),deviceState:'checking',failed:[],fetchedAt:new Date().toISOString()} as MapData;
  setData(initial);
  const publish=(key:string,value:PointCollection)=>{if(!controller.signal.aborted)setData(current=>({...current!,[key]:value}))};
  try {
   const fetcher=(url:string)=>fetch(url,{cache:'no-store',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(12000)])});
   const [layers,reports,device]=await Promise.all([
    loadSfLayers(fetcher,new Date(),publish),
    loadNoiseReports(fetcher).then(data=>{publish('reports',data);return {data,failed:false}}).catch(()=>({data:emptyCollection(),failed:true})),
    fetcher('/api/map').then(async r=>{if(!r.ok)throw new Error();return r.json() as Promise<Pick<MapData,'device'|'deviceState'>>}).catch(()=>({device:emptyCollection(),deviceState:'unavailable'})).then(result=>{if(!controller.signal.aborted)setData(current=>({...current!,...result}));return result}),
   ]);
   const next={...layers,reports:reports.data,device:device.device,deviceState:device.deviceState,failed:[...layers.failed,...(reports.failed?['reports']:[])],fetchedAt:new Date().toISOString()} as MapData;
   if(!controller.signal.aborted){setData(next);setDataError(false)}
  }catch{if(!controller.signal.aborted)setDataError(true)}finally{if(!controller.signal.aborted)setLoading(false)}
 },[]);
 useEffect(()=>{const timer=setTimeout(()=>void refresh(),0);return()=>{clearTimeout(timer);request.current?.abort()}},[refresh]);
 useEffect(()=>{
  let pending:AbortController|null=null;
  const timer=setInterval(()=>{
   if(document.hidden||pending)return;
   pending=new AbortController();
   void fetch('/api/map',{cache:'no-store',signal:pending.signal})
    .then(async r=>{if(!r.ok)throw Error();return r.json() as Promise<Pick<MapData,'device'|'deviceState'>>})
    .then(result=>{if(!pending?.signal.aborted)setData(current=>current?{...current,...result}:current)})
    .catch(()=>{}).finally(()=>{pending=null});
  },30000);
  return()=>{clearInterval(timer);pending?.abort()};
 },[]);
 useEffect(()=>{
  if(!mcp)return;
  const controller=new AbortController();
  fetch('/api/mcp/status',{cache:'no-store',signal:controller.signal}).then(async r=>{if(!r.ok)throw new Error();return r.json() as Promise<McpConnection>})
   .then(v=>{if(!controller.signal.aborted)setConnection(v)}).catch(()=>{if(!controller.signal.aborted)setConnection({state:'unavailable',endpoint:null})});
  return()=>controller.abort();
 },[mcp,connectionCheck]);
 useEffect(()=>{
  let disposed=false;
  initialView.current=new URLSearchParams(window.location.search).get('demo')==='front-street'?demoHome:home;
  const startFallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}},p=>setSelection(p));
   if(!result)return;map.current=result.controls;result.controls.flyTo({...initialView.current,duration:1});fallbackUpdate.current=result.setFeatures;setFallback(true);
  };
  void(async()=>{try{
   const lib=await import('maplibre-gl');if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...initialView.current,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;glMap.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true,customAttribution:'DataSF'}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','Map of San Francisco with real data only. Violet areas show how many noise complaints (311) and police noise-nuisance calls were reported in the last 24 hours: darker means more reports, not louder sound, and areas without colour have no reports (unknown, not quiet). Black dots are measurements: SFO monitors and shared phone readings (uncalibrated). Gray marks are permits, closures, calls and complaints; white rings are unmeasured candidate places.');
   instance.on('load',()=>{if(!disposed){setReady(true);setFailed(false)}});
   filterRef.current=f=>{if(instance.getLayer('report-field'))instance.setFilter('report-field',f==='all'?null:['==',['get','level'],f])};
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   const ids=[...layerRows.flatMap(r=>r.mapIds).filter(id=>id!=='report-field'),'venue-points'];
   for(const id of ids){instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''})}
   instance.on('click',e=>{
    const f=instance.queryRenderedFeatures(e.point,{layers:ids})[0];
    if(f){setSelection(f.properties as Properties);return}
    const cell=instance.getLayer('report-field')?instance.queryRenderedFeatures(e.point,{layers:['report-field']})[0]:undefined;
    if(cell){setSelection({label:'Reported noise in this area',evidence:'report_density',kind:'311 + police noise-nuisance count',caveat:describeCell(cell.properties as Parameters<typeof describeCell>[0])+' Source: DataSF 311 cases and SFPD dispatch calls.'});return}
    setSelection({label:'This location',evidence:'unmeasured_candidate',caveat:'No sound measurement is available at this location.'});
   });
  }catch{try{await startFallback()}catch{if(!disposed)setFailed(true)}}})();
  return()=>{disposed=true;map.current?.remove();map.current=null;glMap.current=null;fallbackUpdate.current=null};
 },[]);
 useEffect(()=>{
  const gl=glMap.current;if(!ready)return;
  const features:PointFeature[]=[];
  for(const row of layerRows){
   if(row.key==='field')continue;
   const collection=data?.[row.key]||emptyCollection();
   const visible=shown[row.key];
   if(sourceData.current[row.key]!==collection){(gl?.getSource(row.key) as GeoJSONSource|undefined)?.setData(collection as PointCollection);sourceData.current[row.key]=collection;}
   for(const id of row.mapIds)if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',visible?'visible':'none');
   if(visible)features.push(...collection.features as PointFeature[]);
  }
  // The violet field is built only from what DataSF returned (311 + police calls). If both fail it stays empty.
  const key=(data?.reports.features.length||0)+':'+(data?.cad.features.length||0);
  if(fieldKey.current!==key){fieldKey.current=key;(gl?.getSource('field') as GeoJSONSource|undefined)?.setData(report.collection as unknown as Parameters<GeoJSONSource['setData']>[0])}
  for(const id of ['report-field'])if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',shown.field?'visible':'none');
  // Venue pins are grey (no data) unless a released shared measurement exists for that venue.
  const deviceFeatures=data?.device.features||[];
  const venueFeatures=venues.map(v=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[v.lng,v.lat]},properties:venuePin(venueMapProperties(v),v.id,deviceFeatures) as Properties}));
  const venueKey=venueFeatures.map(f=>f.properties.evidence+':'+f.properties.dbfs).join('|');
  if(gl&&venueKeyRef.current!==venueKey){venueKeyRef.current=venueKey;(gl.getSource('venuepts') as GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:venueFeatures} as unknown as Parameters<GeoJSONSource['setData']>[0])}
  features.push(...venueFeatures);
  fallbackUpdate.current?.(features);
 },[data,ready,shown,fallback,report]);
 useEffect(()=>{filterRef.current(filter)},[filter,ready]);
 useEffect(()=>{
  const key=(e:KeyboardEvent)=>{if(e.key==='Escape'){setSelection(null);setHist(false);if(mcp){setMcp(false);mcpButton.current?.focus()}}};
  document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 useEffect(()=>{
  if(!mcp)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{if(e.key!=='Tab')return;const controls=Array.from(dialog.current?.querySelectorAll<HTMLElement>('button,a[href],input,textarea,summary,[tabindex="0"]')||[]).filter(el=>el.tabIndex>=0&&!el.matches(':disabled')&&el.getClientRects().length>0);if(!controls.length)return;const first=controls[0],last=controls[controls.length-1];if(!dialog.current?.contains(document.activeElement)){e.preventDefault();(e.shiftKey?last:first).focus()}else if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}};
  document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 const reportsOk=!!data&&!data.failed.includes('reports'),callsOk=!!data&&!data.failed.includes('cad');
 const sourceLine=loading?'Loading real data from DataSF, SFO and the shared phone map…':!reportsOk&&!callsOk?'DataSF could not be reached. No report density is shown: unknown, not quiet.':FIELD_SOURCES+(data?' Updated '+new Date(data.fetchedAt).toLocaleString('en-US',{dateStyle:'medium',timeStyle:'short'}):'')+(!reportsOk||!callsOk?'. One report source was unavailable, so counts are incomplete.':'.');
 const entries=data?.device.features||[];
 const count=data?['device','measured','sfoEvents'].reduce((sum,key)=>sum+data[key as Exclude<LayerKey,'field'>].features.length,0):0;
 function openMcp(){setConnection({state:'checking',endpoint:null});setCopied(null);setCopyError(false);setMcp(true)}
 function reset(){map.current?.flyTo({...initialView.current,duration:1000});setSelection(null);setFilter('all')}
 async function copyText(key:string,text:string){setCopyError(false);try{await navigator.clipboard.writeText(text);setCopied(key);setTimeout(()=>setCopied(c=>c===key?null:c),1800)}catch{setCopied(null);setCopyError(true)}}
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset starting view" aria-label="Reset starting view"><Compass size={25} strokeWidth={1.4}/></button>
  <div className="quiet-filters" role="group" aria-label="Filter areas by number of reports" title={FILTER_NOTE}>{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} title={f.hint} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>
  <button className="quiet-mcp" ref={mcpButton} onClick={openMcp} aria-haspopup="dialog"><Plug size={14}/>MCP</button>
  {selection&&<aside className={'quiet-card '+(measured(selection)?'':'is-unmeasured')} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close place details" onClick={()=>setSelection(null)}><X size={16}/></button>
   <strong>{selection.label||selection.name||'Location'}</strong>
   <span className={'quiet-card-level '+(measured(selection)?'':'quiet-card-none')}>{measurementText(selection)}</span>
   {selection.kind&&<p>{selection.kind}</p>}
   {selection.observedOn&&<small>Observed: {selection.observedOn.replace('T',' ').replace(/\.\d+$/,'')}</small>}
   {selection.detail&&<p>{selection.detail}</p>}
   <p>{selection.caveat}</p>
   {selection.dataset&&<a className="quiet-source-link" href={`https://data.sf.gov/resource/${encodeURIComponent(selection.dataset)}.json`} target="_blank" rel="noreferrer">View source ↗</a>}
   {selection.id&&<a className="quiet-share quiet-open" href={'/venue?v='+encodeURIComponent(selection.id)}>Venue details</a>}
  </aside>}
  <a className="quiet-venue-btn quiet-icon" href="/venue" title="Venue data" aria-label="Venue data"><Building2 size={18}/></a>
  <button className="quiet-history-btn quiet-icon" aria-label="Open agent contributions" title="Agent contributions" aria-expanded={hist} onClick={()=>setHist(v=>!v)}><Users size={18}/></button>
  {hist&&<aside className="quiet-history" aria-label="Agent contributions">
   <div className="quiet-history-head"><strong>Contributions</strong><button className="quiet-icon" aria-label="Close contributions" onClick={()=>setHist(false)}><X size={16}/></button></div>
   {entries.length?<ul>{entries.map((f,i)=><li key={i}><span>{f.properties.label}</span><code>{measurementText(f.properties)}</code><time>{f.properties.observedOn}</time></li>)}</ul>:<div className="quiet-history-empty"><strong>{loading?'Checking contributions…':'No contributions available'}</strong><p>{dataError?'Could not reach the data service.':data?deviceLabels[data.deviceState]:'Waiting for the data service.'}</p><button className="quiet-share" onClick={()=>{setHist(false);openMcp()}}>Connect your agent</button></div>}
  </aside>}
  <div className="quiet-map-controls"><button className="quiet-icon" title="Refresh real data" aria-label="Refresh real data" disabled={loading} onClick={()=>void refresh()}><RefreshCw size={18}/></button><button className="quiet-icon" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button><button className="quiet-icon" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button></div>
  <section className="quiet-layers" aria-label="Map layers">
   <button className="quiet-layers-head" aria-expanded={layersOpen} onClick={()=>setLayersOpen(!layersOpen)}><Layers size={14}/>Layers</button>
   {layersOpen&&<p className="quiet-data-status" role="status">{loading?'Loading city data…':dataError?"Couldn't load the city data. Try refresh.":`${count} places with real measurements`}</p>}
   {layersOpen&&<ul>{layerRows.map(r=><li key={r.key}><label title={r.hint}><input type="checkbox" checked={shown[r.key]} onChange={()=>setShown(s=>({...s,[r.key]:!s[r.key]}))}/><i className={'quiet-swatch swatch-'+r.swatch} aria-hidden="true"/><span>{r.label} {data&&(r.key==='field'?<small>({report.cells} areas)</small>:<small>({data[r.key].features.length})</small>)}</span><em>{r.tag}</em></label></li>)}</ul>}
  </section>
  <span className="quiet-source" role="status" title="Violet = number of real reports per area (311 complaints + police noise-nuisance calls, last 24 hours). Dark, gray and ringed marks are other real data, labelled by what they are.">{sourceLine}</span>
  {!loading&&!reportsOk&&!callsOk&&<div className="quiet-data-error" role="status">DataSF could not be reached, so there is no report density to show. Nothing is simulated in its place.</div>}
  <div className="quiet-reportlegend" role="img" aria-label="Reported noise: lighter violet means fewer reports, darker violet means more reports in the last 24 hours. Counts of complaints and calls, not decibels. Grey means no data: no reports, so unknown, not quiet." title={FIELD_NOTE}><b>Reports, last 24 hours · not dB</b><div><em>Fewer</em><span/><em>More</em></div><small><i className="quiet-nodata-swatch" aria-hidden="true"/>Grey = no data (not quiet)</small></div>
  {mcp&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <header className="quiet-mcp-heading">
    <div><h1 id="mcp-title"><Plug size={18} aria-hidden="true"/>MCP connection</h1><div className="quiet-mcp-state" role="status" data-state={connection.state}><span/>{connectionLabels[connection.state]||'Server unavailable'}</div></div>
    <button ref={closeButton} className="quiet-icon" aria-label="Close MCP" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><X size={20}/></button>
   </header>
   <div className="quiet-mcp-body">
    <section className="quiet-mcp-intro" aria-labelledby="mcp-intro-title">
     <h2 id="mcp-intro-title">Contribute once.<br/>Ask for 15 minutes.</h2>
     <p className="quiet-exchange-detail">With your permission, an agent shares a recent sound summary and receives 15 minutes of access to the shared map. Repeating the same summary does not renew access.</p>
     <a className="quiet-mcp-phone" href="/measure"><Smartphone size={17} aria-hidden="true"/>Measure with your phone<ArrowUpRight size={16} aria-hidden="true"/></a>
    </section>
    {(connection.state!=='available'||(tab==='dot'&&!connection.dotReady))&&<div className="quiet-mcp-notice" aria-busy={connection.state==='checking'}>
     <p>{connection.state==='checking'?'Checking the shared connection…':connection.state==='available'?'ChatGPT Dot sign-in needs the latest server update.': 'The shared connection needs server setup. Check again after updating your server.'}</p>
     <button disabled={connection.state==='checking'} onClick={()=>{dialog.current?.querySelector<HTMLInputElement>('#mcp-url')?.focus();setConnection({state:'checking',endpoint:null});setConnectionCheck(v=>v+1)}}><RefreshCw size={14} aria-hidden="true"/>{connection.state==='checking'?'Checking…':'Check again'}</button>
    </div>}
    <section className="quiet-mcp-setup" aria-label="Agent configuration">
     <label className="quiet-mcp-label" htmlFor="mcp-url">Server URL{tab==='dot'&&!connection.dotReady&&<span>Server update needed</span>}</label>
     <div className="quiet-field"><input id="mcp-url" readOnly value={displayedUrl} onFocus={e=>e.currentTarget.select()}/><button className="quiet-icon" aria-label={copied==='url'?'URL copied':'Copy server URL'} title="Copy server URL" onClick={()=>copyText('url',displayedUrl)}>{copied==='url'?<Check size={16}/>:<Copy size={16}/>}</button></div>
     <div className="quiet-tabs" role="tablist" aria-label="How to connect">{(Object.keys(snippets) as (keyof typeof snippets)[]).map(k=><button key={k} id={'mcp-tab-'+k} role="tab" aria-selected={tab===k} aria-controls="mcp-config" tabIndex={tab===k?0:-1} className={tab===k?'is-active':''} onClick={()=>{setTab(k);setCopied(null);setCopyError(false)}} onKeyDown={e=>{
      const keys=Object.keys(snippets) as (keyof typeof snippets)[];
      const index=keys.indexOf(k);
      const next=e.key==='ArrowRight'?keys[(index+1)%keys.length]:e.key==='ArrowLeft'?keys[(index+keys.length-1)%keys.length]:e.key==='Home'?keys[0]:e.key==='End'?keys[keys.length-1]:null;
      if(next){e.preventDefault();setTab(next);setCopied(null);setCopyError(false);document.getElementById('mcp-tab-'+next)?.focus()}
     }}>{snippets[k].label}</button>)}</div>
     <div id="mcp-config" role="tabpanel" aria-labelledby={'mcp-tab-'+tab} className="quiet-snippet">
      <div className="quiet-snippet-toolbar"><span>{tab==='dot'?'ChatGPT setup':tab==='code'?'Terminal command':tab==='app'?'Connector settings':tab==='json'?'MCP configuration':'Agent instructions'}</span><button onClick={()=>copyText('snippet',snippets[tab].text)} aria-label={'Copy '+snippets[tab].label}>{copied==='snippet'?<Check size={14}/>:<Copy size={14}/>}<span>{copied==='snippet'?'Copied':'Copy'}</span></button></div>
      <pre key={tab} tabIndex={0} className={tab==='prompt'?'is-prose':undefined} aria-label={snippets[tab].label+' content'}>{snippets[tab].text}</pre>
     </div>
     <p className="quiet-mcp-hint">{tab==='dot'?'Choose OAuth in ChatGPT. Enter the shared access key only on the Quiet Compass authorization page.':<>For other MCP clients, replace <code>YOUR_SHARED_TOKEN</code> with the shared access key. Never use the private owner key.</>}</p>
     <p className={copyError?'quiet-copy-feedback is-error':'quiet-copy-feedback'} role="status">{copyError?'Could not copy. Select the text and copy it manually.':copied?(copied==='url'?'Server URL copied.':'Copied to clipboard.'):''}</p>
    </section>
    <details className="quiet-mcp-tools"><summary><span>Available tools <small>{sharedTools.length}</small></span><ChevronDown size={16} aria-hidden="true"/></summary><ul className="quiet-tools">{sharedTools.map(t=><li key={t.name}><code>{t.name}</code><span>{t.purpose}</span></li>)}</ul></details>
   </div>
  </div></div>}
 </main>;
}
