'use client';
import {useEffect,useRef,useState} from 'react';
import {Check,Compass,Copy,Plug,Cuboid,Layers2,HelpCircle,Minus,Pause,Play,Plus,RotateCcw,Volume1,Volume2,X} from 'lucide-react';
import type {StyleSpecification} from 'maplibre-gl';
import 'ol/ol.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import './map.css';

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
const soundData={type:'FeatureCollection' as const,features:points.map((p,i)=>({type:'Feature' as const,id:i,geometry:{type:'Point' as const,coordinates:[p.lng,p.lat]},properties:{score:p.score}}))};
const mapStyle:StyleSpecification={
 version:8,
 sources:{city:{type:'vector',url:'https://tiles.openfreemap.org/planet'},sound:{type:'geojson',data:soundData}},
 light:{anchor:'viewport',color:'#ffffff',intensity:.4,position:[1.5,205,40]},
 layers:[
  {id:'background',type:'background',paint:{'background-color':'#ffffff'}},
  {id:'land',type:'fill',source:'city','source-layer':'landcover',paint:{'fill-color':'#f3f2f5','fill-opacity':.6}},
  {id:'parks',type:'fill',source:'city','source-layer':'park',paint:{'fill-color':'#f0f0f1','fill-outline-color':'#e8e8eb'}},
  {id:'water',type:'fill',source:'city','source-layer':'water',paint:{'fill-color':'#f6f6f7'}},
  {id:'roads-edge',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#e1e1e5','line-width':['interpolate',['linear'],['zoom'],11,.3,13,.8,16,5,19,20]}},
  {id:'roads',type:'line',source:'city','source-layer':'transportation',paint:{'line-color':'#ffffff','line-width':['interpolate',['linear'],['zoom'],11,.1,13,.25,16,3.6,19,17]}},
  {id:'footprints',type:'fill',source:'city','source-layer':'building',paint:{'fill-color':'#eae7ed','fill-outline-color':'#dfdbe5'}},
  {id:'structures',type:'fill-extrusion',source:'city','source-layer':'building',minzoom:13.5,filter:['!=',['get','hide_3d'],true],paint:{'fill-extrusion-color':'#fcfcfd','fill-extrusion-height':['interpolate',['linear'],['zoom'],13.5,0,15,['coalesce',['get','render_height'],8]],'fill-extrusion-base':['coalesce',['get','render_min_height'],0],'fill-extrusion-opacity':1,'fill-extrusion-vertical-gradient':true}},
  // Color encodes noise score, not the number of contributors. No density heatmap.
  {id:'sound-fields',type:'circle',source:'sound',paint:{'circle-color':['interpolate',['linear'],['get','score'],0,'#d9c7fa',.5,'#ae77ee',1,'#6720c4'],'circle-radius':['interpolate',['linear'],['zoom'],11,16,13,43,16,120,19,220],'circle-blur':.85,'circle-opacity':.48,'circle-pitch-alignment':'map'}},
 ]
};
type Level='quiet'|'moderate'|'loud';
const levelOf=(score:number):Level=>score>.65?'loud':score>.35?'moderate':'quiet';
const filters:{id:Level|'all';label:string}[]=[{id:'all',label:'All'},{id:'quiet',label:'Quiet'},{id:'moderate',label:'Moderate'},{id:'loud',label:'Loud'}];
const home={center:[-122.447,37.776] as [number,number],zoom:12.75,pitch:0,bearing:0};
const contract={name:'quiet-compass',status:'proposal',connected:false,data:'synthetic-demo',tools:[{name:'query_sound_map',input:{bounds:'[west,south,east,north]',max_age_minutes:'number'}},{name:'find_suitable_places',input:{area:'coarse zone',preference:'user-selected acoustic preference'}},{name:'submit_observation',input:{zone_id:'coarse zone',time_bucket:'rounded time',acoustic_summary:'aggregated calibrated indicators'},requires:'explicit contribution consent'}],excluded:['raw_audio','personal_routes','health_data']};
type ViewOptions={center?:[number,number];zoom?:number;pitch?:number;bearing?:number;duration?:number};
type MapControls={zoomIn:()=>unknown;zoomOut:()=>unknown;getZoom:()=>number;flyTo:(o:ViewOptions)=>unknown;easeTo:(o:ViewOptions)=>unknown;remove:()=>unknown};
export default function CityMap(){
 const container=useRef<HTMLDivElement>(null),map=useRef<MapControls|null>(null),markers=useRef<{marker:{remove:()=>unknown};button:HTMLButtonElement}[]>([]),playRef=useRef(true);
 const mcpButton=useRef<HTMLButtonElement>(null),closeButton=useRef<HTMLButtonElement>(null),dialog=useRef<HTMLDivElement>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[playing,setPlaying]=useState(true),[supports3D,setSupports3D]=useState(true),[threeD,setThreeD]=useState(false),[mcp,setMcp]=useState(false),[help,setHelp]=useState(false),[copied,setCopied]=useState(false),[copyFallback,setCopyFallback]=useState(false),[selected,setSelected]=useState<number|null>(null),[filter,setFilter]=useState<Level|'all'>('all');
 useEffect(()=>{playRef.current=playing},[playing]);
 useEffect(()=>{
  let disposed=false,index=0,interval:ReturnType<typeof setInterval>;
  const timeouts=new Set<ReturnType<typeof setTimeout>>();
  const fallback=async()=>{
   const {createCanvasMap}=await import('../lib/canvas-map');
   if(disposed||!container.current)return;
   const result=await createCanvasMap(container.current,points,()=>disposed,()=>{if(!disposed){setReady(true);setFailed(false)}});
   if(!result)return;
   map.current=result.controls;markers.current=result.markers;setSupports3D(false);
   interval=setInterval(()=>{if(!playRef.current||disposed)return;const next=markers.current[(index*7+2)%points.length];index++;next.button.classList.add('is-contributing');const timer=setTimeout(()=>{next.button.classList.remove('is-contributing');timeouts.delete(timer)},2300);timeouts.add(timer)},1300);
  };
  const start=async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const instance=new lib.Map({container:container.current,style:mapStyle,...home,minZoom:10,maxZoom:19,attributionControl:false,canvasContextAttributes:{antialias:true}});
   map.current=instance;
   instance.addControl(new lib.AttributionControl({compact:true}),'bottom-right');
   instance.getCanvas().setAttribute('aria-label','Map of San Francisco. Drag to explore. Darker violet means higher simulated sound levels. Pulses represent fictional contributions.');
   instance.on('load',()=>{if(!disposed){setReady(true);setFailed(false)}});
   instance.on('error',()=>{if(!disposed&&!instance.isStyleLoaded())setFailed(true)});
   markers.current=points.map((p,i)=>{
    const button=document.createElement('button');
    button.className='sound-point'+(p.landmark?' landmark-point':'');button.type='button';
    button.setAttribute('aria-label',p.name+' · sound level '+(p.score>.65?'high':p.score>.35?'moderate':'low')+' simulated');button.setAttribute('aria-pressed','false');button.title=p.name;
    button.style.setProperty('--point-color',p.score>.75?'#6623bb':p.score>.5?'#9250d3':p.score>.3?'#b07be1':'#c5a2ed');
    button.innerHTML='<span class="point-ripple"></span><span class="point-core"></span><span class="point-label">'+p.name+'</span>';
    button.addEventListener('click',e=>{e.stopPropagation();setSelected(i);instance.flyTo({center:[p.lng,p.lat],zoom:Math.max(instance.getZoom(),15.4),duration:1100})});
    const marker=new lib.Marker({element:button,anchor:'center'}).setLngLat([p.lng,p.lat]).addTo(instance);
    return {marker,button};
   });
   interval=setInterval(()=>{
    if(!playRef.current||disposed)return;
    const next=markers.current[(index*7+2)%points.length];index++;
    next.button.classList.add('is-contributing');
    const timer=setTimeout(()=>{next.button.classList.remove('is-contributing');timeouts.delete(timer)},2300);timeouts.add(timer);
   },1300);
  }catch{try{await fallback()}catch{if(!disposed)setFailed(true)}}};
  void start();
  return()=>{disposed=true;clearInterval(interval);timeouts.forEach(clearTimeout);markers.current.forEach(m=>m.marker.remove());markers.current=[];map.current?.remove();map.current=null};
 },[]);
 useEffect(()=>{markers.current.forEach((m,n)=>{const on=n===selected;m.button.classList.toggle('is-selected',on);m.button.setAttribute('aria-pressed',String(on));m.button.classList.toggle('is-dimmed',filter!=='all'&&levelOf(points[n].score)!==filter)})},[selected,filter,ready]);
 useEffect(()=>{if(selected===null||mcp||help)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setSelected(null)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[selected,mcp,help]);
 useEffect(()=>{
  if(!mcp&&!help)return;closeButton.current?.focus();
  const key=(e:KeyboardEvent)=>{
   if(e.key==='Escape'){setMcp(false);setHelp(false);mcpButton.current?.focus()}
   if(e.key==='Tab'){const buttons=dialog.current?.querySelectorAll<HTMLButtonElement>('button');if(!buttons?.length)return;const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}
  };document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[mcp,help]);
 function reset(){map.current?.flyTo({...home,duration:1000});setThreeD(false);setSelected(null);setFilter('all')}
 function tilt(){const next=!threeD;setThreeD(next);map.current?.easeTo({pitch:next?54:0,bearing:next?-24:0,...(next&&map.current.getZoom()<14?{center:[-122.4042,37.793] as [number,number],zoom:15.4}:{}),duration:900})}
 async function copy(){try{await navigator.clipboard.writeText(JSON.stringify(contract,null,2));setCopied(true)}catch{setCopied(false);setCopyFallback(true)}}
 return <main className="quiet-map-only">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading map"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The map could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  <button className="quiet-home quiet-icon" onClick={reset} title="Reset San Francisco view" aria-label="Reset San Francisco view"><Compass size={25} strokeWidth={1.4}/></button>
  <button className="quiet-mcp" ref={mcpButton} onClick={()=>{setMcp(true);setHelp(false);setCopied(false);setCopyFallback(false)}} aria-haspopup="dialog"><Plug size={14} strokeWidth={1.5}/>MCP</button>
  <button className="quiet-help quiet-icon" aria-label="How to use the map" title="How it works" onClick={()=>{setHelp(true);setMcp(false)}}><HelpCircle size={19} strokeWidth={1.5}/></button>
  <div className="quiet-filters" role="group" aria-label="Filter places by sound level">{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>
  {selected!==null&&<aside className="quiet-card" key={selected} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close place details" onClick={()=>setSelected(null)}><X size={16}/></button>
   <span className={'quiet-card-level '+levelOf(points[selected].score)}>{levelOf(points[selected].score)}</span>
   <strong>{points[selected].name}</strong>
   <p>{points[selected].landmark?'Landmark':'Neighborhood or park'} · simulated sound level</p>
   <div className="quiet-card-bar" role="img" aria-label={'Simulated level '+Math.round(points[selected].score*100)+' out of 100'}><span style={{width:Math.round(points[selected].score*100)+'%'}}/></div>
   <small>{Math.round(points[selected].score*100)} / 100</small>
  </aside>}
  <div className="quiet-map-controls">
   <button className="quiet-icon" title={playing?'Pause demo':'Play demo'} aria-label={playing?'Pause simulated contributions':'Play simulated contributions'} onClick={()=>setPlaying(!playing)}>{playing?<Pause size={17}/>:<Play size={17}/>}</button>
   <span className="quiet-control-divider"/>
   {supports3D&&<button className="quiet-icon" title={threeD?'2D view':'3D view'} aria-label={threeD?'Switch to 2D view':'Switch to 3D view'} onClick={tilt}>{threeD?<Layers2 size={19}/>:<Cuboid size={19}/>}</button>}
   <button className="quiet-icon" title="Zoom in" aria-label="Zoom in" onClick={()=>map.current?.zoomIn()}><Plus size={20}/></button>
   <button className="quiet-icon" title="Zoom out" aria-label="Zoom out" onClick={()=>map.current?.zoomOut()}><Minus size={20}/></button>
  </div>
  <span className="quiet-demo" title="Simulated contributions and noise. No agents are connected and nothing is measured.">DEMO</span>
  <div className="quiet-intensity" role="img" aria-label="Simulated sound intensity: lighter violet means lower levels; darker violet means higher levels. White has no observations." title="Simulated sound intensity · darker violet = higher levels · white = no observations"><Volume1 size={14}/><span/><Volume2 size={14}/></div>
  {(mcp||help)&&<div className="quiet-mcp-overlay" onClick={()=>{setMcp(false);setHelp(false);mcpButton.current?.focus()}}><div className="quiet-mcp-panel" ref={dialog} role="dialog" aria-modal="true" aria-labelledby="mcp-title" onClick={e=>e.stopPropagation()}>
   <div className="quiet-mcp-heading"><strong id="mcp-title">{help?'How it works':'MCP'}</strong><button ref={closeButton} className="quiet-icon" aria-label="Close help or MCP" onClick={()=>{setMcp(false);setHelp(false);mcpButton.current?.focus()}}><X size={18}/></button></div>
   {help?<div className="quiet-guide">
    <div><span>01</span><section><strong>Explore San Francisco.</strong><p>Drag the map. Select a point to zoom in. Square markers identify landmarks and important buildings.</p></section></div>
    <div><span>02</span><section><strong>Read the violet.</strong><p>Darker means higher sound levels. Lighter means lower levels. White means no observations, not silence.</p></section></div>
    <div><span>03</span><section><strong>Watch contributions.</strong><p>A pulse illustrates a new contribution. Use pause to stop the animation.</p></section></div>
    <div><span>04</span><section><strong>Bring your agent.</strong><p>The proposed MCP tools let agents query places and contribute summaries with consent. Raw audio and personal routes stay private.</p></section></div>
    <div className="quiet-guide-note">Visual demo · synthetic levels and contributions. MCP is not connected.</div>
   </div>:<><div className="quiet-mcp-state"><span/>Proposed contract · not connected</div>
   <div className="quiet-tool-list">{contract.tools.map(t=><code key={t.name}>{t.name}<span>↗</span></code>)}</div>
   <button className="quiet-copy" onClick={copy} aria-label={copied?'Contract copied':'Copy proposed MCP contract'} title={copied?'Copied':'Copy contract'}>{copied?<Check size={17}/>:<Copy size={17}/>}</button>{copyFallback&&<textarea className="quiet-contract" aria-label="MCP contract for manual copying" readOnly value={JSON.stringify(contract,null,2)} onFocus={e=>e.currentTarget.select()}/>}</>}
  </div></div>}
 </main>;
}
