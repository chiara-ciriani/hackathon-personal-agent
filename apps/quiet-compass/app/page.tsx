'use client';
import {useEffect,useRef,useState} from 'react';
import {Building2,Check,Compass,Copy,Layers,Plug,Minus,Plus,RotateCcw,X} from 'lucide-react';
import type {StyleSpecification} from 'maplibre-gl';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';
import {loadSfLayers,REFERENCE_LEVELS,REFERENCE_NOTE} from '../lib/sf-layers.mjs';
import {buildReportField,describeCell,FIELD_NOTE,FIELD_SOURCES,FILTER_NOTE,load311Reports} from '../lib/noise-field.mjs';

// Every value on this map comes from a published dataset. Nothing is invented, simulated or filled in.
type Level='few'|'some'|'many';
const emptyCollection={type:'FeatureCollection' as const,features:[]};
function ago(at:string){const t=new Date(at+'-07:00').getTime();if(!Number.isFinite(t))return at.slice(0,10);const m=Math.round((Date.now()-t)/60000);return m<60?m+' min ago':m<1440?Math.round(m/60)+' h ago':Math.round(m/1440)+' d ago'}
// Colour = number of reports in the area (sqrt-scaled, capped at the 95th percentile). Not a sound level.
const reportRamp:import('maplibre-gl').ExpressionSpecification=['interpolate',['linear'],['get','t'],0,'#e6dcff',.3,'#b996f5',.55,'#8a45e8',.8,'#5a14b0',1,'#2b0a63'];
const mapStyle:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},field:{type:'geojson',data:{type:'FeatureCollection',features:[]}},reports:{type:'geojson',data:{type:'FeatureCollection',features:[]}},measured:{type:'geojson',data:{type:'FeatureCollection',features:[]}},sfoEvents:{type:'geojson',data:{type:'FeatureCollection',features:[]}},crowd:{type:'geojson',data:{type:'FeatureCollection',features:[]}},cad:{type:'geojson',data:{type:'FeatureCollection',features:[]}},proxies:{type:'geojson',data:{type:'FeatureCollection',features:[]}},candidates:{type:'geojson',data:{type:'FeatureCollection',features:[]}}},
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
  // Violet = how many real reports (311 + police noise-nuisance calls) fall in each ~280 m area. Areas with no reports have no fill: unknown, not quiet.
  {id:'report-field',type:'fill',source:'field',paint:{'fill-color':reportRamp,'fill-opacity':.55,'fill-outline-color':'#ffffff00'}},
  {id:'place-labels',type:'symbol',source:'city','source-layer':'place',minzoom:11,filter:['in',['get','class'],['literal',['suburb','neighbourhood','quarter']]],layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':['interpolate',['linear'],['zoom'],11,10,15,13],'text-letter-spacing':.08,'text-transform':'uppercase'},paint:{'text-color':'#6b6b73','text-halo-color':'#ffffff','text-halo-width':1.5}},
  // Real layers stay out of the violet scale: ink for measured, grays for the rest. Violet is reserved for the reported-noise density.
  {id:'proxy-context',type:'circle',source:'proxies',minzoom:13,layout:{visibility:'none'},paint:{'circle-color':'#a1a1aa','circle-radius':['interpolate',['linear'],['zoom'],13,1.8,17,4],'circle-stroke-color':'#ffffff','circle-stroke-width':1,'circle-opacity':.85}},
  {id:'candidate-places',type:'circle',source:'candidates',minzoom:12,paint:{'circle-color':'#ffffff','circle-radius':['interpolate',['linear'],['zoom'],12,3,17,6],'circle-stroke-color':'#171717','circle-stroke-width':1.5}},
  {id:'noise-reports',type:'circle',source:'reports',minzoom:13,paint:{'circle-color':'#52525b','circle-radius':['interpolate',['linear'],['zoom'],13,1.6,17,3.4],'circle-opacity':.6}},
  {id:'cad-calls',type:'circle',source:'cad',minzoom:12,paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],12,['+',2,['*',.25,['min',['get','count'],16]]],17,['+',3,['*',.6,['min',['get','count'],16]]]],'circle-stroke-color':'#71717a','circle-stroke-width':1.4,'circle-opacity':.8}},
  {id:'crowd-cells',type:'circle',source:'crowd',paint:{'circle-color':'#17171799','circle-radius':['interpolate',['linear'],['zoom'],11,4,16,9],'circle-stroke-color':'#171717','circle-stroke-width':1.5}},
  {id:'measured-sfo-events',type:'circle',source:'sfoEvents',paint:{'circle-color':'#ffffff00','circle-radius':['interpolate',['linear'],['zoom'],11,9,16,15],'circle-stroke-color':'#171717','circle-stroke-width':2.2}},
  {id:'measured-sfo',type:'circle',source:'measured',paint:{'circle-color':'#171717','circle-radius':['interpolate',['linear'],['zoom'],11,5,16,9],'circle-stroke-color':'#ffffff','circle-stroke-width':2}},
 ]
};
// A contribution carries only a coarse zone, a level and a rounded time. No agent id, no audio, no route.
// Evidence labels stay separate: measured / measured crowdsourced / proxy / unmeasured candidate / reports. Unknown is not quiet.
type LayerKey='field'|'measured'|'sfoEvents'|'crowd'|'proxies'|'cad'|'candidates'|'reports';
const layerRows:{key:LayerKey;label:string;tag:string;swatch:string;mapIds:string[];hint:string}[]=[
 {key:'measured',label:'Airport monitors',tag:'measured',swatch:'measured',mapIds:['measured-sfo'],hint:'Daily CNEL in dB at 6 SFO monitors inside SF. Not live, not at your spot.'},
 {key:'sfoEvents',label:'Airport loud events',tag:'measured',swatch:'events',mapIds:['measured-sfo-events'],hint:'Aircraft noise exceedance events per SFO monitor, last 365 days: count, median and max dBA, latest date. Only events above each monitor threshold are published. No license declared.'},
 {key:'crowd',label:'NoiseCapture cells',tag:'crowdsourced, uncalibrated',swatch:'crowd',mapIds:['crowd-cells'],hint:'About 20 cells of ~100 m with 3+ volunteer tracks, 2017-2025. Uncalibrated phones, several dB of error, not dBA. ODbL, NoiseCapture / Noise-Planet.'},
 {key:'proxies',label:'Permits & closures',tag:'indirect',swatch:'proxy',mapIds:['proxy-context'],hint:'Entertainment permits, night work today or tomorrow, street closures now. Possible noise, not levels.'},
 {key:'cad',label:'Noise-nuisance calls',tag:'indirect',swatch:'cad',mapIds:['cad-calls'],hint:'Police dispatches classified NOISE NUISANCE per masked intersection, last 30 days. Complaints, not measurements.'},
 {key:'candidates',label:'Parks, POPOS & libraries',tag:'unmeasured',swatch:'candidate',mapIds:['candidate-places'],hint:'Places from city inventories that might be calm (parks and playgrounds can be loud). Nobody has measured them.'},
 {key:'reports',label:'311 complaints',tag:'reports',swatch:'report',mapIds:['noise-reports'],hint:'311 noise complaints, last 30 days, at the published location. A complaint is not a measurement.'},
 {key:'field',label:'Reported noise density',tag:'reports, not dB',swatch:'field',mapIds:['report-field'],hint:FIELD_NOTE},
];
const filters:{id:Level|'all';label:string;hint:string}[]=[{id:'all',label:'All',hint:'Every area with reports.'},{id:'few',label:'Fewer',hint:'Lowest third of areas by number of reports. '+FILTER_NOTE},{id:'some',label:'Mid',hint:'Middle third of areas by number of reports. '+FILTER_NOTE},{id:'many',label:'Most',hint:'Highest third of areas by number of reports. '+FILTER_NOTE}];
const home={center:[-122.44,37.768] as [number,number],zoom:12.6,pitch:48,bearing:-12};
const contract={name:'quiet-compass',status:'proposal',connected:false,data:'real data only: DataSF 311 + police noise-nuisance report density, SFO monitors, NoiseCapture, permits/closures, parks/POPOS/libraries (labelled measured / measured crowdsourced / proxy / unmeasured candidate)',tools:[{name:'quiet_sf_layers',input:{lat:'number',lon:'number',radius_m:'50-2000',include:'quiet_candidates | entertainment_permits | night_noise_permits | street_closures | sfo_cnel | sfo_events | cad_noise_calls | noisecapture',include_references:'boolean'},returns:'points with evidence = measured | measured_crowdsourced | proxy | unmeasured_candidate (source seed), optional reference_measured table'},{name:'query_sound_map',input:{bounds:'[west,south,east,north]',max_age_minutes:'number'}},{name:'find_suitable_places',input:{area:'coarse zone',preference:'user-selected acoustic preference'}},{name:'submit_observation',input:{zone_id:'coarse zone',time_bucket:'rounded time',acoustic_summary:'aggregated calibrated indicators'},requires:'explicit contribution consent'}],excluded:['raw_audio','personal_routes','health_data']};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;easeTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
export default function CityMap(){
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),glMap=useRef<import('maplibre-gl').Map|null>(null),filterRef=useRef<(f:Level|'all')=>void>(()=>{});
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[mcp,setMcp]=useState(false),[shown,setShown]=useState<Record<LayerKey,boolean>>({field:true,measured:true,sfoEvents:true,crowd:true,proxies:false,cad:false,candidates:true,reports:true}),[failedLayers,setFailedLayers]=useState<string[]>([]),[layersOpen,setLayersOpen]=useState(false),[copied,setCopied]=useState(false),[copyFallback,setCopyFallback]=useState(false),[filter,setFilter]=useState<Level|'all'>('all');
 const [data,setData]=useState<{state:'loading'|'ok'|'partial'|'failed'|'basemap';total:number;cells:number;at:string}>({state:'loading',total:0,cells:0,at:''});
 useEffect(()=>{
  let disposed=false;
  const fallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');
   if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,[],()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}});
   if(!result)return;
   map.current=result.controls;
   setData({state:'basemap',total:0,cells:0,at:''});
  };
  const start=async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...home,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;glMap.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','Map of San Francisco with real data only. Violet areas show how many noise complaints (311) and police noise-nuisance calls were reported in the last 30 days: darker means more reports, not louder sound, and areas without colour have no reports (unknown, not quiet). Filled and ringed dark dots are SFO noise monitors (measured), semi-filled dark dots are NoiseCapture phone cells (crowdsourced, uncalibrated), small gray dots are permits and closures and gray rings are noise-nuisance call counts (proxies), white rings are unmeasured candidate places, tiny gray dots are 311 noise complaints.');
   const setSource=(id:string,d:unknown)=>(instance.getSource(id) as import('maplibre-gl').GeoJSONSource|undefined)?.setData(d as Parameters<import('maplibre-gl').GeoJSONSource['setData']>[0]);
   instance.on('load',()=>{
    if(disposed)return;setReady(true);setFailed(false);
    const layers=loadSfLayers().then(r=>{if(disposed)return r;setSource('candidates',r.candidates);setSource('proxies',r.proxies);setSource('measured',r.measured);setSource('sfoEvents',r.sfoEvents);setSource('crowd',r.crowd);setSource('cad',r.cad);setFailedLayers(r.failed);return r}).catch(()=>{if(!disposed)setFailedLayers(['measured','sfoEvents','crowd','proxies','cad','candidates']);return null});
    const reports=load311Reports().catch(()=>null);
    // The violet field is built only from what DataSF returned. If both report sources fail it stays empty.
    void Promise.all([layers,reports]).then(([r,rep])=>{
     if(disposed)return;
     if(rep)setSource('reports',rep);
     const cadOk=!!r&&!r.failed.includes('cad');
     const built=buildReportField(rep?.features||[],cadOk?r!.cad.features:[]);
     setSource('field',built.collection);
     const state=!rep&&!cadOk?'failed':!rep||!cadOk?'partial':'ok';
     setData({state,total:built.total,cells:built.cells,at:new Date().toLocaleString('en-US',{dateStyle:'medium',timeStyle:'short'})});
    });
   });
   const ids=['measured-sfo','measured-sfo-events','crowd-cells','cad-calls','proxy-context','candidate-places','noise-reports','report-field'];
   instance.on('click','noise-reports',e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {kind:string;place:string;at:string};new lib.Popup({closeButton:false,className:'report-popup',maxWidth:'280px'}).setLngLat(e.lngLat).setText('311 noise report · '+p.kind+(p.place?' · '+p.place:'')+' · '+ago(p.at)+' · Source: DataSF 311 cases. A complaint, not a measurement.').addTo(instance)});
   instance.on('click','report-field',e=>{
    if(instance.queryRenderedFeatures(e.point,{layers:ids.filter(x=>x!=='report-field')}).length)return;
    const f=e.features?.[0];if(!f)return;
    new lib.Popup({closeButton:false,className:'report-popup',maxWidth:'300px'}).setLngLat(e.lngLat).setText(describeCell(f.properties as Parameters<typeof describeCell>[0])+' Source: DataSF 311 cases and SFPD dispatch calls.').addTo(instance)});
   for(const id of ['measured-sfo','measured-sfo-events','crowd-cells','cad-calls','proxy-context','candidate-places']){
    instance.on('click',id,e=>{const f=e.features?.[0];if(!f)return;const p=f.properties as {evidence:string;kind:string;label:string;detail?:string;cnel?:number;count?:number;medianDb?:number;maxDb?:number;laeqDb?:number;observedOn?:string;dataset?:string;caveat:string};
     const head=p.evidence==='measured_crowdsourced'?'MEASURED, CROWDSOURCED, UNCALIBRATED · '+p.kind+' · median 5-min '+p.medianDb+' dB (energy mean '+p.laeqDb+')':p.evidence==='measured'?(p.cnel!==undefined?'MEASURED · '+p.kind+' · CNEL '+p.cnel+' dB ('+p.observedOn+')':'MEASURED · '+p.kind+' · '+p.count+' events, median '+p.medianDb+' dBA, max '+p.maxDb+' dBA, latest '+p.observedOn):p.evidence==='proxy'?'PROXY · '+p.kind:'UNMEASURED CANDIDATE · '+p.kind;
     new lib.Popup({closeButton:false,className:'report-popup',maxWidth:'280px'}).setLngLat(e.lngLat).setText(head+' · '+p.label+(p.detail?' · '+p.detail:'')+' · Source: '+(p.dataset?(p.dataset.includes('.')?p.dataset:'DataSF '+p.dataset):'DataSF')+' · '+p.caveat).addTo(instance)});
   }
   for(const id of ids){instance.on('mouseenter',id,()=>{instance.getCanvas().style.cursor='pointer'});instance.on('mouseleave',id,()=>{instance.getCanvas().style.cursor=''})}
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   filterRef.current=f=>{if(instance.getLayer('report-field'))instance.setFilter('report-field',f==='all'?null:['==',['get','level'],f])};
  }catch{try{await fallback()}catch{if(!disposed)setFailed(true)}}};
  void start();
  return()=>{disposed=true;map.current?.remove();map.current=null};
 },[]);
 useEffect(()=>{const gl=glMap.current;for(const row of layerRows){for(const id of row.mapIds){if(gl?.getLayer(id))gl.setLayoutProperty(id,'visibility',shown[row.key]?'visible':'none')}}},[shown,ready]);
 useEffect(()=>{filterRef.current(filter)},[filter,ready]);
 useEffect(()=>{
  if(!mcp)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{
   if(e.key==='Escape'){setMcp(false);mcpButton.current?.focus()}
   if(e.key==='Tab'){const buttons=dialog.current?.querySelectorAll<HTMLButtonElement>('button');if(!buttons?.length)return;const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}
  };document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp]);
 function reset(){map.current?.flyTo({...home,duration:1000});setFilter('all')}
 async function copy(){try{await navigator.clipboard.writeText(JSON.stringify(contract,null,2));setCopied(true)}catch{setCopied(false);setCopyFallback(true)}}
 const sourceLine=data.state==='loading'?'Loading real data from DataSF, SFO and NoiseCapture…':data.state==='basemap'?'Basemap only. No data layers: this browser could not start the WebGL map.':data.state==='failed'?'DataSF could not be reached. No report density is shown: unknown, not quiet.':FIELD_SOURCES+' Updated '+data.at+(data.state==='partial'?'. One report source was unavailable, so counts are incomplete.':'.');
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset San Francisco view" aria-label="Reset San Francisco view"><Compass size={25} strokeWidth={1.4}/></button>
  <button className="quiet-mcp" ref={mcpButton} onClick={()=>{setMcp(true);setCopied(false);setCopyFallback(false)}} aria-haspopup="dialog"><Plug size={14} strokeWidth={1.5}/>MCP</button>
  <div className="quiet-filters" role="group" aria-label="Filter areas by number of reports" title={FILTER_NOTE}>{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} title={f.hint} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>
  <a className="quiet-venue-btn quiet-icon" href="/venue" title="Event venue in 3D" aria-label="Event venue in 3D"><Building2 size={18} strokeWidth={1.5}/></a>
  <div className="quiet-map-controls">
   <button className="quiet-icon" title="Zoom in" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button>
   <button className="quiet-icon" title="Zoom out" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button>
  </div>
  <section className="quiet-layers" aria-label="Map layers">
   <button className="quiet-layers-head" aria-expanded={layersOpen} onClick={()=>setLayersOpen(!layersOpen)}><Layers size={14}/>Layers</button>
   {layersOpen&&<ul>{layerRows.map(r=><li key={r.key}><label title={r.hint}><input type="checkbox" checked={shown[r.key]} onChange={()=>setShown({...shown,[r.key]:!shown[r.key]})}/><i className={'quiet-swatch swatch-'+r.swatch} aria-hidden="true"/><span>{r.label}</span><em>{r.tag}</em></label></li>)}</ul>}
   {layersOpen&&failedLayers.length>0&&<p className="quiet-layers-warn" role="status">Couldn&apos;t load {failedLayers.join(', ')}. Unknown, not quiet.</p>}
   {layersOpen&&<div className="quiet-layers-note"><p>Violet counts reports (311 complaints and police noise-nuisance calls), not sound. Complaints and calls are not measurements. NoiseCapture values are uncalibrated and are not dBA. Contains information from the NoiseCapture / Noise-Planet community, ODbL 1.0.</p><details><summary>Published reference levels</summary><p>{REFERENCE_NOTE}</p><ul className="quiet-refs">{REFERENCE_LEVELS.map((r:{location:string;ldn:number;note:string;date:string})=><li key={r.location}><b>{r.ldn}</b> dBA Ldn · {r.location} · {r.note} · {r.date}</li>)}</ul><a href={REFERENCE_LEVELS[0].sourceUrl} target="_blank" rel="noreferrer">Central SoMa Plan Draft EIR, Dec 2016</a></details></div>}
  </section>
  <span className="quiet-source" role="status" title="Violet = number of real reports per area (311 complaints + police noise-nuisance calls, last 30 days). Dark, gray and ringed marks are other real data, labelled by what they are.">{sourceLine}</span>
  {data.state==='failed'&&<div className="quiet-data-error" role="status">DataSF could not be reached, so there is no report density to show. Nothing is simulated in its place.</div>}
  <div className="quiet-reportlegend" role="img" aria-label="Reported noise: lighter violet means fewer reports, darker violet means more reports in the last 30 days. Counts of complaints and calls, not decibels. No colour means no reports: unknown, not quiet." title={FIELD_NOTE}><b>Reports, last 30 days · not dB</b><div><em>Fewer</em><span/><em>More</em></div><small>No colour = no reports: unknown</small></div>
  {mcp&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <div className="quiet-mcp-heading"><strong id="mcp-title">MCP</strong><button ref={closeButton} className="quiet-icon" aria-label="Close MCP" onClick={()=>{setMcp(false);mcpButton.current?.focus()}}><X size={18}/></button></div>
   <><div className="quiet-mcp-state"><span/>Proposed contract · not connected</div>
   <div className="quiet-tool-list">{contract.tools.map(t=><code key={t.name}>{t.name}<span>↗</span></code>)}</div>
   <button className="quiet-copy" onClick={copy} aria-label={copied?'Contract copied':'Copy proposed MCP contract'} title={copied?'Copied':'Copy contract'}>{copied?<Check size={17}/>:<Copy size={17}/>}</button>{copyFallback&&<textarea className="quiet-contract" aria-label="MCP contract for manual copying" readOnly value={JSON.stringify(contract,null,2)} onFocus={e=>e.currentTarget.select()}/>}</>
  </div></div>}
 </main>;
}
