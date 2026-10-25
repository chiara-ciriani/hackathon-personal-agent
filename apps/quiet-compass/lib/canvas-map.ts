import type {PointFeature} from './map-types';
import Map from 'ol/Map.js';
import View from 'ol/View.js';
import Overlay from 'ol/Overlay.js';
import MVT from 'ol/format/MVT.js';
import VectorTileLayer from 'ol/layer/VectorTile.js';
import VectorTileSource from 'ol/source/VectorTile.js';
import Style from 'ol/style/Style.js';
import Fill from 'ol/style/Fill.js';
import Stroke from 'ol/style/Stroke.js';
import Attribution from 'ol/control/Attribution.js';
import {fromLonLat,toLonLat} from 'ol/proj.js';

type Options={center?:[number,number];zoom?:number;duration?:number};
export async function createCanvasMap(container:HTMLDivElement,isDisposed:()=>boolean,onReady:()=>void,onSelect:(p:Record<string,unknown>)=>void){
 const response=await fetch('https://tiles.openfreemap.org/planet',{signal:AbortSignal.timeout(12000)});
 if(!response.ok)throw new Error('Map source unavailable');
 const json=await response.json() as {tiles:string[];maxzoom?:number};
 if(isDisposed())return null;
 container.replaceChildren();
 const styles:Record<string,Style>={
  water:new Style({fill:new Fill({color:'#f6f6f7'}),zIndex:0}),
  landcover:new Style({fill:new Fill({color:'#f8f8f9'}),zIndex:1}),
  park:new Style({fill:new Fill({color:'#f0f0f1'}),stroke:new Stroke({color:'#e9e9eb',width:.5}),zIndex:2}),
  building:new Style({fill:new Fill({color:'#e8e5ee'}),stroke:new Stroke({color:'#ded9e6',width:.35}),zIndex:4}),
  transportation:new Style({stroke:new Stroke({color:'#dfdfe3',width:.8}),zIndex:3}),
 };
 const source=new VectorTileSource({format:new MVT(),url:json.tiles[0],maxZoom:json.maxzoom||14,attributions:'<a href="https://openfreemap.org/" target="_blank" rel="noreferrer">OpenFreeMap</a> · © <a href="https://openmaptiles.org/" target="_blank" rel="noreferrer">OpenMapTiles</a> · © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>'});
 const layer=new VectorTileLayer({source,background:'#e9e9ec',style:(feature)=>styles[feature.get('layer')]});
 const view=new View({center:fromLonLat([-122.447,37.776]),zoom:13.75,minZoom:11,maxZoom:20});
 const instance=new Map({target:container,view,layers:[layer],controls:[new Attribution({collapsible:true,collapsed:true})]});
 instance.once('rendercomplete',onReady);
 const move=(o:Options)=>view.animate({center:fromLonLat(o.center||toLonLat(view.getCenter()!)),zoom:o.zoom===undefined?view.getZoom():o.zoom+1,duration:o.duration||700});
 let overlays:Overlay[]=[];
 const setFeatures=(features:PointFeature[])=>{
  overlays.forEach(overlay=>instance.removeOverlay(overlay));
  overlays=features.map(f=>{
   const p=f.properties,hasMeasurement=['measured','measured_device'].includes(String(p.evidence));
   const button=document.createElement('button');button.className='sound-point';button.type='button';
   button.setAttribute('aria-label',String(p.label||'Location')+(hasMeasurement?' · dated measurement':' · no measurement'));
   button.title=button.getAttribute('aria-label')||'';
   button.style.setProperty('--point-color',hasMeasurement?'#6720c4':'#a1a1aa');
   const core=document.createElement('span');core.className='point-core';button.appendChild(core);
   const overlay=new Overlay({element:button,position:fromLonLat(f.geometry.coordinates),positioning:'center-center',stopEvent:true});instance.addOverlay(overlay);
   button.addEventListener('click',()=>onSelect(p));return overlay;
  });
 };
 return{setFeatures,controls:{zoomIn:()=>view.animate({zoom:Math.min(20,view.getZoom()!+1),duration:250}),zoomOut:()=>view.animate({zoom:Math.max(11,view.getZoom()!-1),duration:250}),getZoom:()=>view.getZoom()!-1,flyTo:move,easeTo:move,remove:()=>instance.dispose()}};
}
