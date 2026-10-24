'use client';
import {useEffect,useRef,useState} from 'react';
import {Compass,Minus,Plus,RotateCcw,X} from 'lucide-react';
import type {ExpressionSpecification,GeoJSONSource,StyleSpecification} from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import '../map.css';
import {venueById} from '../../lib/venues';

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
const disc=(cx:number,cy:number,r:number,n=28)=>[Array.from({length:n+1},(_,i)=>ll(cx+r*Math.cos(i/n*6.2832),cy+r*Math.sin(i/n*6.2832)))];
type Poly={type:'Polygon';coordinates:[number,number][][]};
const feat=(geometry:Poly,properties:Record<string,unknown>)=>({type:'Feature' as const,geometry,properties});
const fc=(features:ReturnType<typeof feat>[])=>({type:'FeatureCollection' as const,features});
const box=(x0:number,y0:number,x1:number,y1:number,props:Record<string,unknown>)=>feat({type:'Polygon',coordinates:rect(x0,y0,x1,y1)},props);
const floorH=(z:Zone)=>z.score===null?.12:.12;
const frame=(z:Zone)=>feat({type:'Polygon',coordinates:[rect(z.x[0]+INSET,z.y[0]+INSET,z.x[1]-INSET,z.y[1]-INSET)[0],rect(z.x[0]+INSET+.7,z.y[0]+INSET+.7,z.x[1]-INSET-.7,z.y[1]-INSET-.7)[0]]},{h:floorH(z)});
const floors=fc(zones.map(z=>feat({type:'Polygon',coordinates:rect(z.x[0]+INSET,z.y[0]+INSET,z.x[1]-INSET,z.y[1]-INSET)},{id:z.id,name:z.name,score:z.score??-1})));
const labelData=fc(zones.map(z=>feat({type:'Point',coordinates:ll((z.x[0]+z.x[1])/2,(z.y[0]+z.y[1])/2)} as unknown as Poly,{name:z.name})));
// Walls are thin boxes with doorway gaps. The courtyard is open air, so its outer walls are low.
const WALL=1.8,LOW=.7;
const wall=(horizontal:boolean,pos:number,a:number,b:number,gaps:[number,number][],h=WALL,t=.4)=>{
 const out:ReturnType<typeof feat>[]=[];let cursor=a;
 const seg=(s0:number,s1:number)=>{if(s1-s0>.05)out.push(horizontal?box(s0,pos-t/2,s1,pos+t/2,{h}):box(pos-t/2,s0,pos+t/2,s1,{h}))};
 for(const g of gaps){seg(cursor,g[0]);cursor=g[1]}seg(cursor,b);return out;
};
const walls=fc([
 ...wall(true,0,0,60,[[8,12]]),...wall(true,40,0,20,[],LOW),...wall(true,40,20,60,[]),
 ...wall(false,0,0,22,[]),...wall(false,0,22,40,[],LOW),...wall(false,60,0,40,[]),
 ...wall(true,14,0,60,[[8,12],[26,30],[46,52]]),...wall(true,22,0,35,[[8,12],[26,30]]),
 ...wall(false,21,0,14,[[6,9]]),...wall(false,21,22,40,[]),...wall(false,35,14,40,[[17,21]]),
]);
const slab=fc([box(-1.2,-1.2,61.2,41.2,{})]);
// Sound sources: nested translucent domes, tallest and darkest at the centre. Heights are metres.
const sources:{zone:string;x:number;y:number;rings:[number,number,number][]}[]=[
 {zone:'stage',x:48,y:28,rings:[[4.5,.95,6.5],[8.5,.8,4.2],[12.5,.6,2.2]]},
 {zone:'food',x:40,y:7,rings:[[3,.75,3.6],[6.5,.6,2]]},
 {zone:'entrance',x:10,y:7,rings:[[3,.55,2.6],[5.5,.45,1.5]]},
];
const domes=fc(sources.flatMap(src=>{const z=zones.find(q=>q.id===src.zone)!;return [...src.rings].reverse().map(([r,score,h])=>feat({type:'Polygon',coordinates:disc(src.x,src.y,r)},{score,zscore:z.score,h}))}));
// Props give the rooms scale: stage, speakers, seats, tables, counters, planters.
const prop=(x0:number,y0:number,x1:number,y1:number,h:number,color:string,base=.12)=>box(x0,y0,x1,y1,{h,color,base});
const props=fc([
 prop(38,34,58,39,1.2,'#3f3f46'),prop(38,38.6,58,39.2,4.4,'#171717'),prop(38.4,34.6,40.4,36.6,3.2,'#27272a',1.2),prop(55.6,34.6,57.6,36.6,3.2,'#27272a',1.2),
 ...Array.from({length:6},(_,r)=>Array.from({length:11},(_,c)=>prop(39.6+c*1.7,17+r*2.4,40.6+c*1.7,18+r*2.4,.6,'#c9c9d1'))).flat(),
 prop(24,10.6,56,11.8,1.1,'#27272a'),
 ...Array.from({length:5},(_,i)=>prop(25+i*6.6,3.4,27+i*6.6,5.4,.8,'#d4d4da')),
 prop(3.5,9,8,10,1.1,'#27272a'),
 ...[[3,25],[3,36],[9,38],[15,26],[16,36]].map(([x,y])=>feat({type:'Polygon',coordinates:disc(x,y,1.3,12)},{h:3.2,base:1.1,color:'#d4d4da'})),
 ...[[3,25],[3,36],[9,38],[15,26],[16,36]].map(([x,y])=>feat({type:'Polygon',coordinates:disc(x,y,.35,8)},{h:1.2,base:.12,color:'#a1a1aa'})),
 prop(7,30,13,30.8,.5,'#c9c9d1'),prop(24,25,27,28,.8,'#d4d4da'),prop(29,31,32,34,.8,'#d4d4da'),
]);
const dotRamp:ExpressionSpecification=['interpolate',['linear'],['get','score'],0,'#d9c7fa',.3,'#b996f5',.55,'#8a45e8',.8,'#5a14b0',1,'#2b0a63'];
const empty={type:'FeatureCollection' as const,features:[]};
const style:StyleSpecification={
 version:8,
 glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
 sources:{floors:{type:'geojson',data:floors},labels:{type:'geojson',data:labelData},walls:{type:'geojson',data:walls},slab:{type:'geojson',data:slab},props:{type:'geojson',data:props},domes:{type:'geojson',data:domes},sel:{type:'geojson',data:empty},dots:{type:'geojson',data:empty}},
 layers:[
  {id:'bg',type:'background',paint:{'background-color':'#f4f4f6'}},
  {id:'slab',type:'fill-extrusion',source:'slab',paint:{'fill-extrusion-color':'#fbfbfc','fill-extrusion-height':.12}},
  {id:'zones',type:'fill-extrusion',source:'floors',paint:{'fill-extrusion-color':'#eeeef1','fill-extrusion-height':.2,'fill-extrusion-base':.12}},
  {id:'zone-edge',type:'line',source:'floors',paint:{'line-color':'#171717','line-width':1,'line-opacity':.55}},
  {id:'sel',type:'fill-extrusion',source:'sel',paint:{'fill-extrusion-color':'#5a14b0','fill-extrusion-height':.5,'fill-extrusion-base':.2}},
  {id:'props',type:'fill-extrusion',source:'props',paint:{'fill-extrusion-color':['get','color'],'fill-extrusion-height':['get','h'],'fill-extrusion-base':['coalesce',['get','base'],.12],'fill-extrusion-vertical-gradient':true}},
  {id:'walls',type:'fill-extrusion',source:'walls',paint:{'fill-extrusion-color':'#1c1c21','fill-extrusion-height':['get','h'],'fill-extrusion-base':.12,'fill-extrusion-vertical-gradient':false}},
  {id:'domes-edge',type:'line',source:'domes',paint:{'line-color':'#8a45e8','line-width':1,'line-opacity':.55}},
  {id:'dots',type:'circle',source:'dots',paint:{'circle-color':['case',['<',['get','score'],0],'#ffffff',dotRamp],'circle-radius':['interpolate',['linear'],['zoom'],18,1.1,20,['+',2,['*',2.2,['max',['get','score'],0]]],22,['+',7,['*',9,['max',['get','score'],0]]]],'circle-stroke-color':['case',['<',['get','score'],0],'#a1a1aa','#00000000'],'circle-stroke-width':['case',['<',['get','score'],0],1,0],'circle-opacity':['case',['<',['get','score'],0],1,['+',.55,['*',.4,['get','score']]]],'circle-pitch-alignment':'map'}},
  {id:'zone-labels',type:'symbol',source:'labels',layout:{'text-field':['get','name'],'text-font':['Noto Sans Regular'],'text-size':11,'text-letter-spacing':.1,'text-transform':'uppercase','text-allow-overlap':true},paint:{'text-color':'#171717','text-halo-color':'#ffffff','text-halo-width':1.6}},
 ],
};
const home=()=>({center:[0,0] as [number,number],zoom:typeof window!=='undefined'&&window.innerWidth<600?18.85:20.1,pitch:62,bearing:-32});
// Zones shifted by the venue's bias; zones without a score stay without one.
const clamp=(v:number,lo=.04,hi=.98)=>Math.min(hi,Math.max(lo,v));
const zonesFor=(bias:number):Zone[]=>zones.map(z=>({...z,score:z.score===null?null:clamp(z.score+bias)}));
const hash=(x:number,y:number)=>{const v=Math.sin(x*12.9898+y*78.233)*43758.5453;return v-Math.floor(v)};
// The floor is a field of points, not a solid fill: each point carries the local level, which rises near the loud sources.
const dotField=(zs:Zone[])=>fc(zs.flatMap(z=>{
 const out:ReturnType<typeof feat>[]=[];const known=z.score!==null,step=known?1.5:2.4;
 for(let x=z.x[0]+INSET+step/2;x<z.x[1]-INSET;x+=step)for(let y=z.y[0]+INSET+step/2;y<z.y[1]-INSET;y+=step){
  let level=-1;
  if(known){
   level=z.score!+(hash(x,y)-.5)*.3;
   for(const src of sources){const d=Math.hypot(x-src.x,y-src.y);const base=zs.find(q=>q.id===src.zone)?.score??0;if(base>.6)level+=.28*Math.exp(-d/7)*(base-.4)}
   level=clamp(level,.03,1);
  }
  out.push(feat({type:'Polygon',coordinates:[]} as unknown as Poly,{score:level,zscore:z.score??-1,x,y}));
 }
 return out;
}).map(f=>({...f,geometry:{type:'Point' as const,coordinates:ll(f.properties.x as number,f.properties.y as number)}})) as unknown as ReturnType<typeof feat>[]);
const floorsFor=(zs:Zone[])=>fc(zs.map(z=>feat({type:'Polygon',coordinates:rect(z.x[0]+INSET,z.y[0]+INSET,z.x[1]-INSET,z.y[1]-INSET)},{id:z.id,name:z.name,score:z.score??-1})));
export default function Venue(){
 const container=useRef<HTMLDivElement>(null),mapRef=useRef<import('maplibre-gl').Map|null>(null);
 const [ready,setReady]=useState(false),[failed,setFailed]=useState(false),[selected,setSelected]=useState<string|null>(null),[filter,setFilter]=useState<Level|'all'>('all');
 // The venue comes from ?v=<id>; the title only renders after the map is ready, so there is no hydration mismatch.
 const [venueId]=useState(()=>typeof window==='undefined'?'moscone':new URLSearchParams(window.location.search).get('v')??'moscone');
 const venue=venueById(venueId),zs=zonesFor(venue.bias);
 useEffect(()=>{
  let disposed=false;
  const timeouts=new Set<ReturnType<typeof setTimeout>>();let interval:ReturnType<typeof setInterval>|undefined;
  void (async()=>{try{
   const lib=await import('maplibre-gl');
   if(disposed||!container.current)return;
   lib.setWorkerUrl('/maplibre-gl-worker.mjs');
   const map=new lib.Map({container:container.current,style,...home(),minZoom:18.2,maxZoom:22,maxPitch:70,attributionControl:false,canvasContextAttributes:{antialias:true}});
   mapRef.current=map;
   map.getCanvas().setAttribute('aria-label','3D model of an event venue. Darker, larger dots are louder. Hollow grey dots have no observations. All levels are simulated.');
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
  const f=(prop:string):ExpressionSpecification|null=>filter==='all'?null:filter==='quiet'?['all',['>=',['get',prop],0],['<=',['get',prop],.35]]:filter==='moderate'?['all',['>',['get',prop],.35],['<=',['get',prop],.65]]:['>',['get',prop],.65];
  map.setFilter('zones',f('score'));map.setFilter('dots',f('zscore'));
 },[filter,ready]);
 useEffect(()=>{const map=mapRef.current;if(!map||!ready)return;
  const zl=zonesFor(venue.bias);
  (map.getSource('floors') as GeoJSONSource|undefined)?.setData(floorsFor(zl));
  (map.getSource('dots') as GeoJSONSource|undefined)?.setData(dotField(zl));
 },[venue.bias,ready]);
 useEffect(()=>{const map=mapRef.current;if(!map||!ready)return;
  const f=zones.filter(q=>q.id===selected).map(frame);
  (map.getSource('sel') as GeoJSONSource|undefined)?.setData(fc(f));
 },[selected,ready]);
 useEffect(()=>{if(!selected)return;const key=(e:KeyboardEvent)=>{if(e.key==='Escape')setSelected(null)};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key)},[selected]);
 const zone=zs.find(z=>z.id===selected);
 const reset=()=>{mapRef.current?.flyTo({...home(),duration:1000});setSelected(null);setFilter('all')};
 return <main className="quiet-map-only quiet-venue">
  <div className="quiet-map-canvas" ref={container}/>
  {!ready&&!failed&&<div className="quiet-loading" role="status" aria-label="Loading venue"><span/></div>}
  {failed&&!ready&&<div className="quiet-map-error" role="status">The venue could not be loaded.<button onClick={()=>window.location.reload()} aria-label="Try again"><RotateCcw size={18}/></button></div>}
  {/* A plain anchor: next/link breaks under this project's vinext dev server. */}
  {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
  <a className="quiet-home quiet-icon" href="/" title="Back to the city map" aria-label="Back to the city map"><Compass size={25} strokeWidth={1.4}/></a>
  {ready&&<span className="quiet-venue-title">{venue.name}</span>}
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
  <div className="quiet-intensity" role="img" aria-label="Quiet to loud: lighter, smaller dots are quieter; darker, larger dots are louder."><em>Quiet</em><span/><em>Loud</em></div>
 </main>;
}
