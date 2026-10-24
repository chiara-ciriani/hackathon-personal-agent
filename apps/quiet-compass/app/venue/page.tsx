'use client';
import {useEffect,useRef,useState} from 'react';
import {Compass,Minus,Plus,RotateCcw,X} from 'lucide-react';
import type {ExpressionSpecification,GeoJSONSource,StyleSpecification} from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import '../map.css';

// A fictional venue drawn in metres around (0,0). Levels are synthetic; zones without a score have no observations.
type Zone={id:string;name:string;x:[number,number];y:[number,number];score:number|null};
const zones:Zone[]=[
 {id:'courtyard',name:'Courtyard',x:[0,20],y:[22,40],score:.2},
 {id:'roomb',name:'Room B',x:[22,34],y:[22,40],score:null},
 {id:'stage',name:'Main stage',x:[36,60],y:[14,40],score:.92},
 {id:'hall',name:'Hallway',x:[0,36],y:[14,22],score:.55},
 {id:'entrance',name:'Entrance',x:[0,20],y:[0,14],score:.48},
 {id:'food',name:'Food area',x:[22,60],y:[0,14],score:.68},
];
type Level='quiet'|'moderate'|'loud';
const levelOf=(s:number):Level=>s>.65?'loud':s>.35?'moderate':'quiet';
const filters:{id:Level|'all';label:string}[]=[{id:'all',label:'All'},{id:'quiet',label:'Quiet'},{id:'moderate',label:'Moderate'},{id:'loud',label:'Loud'}];
const M=1/111320,OX=-30,OY=-20,INSET=.6;
const ll=(x:number,y:number):[number,number]=>[(x+OX)*M,(y+OY)*M];
const rect=(x0:number,y0:number,x1:number,y1:number)=>[[ll(x0,y0),ll(x1,y0),ll(x1,y1),ll(x0,y1),ll(x0,y0)]];
const height=(z:Zone)=>z.score===null?.3:.4+z.score*2.4;
const zoneData={type:'FeatureCollection' as const,features:zones.map(z=>({type:'Feature' as const,geometry:{type:'Polygon' as const,coordinates:rect(z.x[0]+INSET,z.y[0]+INSET,z.x[1]-INSET,z.y[1]-INSET)},properties:{id:z.id,name:z.name,score:z.score??-1,h:height(z)}}))};
const frame=(z:Zone)=>({type:'Feature' as const,geometry:{type:'Polygon' as const,coordinates:[rect(z.x[0]+INSET,z.y[0]+INSET,z.x[1]-INSET,z.y[1]-INSET)[0],rect(z.x[0]+INSET+.7,z.y[0]+INSET+.7,z.x[1]-INSET-.7,z.y[1]-INSET-.7)[0]]},properties:{h:height(z)}});
const labelData={type:'FeatureCollection' as const,features:zones.map(z=>({type:'Feature' as const,geometry:{type:'Point' as const,coordinates:ll((z.x[0]+z.x[1])/2,(z.y[0]+z.y[1])/2)},properties:{name:z.name}}))};
const wallData={type:'FeatureCollection' as const,features:[{type:'Feature' as const,geometry:{type:'Polygon' as const,coordinates:[rect(0,0,60,40)[0],rect(.7,.7,59.3,39.3)[0]]},properties:{}}]};
const stageBlock={type:'FeatureCollection' as const,features:[{type:'Feature' as const,geometry:{type:'Polygon' as const,coordinates:rect(40,35,56,39)},properties:{}}]};
const noiseRamp:ExpressionSpecification=['case',['<',['get','score'],0],'#e8e8ec',['interpolate',['linear'],['get','score'],0,'#e6dcff',.3,'#b996f5',.55,'#8a45e8',.8,'#5a14b0',1,'#2b0a63']];
const style:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{zones:{type:'geojson',data:zoneData},labels:{type:'geojson',data:labelData},walls:{type:'geojson',data:wallData},stage:{type:'geojson',data:stageBlock},sel:{type:'geojson',data:{type:'FeatureCollection',features:[]}}},
 layers:[
  {id:'bg',type:'background',paint:{'background-color':'#fafafa'}},
  {id:'slab',type:'fill-extrusion',source:'walls',paint:{'fill-extrusion-color':'#ffffff','fill-extrusion-height':.15}},
  {id:'zones',type:'fill-extrusion',source:'zones',paint:{'fill-extrusion-color':noiseRamp,'fill-extrusion-height':['get','h'],'fill-extrusion-base':.15,'fill-extrusion-opacity':.95,'fill-extrusion-vertical-gradient':true}},
  {id:'stage-block',type:'fill-extrusion',source:'stage',paint:{'fill-extrusion-color':'#52525b','fill-extrusion-height':3.9,'fill-extrusion-base':2.7}},
  {id:'sel',type:'fill-extrusion',source:'sel',paint:{'fill-extrusion-color':'#171717','fill-extrusion-height':['+',['get','h'],.35],'fill-extrusion-base':['get','h']}},
  {id:'walls',type:'fill-extrusion',source:'walls',paint:{'fill-extrusion-color':'#d4d4da','fill-extrusion-height':2.2,'fill-extrusion-opacity':.4}},
  {id:'zone-labels',type:'symbol',source:'labels',layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':12,'text-allow-overlap':true},paint:{'text-color':'#171717','text-halo-color':'#ffffff','text-halo-width':1.5}},
 ],
};
const home=()=>({center:[0,0] as [number,number],zoom:typeof window!=='undefined'&&window.innerWidth<600?18.85:20.1,pitch:58,bearing:-28});
export default function Venue(){
 const container=useRef<HTMLDivElement>(null),mapRef=useRef<import('maplibre-gl').Map|null>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[selected,setSelected]=useState<string|null>(null),[filter,setFilter]=useState<Level|'all'>('all');
 useEffect(()=>{
  let disposed=false;
  const timeouts=new Set<ReturnType<typeof setTimeout>>();let interval:ReturnType<typeof setInterval>|undefined;
  void (async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const map=new lib.Map({container:container.current,style,...home(),minZoom:18.2,maxZoom:22,maxPitch:70,attributionControl:false,canvasContextAttributes:{antialias:true}});
   mapRef.current=map;
   map.getCanvas().setAttribute('aria-label','3D model of a demo event venue. Taller, darker zones are louder. Grey zones have no observations. All levels are simulated.');
   map.on('load',()=>{if(!disposed){setReady(true);setFailed(false)}});
   map.on('error',()=>{if(!disposed&&!map.isStyleLoaded())setFailed(true)});
   map.on('click','zones',e=>{const id=e.features?.[0]?.properties?.id as string|undefined;if(id)setSelected(id)});
   map.on('click',e=>{if(!map.queryRenderedFeatures(e.point,{layers:['zones']}).length)setSelected(null)});
   map.on('mouseenter','zones',()=>{map.getCanvas().style.cursor='pointer'});
   map.on('mouseleave','zones',()=>{map.getCanvas().style.cursor=''});
   // A soft ripple on a loud or moderate zone, standing in for an agent's new report.
   let n=0;interval=setInterval(()=>{
    const z=zones.filter(q=>q.score!==null)[n++%5];
    const el=document.createElement('div');el.className='quiet-ripple';
    const r=new lib.Marker({element:el,anchor:'center'}).setLngLat(ll((z.x[0]+z.x[1])/2,(z.y[0]+z.y[1])/2)).addTo(map);
    const t=setTimeout(()=>{r.remove();timeouts.delete(t)},2300);timeouts.add(t);
   },3200);
  }catch{if(!disposed)setFailed(true)}})();
  return()=>{disposed=true;clearInterval(interval);timeouts.forEach(clearTimeout);mapRef.current?.remove();mapRef.current=null};
 },[]);
 useEffect(()=>{const map=mapRef.current;if(!map||!ready)return;
  map.setFilter('zones',filter==='all'?null:filter==='quiet'?['all',['>=',['get','score'],0],['<=',['get','score'],.35]]:filter==='moderate'?['all',['>',['get','score'],.35],['<=',['get','score'],.65]]:['>',['get','score'],.65]);
 },[filter,ready]);
 useEffect(()=>{const map=mapRef.current;if(!map||!ready)return;
  const f=zones.filter(q=>q.id===selected).map(frame);
  (map.getSource('sel') as GeoJSONSource|undefined)?.setData({type:'FeatureCollection',features:f});
 },[selected,ready]);
 useEffect(()=>{if(!selected)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setSelected(null)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[selected]);
 const zone=zones.find(z=>z.id===selected);
 const reset=()=>{mapRef.current?.flyTo({...home(),duration:1000});setSelected(null);setFilter('all')};
 return <main className="quiet-map-only quiet-venue">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading venue"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The venue could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  {/* A plain anchor: next/link breaks under this project's vinext dev server. */}
  {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
  <a className="quiet-home quiet-icon" href="/" title="Back to the city map" aria-label="Back to the city map"><Compass size={25} strokeWidth={1.4}/></a>
  <div className="quiet-filters" role="group" aria-label="Filter zones by sound level">{filters.map(f=><button key={f.id} className={filter===f.id?'is-active':''} aria-pressed={filter===f.id} onClick={()=>setFilter(f.id)}>{f.label}</button>)}</div>
  {zone&&<aside className="quiet-card" key={zone.id} aria-live="polite">
   <button className="quiet-icon quiet-card-close" aria-label="Close zone details" onClick={()=>setSelected(null)}><X size={16}/></button>
   <strong>{zone.name}</strong>
   {zone.score===null?<span className="quiet-card-level quiet-card-none">No observations yet</span>:<><span className={'quiet-card-level '+levelOf(zone.score)}>{levelOf(zone.score)} · simulated</span><div className="quiet-card-bar" role="img" aria-label={'Simulated level '+Math.round(zone.score*100)+' out of 100'}><span style={{width:Math.round(zone.score*100)+'%'}}/></div></>}
  </aside>}
  <div className="quiet-map-controls">
   <button className="quiet-icon" title="Reset view" aria-label="Reset view" onClick={reset}><RotateCcw size={18}/></button>
   <span className="quiet-control-divider"/>
   <button className="quiet-icon" title="Zoom in" aria-label="Zoom in" onClick={()=>mapRef.current?.zoomIn()}><Plus size={20}/></button>
   <button className="quiet-icon" title="Zoom out" aria-label="Zoom out" onClick={()=>mapRef.current?.zoomOut()}><Minus size={20}/></button>
  </div>
  <span className="quiet-demo" title="A fictional venue with simulated sound levels. Taller and darker means louder; grey means no observations.">Demo venue</span>
  <div className="quiet-intensity" role="img" aria-label="Quiet to loud: lighter violet and shorter is quieter, darker and taller is louder."><em>Quiet</em><span/><em>Loud</em></div>
 </main>;
}
