'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {Building2,Check,Compass,Copy,Layers,Plug,Users,Minus,Plus,RefreshCw,RotateCcw,X} from 'lucide-react';
import type {PointFeature as Feature,PointCollection} from '../lib/map-types';
import type {StyleSpecification,GeoJSONSource,Map as GLMap} from 'maplibre-gl';
import {connectionGuide,sharedTools} from '../lib/mcp-exchange.mjs';
import {loadSfLayers} from '../lib/sf-layers.mjs';
import {loadNoiseReports,emptyCollection,measurementText} from '../lib/real-map.mjs';
import {venues} from '../lib/venues';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';

type LayerKey='device'|'measured'|'sfoEvents'|'crowd'|'proxies'|'cad'|'candidates'|'reports';
const layerRows:{key:LayerKey;label:string;tag:string;swatch:string;mapIds:string[];hint:string}[]=[
 {key:'device',label:'Shared device readings',tag:'last 24 hours',swatch:'measured',mapIds:['device-readings'],hint:'Real device readings only; relative dBFS, never combined across capture profiles.'},
 {key:'measured',label:'Airport monitors',tag:'measured · dated',swatch:'measured',mapIds:['measured-sfo'],hint:'Daily CNEL at the monitor. Published monthly; not live.'},
 {key:'crowd',label:'NoiseCapture cells',tag:'historical · uncalibrated',swatch:'crowd',mapIds:['crowd-cells'],hint:'Archived volunteer phone measurements from 2017–2025; not live or dBA.'},
 {key:'sfoEvents',label:'Airport loud events',tag:'measured · last year',swatch:'events',mapIds:['measured-sfo-events'],hint:'Only events above the monitor threshold, not the typical sound level.'},
 {key:'candidates',label:'Parks, POPOS & libraries',tag:'no measurement',swatch:'candidate',mapIds:['candidate-places'],hint:'Real city locations. No sound measurement at these places.'},
 {key:'reports',label:'311 complaints',tag:'reports · no measurement',swatch:'report',mapIds:['noise-reports'],hint:'Latest 100 published complaints. Not sound measurements.'},
 {key:'cad',label:'Noise-nuisance calls',tag:'reports · last 30 days',swatch:'cad',mapIds:['cad-calls'],hint:'Counts at masked intersections, not sound levels.'},
 {key:'proxies',label:'Permits & closures',tag:'context · no measurement',swatch:'proxy',mapIds:['proxy-context'],hint:'Permits and closures do not establish a sound level.'},
];
type Properties={label?:string;name?:string;id?:string;evidence?:string;kind?:string;detail?:string;caveat?:string;observedOn?:string;dataset?:string;dbfs?:number;cnel?:number;medianDb?:number;maxDb?:number;count?:number;captureProfile?:string};
type PointFeature=Feature<Properties>;
type MapData=Record<LayerKey,PointCollection<Properties>>&{failed:string[];fetchedAt:string;deviceState:string};
type McpConnection={state:string;endpoint:string|null};
const connectionLabels:Record<string,string>={checking:'Checking server…',available:'Shared MCP available',not_configured:'Server setup needed',invalid_config:'Check server address',unavailable:'Server unavailable',disabled:'Shared access setup needed',incompatible:'Server update needed'};
const deviceLabels:Record<string,string>={available:'Device measurements available',empty:'No published device readings in the last 24 hours',access_required:'Device readings require a contribution and authorized access',invalid_config:'Device server setup needed',unavailable:'Device readings unavailable'};
const home={center:[-122.44,37.768] as [number,number],zoom:12.6,pitch:48,bearing:-12};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
const measured=(p:Properties)=>['measured','measured_crowdsourced','measured_device'].includes(p.evidence||'');
const mapStyle:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},venuepts:{type:'geojson',data:{type:'FeatureCollection',features:venues.map(v=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[v.lng,v.lat]},properties:{id:v.id,label:v.name,name:v.name,kind:'Venue',evidence:'unmeasured_candidate',caveat:'No acoustic measurements or verified indoor plan are available.'}}))}},...Object.fromEntries(layerRows.map(r=>[r.key,{type:'geojson' as const,data:emptyCollection() as PointCollection}]))},
 light:{anchor:'viewport',color:'#ffffff',intensity:.4,position:[1.5,205,40]},
 layers:[
  {id:'background',type:'background',paint:{'background-color':'#e9e9ec'}},
  {id:'land',type:'fill',source:'city','source-layer':'landcover',paint:{'fill-color':'#f3f2f5','fill-opacity':.6}},
  {id:'parks',type:'fill',source:'city','source-layer':'park',paint:{'fill-color':'#f0f0f1','fill-outline-color':'#e8e8eb'}},
  {id:'water',type:'fill',source:'city','source-layer':'water',paint:{'fill-color':'#f6f6f7'}},
  {id:'roads-edge',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#e1e1e5','line-width':['interpolate',['linear'],['zoom'],11,.3,13,.8,16,5,19,20]}},
  {id:'roads',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#ffffff','line-width':['interpolate',['linear'],['zoom'],11,.1,13,.25,16,3.6,19,17]}},
  {id:'footprints',type:'fill',source:'city','source-layer':'building',paint:{'fill-color':'#eae7ed','fill-outline-color':'#dfdbe5'}},
  {id:'structures',type:'fill-extrusion',source:'city','source-layer':'building',minzoom:12.6,filter:['!=',['get','hide_3d'],true],paint:{'fill-extrusion-color':'#d8d8dd','fill-extrusion-height':['interpolate',['linear'],['zoom'],12.6,0,14.2,['coalesce',['get','render_height'],0]],'fill-extrusion-base':['coalesce',['get','render_min_height'],0],'fill-extrusion-opacity':1,'fill-extrusion-vertical-gradient':true}},
  {id:'place-labels',type:'symbol',source:'city','source-layer':'place',minzoom:11,filter:['in',['get','class'],['literal',['suburb','neighbourhood','quarter']]],layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],11,10,15,13],'text-letter-spacing':.08,'text-transform':'uppercase'},paint:{'text-color':'#6b6b73','text-halo-color':'#ffffff','text-halo-width':1.5}},
  {id:'venue-points',type:'circle',source:'venuepts',paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],11,7,15,10],'circle-stroke-color':'#171717','circle-stroke-width':2.2}},
  {id:'venue-labels',type:'symbol',source:'venuepts',minzoom:12,layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':12,'text-offset':[0,1.5],'text-anchor':'top'},paint:{'text-color':'#171717','text-halo-color':'#ffffff','text-halo-width':1.6}},
  {id:'proxy-context',type:'circle',source:'proxies',minzoom:13,layout:{visibility:'none'},paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],13,1.8,17,4],'circle-stroke-color':'#ffffff','circle-stroke-width':1,'circle-opacity':.85}},
  {id:'candidate-places',type:'circle',source:'candidates',minzoom:12,paint:{'circle-color':'#b6b6bd','circle-radius':['interpolate',['linear'],['zoom'],12,3,17,6],'circle-stroke-color':'#8b8b94','circle-stroke-width':1.5}},
  {id:'noise-reports',type:'circle',source:'reports',minzoom:13,paint:{'circle-color':'#52525b','circle-radius':['interpolate',['linear'],['zoom'],13,1.6,17,3.4],'circle-opacity':.6}},
  {id:'cad-calls',type:'circle',source:'cad',minzoom:12,paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],12,['+',2,['*',.25,['min',['get','count'],16]]],17,['+',3,['*',.6,['min',['get','count'],16]]]],'circle-stroke-color':'#71717a','circle-stroke-width':1.4,'circle-opacity':.8}},
  {id:'crowd-cells',type:'circle',source:'crowd',paint:{'circle-color':'#b996f5','circle-radius':['interpolate',['linear'],['zoom'],11,4,16,9],'circle-stroke-color':'#6720c4','circle-stroke-width':1.5}},
  {id:'measured-sfo-events',type:'circle',source:'sfoEvents',paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],11,9,16,15],'circle-stroke-color':'#6720c4','circle-stroke-width':2.2}},
  {id:'measured-sfo',type:'circle',source:'measured',paint:{'circle-color':'#6720c4','circle-radius':['interpolate',['linear'],['zoom'],11,5,16,9],'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
  {id:'device-readings',type:'circle',source:'device',paint:{'circle-color':'#6720c4','circle-radius':7,'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
 ]
};
export default function CityMap(){
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),glMap=useRef<GLMap|null>(null);
 const fallbackUpdate=useRef<((features:PointFeature[])=>void)|null>(null);
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const request=useRef<AbortController|null>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[fallback,setFallback]=useState(false);
 const [data,setData]=useState<MapData|null>(null),[loading,setLoading]=useState(true),[dataError,setDataError]=useState(false);
 const [shown,setShown]=useState<Record<LayerKey,boolean>>({device:true,measured:true,sfoEvents:false,crowd:true,proxies:false,cad:false,candidates:true,reports:true});
 const [filter,setFilter]=useState<'all'|'measured'|'unmeasured'>('all'),[layersOpen,setLayersOpen]=useState(false);
 const [selection,setSelection]=useState<Properties|null>(null),[hist,setHist]=useState(false),[mcp,setMcp]=useState(false);
 const [connection,setConnection]=useState<McpConnection>({state:'checking',endpoint:null}),[copied,setCopied]=useState(false),[copyFallback,setCopyFallback]=useState(false);
 const contract=connectionGuide(connection.endpoint);
 const refresh=useCallback(async()=>{
  request.current?.abort();const controller=new AbortController();request.current=controller;
  setLoading(true);setData(null);setSelection(null);setDataError(false);
  try {
   const fetcher=(url:string)=>fetch(url,{cache:'no-store',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(12000)])});
   const [layers,reports,device]=await Promise.all([
    loadSfLayers(fetcher),
    loadNoiseReports(fetcher).then(data=>({data,failed:false})).catch(()=>({data:emptyCollection(),failed:true})),
    fetcher('/api/map').then(async r=>{if(!r.ok)throw new Error();return r.json() as Promise<Pick<MapData,'device'|'deviceState'>>}).catch(()=>({device:emptyCollection(),deviceState:'unavailable'})),
   ]);
   const next={...layers,reports:reports.data,device:device.device,deviceState:device.deviceState,failed:[...layers.failed,...(reports.failed?['reports']:[])],fetchedAt:new Date().toISOString()} as MapData;
   if(!controller.signal.aborted){setData(next);setDataError(false)}
  }catch{if(!controller.signal.aborted)setDataError(true)}finally{if(!controller.signal.aborted)setLoading(false)}
 },[]);
 useEffect(()=>{void refresh();return()=>request.current?.abort()},[refresh]);
 useEffect(()=>{
  if(!mcp)return;
  const controller=new AbortController();setConnection({state:'checking',endpoint:null});
  fetch('/api/mcp/status',{cache:'no-store',signal:controller.signal}).then(async r=>{if(!r.ok)throw new Error();return r.json() as Promise<McpConnection>})
   .then(v=>{if(!controller.signal.aborted)setConnection(v)}).catch(()=>{if(!controller.signal.aborted)setConnection({state:'unavailable',endpoint:null})});
  return()=>controller.abort();
 },[mcp]);
 useEffect(()=>{
  let disposed=false;
  const startFallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}},p=>setSelection(p));
   if(!result)return;map.current=result.controls;fallbackUpdate.current=result.setFeatures;setFallback(true);
  };
  void(async()=>{try{
   const lib=await import('maplibre-gl');if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...home,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;glMap.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','San Francisco map. Purple points have dated measurements. Gray locations have no sound measurement. Complaints are shown as gray context.');
   instance.on('load',()=>{if(!disposed){setReady(true);setFailed(false)}});
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   const ids=[...layerRows.flatMap(r=>r.mapIds),'venue-points'];
   for(const id of ids){instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''})}
   instance.on('click',e=>{
    const f=instance.queryRenderedFeatures(e.point,{layers:ids})[0];
    if(f){setSelection(f.properties as Properties);return}
    setSelection({label:'This location',evidence:'unmeasured_candidate',caveat:'No sound measurement is available at this location.'});
   });
  }catch{try{await startFallback()}catch{if(!disposed)setFailed(true)}}})();
  return()=>{disposed=true;map.current?.remove();map.current=null;glMap.current=null;fallbackUpdate.current=null};
 },[]);
 useEffect(()=>{
  const gl=glMap.current;if(!ready)return;
  const features:PointFeature[]=[];
  for(const row of layerRows){
   const collection=data?.[row.key]||emptyCollection();
   const visible=shown[row.key]&&(filter==='all'||(filter==='measured')===['device','measured','sfoEvents','crowd'].includes(row.key));
   (gl?.getSource(row.key) as GeoJSONSource|undefined)?.setData(collection as PointCollection);
   for(const id of row.mapIds)if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',visible?'visible':'none');
   if(visible)features.push(...collection.features as PointFeature[]);
  }
  for(const id of ['venue-points','venue-labels'])if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',filter==='measured'?'none':'visible');
  if(filter!=='measured')features.push(...venues.map(v=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:[v.lng,v.lat]},properties:{id:v.id,label:v.name,evidence:'unmeasured_candidate',kind:'Venue',caveat:'No acoustic measurements or verified indoor plan are available.'}})));
  fallbackUpdate.current?.(features);
 },[data,ready,shown,filter,fallback]);
 useEffect(()=>{
  const key=(e:KeyboardEvent)=>{if(e.key==='Escape'){setSelection(null);setHist(false);if(mcp){setMcp(false);mcpButton.current?.focus()}}};
  document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 useEffect(()=>{
  if(!mcp)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{if(e.key!=='Tab')return;const controls=dialog.current?.querySelectorAll<HTMLElement>('button,a[href],textarea');if(!controls?.length)return;const first=controls[0],last=controls[controls.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}};
  document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 const entries=data?.device.features||[];
 const count=data?['device','measured','sfoEvents','crowd'].reduce((sum,key)=>sum+data[key as LayerKey].features.length,0):0;
 function reset(){map.current?.flyTo({...home,duration:1000});setSelection(null);setFilter('all')}
 async function copy(){try{await navigator.clipboard.writeText(JSON.stringify(contract,null,2));setCopied(true)}catch{setCopied(false);setCopyFallback(true)}}
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset San Francisco view" aria-label="Reset San Francisco view"><Compass size={25} strokeWidth={1.4}/></button>
  <button className="quiet-mcp" ref={mcpButton} onClick={()=>{setMcp(true);setCopied(false);setCopyFallback(false)}} aria-haspopup="dialog"><Plug size={14}/>MCP</button>
  <div className="quiet-filters" role="group" aria-label="Filter by measurement availability">{(['all','measured','unmeasured'] as const).map(f=><button key={f} className={filter===f?'is-active':''} aria-pressed={filter===f} onClick={()=>{setFilter(f);setSelection(null)}}>{f==='all'?'All':f==='measured'?'Measured':'No measurement'}</button>)}</div>
  {selection&&<aside className={'quiet-card '+(measured(selection)?'':'is-unmeasured')} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close place details" onClick={()=>setSelection(null)}><X size={16}/></button>
   <strong>{selection.label||selection.name||'Location'}</strong>
   <span className={'quiet-card-level '+(measured(selection)?'':'quiet-card-none')}>{measurementText(selection)}</span>
   {selection.kind&&<p>{selection.kind}</p>}
   {selection.observedOn&&<small>Observed: {selection.observedOn.replace('T',' ').replace(/\.\d+$/,'')}</small>}
   {selection.detail&&<p>{selection.detail}</p>}
   <p>{selection.caveat}</p>
   {selection.dataset&&<a className="quiet-source-link" href={selection.dataset==='noise-planet.org/dump'?'https://noise-planet.org/noisecapture_data.html':`https://data.sf.gov/resource/${encodeURIComponent(selection.dataset)}.json`} target="_blank" rel="noreferrer">View source ↗</a>}
   {selection.id&&<a className="quiet-share quiet-open" href={'/venue?v='+encodeURIComponent(selection.id)}>Venue details</a>}
  </aside>}
  <a className="quiet-venue-btn quiet-icon" href="/venue" title="Venue data" aria-label="Venue data"><Building2 size={18}/></a>
  <button className="quiet-history-btn quiet-icon" aria-label="Open agent contributions" title="Agent contributions" aria-expanded={hist} onClick={()=>setHist(v=>!v)}><Users size={18}/></button>
  {hist&&<aside className="quiet-history" aria-label="Agent contributions">
   <div className="quiet-history-head"><strong>Contributions</strong><button className="quiet-icon" aria-label="Close contributions" onClick={()=>setHist(false)}><X size={16}/></button></div>
   {entries.length?<ul>{entries.map((f,i)=><li key={i}><span>{f.properties.label}</span><code>{measurementText(f.properties)}</code><time>{f.properties.observedOn}</time></li>)}</ul>:<div className="quiet-history-empty"><strong>{loading?'Checking contributions…':'No contributions available'}</strong><p>{dataError?'Could not reach the data service.':data?deviceLabels[data.deviceState]:'Waiting for the data service.'}</p><button className="quiet-share" onClick={()=>{setHist(false);setMcp(true)}}>Connect your agent</button></div>}
  </aside>}
  <div className="quiet-map-controls"><button className="quiet-icon" title="Refresh real data" aria-label="Refresh real data" disabled={loading} onClick={()=>void refresh()}><RefreshCw size={18}/></button><button className="quiet-icon" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button><button className="quiet-icon" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button></div>
  <section className="quiet-layers" aria-label="Map layers">
   <button className="quiet-layers-head" aria-expanded={layersOpen} onClick={()=>setLayersOpen(!layersOpen)}><Layers size={14}/>Layers</button>
   <p className="quiet-data-status" role="status">{loading?'Fetching real data…':dataError?'Data unavailable · no measurements shown':`${count} measurement points · dated records`}</p>
   {layersOpen&&<ul>{layerRows.map(r=><li key={r.key}><label title={r.hint}><input type="checkbox" checked={shown[r.key]} onChange={()=>setShown(s=>({...s,[r.key]:!s[r.key]}))}/><i className={'quiet-swatch swatch-'+r.swatch} aria-hidden="true"/><span>{r.label} {data&&<small>({data[r.key].features.length})</small>}</span><em>{r.tag}</em></label></li>)}</ul>}
   {layersOpen&&data&&<div className="quiet-layers-note"><p>{deviceLabels[data.deviceState]}</p>{data.failed.length>0&&<p role="status">Unavailable: {data.failed.join(', ')}.</p>}<p>Fetched {new Date(data.fetchedAt).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}. Open a point for its measurement date. No interpolation between points.</p><p>NoiseCapture / Noise-Planet community · ODbL 1.0. Historical, uncalibrated phone data.</p></div>}
  </section>
  <div className="quiet-intensity quiet-evidence-legend"><em><i className="measured-key"/>Dated measurement</em><em><i/>No measurement</em></div>
  {mcp&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <div className="quiet-mcp-heading"><strong id="mcp-title">MCP</strong><button ref={closeButton} className="quiet-icon" aria-label="Close MCP" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><X size={18}/></button></div>
   <><div className="quiet-mcp-state" role="status" data-available={connection.state==='available'}><span/>{connectionLabels[connection.state]||'Server unavailable'}</div>
   <p className="quiet-exchange-summary">Contribute once. Ask for 15 minutes.</p>
   <p className="quiet-exchange-detail">With your permission, an agent shares a recent sound summary and receives 15 minutes of access to the shared map. Repeating the same summary does not renew access.</p>
   <p className="quiet-exchange-detail">{connection.endpoint?'Add this address to your agent and use the shared access key provided by the server owner.':connection.state==='not_configured'?'Deploy the server and configure its address to enable agent connections.':'The shared connection is not ready. Check the server setup and reopen this panel to retry.'}</p>
   {connection.endpoint&&<code className="quiet-endpoint">{connection.endpoint}</code>}
   <div className="quiet-tool-list">{sharedTools.map(t=><code key={t.name}>{t.name}<span>{t.purpose}</span></code>)}</div>
   <button className="quiet-copy" onClick={copy} aria-label={copied?'Setup copied':'Copy MCP setup'} title={copied?'Copied':'Copy setup'}>{copied?<Check size={17}/>:<Copy size={17}/>}</button>{copyFallback&&<textarea className="quiet-contract" aria-label="MCP setup for manual copying" readOnly value={JSON.stringify(contract,null,2)} onFocus={e=>e.currentTarget.select()}/>}</>
  </div></div>}
 </main>;
}
